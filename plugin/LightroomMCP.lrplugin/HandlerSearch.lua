local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrLogger = import 'LrLogger'

local logger = LrLogger('LightroomMCP')

local SearchHandler = {}

local function sanitize(value)
    if type(value) ~= "string" then return value end
    value = value:gsub("\\", "/")
    return value:gsub("[^\32-\126]", "?")
end

function SearchHandler.searchPhotos(args)
    local catalog = LrApplication.activeCatalog()

    -- Step 1: Use findPhotos only for criteria that work reliably (rating, filename)
    local indexedCriteria = {}

    if args.filename then
        table.insert(indexedCriteria, {
            criteria = "filename",
            operation = "contains",
            value = args.filename,
        })
    end

    if args.rating then
        table.insert(indexedCriteria, {
            criteria = "rating",
            operation = "==",
            value = args.rating,
        })
    end

    -- Convert ISO date string (YYYY-MM-DD) to Lightroom timestamp
    local function isoToLrTime(dateStr)
        local y, m, d = dateStr:match("(%d%d%d%d)-(%d%d)-(%d%d)")
        if y then
            return LrDate.timeFromComponents(tonumber(y), tonumber(m), tonumber(d), 0, 0, 0, 0)
        end
        return nil
    end

    local startTime = args.start_date and isoToLrTime(args.start_date) or nil
    local endTime   = args.end_date   and isoToLrTime(args.end_date)   or nil

    if #indexedCriteria == 0 and not startTime and not endTime and
       (not args.keywords or #args.keywords == 0) then
        return { error = "At least one search criterion is required (filename, rating, keywords, start_date, end_date)" }
    end

    -- Run findPhotos with indexed criteria, or fall back to all photos
    local candidatePhotos
    if #indexedCriteria > 0 then
        local searchDesc
        if #indexedCriteria == 1 then
            searchDesc = indexedCriteria[1]
        else
            searchDesc = indexedCriteria
            searchDesc.combine = "intersect"
        end
        candidatePhotos = catalog:findPhotos({ searchDesc = searchDesc })
    else
        -- No indexed criteria — load all photos and filter manually
        catalog:withReadAccessDo(function()
            candidatePhotos = catalog:getAllPhotos()
        end)
    end

    if not candidatePhotos or #candidatePhotos == 0 then
        logger:info("Search found 0 photos")
        return { count = 0, photos = {} }
    end

    -- Step 2: Manual post-filter for keywords and date range
    local results = {}
    local MAX_RESULTS = 500

    catalog:withReadAccessDo(function()
        for _, photo in ipairs(candidatePhotos) do
            if #results >= MAX_RESULTS then break end

            local match = true

            -- Filter by keywords
            if args.keywords and #args.keywords > 0 then
                local photoKeywords = photo:getRawMetadata('keywords')
                local kwNames = {}
                if photoKeywords then
                    for _, kw in ipairs(photoKeywords) do
                        kwNames[kw:getName():lower()] = true
                    end
                end
                for _, searchKw in ipairs(args.keywords) do
                    if not kwNames[searchKw:lower()] then
                        match = false
                        break
                    end
                end
            end

            -- Filter by date range
            if match and (startTime or endTime) then
                local captureTime = photo:getRawMetadata('dateTimeOriginal')
                if captureTime then
                    if startTime and captureTime < startTime then match = false end
                    if endTime   and captureTime > endTime   then match = false end
                else
                    match = false
                end
            end

            if match then
                table.insert(results, {
                    id = photo.localIdentifier,
                    path = sanitize(photo:getRawMetadata('path')),
                    filename = sanitize(photo:getFormattedMetadata('fileName')),
                    rating = photo:getRawMetadata('rating'),
                    dateTimeOriginal = sanitize(photo:getFormattedMetadata('dateTimeOriginal')),
                })
            end
        end
    end)

    logger:info(string.format("Search found %d photos", #results))

    return {
        count = #results,
        photos = results
    }
end

return SearchHandler
