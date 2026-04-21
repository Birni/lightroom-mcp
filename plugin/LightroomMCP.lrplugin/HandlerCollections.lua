local LrApplication = import 'LrApplication'
local LrLogger = import 'LrLogger'

local logger = LrLogger('LightroomMCP')

local CollectionsHandler = {}

function CollectionsHandler.listCollections(args)
    local catalog = LrApplication.activeCatalog()
    local collectionsList = {}

    catalog:withReadAccessDo(function()
        local collections = catalog:getChildCollections()

        for _, collection in ipairs(collections) do
            table.insert(collectionsList, {
                name = collection:getName(),
                type = collection:type(),
                photoCount = #collection:getPhotos()
            })
        end

        -- Also get collection sets
        local collectionSets = catalog:getChildCollectionSets()
        for _, set in ipairs(collectionSets) do
            local function addCollectionsFromSet(collSet, prefix)
                local setCollections = collSet:getChildCollections()
                for _, coll in ipairs(setCollections) do
                    table.insert(collectionsList, {
                        name = prefix .. coll:getName(),
                        parent = collSet:getName(),
                        type = coll:type(),
                        photoCount = #coll:getPhotos()
                    })
                end

                local childSets = collSet:getChildCollectionSets()
                for _, childSet in ipairs(childSets) do
                    addCollectionsFromSet(childSet, prefix .. childSet:getName() .. " / ")
                end
            end

            addCollectionsFromSet(set, set:getName() .. " / ")
        end
    end)

    logger:info(string.format("Found %d collections", #collectionsList))

    return {
        count = #collectionsList,
        collections = collectionsList
    }
end

return CollectionsHandler
