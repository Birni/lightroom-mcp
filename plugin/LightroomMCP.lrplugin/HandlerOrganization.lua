local LrApplication = import 'LrApplication'
local LrLogger = import 'LrLogger'

local logger = LrLogger('LightroomMCP')

local OrganizationHandler = {}

-- Find a photo by ID, path, or filename (outside withWriteAccessDo)
local function findPhoto(catalog, photoId)
    local numericId = tonumber(photoId)
    if numericId then
        local photo = nil
        catalog:withReadAccessDo(function()
            photo = catalog:findPhotoByLocalIdentifier(numericId)
        end)
        return photo
    end

    -- Try absolute path
    local photo = catalog:findPhotoByPath(photoId)
    if photo then return photo end

    -- Try filename via findPhotos
    local found = catalog:findPhotos({
        searchDesc = {
            criteria = "filename",
            operation = "==",
            value = photoId,
        }
    })
    if found and #found > 0 then return found[1] end

    return nil
end

function OrganizationHandler.setKeywords(args)
    if not args.photo_ids or #args.photo_ids == 0 then
        return { error = "photo_ids is required" }
    end

    local catalog = LrApplication.activeCatalog()
    local updatedCount = 0

    -- Find all photos first (outside withWriteAccessDo — findPhotos/findPhotoByPath yield)
    local photos = {}
    for _, photoId in ipairs(args.photo_ids) do
        local photo = findPhoto(catalog, photoId)
        if photo then
            table.insert(photos, photo)
        else
            logger:info("Photo not found: " .. tostring(photoId))
        end
    end

    if #photos == 0 then
        return { error = "No photos found for the given IDs" }
    end

    catalog:withWriteAccessDo("Set Keywords", function()
        for _, photo in ipairs(photos) do
            -- Add keywords
            if args.add_keywords and #args.add_keywords > 0 then
                for _, kw in ipairs(args.add_keywords) do
                    photo:addKeyword(catalog:createKeyword(kw, {}, true, nil, true))
                end
            end

            -- Remove keywords
            if args.remove_keywords and #args.remove_keywords > 0 then
                local existingKeywords = photo:getRawMetadata('keywords')
                if existingKeywords then
                    for _, existingKw in ipairs(existingKeywords) do
                        for _, removeKw in ipairs(args.remove_keywords) do
                            if existingKw:getName() == removeKw then
                                photo:removeKeyword(existingKw)
                            end
                        end
                    end
                end
            end

            updatedCount = updatedCount + 1
        end
    end)

    logger:info(string.format("Updated keywords for %d photos", updatedCount))

    return {
        success = true,
        updated = updatedCount,
        message = string.format("Updated keywords for %d photos", updatedCount)
    }
end

function OrganizationHandler.setRating(args)
    if not args.photo_ids or #args.photo_ids == 0 then
        return { error = "photo_ids is required" }
    end

    if not args.rating then
        return { error = "rating is required" }
    end

    if args.rating < 0 or args.rating > 5 then
        return { error = "rating must be between 0 and 5" }
    end

    local catalog = LrApplication.activeCatalog()
    local updatedCount = 0

    -- Find all photos first (outside withWriteAccessDo)
    local photos = {}
    for _, photoId in ipairs(args.photo_ids) do
        local photo = findPhoto(catalog, photoId)
        if photo then
            table.insert(photos, photo)
        end
    end

    if #photos == 0 then
        return { error = "No photos found for the given IDs" }
    end

    catalog:withWriteAccessDo("Set Rating", function()
        for _, photo in ipairs(photos) do
            photo:setRawMetadata('rating', args.rating)
            updatedCount = updatedCount + 1
        end
    end)

    logger:info(string.format("Set rating to %d for %d photos", args.rating, updatedCount))

    return {
        success = true,
        updated = updatedCount,
        rating = args.rating,
        message = string.format("Set rating to %d for %d photos", args.rating, updatedCount)
    }
end

return OrganizationHandler
