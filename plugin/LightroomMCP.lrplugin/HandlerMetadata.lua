local LrApplication = import 'LrApplication'
local LrLogger = import 'LrLogger'

local logger = LrLogger('LightroomMCP')

local MetadataHandler = {}

-- Make strings safe for JSON: forward-slash Windows paths, strip non-ASCII
local function sanitize(value)
    if type(value) ~= "string" then return value end
    value = value:gsub("\\", "/")         -- Windows paths: \ -> /
    return value:gsub("[^\32-\126]", "?") -- strip non-ASCII bytes
end

function MetadataHandler.getPhotoMetadata(args)
    if not args.photo_id then
        error("photo_id is required")
    end

    local catalog = LrApplication.activeCatalog()
    local photo = nil

    -- Try numeric local identifier first
    local numericId = tonumber(args.photo_id)
    if numericId then
        logger:info("Searching by numeric ID: " .. args.photo_id)
        catalog:withReadAccessDo(function()
            photo = catalog:findPhotoByLocalIdentifier(numericId)
        end)
    else
        -- Try as absolute file path
        logger:info("Trying findPhotoByPath...")
        photo = catalog:findPhotoByPath(args.photo_id)
        logger:info("findPhotoByPath result: " .. tostring(photo))

        -- Try by filename via findPhotos (native indexed search)
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

    local photoData = nil

    catalog:withReadAccessDo(function()
        -- Get keywords
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

    -- getDevelopSettings called outside withReadAccessDo
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

    logger:info("Retrieved metadata for photo: " .. args.photo_id)

    return photoData
end

return MetadataHandler
