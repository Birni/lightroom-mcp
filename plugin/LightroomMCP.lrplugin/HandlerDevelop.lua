local LrApplication = import 'LrApplication'
local LrDevelopController = import 'LrDevelopController'
local LrLogger = import 'LrLogger'

local logger = LrLogger('LightroomMCP')

local DevelopHandler = {}

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

-- MCP snake_case → SDK PascalCase
local PARAM_MAP = {
    -- Basic
    temperature             = "Temperature",
    tint                    = "Tint",
    exposure                = "Exposure2012",
    contrast                = "Contrast2012",
    highlights              = "Highlights2012",
    shadows                 = "Shadows2012",
    whites                  = "Whites2012",
    blacks                  = "Blacks2012",
    texture                 = "Texture",
    clarity                 = "Clarity2012",
    dehaze                  = "Dehaze",
    vibrance                = "Vibrance",
    saturation              = "Saturation",
    -- Tone Curve (parametric)
    tone_darks              = "ParametricDarks",
    tone_lights             = "ParametricLights",
    tone_shadows            = "ParametricShadows",
    tone_highlights         = "ParametricHighlights",
    tone_darks_split        = "ParametricDarksSplit",
    tone_midtone_split      = "ParametricMidtoneSplit",
    tone_highlights_split   = "ParametricHighlightsSplit",
    -- HSL — Hue
    hue_red                 = "HueAdjustmentRed",
    hue_orange              = "HueAdjustmentOrange",
    hue_yellow              = "HueAdjustmentYellow",
    hue_green               = "HueAdjustmentGreen",
    hue_aqua                = "HueAdjustmentAqua",
    hue_blue                = "HueAdjustmentBlue",
    hue_purple              = "HueAdjustmentPurple",
    hue_magenta             = "HueAdjustmentMagenta",
    -- HSL — Saturation
    sat_red                 = "SaturationAdjustmentRed",
    sat_orange              = "SaturationAdjustmentOrange",
    sat_yellow              = "SaturationAdjustmentYellow",
    sat_green               = "SaturationAdjustmentGreen",
    sat_aqua                = "SaturationAdjustmentAqua",
    sat_blue                = "SaturationAdjustmentBlue",
    sat_purple              = "SaturationAdjustmentPurple",
    sat_magenta             = "SaturationAdjustmentMagenta",
    -- HSL — Luminance
    lum_red                 = "LuminanceAdjustmentRed",
    lum_orange              = "LuminanceAdjustmentOrange",
    lum_yellow              = "LuminanceAdjustmentYellow",
    lum_green               = "LuminanceAdjustmentGreen",
    lum_aqua                = "LuminanceAdjustmentAqua",
    lum_blue                = "LuminanceAdjustmentBlue",
    lum_purple              = "LuminanceAdjustmentPurple",
    lum_magenta             = "LuminanceAdjustmentMagenta",
    -- Color Grading – hue/sat/balance via applyDevelopSettings (legacy SplitToning names)
    cg_shadow_hue           = "SplitToningShadowHue",
    cg_shadow_sat           = "SplitToningShadowSaturation",
    cg_highlight_hue        = "SplitToningHighlightHue",
    cg_highlight_sat        = "SplitToningHighlightSaturation",
    cg_balance              = "SplitToningBalance",
    -- Detail
    sharpness               = "Sharpness",
    sharpen_radius          = "SharpenRadius",
    sharpen_detail          = "SharpenDetail",
    sharpen_masking         = "SharpenEdgeMasking",
    noise_luminance         = "LuminanceSmoothing",
    noise_color             = "ColorNoiseReduction",
    -- Effects
    vignette_amount         = "PostCropVignetteAmount",
    vignette_midpoint       = "PostCropVignetteMidpoint",
    vignette_feather        = "PostCropVignetteFeather",
    vignette_roundness      = "PostCropVignetteRoundness",
    grain_amount            = "GrainAmount",
    grain_size              = "GrainSize",
    grain_roughness         = "GrainFrequency",
}

-- Color Grading params only accessible via LrDevelopController.setValue (not applyDevelopSettings)
local CG_CONTROLLER_MAP = {
    cg_shadow_lum           = "ColorGradeShadowLum",
    cg_highlight_lum        = "ColorGradeHighlightLum",
    cg_midtone_hue          = "ColorGradeMidtoneHue",
    cg_midtone_sat          = "ColorGradeMidtoneSat",
    cg_midtone_lum          = "ColorGradeMidtoneLum",
    cg_global_hue           = "ColorGradeGlobalHue",
    cg_global_sat           = "ColorGradeGlobalSat",
    cg_global_lum           = "ColorGradeGlobalLum",
    cg_blending             = "ColorGradeBlending",
}

function DevelopHandler.setDevelopSettings(args)
    local catalog = LrApplication.activeCatalog()
    local photo = lookupPhoto(catalog, args)
    if not photo then return { error = "No photo found" } end

    -- Auto tone/WB operate on the active photo in Develop module
    if args.auto_tone then
        LrDevelopController.setAutoTone()
        logger:info("setAutoTone called")
    end
    if args.auto_white_balance then
        LrDevelopController.setAutoWhiteBalance()
        logger:info("setAutoWhiteBalance called")
    end

    -- Build SDK settings table from provided args
    local settings = {}
    local applied = {}
    for mcpKey, sdkKey in pairs(PARAM_MAP) do
        if args[mcpKey] ~= nil then
            settings[sdkKey] = args[mcpKey]
            table.insert(applied, mcpKey .. "=" .. tostring(args[mcpKey]))
        end
    end

    if next(settings) then
        catalog:withWriteAccessDo("Set Develop Settings", function()
            photo:applyDevelopSettings(settings)
        end)
        logger:info("applyDevelopSettings: " .. table.concat(applied, ", "))
    end

    -- Color Grading Luminance + midtone/global params require LrDevelopController.setValue
    for mcpKey, sdkKey in pairs(CG_CONTROLLER_MAP) do
        if args[mcpKey] ~= nil then
            LrDevelopController.setValue(sdkKey, args[mcpKey])
            table.insert(applied, mcpKey .. "=" .. tostring(args[mcpKey]))
            logger:info("LrDevelopController.setValue: " .. sdkKey .. " = " .. tostring(args[mcpKey]))
        end
    end

    return {
        status = "ok",
        auto_tone = args.auto_tone or false,
        auto_white_balance = args.auto_white_balance or false,
        applied = applied,
    }
end

function DevelopHandler.resetDevelopSettings(args)
    local catalog = LrApplication.activeCatalog()
    local resetCrop = args and args.reset_crop

    -- Save crop before reset so it can be restored (default: protect crop)
    local savedCrop = nil
    if not resetCrop then
        local photo = catalog:getTargetPhoto()
        if photo then
            catalog:withReadAccessDo(function()
                local s = photo:getDevelopSettings()
                if s and s.HasCrop then
                    savedCrop = {
                        HasCrop    = s.HasCrop,
                        CropTop    = s.CropTop,
                        CropLeft   = s.CropLeft,
                        CropBottom = s.CropBottom,
                        CropRight  = s.CropRight,
                        CropAngle  = s.CropAngle,
                    }
                end
            end)
        end
    end

    LrDevelopController.resetAllDevelopAdjustments()
    logger:info("resetAllDevelopAdjustments called")

    -- Restore crop unless explicitly reset
    if savedCrop then
        local photo = catalog:getTargetPhoto()
        if photo then
            catalog:withWriteAccessDo("Restore Crop", function()
                photo:applyDevelopSettings(savedCrop)
            end)
            logger:info("Crop restored after reset")
        end
    end

    return { status = "ok", crop_reset = resetCrop and true or false }
end

function DevelopHandler.createSnapshot(args)
    if not args.name then return { error = "name is required" } end
    local catalog = LrApplication.activeCatalog()
    local photo = lookupPhoto(catalog, args)
    if not photo then return { error = "No photo found" } end

    local success = false
    catalog:withWriteAccessDo("Create Snapshot", function()
        success = photo:createDevelopSnapshot(args.name, false)
    end)

    return { status = success and "ok" or "failed", name = args.name }
end

function DevelopHandler.listSnapshots(args)
    local catalog = LrApplication.activeCatalog()
    local photo = lookupPhoto(catalog, args)
    if not photo then return { error = "No photo found" } end

    local snapshots = nil
    catalog:withReadAccessDo(function()
        snapshots = photo:getDevelopSnapshots()
    end)

    return { snapshots = snapshots or {} }
end

function DevelopHandler.applySnapshot(args)
    if not args.snapshot_id then return { error = "snapshot_id is required" } end
    local catalog = LrApplication.activeCatalog()
    local photo = lookupPhoto(catalog, args)
    if not photo then return { error = "No photo found" } end

    catalog:withWriteAccessDo("Apply Snapshot", function()
        photo:applyDevelopSnapshot(args.snapshot_id)
    end)

    return { status = "ok", snapshot_id = args.snapshot_id }
end

return DevelopHandler
