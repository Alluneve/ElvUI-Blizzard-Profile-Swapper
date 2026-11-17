-- Associate each ElvUI profile with a Blizzard Edit Mode layout index.
-- Layout indices are positions in the combined Edit Mode list (presets + saved).
-- They are not permanent IDs: adding/removing layouts may change them.

local E = ElvUI[1]
local selectedProfile
local pendingLayout
local optionsAdded
local NONE = 0

local function Database()
    ElvProfileSwapperDB = ElvProfileSwapperDB or {}
    return ElvProfileSwapperDB
end

-- Unlike C_EditMode.GetLayouts().layouts, this list includes presets.
-- Its array indices match C_EditMode.SetActiveLayout(index).
local function GetLayouts()
    local manager = EditModeManagerFrame
    if manager and manager.GetLayouts then
        return manager:GetLayouts()
    end
end

-- Convert the v0.1.0 profile-name mappings to numeric layout indices once.
-- Normal lookup and selection are numeric-only afterward.
local function GetLayoutID(profile, layouts)
    local db = Database()
    local value = db[profile]
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" and layouts then
        for id, layout in ipairs(layouts) do
            if layout.layoutName == value then
                db[profile] = id
                return id
            end
        end
    end
end

local function ApplyLayout()
    if not E.data or not C_EditMode or not C_EditMode.GetLayouts
        or not C_EditMode.SetActiveLayout then return end

    local layouts = GetLayouts()
    if not layouts then return end

    local profile = E.data:GetCurrentProfile()
    local id = profile and GetLayoutID(profile, layouts)
    if not id or not layouts[id] then return end

    if InCombatLockdown() then
        pendingLayout = true
        return
    end
    pendingLayout = false

    if C_EditMode.GetLayouts().activeLayout ~= id then
        C_EditMode.SetActiveLayout(id)
    end
end

local function ScheduleLayout()
    -- ElvUI needs to finish applying its new profile first.
    C_Timer.After(0, ApplyLayout)
end

local function GetProfileChoices()
    local choices = {}
    if E.data then
        for _, profile in ipairs(E.data:GetProfiles()) do
            choices[profile] = profile
        end
    end
    return choices
end

local function GetLayoutChoices()
    local choices = { [NONE] = "None (do not switch)" }
    local layouts = GetLayouts()
    if layouts then
        for id, layout in ipairs(layouts) do
            -- Show saved layouts, not the built-in presets.
            if layout.layoutType ~= Enum.EditModeLayoutType.Preset then
                choices[id] = layout.layoutName
            end
        end
    end
    return choices
end

local function ChosenProfile()
    return selectedProfile or (E.data and E.data:GetCurrentProfile())
end

local function AddOptions()
    if optionsAdded or not E.Options or not E.Options.args then return end

    local profiles = E.Options.args.profiles
    local profileTab = profiles and profiles.args and profiles.args.profile
    if not profileTab or not profileTab.args then return end

    -- AceDBOptions shares its args table between Profile and Private.
    -- Copy the outer table to add controls only to the Profile tab.
    local args = {}
    for key, value in pairs(profileTab.args) do args[key] = value end
    profileTab.args = args

    args.autoBlizzEditMode = {
        type = "group",
        name = "Blizzard Edit Mode",
        inline = true,
        order = 1000,
        args = {
            description = {
                type = "description",
                name = "Link an ElvUI profile to a Blizzard Edit Mode layout. The layout will change whenever the ElvUI profile changes.",
                order = 1,
                width = "full",
            },
            elvuiProfile = {
                type = "select",
                name = "ElvUI profile",
                order = 2,
                width = "double",
                values = GetProfileChoices,
                get = function() return ChosenProfile() end,
                set = function(_, value) selectedProfile = value end,
            },
            editModeLayout = {
                type = "select",
                name = "Edit Mode layout",
                order = 3,
                width = "double",
                values = GetLayoutChoices,
                get = function()
                    local profile = ChosenProfile()
                    return (profile and GetLayoutID(profile, GetLayouts())) or NONE
                end,
                set = function(_, value)
                    local profile = ChosenProfile()
                    if not profile then return end
                    Database()[profile] = value ~= NONE and value or nil
                    if E.data and profile == E.data:GetCurrentProfile() then
                        ScheduleLayout()
                    end
                end,
            },
        },
    }

    optionsAdded = true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_LOGIN" then
        Database()
        if E.data then
            E.data:RegisterCallback("OnProfileChanged", ScheduleLayout)
        end
        AddOptions()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
        ScheduleLayout()
    elseif event == "ADDON_LOADED" and addon == "ElvUI_Options" then
        AddOptions()
    elseif event == "PLAYER_REGEN_ENABLED" and pendingLayout then
        ApplyLayout()
    end
end)
