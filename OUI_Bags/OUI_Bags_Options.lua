-- ===========================================================================
--  OldschoolUI -- Bags options (stub; fleshed out in Bags9)
-- ===========================================================================
local _, ns = ...
local OUI = OldschoolUI
if not (OUI and OUI.RegisterModule) then return end

local Bags = ns.Bags
local function DB() return (Bags and Bags.db and Bags.db.profile) or {} end
local function L(s) return (OUI.L and OUI.L(s)) or s end
local function Font() return (OUI.GetFontPath and OUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF" end

local function Header(page, text)
    local f = CreateFrame("Frame", nil, page)
    f:SetHeight(20)
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Font(), 13, "OUTLINE"); fs:SetPoint("LEFT", 0, 0)
    fs:SetText(L(text)); fs:SetTextColor(OUI.ACCENT.r, OUI.ACCENT.g, OUI.ACCENT.b)
    return f
end

local NUM_OPS      = { lt = "<", le = "<=", eq = "=", ge = ">=", gt = ">" }
local NUM_OP_ORDER = { "lt", "le", "eq", "ge", "gt" }
local NAME_OPS     = { contains = "contains", ncontains = "does not contain", begins = "begins with", ends = "ends with" }
local NAME_OP_ORDER= { "contains", "ncontains", "begins", "ends" }
local FIELD_LABELS = { itemlevel = "Item level", quality = "Quality", itemtype = "Type",
                       name = "Name", sellitem = "Sell value (per item)", sellstack = "Sell value (per stack)" }
local FIELD_ORDER  = { "itemlevel", "quality", "itemtype", "name", "sellitem", "sellstack" }
local QUAL_LABELS  = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare" }
local QUAL_ORDER   = { 0, 1, 2, 3 }
local TYPE_LABELS  = { [0] = "Consumable", [2] = "Weapon", [4] = "Armor", [7] = "Trade Goods",
                       [3] = "Gems", [16] = "Glyphs", [9] = "Recipes", [12] = "Quest", [15] = "Miscellaneous" }
local TYPE_ORDER   = { 0, 2, 4, 7, 3, 16, 9, 12, 15 }
local LOGIC_LABELS = { AND = "All conditions (AND)", OR = "Any condition (OR)", XOR = "Exactly one (XOR)" }
local LOGIC_ORDER  = { "AND", "OR", "XOR" }
local STRAT_LABELS = { all = "Sell whole stack", fullonly = "Only full stacks",
                       partialonly = "Only non-full stacks", keep = "Sell down to X kept" }
local STRAT_ORDER  = { "all", "fullonly", "partialonly", "keep" }

local function isNameField(f) return f == "name" end
local function isNumField(f)  return f == "itemlevel" or f == "sellitem" or f == "sellstack" end

-- text-entry popup (no text widget in the toolkit; used for name conditions + rename)
-- NOTE: never assign the global `StaticPopupDialogs` itself (e.g. `= ... or {}`):
-- writing the global from insecure code taints it, and Blizzard's secure code
-- (game-menu Logout/Quit -> StaticPopup_Show) reads it -> ADDON_ACTION_FORBIDDEN.
-- Only mutate a key; the table always exists in WoW.
StaticPopupDialogs["OUIBAGS_TEXTINPUT"] = {
    text = "%s", button1 = ACCEPT or "OK", button2 = CANCEL or "Cancel",
    hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self)
        local eb = self.EditBox or self.editBox
        if eb then eb:SetText(OUI._bagsTextDefault or ""); eb:HighlightText(); eb:SetFocus() end
    end,
    OnAccept = function(self)
        local eb = self.EditBox or self.editBox
        if OUI._bagsTextCB and eb then OUI._bagsTextCB(eb:GetText() or "") end
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        if OUI._bagsTextCB then OUI._bagsTextCB(self:GetText() or "") end
        if dialog and dialog.Hide then dialog:Hide() end
    end,
    EditBoxOnEscapePressed = function(self)
        local dialog = self:GetParent()
        if dialog and dialog.Hide then dialog:Hide() end
    end,
}
local function PromptText(prompt, default, cb)
    OUI._bagsTextCB, OUI._bagsTextDefault = cb, default or ""
    StaticPopup_Show("OUIBAGS_TEXTINPUT", prompt)
end

local function CondText(c)
    local f = L(FIELD_LABELS[c.field] or c.field)
    if c.field == "name" then
        return f .. " " .. L(NAME_OPS[c.op] or c.op) .. " \"" .. tostring(c.value or "") .. "\""
    end
    local op = NUM_OPS[c.op] or c.op
    local v
    if c.field == "quality" then v = L(QUAL_LABELS[c.value] or tostring(c.value))
    elseif c.field == "itemtype" then v = L(TYPE_LABELS[c.value] or tostring(c.value))
    else v = tostring(c.value) end
    return f .. " " .. op .. " " .. v
end

OUI:RegisterModule("OUI_Bags", {
    category    = "Main Modules", order = 40,
    title       = "Bags",
    description = "Enhanced bags, bank and guild bank. Use /ouibags to open, or /ouibags move to position.",
    build = function(page)
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Bag scale", min = 50, max = 150, step = 1,
            get = function() return math.floor((DB().bagScale or 1) * 100 + 0.5) end,
            set = function(v) DB().bagScale = v / 100; if Bags then Bags:ApplyScale() end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Columns", min = 6, max = 20, step = 1,
            get = function() return DB().bagColumns or 12 end,
            set = function(v) DB().bagColumns = v; if Bags and Bags.RebuildLayout then Bags:RebuildLayout() end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Stack count text size", min = 8, max = 20, step = 1,
            get = function() return DB().bagCountFontSize or 14 end,
            set = function(v) DB().bagCountFontSize = v; if Bags then Bags:RefreshFonts() end end,
        }))
        page:AddRow(OUI.Widgets.Dropdown(page, {
            label = "Sort order",
            values = { none = "Bag order", quality = "Quality", name = "Name", itemlevel = "Item level", type = "Type" },
            order = { "none", "quality", "name", "itemlevel", "type" },
            get = function() return DB().sortMode or "quality" end,
            set = function(v) DB().sortMode = v; if Bags then Bags:RebuildLayout() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show 'Pinned' category",
            get = function() return DB().showPinned ~= false end,
            set = function(v) DB().showPinned = v; if Bags then Bags:RebuildLayout() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show 'Recent' category",
            get = function() return DB().showRecent ~= false end,
            set = function(v) DB().showRecent = v; if Bags then Bags:RebuildLayout() end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Recent: keep for (minutes)", min = 5, max = 120, step = 5,
            get = function() return DB().recentMinutes or 30 end,
            set = function(v) DB().recentMinutes = v; if Bags then Bags:RebuildLayout() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show category sidebar",
            get = function() return DB().showCategorySidebar ~= false end,
            set = function(v) DB().showCategorySidebar = v; if Bags then Bags:RebuildLayout() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Hide empty categories",
            get = function() return DB().hideEmptyCategories ~= false end,
            set = function(v) DB().hideEmptyCategories = v; if Bags then Bags:RebuildLayout() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show item quality border",
            get = function() return DB().showQualityBorder ~= false end,
            set = function(v) DB().showQualityBorder = v; if Bags then Bags:RebuildLayout() end end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Show item level (gear)",
            get = function() return DB().showItemlevelInBags ~= false end,
            set = function(v) DB().showItemlevelInBags = v; if Bags then Bags:RebuildLayout() end end,
        }))
        page:AddRow(OUI.Widgets.Slider(page, {
            label = "Item level text size", min = 8, max = 20, step = 1,
            get = function() return DB().itemlevelFontSize or 12 end,
            set = function(v) DB().itemlevelFontSize = v; if Bags then Bags:RefreshFonts() end end,
        }))

        -- ---- Auto-sell ----
        local function rebuild() if OUI.SelectModule then OUI:SelectModule("OUI_Bags") end end
        local function AS() return DB().autoSell end

        page:AddRow(Header(page, "Auto-sell at merchant"))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Enable auto-sell",
            tooltip = "Sells matching items automatically when you open a vendor. Never sells pinned items or quality Epic and above.",
            get = function() return AS().enabled and true or false end,
            set = function(v) AS().enabled = v end,
        }))
        page:AddRow(OUI.Widgets.Toggle(page, {
            label = "Sell gray (poor) items",
            get = function() return AS().sellGray ~= false end,
            set = function(v) AS().sellGray = v end,
        }))

        local sets = AS().rulesets
        -- ruleset selector + add/rename/delete
        Bags._editRS = math.min(math.max(Bags._editRS or 1, 1), math.max(#sets, 1))
        if #sets > 0 then
            local names, order = {}, {}
            for i, rs in ipairs(sets) do names[i] = rs.name or ("Ruleset " .. i); order[i] = i end
            page:AddRow(OUI.Widgets.Dropdown(page, {
                label = "Edit ruleset", values = names, order = order,
                get = function() return Bags._editRS end,
                set = function(v) Bags._editRS = v; rebuild() end,
            }))
        end
        page:AddRow(OUI.Widgets.Button(page, {
            label = "New ruleset", width = 130,
            onClick = function()
                table.insert(sets, { name = "Ruleset " .. (#sets + 1), logic = "AND",
                                     strategy = { mode = "all", keep = 0 }, conditions = {} })
                Bags._editRS = #sets; rebuild()
            end,
        }))

        local rs = sets[Bags._editRS]
        if rs then
            page:AddRow(Header(page, (rs.name or ("Ruleset " .. Bags._editRS))))
            page:AddRow(OUI.Widgets.Button(page, {
                label = "Rename", width = 110,
                onClick = function() PromptText(L("Ruleset name"), rs.name, function(t)
                    if t ~= "" then rs.name = t end; rebuild() end) end,
            }))
            page:AddRow(OUI.Widgets.Button(page, {
                label = "Delete ruleset", width = 130,
                onClick = function() table.remove(sets, Bags._editRS); Bags._editRS = 1; rebuild() end,
            }))
            page:AddRow(OUI.Widgets.Dropdown(page, {
                label = "Combine conditions", values = LOGIC_LABELS, order = LOGIC_ORDER,
                get = function() return rs.logic or "AND" end,
                set = function(v) rs.logic = v end,
            }))
            rs.strategy = rs.strategy or { mode = "all", keep = 0 }
            page:AddRow(OUI.Widgets.Dropdown(page, {
                label = "Sell strategy", values = STRAT_LABELS, order = STRAT_ORDER,
                tooltip = "Full/non-full only apply to stackable items.",
                get = function() return rs.strategy.mode or "all" end,
                set = function(v) rs.strategy.mode = v; rebuild() end,
            }))
            if rs.strategy.mode == "keep" then
                page:AddRow(OUI.Widgets.Slider(page, {
                    label = "Keep at least (count)", min = 0, max = 200, step = 1,
                    get = function() return rs.strategy.keep or 0 end,
                    set = function(v) rs.strategy.keep = v end,
                }))
            end

            -- existing conditions (removable)
            for i = 1, #rs.conditions do
                local idx = i
                page:AddRow(OUI.Widgets.Button(page, {
                    label = CondText(rs.conditions[idx]) .. "    (" .. L("Remove") .. ")", width = 320,
                    onClick = function() table.remove(rs.conditions, idx); rebuild() end,
                }))
            end

            -- add-condition builder
            Bags._newCond = Bags._newCond or { field = "itemlevel", op = "le", value = 1 }
            local nc = Bags._newCond
            page:AddRow(Header(page, "Add condition"))
            page:AddRow(OUI.Widgets.Dropdown(page, {
                label = "Field", values = FIELD_LABELS, order = FIELD_ORDER,
                get = function() return nc.field end,
                set = function(v)
                    nc.field = v
                    if isNameField(v) then nc.op, nc.value = "contains", ""
                    elseif v == "quality" then nc.op, nc.value = "le", 0
                    elseif v == "itemtype" then nc.op, nc.value = "eq", 0
                    else nc.op, nc.value = "le", (v == "itemlevel" and 1 or 0) end
                    rebuild()
                end,
            }))
            if isNameField(nc.field) then
                page:AddRow(OUI.Widgets.Dropdown(page, {
                    label = "Operator", values = NAME_OPS, order = NAME_OP_ORDER,
                    get = function() return nc.op end, set = function(v) nc.op = v end,
                }))
                page:AddRow(OUI.Widgets.Button(page, {
                    label = (nc.value ~= "" and ("\"" .. nc.value .. "\"") or L("Set text...")), width = 220,
                    onClick = function() PromptText(L("Enter text to match"), nc.value, function(t) nc.value = t; rebuild() end) end,
                }))
            else
                page:AddRow(OUI.Widgets.Dropdown(page, {
                    label = "Operator", values = NUM_OPS, order = NUM_OP_ORDER,
                    get = function() return nc.op end, set = function(v) nc.op = v end,
                }))
                if nc.field == "itemlevel" then
                    page:AddRow(OUI.Widgets.Slider(page, {
                        label = "Value", min = 1, max = 600, step = 1,
                        get = function() return nc.value or 1 end, set = function(v) nc.value = v end,
                    }))
                elseif nc.field == "quality" then
                    page:AddRow(OUI.Widgets.Dropdown(page, {
                        label = "Value", values = QUAL_LABELS, order = QUAL_ORDER,
                        get = function() return nc.value or 0 end, set = function(v) nc.value = v end,
                    }))
                elseif nc.field == "itemtype" then
                    page:AddRow(OUI.Widgets.Dropdown(page, {
                        label = "Value", values = TYPE_LABELS, order = TYPE_ORDER,
                        get = function() return nc.value or 0 end, set = function(v) nc.value = v end,
                    }))
                else  -- sellitem / sellstack (copper)
                    page:AddRow(OUI.Widgets.Slider(page, {
                        label = "Value (copper)", min = 0, max = 500000, step = 100,
                        get = function() return nc.value or 0 end, set = function(v) nc.value = v end,
                    }))
                end
            end
            page:AddRow(OUI.Widgets.Button(page, {
                label = "Add condition", primary = true, width = 150,
                onClick = function()
                    table.insert(rs.conditions, { field = nc.field, op = nc.op, value = nc.value })
                    rebuild()
                end,
            }))
        end
    end,
})
