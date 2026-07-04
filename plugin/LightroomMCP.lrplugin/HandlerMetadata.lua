local LrApplication = import 'LrApplication'
local LrLogger = import 'LrLogger'
local LrExportSession = import 'LrExportSession'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'

local logger = LrLogger('LightroomMCP')

local MetadataHandler = {}

-- Shared photo lookup: by numeric ID, path, exact filename, or partial filename.
-- Returns (photo, nil) on success, (nil, errorMsg) on ambiguity, (nil, nil) when not found.
local function lookupPhoto(catalog, args)
    if args and args.photo_id then
        local numericId = tonumber(args.photo_id)
        if numericId then
            local photo = nil
            catalog:withReadAccessDo(function()
                photo = catalog:findPhotoByLocalIdentifier(numericId)
            end)
            return photo, nil
        end
        local photo = catalog:findPhotoByPath(args.photo_id)
        if photo then return photo, nil end
        local found = catalog:findPhotos({
            searchDesc = { criteria = "filename", operation = "==", value = args.photo_id }
        })
        if found and #found > 0 then return found[1], nil end
        -- Fallback: partial filename match
        found = catalog:findPhotos({
            searchDesc = { criteria = "filename", operation = "any", value = args.photo_id }
        })
        if found and #found == 1 then return found[1], nil end
        if found and #found > 1 then
            return nil, "Ambiguous: " .. #found .. " photos match '" .. args.photo_id .. "'. Use a more specific name."
        end
        return nil, nil
    end
    return catalog:getTargetPhoto(), nil
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

-- Export the photo as a JPEG to a unique temp directory.
-- Each call gets its own dir to avoid any file collision between retries.
-- Returns binary data string, or nil on failure.
local function exportJpegSync(catalog, photo, quality, maxDim)
    local tempBase = LrPathUtils.getStandardFilePath('temp')
    -- Unique dir per dimension+quality so steps never share a folder
    local exportDir = LrPathUtils.child(tempBase, 'lrmcp_' .. tostring(maxDim) .. '_q' .. tostring(quality))

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

-- Single render: export the photo ONCE. The Node server fits the JPEG under the
-- MCP size budget afterwards (fast in-memory recompression), so we no longer
-- re-render at decreasing sizes here. The old cascade did up to 6 sequential
-- renders; on heavily-masked/textured edits each render is expensive and the
-- total blew past the server's 50s timeout — even though every render succeeded
-- (which is why Lightroom still marked the photo as exported).
local RENDER_MAXDIM  = 1600
local RENDER_QUALITY = 80

-- Shared export helper: export active/specified photo, return file path only
local function exportPhoto(catalog, photo)
    logger:info("Exporting at " .. RENDER_MAXDIM .. "px q" .. RENDER_QUALITY .. " (single render)")
    local path = exportJpegSync(catalog, photo, RENDER_QUALITY, RENDER_MAXDIM)
    if not path then
        logger:info("exportJpegSync returned nil")
        return nil
    end
    local f = io.open(path, 'rb')
    local size = 0
    if f then size = f:seek('end'); f:close() end
    logger:info("Exported: " .. size .. " bytes q" .. RENDER_QUALITY .. " " .. RENDER_MAXDIM .. "px (Node fits under MCP limit)")
    return path
end

-- get_photo: image only, no metadata (server returns bare image block)
function MetadataHandler.getPhoto(args)
    local catalog = LrApplication.activeCatalog()
    local photo, err = lookupPhoto(catalog, args)
    if err then return { error = err } end
    if not photo then return { error = "No photo found" } end
    local path = exportPhoto(catalog, photo)
    if not path then return { error = "Export failed" } end
    return { imagePath = path, mimeType = "image/jpeg" }
end

-- analyze_raw_photo: return RAW file path — server extracts embedded JPEG and analyses
function MetadataHandler.analyzeRawPhoto(args)
    local catalog = LrApplication.activeCatalog()
    local photo, err = lookupPhoto(catalog, args)
    if err then return { error = err } end
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
    local photo, err = lookupPhoto(catalog, args)
    if err then return { error = err } end
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
