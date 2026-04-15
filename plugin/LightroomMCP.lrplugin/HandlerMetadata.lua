local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrLogger = import 'LrLogger'

local logger = LrLogger('LightroomMCP')

local MetadataHandler = {}

local function base64Encode(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x)
        local r, byte = '', x:byte()
        for i = 8, 1, -1 do r = r .. (byte % 2^i - byte % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2^(6-i) or 0) end
        return b:sub(c+1, c+1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
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

-- Global state for thumbnail generation
local generatingThumbnails = {}

-- Helper: Generate JPEG thumbnail asynchronously
local function generateThumbnailAsync(photo, photoId)
    generatingThumbnails[photoId] = { status = "generating", data = nil }

    LrTasks.startAsyncTask(function()
        photo:requestJpegThumbnail(800, 800, function(jpegData)
            if jpegData and #jpegData > 0 then
                generatingThumbnails[photoId] = { status = "ready", data = jpegData }
                logger:info("Generated thumbnail for " .. photoId .. " (" .. #jpegData .. " bytes)")
            else
                generatingThumbnails[photoId] = { status = "error", data = nil }
                logger:info("Failed to generate thumbnail for " .. photoId)
            end
        end)
    end)
end

function MetadataHandler.getPhotoForReview(args)
    local catalog = LrApplication.activeCatalog()
    local photo

    if args and args.photo_id then
        local numericId = tonumber(args.photo_id)
        if numericId then
            catalog:withReadAccessDo(function()
                photo = catalog:findPhotoByLocalIdentifier(numericId)
            end)
        else
            photo = catalog:findPhotoByPath(args.photo_id)
            if not photo then
                local found = catalog:findPhotos({
                    searchDesc = { criteria = "filename", operation = "==", value = args.photo_id }
                })
                if found and #found > 0 then photo = found[1] end
            end
        end
    else
        photo = catalog:getTargetPhoto()
    end

    if not photo then
        return { error = "No photo found" }
    end

    local photoId = tostring(photo.localIdentifier)
    local metadata = buildPhotoData(catalog, photo)

    -- Check if thumbnail is already ready
    local thumbState = generatingThumbnails[photoId]
    if thumbState and thumbState.status == "ready" and thumbState.data then
        logger:info("Returning ready thumbnail for " .. photoId)
        return {
            imageData = base64Encode(thumbState.data),
            mimeType = "image/jpeg",
            metadata = metadata,
        }
    end

    -- If not ready, start generation and return immediately with empty data
    -- (getActivePhoto should have already started this, so it should be ready soon)
    logger:info("Thumbnail not ready yet for " .. photoId .. ", starting generation")
    generateThumbnailAsync(photo, photoId)

    return {
        imageData = nil,
        metadata = metadata,
        status = "thumbnail_not_ready",
    }
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
