local LrApplication = import 'LrApplication'
local LrLogger = import 'LrLogger'
local LrExportSession = import 'LrExportSession'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'

local logger = LrLogger('LightroomMCP')

local MetadataHandler = {}

-- Shared photo lookup: by numeric ID, path, filename, or active photo
local function lookupPhoto(catalog, args)
    if args and args.photo_id then
        local numericId = tonumber(args.photo_id)
        if numericId then
            local photo = nil
            catalog:withReadAccessDo(function()
                photo = catalog:findPhotoByLocalIdentifier(numericId)
            end)
            return photo
        end
        local photo = catalog:findPhotoByPath(args.photo_id)
        if not photo then
            local found = catalog:findPhotos({
                searchDesc = { criteria = "filename", operation = "==", value = args.photo_id }
            })
            if found and #found > 0 then return found[1] end
        end
        return photo
    end
    return catalog:getTargetPhoto()
end

local function sanitize(value)
    if type(value) ~= "string" then return value end
    value = value:gsub("\\", "/")
    return value:gsub("[^\32-\126]", "?")
end

local function buildPhotoData(catalog, photo)
    local photoData = nil

    catalog:withReadAccessDo(function()
        local keywords = {}
        local photoKeywords = photo:getRawMetadata('keywords')
        if photoKeywords then
            for _, kw in ipairs(photoKeywords) do
                table.insert(keywords, kw:getName())
            end
        end

        photoData = {
            id = photo.localIdentifier,
            path = sanitize(photo:getRawMetadata('path')),
            filename = sanitize(photo:getFormattedMetadata('fileName')),
            rating = photo:getRawMetadata('rating'),
            colorLabel = sanitize(photo:getRawMetadata('colorNameForLabel')),
            pickStatus = photo:getRawMetadata('pickStatus'),
            keywords = keywords,
            dateTimeOriginal = sanitize(photo:getFormattedMetadata('dateTimeOriginal')),
            cameraMake = sanitize(photo:getFormattedMetadata('cameraMake')),
            cameraModel = sanitize(photo:getFormattedMetadata('cameraModel')),
            lens = sanitize(photo:getFormattedMetadata('lens')),
            isoSpeedRating = sanitize(photo:getFormattedMetadata('isoSpeedRating')),
            focalLength = sanitize(photo:getFormattedMetadata('focalLength')),
            aperture = sanitize(photo:getFormattedMetadata('aperture')),
            shutterSpeed = sanitize(photo:getFormattedMetadata('shutterSpeed')),
            dimensions = sanitize(photo:getFormattedMetadata('dimensions')),
            fileSize = sanitize(photo:getFormattedMetadata('fileSize')),
            fileFormat = sanitize(photo:getRawMetadata('fileFormat')),
        }
    end)

    local developSettings = photo:getDevelopSettings()
    if developSettings then
        photoData.developSettings = {
            whiteBalance = developSettings.WhiteBalance,
            exposure = developSettings.Exposure2012,
            contrast = developSettings.Contrast2012,
            highlights = developSettings.Highlights2012,
            shadows = developSettings.Shadows2012,
            whites = developSettings.Whites2012,
            blacks = developSettings.Blacks2012,
            clarity = developSettings.Clarity2012,
            vibrance = developSettings.Vibrance,
            saturation = developSettings.Saturation,
        }
    end

    return photoData
end

local MAX_BYTES = 786432  -- 750 KB raw → ~1000 KB base64 → fits under MCP 1 MB limit

-- Export the photo as a JPEG to a unique temp directory.
-- Each call gets its own dir to avoid any file collision between retries.
-- Returns binary data string, or nil on failure.
local function exportJpegSync(catalog, photo, quality, maxDim)
    local tempBase = LrPathUtils.getStandardFilePath('temp')
    -- Unique dir per quality so retries never collide
    local exportDir = LrPathUtils.child(tempBase, 'lrmcp_q' .. tostring(quality))

    pcall(function() LrFileUtils.delete(exportDir) end)
    pcall(function() LrFileUtils.createAllDirectories(exportDir) end)

    local resultPath = nil
    local exportErr = nil

    -- NOTE: Do NOT wrap in pcall — waitForRender() yields, illegal inside pcall in Lua 5.1
    local exportSession = LrExportSession {
        photosToExport = { photo },
        exportSettings = {
            LR_export_destinationType        = 'specificFolder',
            LR_export_destinationPathPrefix  = exportDir,
            LR_export_useSubfolder           = false,
            LR_format                        = 'JPEG',
            LR_jpeg_quality                  = quality,
            LR_size_doConstrain              = true,
            LR_size_maxWidth                 = maxDim,
            LR_size_maxHeight                = maxDim,
            LR_export_colorSpace             = 'sRGB',
        }
    }

    for _, rendition in exportSession:renditions() do
        local success, pathOrMessage = rendition:waitForRender()
        logger:info("Rendition q" .. quality .. ": success=" .. tostring(success) .. " path=" .. tostring(pathOrMessage))
        if success then
            resultPath = pathOrMessage
        end
    end

    -- Return the path; caller checks size and reads the file
    return resultPath
end

-- Try exporting with decreasing dimension (then quality) until result fits under MAX_BYTES.
-- Returns filePath, quality, maxDim, fileSize — or nil on total failure.
local function exportWithSizeLimit(catalog, photo)
    local steps = {
        { maxDim = 1400, quality = 75 },
        { maxDim = 1200, quality = 75 },
        { maxDim = 1000, quality = 75 },
        { maxDim = 1000, quality = 60 },
    }

    for _, step in ipairs(steps) do
        logger:info("Exporting at " .. step.maxDim .. "px q" .. step.quality)
        local path = exportJpegSync(catalog, photo, step.quality, step.maxDim)
        if path then
            local f = io.open(path, 'rb')
            if f then
                local size = f:seek('end')
                f:close()
                logger:info("Export: " .. size .. " bytes (limit " .. MAX_BYTES .. ")")
                if size <= MAX_BYTES then
                    return path, step.quality, step.maxDim, size
                end
                logger:info("Too large, trying next step")
            end
        else
            logger:info("exportJpegSync returned nil at " .. step.maxDim .. "px q" .. step.quality)
        end
    end

    return nil, nil, nil, nil
end

-- Shared export helper: export active/specified photo, return file path only
local function exportPhoto(catalog, photo)
    local exportPath, usedQuality, usedMaxDim, fileSize = exportWithSizeLimit(catalog, photo)
    if not exportPath then return nil end
    logger:info("Exported: " .. fileSize .. " bytes q" .. usedQuality .. " " .. usedMaxDim .. "px")
    return exportPath
end

-- get_photo: image only, no metadata (server returns bare image block)
function MetadataHandler.getPhoto(args)
    local catalog = LrApplication.activeCatalog()
    local photo = lookupPhoto(catalog, args)
    if not photo then return { error = "No photo found" } end
    local path = exportPhoto(catalog, photo)
    if not path then return { error = "Export failed" } end
    return { imagePath = path, mimeType = "image/jpeg" }
end

-- analyze_raw_photo: return RAW file path — server extracts embedded JPEG and analyses
function MetadataHandler.analyzeRawPhoto(args)
    local catalog = LrApplication.activeCatalog()
    local photo = lookupPhoto(catalog, args)
    if not photo then return { error = "No photo found" } end
    local rawPath = nil
    catalog:withReadAccessDo(function()
        rawPath = photo:getRawMetadata('path')
    end)
    if not rawPath then return { error = "Could not get RAW path" } end
    logger:info("analyzeRawPhoto: " .. rawPath)
    return { rawPath = rawPath, photoId = tostring(photo.localIdentifier) }
end

-- analyze_edit: export with current LR settings — server analyses + returns image + JSON
function MetadataHandler.analyzeEdit(args)
    local catalog = LrApplication.activeCatalog()
    local photo = lookupPhoto(catalog, args)
    if not photo then return { error = "No photo found" } end
    local path = exportPhoto(catalog, photo)
    if not path then return { error = "Export failed" } end
    return { imagePath = path, mimeType = "image/jpeg" }
end

function MetadataHandler.getActivePhoto()
    local catalog = LrApplication.activeCatalog()
    local photo = catalog:getTargetPhoto()

    if not photo then
        return { error = "No photo is currently active in Lightroom" }
    end

    logger:info("Retrieved active photo: " .. tostring(photo.localIdentifier))
    return buildPhotoData(catalog, photo)
end

function MetadataHandler.getPhotoMetadata(args)
    if not args.photo_id then
        error("photo_id is required")
    end

    local catalog = LrApplication.activeCatalog()
    local photo = nil

    local numericId = tonumber(args.photo_id)
    if numericId then
        logger:info("Searching by numeric ID: " .. args.photo_id)
        catalog:withReadAccessDo(function()
            photo = catalog:findPhotoByLocalIdentifier(numericId)
        end)
    else
        logger:info("Trying findPhotoByPath...")
        photo = catalog:findPhotoByPath(args.photo_id)
        logger:info("findPhotoByPath result: " .. tostring(photo))

        if not photo then
            logger:info("Trying findPhotos by filename...")
            local found = catalog:findPhotos({
                searchDesc = {
                    criteria = "filename",
                    operation = "==",
                    value = args.photo_id,
                }
            })
            logger:info("findPhotos result count: " .. tostring(found and #found or 0))
            if found and #found > 0 then
                photo = found[1]
            end
        end
    end

    if not photo then
        return { error = "Photo not found: " .. args.photo_id }
    end

    logger:info("Retrieved metadata for photo: " .. args.photo_id)
    return buildPhotoData(catalog, photo)
end

return MetadataHandler
