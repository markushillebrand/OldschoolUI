-------------------------------------------------------------------------------
--  OUI_DamageMeter_Options.lua  --  Settings page for the Damage Meter
--  Most per-window settings (mode, segment, position, size) live in each
--  window's "M" menu; this page exposes the shared defaults across all windows.
-------------------------------------------------------------------------------

local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local L = OUI.L or function(s) return s end

-- accent section header (matches the Bags options pattern)
local function Header(page, text)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(280, 22)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont((OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT, 13, "")
    fs:SetPoint("LEFT", 2, 0)
    fs:SetText(L(text))
    if OUI.ACCENT then fs:SetTextColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b) end
    return row
end

-- greyed hint line
local function Note(page, text)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(280, 18)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont((OUI.GetFontPath and OUI.GetFontPath()) or STANDARD_TEXT_FONT, 11, "")
    fs:SetPoint("LEFT", 2, 0)
    fs:SetWidth(360)
    fs:SetJustifyH("LEFT")
    fs:SetText(L(text))
    fs:SetTextColor(0.6, 0.6, 0.6)
    return row
end

OUI:RegisterModule("OUI_DamageMeter", {
    title = L("Damage Meter"),
    build = function(page)
        page:AddRow(Header(page, "Damage Meter"))

        page:AddRow(OUI.Widgets.Toggle(page, {
            label = L("Lock all windows"),
            get = function() return _G.OldschoolUI_DM_GetLockedDefault and OldschoolUI_DM_GetLockedDefault() or false end,
            set = function(v) if _G.OldschoolUI_DM_SetLockedAll then OldschoolUI_DM_SetLockedAll(v) end end,
        }))

        page:AddRow(OUI.Widgets.Slider(page, {
            label = L("Max bars per window"), min = 3, max = 20, step = 1,
            get = function() return _G.OldschoolUI_DM_GetMaxBars and OldschoolUI_DM_GetMaxBars() or 8 end,
            set = function(v) if _G.OldschoolUI_DM_SetMaxBarsAll then OldschoolUI_DM_SetMaxBarsAll(v) end end,
        }))

        page:AddRow(Note(page, "Mode, segment, position and size are set per window via the \"M\" menu."))

        page:AddRow(OUI.Widgets.Button(page, {
            label = L("Reset Damage Meter"), width = 170,
            onClick = function()
                if OUI.ShowConfirmPopup then
                    OUI:ShowConfirmPopup({
                        title       = L("Reset Damage Meter"),
                        message     = L("This resets all Damage Meter windows and settings, then reloads your UI."),
                        confirmText = L("Reset"),
                        cancelText  = L("Cancel"),
                        onConfirm   = function() if _G.OldschoolUI_DM_ResetAll then OldschoolUI_DM_ResetAll() end end,
                    })
                elseif _G.OldschoolUI_DM_ResetAll then
                    OldschoolUI_DM_ResetAll()
                end
            end,
        }))
    end,
})
