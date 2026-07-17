local ADDON, ns = ...
local SG = ns

local frame, tabs, content, activeTab, ticker
-- Tab A (Run detail)
local timerFS, gphFS, sessFS, coinFS, repairFS, netFS, durFS, breakdownFS, labelEdit, runBtn, pauseBtn, resetBtn
-- Tab B (Weekly)
local todayFS, weekFS, allFS, bars, chartLabel, bestRunFS, scopeBtn
-- Tab C (Grounds): run journal + farm-location intel, toggled by journalMode
local journalScroll, journalRows, journalToggleBtn, journalHdr, journalCatBtns
local journalMode = "runs"        -- "runs" | "locations" | "market"
local JROW_H, JMAX = 24, 12
-- Tab D (Gains): two side-by-side scrollable goods columns — vendor pile + AH goods,
-- plus a sell footer (this tab IS the #14 sell interface when you're at a merchant)
local gV, gA, gainsSellFS, gainsSellBtn, gainsUndoBtn
local GAINS_ROWS, GAINS_RH = 12, 22

-- Tab labels: Grind (current run) · Gold (earnings history) · Grounds (farm
-- locations/journal) · Gains (what this run gave you + where it goes: vendor / AH).
local TABS = { "Grind", "Gold", "Grounds", "Gains" }
local WIN_W, WIN_H = 460, 420   -- ALL tabs share one size (no jarring resize)

----------------------------------------------------------------------
-- Theme (dark / light)
----------------------------------------------------------------------
-- One shared DARK base (WoW's item quality colors only read well on dark, so we don't do a
-- light mode); each named theme just swaps the ACCENT family (border / active tab / buttons).
local BASE = {
  shadow = true, outline = true,
  bg = { 0.06, 0.06, 0.07, 0.94 },
  base = { 0.90, 0.90, 0.90 }, label = { 1.00, 0.82, 0.00 }, dim = { 0.55, 0.55, 0.55 },
  pop = { 1.00, 0.65, 0.20 },
  baseHex = "ffffff", goldHex = "ffd200", dimHex = "808080", redHex = "ff7070",
  tabOff = { 0.12, 0.12, 0.13, 0.90 }, tabOnText = { 1, 1, 1 }, tabOffText = { 0.7, 0.7, 0.7 },
  btnDim = { 0.20, 0.22, 0.22 }, barVend = { 0.62, 0.62, 0.62 },
}
-- Per-theme accent palettes. accent/accentHex = headers & highlights; border = window edge;
-- tabOn = active tab fill; btn/btnDown/btnText = buttons.
local THEMES = {
  Seafoam  = { accent = { 0.56, 0.84, 0.58 }, accentHex = "8fd694", border = { 0.20, 0.50, 0.30 }, tabOn = { 0.20, 0.50, 0.30, 0.85 }, btn = { 0.11, 0.26, 0.16 }, btnDown = { 0.07, 0.17, 0.10 }, btnText = { 0.65, 0.84, 0.71 } },
  Amethyst = { accent = { 0.78, 0.62, 0.96 }, accentHex = "c79ef5", border = { 0.40, 0.24, 0.60 }, tabOn = { 0.40, 0.20, 0.60, 0.85 }, btn = { 0.30, 0.16, 0.46 }, btnDown = { 0.20, 0.10, 0.32 }, btnText = { 0.86, 0.74, 1.00 } },
  Amber    = { accent = { 0.96, 0.80, 0.38 }, accentHex = "f5cc61", border = { 0.55, 0.42, 0.16 }, tabOn = { 0.50, 0.38, 0.14, 0.90 }, btn = { 0.42, 0.30, 0.10 }, btnDown = { 0.30, 0.21, 0.06 }, btnText = { 1.00, 0.90, 0.60 } },
  Crimson  = { accent = { 0.96, 0.52, 0.52 }, accentHex = "f58585", border = { 0.55, 0.20, 0.20 }, tabOn = { 0.50, 0.18, 0.18, 0.90 }, btn = { 0.40, 0.14, 0.14 }, btnDown = { 0.28, 0.09, 0.09 }, btnText = { 1.00, 0.78, 0.78 } },
  Steel    = { accent = { 0.58, 0.74, 0.96 }, accentHex = "94bcf5", border = { 0.24, 0.38, 0.58 }, tabOn = { 0.20, 0.34, 0.55, 0.90 }, btn = { 0.14, 0.24, 0.40 }, btnDown = { 0.09, 0.17, 0.29 }, btnText = { 0.78, 0.88, 1.00 } },
}
local THEME_ORDER = { "Seafoam", "Amethyst", "Amber", "Crimson", "Steel", "Class Color" }
function SG.ThemeList() return THEME_ORDER end

-- "Class Color" is computed from the player's class (guarded per the Secret-Value rules).
local function classColorTheme()
  local ok, _, class = pcall(UnitClass, "player")
  if not ok or not class then return nil end
  if issecretvalue and issecretvalue(class) then return nil end
  local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
            or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
  if not c then return nil end
  local function lite(x) return x + (1 - x) * 0.35 end
  return {
    accent = { lite(c.r), lite(c.g), lite(c.b) }, accentHex = c.GenerateHexColor and c:GenerateHexColor():sub(3) or "ffffff",
    border = { c.r * 0.55, c.g * 0.55, c.b * 0.55 }, tabOn = { c.r * 0.55, c.g * 0.55, c.b * 0.55, 0.9 },
    btn = { c.r * 0.32, c.g * 0.32, c.b * 0.32 }, btnDown = { c.r * 0.20, c.g * 0.20, c.b * 0.20 }, btnText = { lite(c.r), lite(c.g), lite(c.b) },
  }
end

local resolved   -- cached merged theme (BASE + chosen accent); rebuilt on theme change
local function resolveTheme()
  local s = TimeIsMoneyDB and TimeIsMoneyDB.settings
  local name = (s and s.theme) or "Seafoam"
  if name ~= "Class Color" and not THEMES[name] then      -- normalize legacy "dark"/"light" -> Seafoam
    name = "Seafoam"; if s then s.theme = name end
  end
  local t = (name == "Class Color" and classColorTheme()) or THEMES[name] or THEMES.Seafoam
  local out = {}
  for k, v in pairs(BASE) do out[k] = v end
  for k, v in pairs(t) do out[k] = v end
  resolved = out
end

function SG.Theme() if not resolved then resolveTheme() end; return resolved end

-- Register a FontString for theming with a role: "base" | "label" | "dim" | "accent" | "pop".
local themedFS = {}
local function TFS(fs, role) themedFS[#themedFS + 1] = { fs = fs, role = role or "base" }; return fs end

-- Restyle a UIPanelButtonTemplate button into a flat themed button (green fill, white text).
-- Replaces the default red art with WHITE8X8 swatches we vertex-color per theme in ApplyTheme.
local themedBtns = {}
-- Paint a styled button. Uses per-button overrides (b._bg / b._txt) when set, else theme green.
local function ColorButton(b, T)
  local bg   = b._bg   or T.btn
  local down = b._down or T.btnDown
  local txt  = b._txt  or T.btnText
  local n = b:GetNormalTexture();   if n then n:SetVertexColor(bg[1], bg[2], bg[3], 1) end
  local p = b:GetPushedTexture();   if p then p:SetVertexColor(down[1], down[2], down[3], 1) end
  local d = b:GetDisabledTexture(); if d then d:SetVertexColor(T.btnDim[1], T.btnDim[2], T.btnDim[3], 1) end
  local fs = b:GetFontString();     if fs then fs:SetTextColor(txt[1], txt[2], txt[3]) end
end
-- StyleButton(btn[, bg][, txt]): bg/txt are optional {r,g,b} overrides (0-1). Without them the
-- button follows the theme's green.
local function StyleButton(btn, bg, txt)
  if not btn then return btn end
  btn:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
  btn:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
  btn:SetDisabledTexture("Interface\\Buttons\\WHITE8X8")
  btn:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
  local hi = btn:GetHighlightTexture(); if hi then hi:SetVertexColor(1, 1, 1, 0.18) end
  if bg  then btn._bg = bg; btn._down = { bg[1] * 0.65, bg[2] * 0.65, bg[3] * 0.65 } end
  if txt then btn._txt = txt end
  themedBtns[#themedBtns + 1] = btn
  ColorButton(btn, SG.Theme())   -- color now so lazily-built buttons don't flash white pre-theme
  return btn
end

local function ApplyTheme()
  local T = SG.Theme()
  local function bd(f)
    if not f or not f.SetBackdropColor then return end
    f:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], T.bg[4])
    f:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
  end
  bd(frame); bd(ticker); bd(SG.sellFrame); bd(SG.configFrame)
  -- Shadows: the default dark font shadow reads as fuzz on the light background, so drop it
  -- in light mode; keep it in dark where it helps text pop.
  local sa = T.shadow and 0.9 or 0
  local sx, sy = (T.shadow and 1 or 0), (T.shadow and -1 or 0)
  local function shade(fs) if fs then fs:SetShadowColor(0, 0, 0, sa); fs:SetShadowOffset(sx, sy) end end
  for _, e in ipairs(themedFS) do
    local c = T[e.role] or T.base
    e.fs:SetTextColor(c[1], c[2], c[3])
    shade(e.fs)
  end
  -- Big timers: a black OUTLINE around dark digits muddies them on light; drop it there.
  if timerFS then timerFS:SetFont(STANDARD_TEXT_FONT, 44, T.outline and "OUTLINE" or "") end
  if ticker and ticker.timer then
    ticker.timer:SetFont(STANDARD_TEXT_FONT, 22, T.outline and "OUTLINE" or "")
    shade(ticker.timer); shade(ticker.gold); shade(ticker.gph)
  end
  if tabs then
    for j = 1, #tabs do
      local on = (j == activeTab)
      tabs[j].bg:SetColorTexture(unpack(on and T.tabOn or T.tabOff))
      local tc = on and T.tabOnText or T.tabOffText
      tabs[j].fs:SetTextColor(tc[1], tc[2], tc[3])
    end
  end
  for _, b in ipairs(themedBtns) do ColorButton(b, T) end
  if bars and T.barVend then                        -- weekly chart: darken the vendor bar for light mode
    for i = 1, #bars do
      if bars[i].vend then bars[i].vend:SetColorTexture(T.barVend[1], T.barVend[2], T.barVend[3], 0.95) end
    end
    if chartLabel then                              -- keep the legend swatches matching + readable
      local v = T.barVend
      local vHex = ("%02x%02x%02x"):format(math.floor(v[1] * 255 + 0.5), math.floor(v[2] * 255 + 0.5), math.floor(v[3] * 255 + 0.5))
      chartLabel:SetText(("Banked per day (last 7):  |cff%scoin|r  |cff%svendor|r  |cff4d94ffAH|r"):format(T.goldHex, vHex))
    end
  end
  if SG.RefreshUI then SG.RefreshUI() end
  if SG.RefreshConfig then SG.RefreshConfig() end   -- recolor the Options panel too, if it exists
end
SG.ApplyTheme = ApplyTheme

-- Set a theme by name (falls back to Seafoam if unknown).
function SG.SetTheme(name)
  local ok = (name == "Class Color")
  for _, n in ipairs(THEME_ORDER) do if n == name then ok = true end end
  SG.SetCharOpt("theme", ok and name or "Seafoam")   -- per-character
  resolveTheme()
  ApplyTheme()
  SG.Print("Theme = |cff" .. (SG.Theme().accentHex or "ffffff") .. (TimeIsMoneyDB.settings.theme) .. "|r")
end

-- Cycle to the next theme (used by the Options button and /tim theme).
function SG.CycleTheme()
  local cur = TimeIsMoneyDB.settings.theme or "Seafoam"
  local i = 1
  for n, name in ipairs(THEME_ORDER) do if name == cur then i = n end end
  SG.SetTheme(THEME_ORDER[(i % #THEME_ORDER) + 1])
end
SG.ToggleTheme = SG.CycleTheme   -- back-compat alias

-- Scale: the main panel and the floating widget size independently.
local function ApplyScale()
  local s = TimeIsMoneyDB and TimeIsMoneyDB.settings
  if frame  then frame:SetScale((s and s.uiScale) or 1.0) end
  if ticker then ticker:SetScale((s and s.tickerScale) or 1.0) end
end
SG.ApplyScale = ApplyScale

function SG.SetUIScale(arg)
  local n = tonumber(arg)
  if not n then
    SG.Print(("Window scale is %.2f. Set with /tim scale 0.6 - 1.6."):format(TimeIsMoneyDB.settings.uiScale or 1.0))
    return
  end
  TimeIsMoneyDB.settings.uiScale = math.max(0.6, math.min(1.6, n))
  ApplyScale()
  SG.Print(("Window scale = |cff8fd694%.2f|r"):format(TimeIsMoneyDB.settings.uiScale))
end

-- Floating-widget scale (also driven by the Options slider).
function SG.SetTickerScale(n)
  n = tonumber(n); if not n then return end
  TimeIsMoneyDB.settings.tickerScale = math.max(0.6, math.min(2.0, n))
  ApplyScale()
end

-- Tab C list. Two modes: "runs" (journal, newest first, per-run delete) and "locations"
-- (#15 - runs folded to one row per zone, best earners first, no delete).
local function RefreshJournal()
  if not journalRows then return end
  local T = SG.Theme()

  if journalToggleBtn then
    journalToggleBtn:SetText(journalMode == "runs" and "By location"
      or journalMode == "locations" and "By market" or "By run")
  end
  if journalHdr then
    journalHdr:SetText(
      journalMode == "runs"      and "Run journal - this character, newest first. Click x to delete."
      or journalMode == "locations" and "Farm locations - this character, best earners first (net · runs · gold/hour)."
      or "AH market - |cffffd200gold buttons are your professions|r. Thin + valuable mats = worth farming.")
  end

  -- Category buttons only show in market mode; the active source is disabled (segmented look);
  -- categories YOUR character can gather get a gold label (#15 professions-vs-selling).
  if journalCatBtns then
    local cat = SG.AHBrowseCategory and SG.AHBrowseCategory()
    local gathered = (journalMode == "market" and SG.GatherCategories and SG.GatherCategories()) or {}
    for _, b in ipairs(journalCatBtns) do
      b:SetShown(journalMode == "market")
      if (b.catKey or false) == (cat or false) then b:Disable() else b:Enable() end
      if b.catLabel then
        b:SetText((b.catKey and gathered[b.catKey]) and ("|cffffd200" .. b.catLabel .. "|r") or b.catLabel)
      end
    end
  end

  if journalMode == "market" then
    local cat = SG.AHBrowseCategory and SG.AHBrowseCategory()
    local mkt = cat and ((SG.AHBrowseResults and SG.AHBrowseResults()) or {})
                    or  ((SG.AHMarket and SG.AHMarket()) or {})
    if #mkt == 0 then
      FauxScrollFrame_Update(journalScroll, 0, JMAX, JROW_H)
      for i = 1, JMAX do
        local row = journalRows[i]; row.absIdx = nil; row.del:Hide()
        if i == 1 then
          row.text:SetText(cat
            and ("|cff808080Browsing the AH for %s...|r"):format(cat)
            or  "|cff808080Open the AH (auto-scans your bag mats), or pick a category above to search the market.|r")
          row:Show()
        else row:Hide() end
      end
      return
    end
    FauxScrollFrame_Update(journalScroll, #mkt, JMAX, JROW_H)
    local offset = FauxScrollFrame_GetOffset(journalScroll)
    for i = 1, JMAX do
      local row, e = journalRows[i], mkt[i + offset]
      row.absIdx = nil; row.del:Hide(); row.itemID = e and e.itemID or nil
      if e then
        local link = e.link
        if not link then
          if e.name then                                  -- browse result: name + quality from the AH
            local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality or 1]
            if c then
              link = ("|cff%02x%02x%02x%s|r"):format(
                math.floor((c.r or 1) * 255 + 0.5), math.floor((c.g or 1) * 255 + 0.5),
                math.floor((c.b or 1) * 255 + 0.5), e.name)
            else
              link = e.name
            end
          elseif e.itemID then
            local n, l = C_Item.GetItemInfo(e.itemID); link = l or n or ("item:" .. e.itemID)
          end
        end
        local price, qty = e.unit or e.minPrice or 0, e.qty or 0
        local rate
        if qty <= 0      then rate = "|cff808080none listed|r"
        elseif qty < 50  then rate = "|cff40ff40thin|r"
        elseif qty < 500 then rate = "|cffffd200moderate|r"
        else                  rate = "|cffff7070saturated|r" end
        row.text:SetText(("%s   |cff%s%s|r   |cff808080%d up · %s|r"):format(
          link or "?", T.goldHex, SG.Money(price), qty, rate))
        row:Show()
      else
        row:Hide()
      end
    end
    return
  end

  if journalMode == "locations" then
    local locs = (SG.RunLocations and SG.RunLocations()) or {}
    FauxScrollFrame_Update(journalScroll, #locs, JMAX, JROW_H)
    local offset = FauxScrollFrame_GetOffset(journalScroll)
    for i = 1, JMAX do
      local row, e = journalRows[i], locs[i + offset]
      row.absIdx = nil; row.del:Hide()
      if e then
        row.text:SetText(("|cff%s%s|r   net %s   |cff808080%d run%s · %s/hr|r"):format(
          T.goldHex, e.zone, SG.Money(e.net or 0), e.count, e.count == 1 and "" or "s", SG.Money(e.gph or 0)))
        row:Show()
      else
        row:Hide()
      end
    end
    return
  end

  local runs = (SG.GetRuns and SG.GetRuns()) or {}
  local total = #runs
  FauxScrollFrame_Update(journalScroll, total, JMAX, JROW_H)
  local offset = FauxScrollFrame_GetOffset(journalScroll)
  for i = 1, JMAX do
    local row = journalRows[i]
    local absIdx = total - (i + offset - 1)   -- newest first
    local r = runs[absIdx]
    if r and absIdx >= 1 then
      row.absIdx = absIdx; row.del:Show()
      row.text:SetText(("|cff%s%s|r   net %s   |cff808080%s · %s|r"):format(
        T.goldHex, r.label or "Run", SG.Money(r.net or 0),
        (SG.FmtDuration and SG.FmtDuration(r.dur or 0)) or "", (r.zone ~= "" and r.zone) or "?"))
      row:Show()
    else
      row.absIdx = nil; row.del:Hide(); row:Hide()
    end
  end
end

local RefreshGains   -- forward declaration: the column scroll handlers call it

-- Compact, text-only money for the narrow Gains rows: just the largest unit (e.g. "422g",
-- "24s", "8c") so the value never collides with the item name the way coin icons do.
local function CoinText(copper)
  copper = math.floor(copper or 0)
  if copper >= 10000 then return ("%dg"):format(math.floor(copper / 10000)) end
  if copper >= 100   then return ("%ds"):format(math.floor(copper / 100)) end
  return ("%dc"):format(copper)
end

-- A small "copy this text" popup (addons can't open a browser, so we hand you a selectable URL).
local copyDlg
local function ShowCopyLink(text)
  if not copyDlg then
    local d = CreateFrame("Frame", "TimeIsMoneyCopyDialog", UIParent, "BackdropTemplate")
    d:SetSize(430, 98); d:SetPoint("CENTER"); d:SetFrameStrata("FULLSCREEN_DIALOG"); d:SetToplevel(true)
    d:EnableMouse(true); d:SetMovable(true); d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving); d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    local T = SG.Theme()
    d:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.98)
    d:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    d.title = TFS(d:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "accent")
    d.title:SetPoint("TOP", 0, -12); d.title:SetText("Press Ctrl+C to copy (closes automatically), then paste in your browser")
    d.edit = CreateFrame("EditBox", nil, d, "BackdropTemplate")
    d.edit:SetSize(402, 26); d.edit:SetPoint("TOP", 0, -38); d.edit:SetAutoFocus(true)
    d.edit:SetFontObject(ChatFontNormal); d.edit:SetTextColor(1, 1, 1); d.edit:SetTextInsets(6, 6, 0, 0)
    d.edit:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    d.edit:SetBackdropColor(0, 0, 0, 0.6); d.edit:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    d.edit:SetScript("OnEscapePressed", function() d:Hide() end)
    d.edit:SetScript("OnEnterPressed", function() d:Hide() end)
    -- Auto-close right after Ctrl+C: give the client a moment to put the text on the clipboard.
    d.edit:SetScript("OnKeyDown", function(self, key)
      if key == "C" and IsControlKeyDown() then C_Timer.After(0.1, function() if copyDlg then copyDlg:Hide() end end) end
    end)
    local close = StyleButton(CreateFrame("Button", nil, d, "UIPanelButtonTemplate"))
    close:SetSize(80, 22); close:SetPoint("BOTTOM", 0, 10); close:SetText("Close")
    close:SetScript("OnClick", function() d:Hide() end)
    d:Hide(); copyDlg = d
  end
  copyDlg:Show()
  copyDlg.edit:SetText(text)
  copyDlg.edit:SetCursorPosition(0); copyDlg.edit:HighlightText(); copyDlg.edit:SetFocus()
end

-- Tab D (Gains): build one scrollable goods column — a header + a FauxScrollFrame of item rows.
-- Rows are clickable: left = keep this visit (vendor column), right = per-item rule menu,
-- shift = link, hover = tooltip. isVendor gates the keep-toggle behavior.
local function BuildGoodsColumn(parent, x, w, scrollName, isVendor)
  local sec = { rows = {}, isVendor = isVendor }
  sec.hdr = TFS(parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), "accent")
  sec.hdr:SetPoint("TOPLEFT", x, -8); sec.hdr:SetWidth(w); sec.hdr:SetJustifyH("LEFT")

  sec.scroll = CreateFrame("ScrollFrame", scrollName, parent, "FauxScrollFrameTemplate")
  sec.scroll:SetPoint("TOPLEFT", x, -28)
  sec.scroll:SetSize(w, GAINS_ROWS * GAINS_RH)
  sec.scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, GAINS_RH, RefreshGains)
  end)

  for i = 1, GAINS_ROWS do
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(GAINS_RH)
    row:SetPoint("TOPLEFT", sec.scroll, "TOPLEFT", 0, -(i - 1) * GAINS_RH)
    row:SetPoint("TOPRIGHT", sec.scroll, "TOPRIGHT", 0, -(i - 1) * GAINS_RH)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(14, 14); row.icon:SetPoint("LEFT", 2, 0)
    row.text = TFS(row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "base")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0); row.text:SetPoint("RIGHT", -40, 0)
    row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false); row.text:SetFont(STANDARD_TEXT_FONT, 11)
    row.val = TFS(row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "dim")
    row.val:SetPoint("RIGHT", -4, 0); row.val:SetFont(STANDARD_TEXT_FONT, 11); row.val:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", function(self)
      if self.e then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.e.link); GameTooltip:Show() end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self, button)
      local e = self.e; if not e then return end
      if HandleModifiedItemClick and HandleModifiedItemClick(e.link) then return end  -- shift-link, ctrl-dress, etc.
      if button == "RightButton" then SG.SellRuleMenu(self, e.link); return end
      if sec.isVendor and SG.SellToggleKeep then SG.SellToggleKeep(e); RefreshGains() end
    end)
    sec.rows[i] = row
  end

  sec.empty = TFS(parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "dim")
  sec.empty:SetPoint("TOPLEFT", sec.scroll, "TOPLEFT", 2, -2); sec.empty:SetWidth(w); sec.empty:SetJustifyH("LEFT")
  return sec
end

-- Fill one scrollable column from a scanned goods list (bag order), honoring its scroll offset.
local function FillGoods(sec, list, total, label, emptyMsg)
  if not sec then return end
  local T = SG.Theme()
  sec.hdr:SetText(("%s  |cff%s%s|r"):format(label, T.goldHex, CoinText(total or 0)))
  local n = #list
  FauxScrollFrame_Update(sec.scroll, n, GAINS_ROWS, GAINS_RH)
  local offset = FauxScrollFrame_GetOffset(sec.scroll)
  for i = 1, GAINS_ROWS do
    local row, e = sec.rows[i], list[i + offset]
    row.e = e
    if e then
      local cnt = (e.count or 1) > 1 and ("|cff808080 x%d|r"):format(e.count) or ""
      row.icon:SetTexture(select(10, C_Item.GetItemInfo(e.link)) or 134400)
      row.text:SetText((e.link or "?") .. cnt)
      if sec.isVendor and SG.SellIsKept and SG.SellIsKept(e) then
        row.val:SetText("|cffff7070keep|r"); row:SetAlpha(0.45)   -- excluded from Sell All this visit
      else
        local shown = CoinText(e.value or 0)
        -- At the AH, each AH-good "upgrades" from its estimate to the recommended POST price
        -- (the undercut of the live scanned lowest), shown in gold - the number to list at.
        if not sec.isVendor and SG.AtAuctionHouse and SG.AtAuctionHouse() then
          local itemID = tonumber((e.link or ""):match("|Hitem:(%d+):"))
          local post = itemID and SG.AHPostPrice and SG.AHPostPrice(itemID)
          if post then shown = "|cffffd200" .. CoinText(post) .. "|r" end
        end
        row.val:SetText(shown); row:SetAlpha(1)
      end
      row:Show()
    else
      row:Hide()
    end
  end
  sec.empty:SetText(emptyMsg or ""); sec.empty:SetShown(n == 0)
end

-- Rescan bags, refill both columns, and drive the sell footer. Each column honors its offset.
RefreshGains = function()
  if not gV then return end
  local r = SG.ScanSellables and SG.ScanSellables()
  if not r then return end
  FillGoods(gV, r.vendor, r.totalVendor, "Vendor",     "Nothing to vendor.")
  FillGoods(gA, r.ah,     r.totalAH,     "Sell on AH", "Nothing to list.")

  if gainsSellFS then
    local atM  = SG.AtMerchant and SG.AtMerchant()
    local atAH = SG.AtAuctionHouse and SG.AtAuctionHouse()
    if atAH then                                   -- AH context: show post prices (posting is
      -- blocked by the client, so this is a price helper - list by hand at the gold numbers)
      gainsSellFS:SetText("|cffffd200Gold = post price|r (undercut) - list these by hand")
      gainsSellBtn:SetText("Rescan"); gainsSellBtn:SetEnabled(true)
      gainsUndoBtn:SetEnabled(false)
    elseif atM then                                -- merchant context: sell the vendor pile
      local n, total = 0, 0
      if SG.SellSummary then n, total = SG.SellSummary(r) end
      gainsSellFS:SetText(("Will sell |cffffffff%d|r for ~|cff8fd694%s|r"):format(n, CoinText(total)))
      gainsSellBtn:SetText("Sell All"); gainsSellBtn:SetEnabled(n > 0)
      local bb = (GetNumBuybackItems and GetNumBuybackItems()) or 0
      gainsUndoBtn:SetEnabled(bb > 0)
    else
      gainsSellFS:SetText("|cff808080Visit a merchant or the Auction House|r")
      gainsSellBtn:SetText("Sell / Post"); gainsSellBtn:SetEnabled(false)
      gainsUndoBtn:SetEnabled(false)
    end
  end
end

StaticPopupDialogs["TIMEISMONEY_RESET"] = {
  text = "Time Is Money: clear all tracked data?",
  button1 = YES, button2 = NO,
  OnAccept = function() SG.ResetData() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Run Journal (#16): a fully custom "name this run" dialog (StaticPopup's editbox/data
-- callbacks are unreliable across retail versions, so we own the whole thing).
local labelDlg
local function BuildLabelDialog()
  if labelDlg then return end
  local d = CreateFrame("Frame", "TimeIsMoneyLabelDialog", UIParent, "BackdropTemplate")
  d:SetSize(330, 128); d:SetPoint("CENTER"); d:SetFrameStrata("DIALOG"); d:SetToplevel(true)
  d:EnableMouse(true); d:SetMovable(true); d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving); d:SetScript("OnDragStop", d.StopMovingOrSizing)
  d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  local T = SG.Theme()
  d:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.98)
  d:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

  d.title = TFS(d:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "accent")
  d.title:SetPoint("TOP", 0, -14); d.title:SetText("Name this run")

  d.edit = CreateFrame("EditBox", nil, d, "BackdropTemplate")
  d.edit:SetSize(292, 26); d.edit:SetPoint("TOP", 0, -42)
  d.edit:SetAutoFocus(false)
  d.edit:SetFontObject(ChatFontNormal)
  d.edit:SetTextColor(1, 1, 1)
  d.edit:SetTextInsets(6, 6, 0, 0)
  d.edit:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  d.edit:SetBackdropColor(0, 0, 0, 0.6)
  d.edit:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

  local function commit()
    if d.rec then d.rec.label = d.edit:GetText(); SG.SaveRun(d.rec) end
    d.rec = nil; d:Hide()
  end
  local function skip()
    if d.rec then SG.SaveRun(d.rec) end   -- log the run with its default label
    d.rec = nil; d:Hide()
  end
  d.commit, d.skip = commit, skip

  d.edit:SetScript("OnEnterPressed", commit)
  d.edit:SetScript("OnEscapePressed", skip)
  -- Select-all only once the user deliberately clicks in, so a single keystroke replaces the
  -- suggestion. We never auto-focus (see PromptRunLabel) - that would eat movement keys.
  d.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

  d.hint = TFS(d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "dim")
  d.hint:SetPoint("TOP", 0, -72); d.hint:SetText("Click the box to rename · Save keeps it")

  local save = StyleButton(CreateFrame("Button", nil, d, "UIPanelButtonTemplate"))
  save:SetSize(94, 22); save:SetPoint("BOTTOMRIGHT", -14, 12); save:SetText("Save"); save:SetScript("OnClick", commit)
  local skipB = StyleButton(CreateFrame("Button", nil, d, "UIPanelButtonTemplate"))
  skipB:SetSize(94, 22); skipB:SetPoint("BOTTOMLEFT", 14, 12); skipB:SetText("Skip"); skipB:SetScript("OnClick", skip)

  d:Hide()
  labelDlg = d
end

function SG.PromptRunLabel(rec)
  BuildLabelDialog()
  local pre = rec.label   -- what the user typed in the Run Label field, if anything
  if not pre or pre == "" then pre = SG.SuggestRunLabel and SG.SuggestRunLabel(rec) end
  if not pre or pre == "" then pre = (rec.zone ~= "" and rec.zone) or "Run" end
  labelDlg.rec = rec
  labelDlg:Show()
  labelDlg.edit:SetText(pre)
  labelDlg.edit:SetCursorPosition(#pre)
  -- Deliberately NO SetFocus/HighlightText here: if the run ends mid-move, an auto-focused box
  -- swallows the held movement key ("wwww…"). The suggestion shows unfocused; Save accepts it
  -- as-is, or the user clicks in to rename (which then selects-all via OnEditFocusGained).
  labelDlg.edit:ClearFocus()
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function StatRow(parent, label, y)
  local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  l:SetPoint("TOPLEFT", 14, y)
  l:SetText(label); l:SetFont(STANDARD_TEXT_FONT, 15); TFS(l, "label")
  local v = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  v:SetPoint("TOPRIGHT", -14, y)
  v:SetJustifyH("RIGHT"); v:SetFont(STANDARD_TEXT_FONT, 15); TFS(v, "base")
  return v
end

local function FmtClock(sec)
  sec = math.max(0, math.floor(sec or 0))
  if sec >= 3600 then
    return ("%d:%02d:%02d"):format(math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60)
  end
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

local function GetFarmLabel()
  local zone = GetRealZoneText()
  if not zone or zone == "" then zone = GetZoneText() end
  if not zone or zone == "" then zone = "Unknown" end
  local _, itype = IsInInstance()
  if itype == "party" then return zone .. " \194\183 Dungeon"
  elseif itype == "raid" then return zone .. " \194\183 Raid"
  elseif itype == "scenario" then return zone .. " \194\183 Scenario"
  elseif itype == "arena" or itype == "pvp" then return zone .. " \194\183 PvP" end
  return zone
end
SG.GetFarmLabel = GetFarmLabel

local function Short(c) return (SG.MoneyShort or SG.Money)(c) end

local function GPHText()
  local txt = Short(SG.SessionGPH()) .. "/hr"
  if not SG.RunActive() then txt = "|cff" .. SG.Theme().dimHex .. txt .. "|r" end
  return txt
end

----------------------------------------------------------------------
-- Detachable floating run timer widget
----------------------------------------------------------------------
local function SaveTickerPos()
  if not ticker then return end
  local p, _, _, x, y = ticker:GetPoint()
  if TimeIsMoneyDB and TimeIsMoneyDB.settings then TimeIsMoneyDB.settings.tickerPos = { p, x, y } end
end

local function RefreshTicker()
  if not ticker then return end
  local T = SG.Theme()
  ticker.timer:SetTextColor(T.base[1], T.base[2], T.base[3])
  ticker.gold:SetTextColor(T.base[1], T.base[2], T.base[3])
  ticker.gph:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
  ticker.timer:SetText(FmtClock(SG.RunElapsed()))
  ticker.gold:SetText(("This run: |cff" .. T.accentHex .. "%s|r"):format(Short(SG.SessionValue())))
  ticker.gph:SetText(GPHText())
  ticker.runBtn:SetText(SG.RunActive() and "|cffffd200Stop|r" or "Start")
  ticker.pauseBtn:SetText(SG.RunPaused() and "Resume" or "Pause")
  ticker.pauseBtn:SetEnabled(SG.RunActive())
end

local function BuildTicker()
  if ticker then return end
  ticker = CreateFrame("Frame", "TimeIsMoneyTicker", UIParent, "BackdropTemplate")
  ticker:SetSize(176, 110)
  ticker:SetFrameStrata("FULLSCREEN_DIALOG")   -- always-on-top HUD widget
  ticker:SetToplevel(true)
  local pos = TimeIsMoneyDB and TimeIsMoneyDB.settings and TimeIsMoneyDB.settings.tickerPos
  if pos then ticker:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else ticker:SetPoint("TOP", 0, -220) end
  ticker:SetMovable(true); ticker:EnableMouse(true); ticker:RegisterForDrag("LeftButton")
  ticker:SetScript("OnDragStart", ticker.StartMoving)
  ticker:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveTickerPos() end)
  ticker:SetClampedToScreen(true)
  ticker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  local T = SG.Theme()
  ticker:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], T.bg[4])
  ticker:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

  ticker.close = CreateFrame("Button", nil, ticker)
  ticker.close:SetSize(16, 16); ticker.close:SetPoint("TOPRIGHT", -3, -3)
  ticker.close.x = TFS(ticker.close:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "dim")
  ticker.close.x:SetPoint("CENTER"); ticker.close.x:SetText("x")
  do local T = SG.Theme(); ticker.close.x:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end
  ticker.close:SetScript("OnClick", function() SG.ToggleTicker() end)  -- hides + remembers closed
  ticker.close:SetScript("OnEnter", function(self) self.x:SetTextColor(1, 0.35, 0.35) end)  -- red on hover
  ticker.close:SetScript("OnLeave", function(self)
    local T = SG.Theme(); self.x:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
  end)

  ticker.timer = ticker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ticker.timer:SetPoint("TOP", -6, -6); ticker.timer:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
  ticker.gold = ticker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ticker.gold:SetPoint("TOP", ticker.timer, "BOTTOM", 0, -4)
  ticker.gold:SetFont(STANDARD_TEXT_FONT, 15)
  ticker.gph = ticker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ticker.gph:SetPoint("TOP", ticker.gold, "BOTTOM", 0, -2)

  ticker.runBtn = StyleButton(CreateFrame("Button", nil, ticker, "UIPanelButtonTemplate"))
  ticker.runBtn:SetSize(80, 20); ticker.runBtn:SetPoint("BOTTOMLEFT", 6, 6)
  ticker.runBtn:SetText("Start"); ticker.runBtn:SetScript("OnClick", function() SG.ToggleRun() end)
  ticker.pauseBtn = StyleButton(CreateFrame("Button", nil, ticker, "UIPanelButtonTemplate"))
  ticker.pauseBtn:SetSize(80, 20); ticker.pauseBtn:SetPoint("BOTTOMRIGHT", -6, 6)
  ticker.pauseBtn:SetText("Pause"); ticker.pauseBtn:SetScript("OnClick", function() SG.PauseRun() end)

  ticker:SetScript("OnUpdate", function(self, e)
    self._t = (self._t or 0) + e
    if self._t > 0.4 then self._t = 0; RefreshTicker() end
  end)
  ticker:Hide()
  ApplyTheme()   -- theme the freshly-built widget (font outline/shadow/colors)
  ApplyScale()
end

function SG.ToggleTicker()
  BuildTicker()
  if ticker:IsShown() then ticker:Hide() else ticker:Show(); RefreshTicker() end
  if TimeIsMoneyDB and TimeIsMoneyDB.settings then TimeIsMoneyDB.settings.tickerShown = ticker:IsShown() end
end

----------------------------------------------------------------------
-- Tab switching (no resize - all tabs share one size)
----------------------------------------------------------------------
local function SelectTab(i)
  activeTab = i
  local T = SG.Theme()
  for j = 1, #TABS do
    content[j]:SetShown(j == i)
    local on = (j == i)
    tabs[j].bg:SetColorTexture(unpack(on and T.tabOn or T.tabOff))
    local tc = on and T.tabOnText or T.tabOffText
    tabs[j].fs:SetTextColor(tc[1], tc[2], tc[3])
  end
  SG.RefreshUI()
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
function SG.InitUI()
  if frame then return end

  frame = CreateFrame("Frame", "TimeIsMoneyFrame", UIParent, "BackdropTemplate")
  frame:SetSize(WIN_W, WIN_H)
  frame:SetPoint("CENTER")
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  frame:Hide()

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("Time Is Money")
  TFS(title, "accent")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  tabs = {}
  local TAB_W, TAB_GAP = 80, 15
  local tabStartX = (WIN_W - (#TABS * TAB_W + (#TABS - 1) * TAB_GAP)) / 2   -- centered as a group
  for i = 1, #TABS do
    local t = CreateFrame("Button", nil, frame)
    t:SetSize(TAB_W, 24)
    t:SetPoint("TOPLEFT", tabStartX + (i - 1) * (TAB_W + TAB_GAP), -27)
    local bg = t:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.12, 0.12, 0.13, 0.90)
    local fs = t:CreateFontString(nil, "OVERLAY", "GameFontNormal"); fs:SetAllPoints(); fs:SetText(TABS[i])
    fs:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")   -- bold + larger so the tab labels read clearly
    t.bg, t.fs = bg, fs
    t:SetScript("OnClick", function() SelectTab(i) end)
    tabs[i] = t
  end

  content = {}
  for i = 1, #TABS do
    local c = CreateFrame("Frame", nil, frame)
    c:SetPoint("TOPLEFT", 6, -54)
    c:SetPoint("BOTTOMRIGHT", -6, 6)
    c:Hide()
    content[i] = c
  end

  ------------------------------------------------------------------
  -- Tab A: detailed run info
  ------------------------------------------------------------------
  local cA = content[1]

  local instBtn = StyleButton(CreateFrame("Button", nil, cA, "UIPanelButtonTemplate"))
  instBtn:SetSize(110, 20); instBtn:SetPoint("TOPLEFT", 4, -4)
  instBtn:SetText("Reset Instances")
  instBtn:SetScript("OnClick", function() SG.ResetInstances() end)
  instBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Reset dungeon instances")
    GameTooltip:AddLine("Clears dungeon lockouts so you can re-run a farm.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Outside the instance, out of combat. Saved raids unaffected.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  instBtn:SetScript("OnLeave", GameTooltip_Hide)

  local tickBtn = StyleButton(CreateFrame("Button", nil, cA, "UIPanelButtonTemplate"))
  tickBtn:SetSize(104, 20); tickBtn:SetPoint("TOPRIGHT", -4, -4)
  tickBtn:SetText("Floating Timer")
  tickBtn:SetScript("OnClick", function() SG.ToggleTicker() end)
  tickBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Detach a floating run timer")
    GameTooltip:AddLine("A small movable widget (timer + gold + GPH) to keep on screen while you farm.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  tickBtn:SetScript("OnLeave", GameTooltip_Hide)

  labelEdit = CreateFrame("EditBox", nil, cA, "InputBoxTemplate")
  labelEdit:SetSize(150, 20)
  labelEdit:SetPoint("LEFT", instBtn, "RIGHT", 16, 0)
  labelEdit:SetPoint("RIGHT", tickBtn, "LEFT", -14, 0)
  labelEdit:SetAutoFocus(false)
  labelEdit:SetScript("OnEnterPressed", function(self) SG.session.label = self:GetText(); self:ClearFocus() end)
  labelEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  labelEdit:SetScript("OnTextChanged", function(self) if self:HasFocus() then SG.session.label = self:GetText() end end)

  timerFS = cA:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  timerFS:SetPoint("TOP", 0, -40)
  timerFS:SetFont(STANDARD_TEXT_FONT, 44, "OUTLINE")
  timerFS:SetText("0:00"); TFS(timerFS, "base")

  -- Rows spread to fill the panel (spacing 30) so the tab reads full, not sparse.
  gphFS    = StatRow(cA, "Gold / hour",    -108)
  sessFS   = StatRow(cA, "This run (est)", -138)
  coinFS   = StatRow(cA, "Coin",           -168)
  repairFS = StatRow(cA, "Repairs",        -198)
  netFS    = StatRow(cA, "Net",            -228)
  durFS    = StatRow(cA, "Durability",     -258)

  breakdownFS = cA:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  breakdownFS:SetPoint("TOPLEFT", 12, -290); breakdownFS:SetPoint("TOPRIGHT", -12, -290)
  breakdownFS:SetJustifyH("CENTER"); breakdownFS:SetSpacing(3); TFS(breakdownFS, "dim")

  -- Run controls spread evenly across the bottom (runBtn pinned left, optBtn pinned right,
  -- Pause/Reset chained with ~24px gaps so they span the whole window width).
  runBtn = StyleButton(CreateFrame("Button", nil, cA, "UIPanelButtonTemplate"))
  runBtn:SetSize(100, 26); runBtn:SetPoint("BOTTOMLEFT", 8, 8)
  runBtn:SetText("Start Run"); runBtn:SetScript("OnClick", function() SG.ToggleRun() end)
  pauseBtn = StyleButton(CreateFrame("Button", nil, cA, "UIPanelButtonTemplate"))
  pauseBtn:SetSize(88, 26); pauseBtn:SetPoint("LEFT", runBtn, "RIGHT", 24, 0)
  pauseBtn:SetText("Pause"); pauseBtn:SetScript("OnClick", function() SG.PauseRun() end)
  resetBtn = StyleButton(CreateFrame("Button", nil, cA, "UIPanelButtonTemplate"))
  resetBtn:SetSize(84, 26); resetBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 24, 0)
  resetBtn:SetText("Reset"); resetBtn:SetScript("OnClick", function() SG.ResetRun() end)
  local optBtn = StyleButton(CreateFrame("Button", nil, cA, "UIPanelButtonTemplate"))
  optBtn:SetSize(88, 26); optBtn:SetPoint("BOTTOMRIGHT", -8, 8)
  optBtn:SetText("Options"); optBtn:SetScript("OnClick", function() SG.ToggleConfig() end)

  ------------------------------------------------------------------
  -- Tab B: weekly / lifetime + liquidated chart
  ------------------------------------------------------------------
  local cB = content[2]
  scopeBtn = StyleButton(CreateFrame("Button", nil, cB, "UIPanelButtonTemplate"))
  scopeBtn:SetSize(120, 20); scopeBtn:SetPoint("TOPRIGHT", -6, -4)
  scopeBtn:SetScript("OnClick", function() SG.ToggleScope() end)
  scopeBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Switch view")
    GameTooltip:AddLine("This character only, or all your characters combined.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  scopeBtn:SetScript("OnLeave", GameTooltip_Hide)

  local bHdr = cB:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  bHdr:SetPoint("TOPLEFT", 12, -10); bHdr:SetPoint("TOPRIGHT", scopeBtn, "TOPLEFT", -8, 0); bHdr:SetJustifyH("LEFT")
  bHdr:SetText("Gold banked - coin + vendor + AH"); TFS(bHdr, "accent")
  todayFS = StatRow(cB, "Today",       -34)
  weekFS  = StatRow(cB, "Last 7 days", -56)
  allFS   = StatRow(cB, "All-time",    -78)

  bestRunFS = cB:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bestRunFS:SetPoint("TOPLEFT", 12, -100); bestRunFS:SetPoint("TOPRIGHT", -12, -100); bestRunFS:SetJustifyH("LEFT")

  chartLabel = TFS(cB:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "dim")
  chartLabel:SetPoint("TOPLEFT", 12, -122)
  chartLabel:SetText("Banked per day (last 7):  |cffffd700coin|r  |cff9d9d9dvendor|r  |cff4d94ffAH|r")

  local chartW, chartH = 424, 188
  local chart = CreateFrame("Frame", nil, cB)
  chart:SetSize(chartW, chartH); chart:SetPoint("TOPLEFT", 12, -140)
  bars = {}
  local n, gap = 7, 10
  local bw = (chartW - gap * (n - 1)) / n
  for i = 1, n do
    local x = (i - 1) * (bw + gap)
    -- Stacked by realized category: coin (gold) -> vendor (grey) -> AH (blue), bottom up.
    local coin = chart:CreateTexture(nil, "ARTWORK"); coin:SetColorTexture(1.0, 0.84, 0.0, 0.95)
    coin:SetWidth(bw); coin:SetPoint("BOTTOMLEFT", x, 16)
    local vend = chart:CreateTexture(nil, "ARTWORK"); vend:SetColorTexture(0.62, 0.62, 0.62, 0.95)
    vend:SetWidth(bw); vend:SetPoint("BOTTOMLEFT", coin, "TOPLEFT", 0, 0)
    local ah = chart:CreateTexture(nil, "ARTWORK"); ah:SetColorTexture(0.30, 0.58, 1.0, 0.95)
    ah:SetWidth(bw); ah:SetPoint("BOTTOMLEFT", vend, "TOPLEFT", 0, 0)
    local lbl = TFS(chart:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "dim")
    lbl:SetPoint("TOP", coin, "BOTTOM", 0, -2)
    local val = TFS(chart:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "dim")
    val:SetPoint("BOTTOM", ah, "TOP", 0, 1)
    bars[i] = { coin = coin, vend = vend, ah = ah, lbl = lbl, val = val }
  end

  ------------------------------------------------------------------
  -- Tab C: Run Journal (this character) - list with per-run delete
  ------------------------------------------------------------------
  local cC = content[3]
  journalHdr = TFS(cC:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "dim")
  journalHdr:SetPoint("TOPLEFT", 12, -8); journalHdr:SetPoint("TOPRIGHT", -12, -8); journalHdr:SetJustifyH("LEFT")

  -- Runs <-> Locations toggle (left) and Undo last (right).
  journalToggleBtn = StyleButton(CreateFrame("Button", nil, cC, "UIPanelButtonTemplate"))
  journalToggleBtn:SetSize(96, 20); journalToggleBtn:SetPoint("TOPLEFT", 8, -24)
  journalToggleBtn:SetText("By location")
  journalToggleBtn:SetScript("OnClick", function()
    journalMode = (journalMode == "runs" and "locations")
      or (journalMode == "locations" and "market") or "runs"     -- cycle runs -> locations -> market
    if FauxScrollFrame_SetOffset then FauxScrollFrame_SetOffset(journalScroll, 0) end   -- reset to top
    local sb = journalScroll.ScrollBar or _G[(journalScroll:GetName() or "") .. "ScrollBar"]
    if sb and sb.SetValue then sb:SetValue(0) end
    RefreshJournal()
  end)

  local undoBtn = StyleButton(CreateFrame("Button", nil, cC, "UIPanelButtonTemplate"))
  undoBtn:SetSize(90, 20); undoBtn:SetPoint("TOPRIGHT", -6, -24)
  undoBtn:SetText("Undo last"); undoBtn:SetScript("OnClick", function() SG.UndoLastRun() end)

  -- Category buttons for the Market view (#15): Bags (your held mats) + trade-good categories.
  journalCatBtns = {}
  local catDefs = { { key = nil, label = "Bags" } }
  for _, c in ipairs(SG.AHCategories or {}) do catDefs[#catDefs + 1] = { key = c.key, label = c.label } end
  local cx = 8
  for _, c in ipairs(catDefs) do
    local b = StyleButton(CreateFrame("Button", nil, cC, "UIPanelButtonTemplate"))
    b:SetSize(64, 18); b:SetPoint("TOPLEFT", cx, -48); b:SetText(c.label); b.catKey = c.key; b.catLabel = c.label
    b:SetScript("OnClick", function()
      if c.key then SG.AHBrowse(c.key) else SG.SetAHBrowseBags() end
      RefreshJournal()
    end)
    journalCatBtns[#journalCatBtns + 1] = b
    cx = cx + 66
  end

  journalScroll = CreateFrame("ScrollFrame", "TimeIsMoneyJournalScroll", cC, "FauxScrollFrameTemplate")
  journalScroll:SetPoint("TOPLEFT", 8, -72); journalScroll:SetPoint("BOTTOMRIGHT", -28, 8)
  journalScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, JROW_H, RefreshJournal)
  end)

  journalRows = {}
  for i = 1, JMAX do
    local row = CreateFrame("Button", nil, cC)
    row:SetHeight(JROW_H)
    row:SetPoint("TOPLEFT", journalScroll, "TOPLEFT", 0, -(i - 1) * JROW_H)
    row:SetPoint("TOPRIGHT", journalScroll, "TOPRIGHT", 0, -(i - 1) * JROW_H)
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
    row.text = TFS(row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "base")
    row.text:SetPoint("LEFT", 4, 0); row.text:SetPoint("RIGHT", -22, 0); row.text:SetJustifyH("LEFT")
    row.del = CreateFrame("Button", nil, row)
    row.del:SetSize(18, 18); row.del:SetPoint("RIGHT", -2, 0)
    row.del.x = TFS(row.del:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "dim")
    row.del.x:SetPoint("CENTER"); row.del.x:SetText("x")
    row.del:SetScript("OnEnter", function(self) self.x:SetTextColor(1, 0.35, 0.35) end)
    row.del:SetScript("OnLeave", function(self) local T = SG.Theme(); self.x:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end)
    row.del:SetScript("OnClick", function() if row.absIdx then SG.DeleteRun(row.absIdx) end end)
    -- Market rows: hover shows the item tooltip, left-click hands you a copyable Wowhead link
    -- ("where do I farm this?"). Inert in the Runs/Locations views.
    row:SetScript("OnEnter", function(self)
      if journalMode == "market" and self.itemID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
      if journalMode == "market" and self.itemID then
        ShowCopyLink("https://www.wowhead.com/item=" .. self.itemID)
      end
    end)
    journalRows[i] = row
  end

  ------------------------------------------------------------------
  -- Tab D (Gains): where this run's loot goes — vendor column (left) + AH column (right),
  -- each independently scrollable so you never scroll past one pile to reach the other.
  ------------------------------------------------------------------
  local cD = content[4]
  local COLW = 200
  gV = BuildGoodsColumn(cD, 6,   COLW, "TimeIsMoneyGainsVendorScroll", true)    -- left: junk to vendor
  gA = BuildGoodsColumn(cD, 228, COLW, "TimeIsMoneyGainsAHScroll",     false)   -- right: mats/BoEs to list

  local gHint = TFS(cD:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "pop")
  gHint:SetPoint("BOTTOMLEFT", 8, 38); gHint:SetPoint("BOTTOMRIGHT", -8, 38); gHint:SetJustifyH("LEFT")
  gHint:SetText("Left-click = keep this visit · Right-click = set a rule · Shift-click = link")

  gainsSellBtn = StyleButton(CreateFrame("Button", nil, cD, "UIPanelButtonTemplate"))
  gainsSellBtn:SetSize(110, 24); gainsSellBtn:SetPoint("BOTTOMRIGHT", -8, 8)
  gainsSellBtn:SetText("Sell All")
  gainsSellBtn:SetScript("OnClick", function()
    if SG.AtAuctionHouse and SG.AtAuctionHouse() then
      if SG.AHScan then SG.AHScan() end                 -- posting is blocked by the client; rescan prices
    elseif SG.AtMerchant and SG.AtMerchant() then SG.SellAll() end
  end)

  gainsUndoBtn = StyleButton(CreateFrame("Button", nil, cD, "UIPanelButtonTemplate"))
  gainsUndoBtn:SetSize(90, 24); gainsUndoBtn:SetPoint("RIGHT", gainsSellBtn, "LEFT", -6, 0)
  gainsUndoBtn:SetText("Undo last"); gainsUndoBtn:SetScript("OnClick", function() SG.SellUndoLast() end)

  gainsSellFS = TFS(cD:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "base")
  gainsSellFS:SetPoint("BOTTOMLEFT", 10, 14)

  -- Live ticking for Tab A timer/GPH
  frame:SetScript("OnUpdate", function(self, elapsed)
    self._t = (self._t or 0) + elapsed
    if self._t > 0.5 then
      self._t = 0
      if activeTab == 1 then
        if timerFS then timerFS:SetText(FmtClock(SG.RunElapsed())) end
        if gphFS then gphFS:SetText(GPHText()) end
      end
    end
  end)

  -- Restore the floating ticker if it was up last session
  if TimeIsMoneyDB and TimeIsMoneyDB.settings and TimeIsMoneyDB.settings.tickerShown then
    BuildTicker(); ticker:Show()
  end

  -- Keep the Gains tab live as bags change (selling, looting, moving items) while it's open.
  local bagEf = CreateFrame("Frame")
  bagEf:RegisterEvent("BAG_UPDATE_DELAYED")
  bagEf:SetScript("OnEvent", function()
    if frame:IsShown() and activeTab == 4 then RefreshGains() end
  end)

  SelectTab(1)
  ApplyTheme()
  ApplyScale()
end

function SG.RefreshUI()
  if not frame then return end
  local T = SG.Theme()

  -- Tab A
  if gphFS   then gphFS:SetText(GPHText()) end
  if sessFS  then sessFS:SetText(Short(SG.SessionValue())) end
  if coinFS  then coinFS:SetText(Short(SG.SessionByProf("money"))) end
  if repairFS then
    local r = SG.SessionRepairs()
    repairFS:SetText(r > 0 and ("|cff" .. T.redHex .. "-" .. Short(r) .. "|r") or Short(0))
  end
  if netFS   then netFS:SetText("|cff" .. T.accentHex .. Short(SG.SessionNet()) .. "|r") end
  if durFS then
    local d = SG.DurabilityPct and SG.DurabilityPct()
    if not d then durFS:SetText("|cff" .. T.dimHex .. "-|r")
    else
      local c = (d < 30) and ("|cff" .. T.redHex) or (d < 60) and "|cffd0a000" or ("|cff" .. T.accentHex)
      durFS:SetText(("%s%d%%|r"):format(c, math.floor(d + 0.5)))
    end
  end
  if timerFS then timerFS:SetText(FmtClock(SG.RunElapsed())) end
  -- Gold text while a run is live (a "you're recording" cue); reverts to the button's mint when stopped.
  if runBtn then runBtn:SetText(SG.RunActive() and "|cffffd200Stop Run|r" or "Start Run") end
  if pauseBtn then
    pauseBtn:SetText(SG.RunPaused() and "Resume" or "Pause")
    pauseBtn:SetEnabled(SG.RunActive())
  end
  if resetBtn then resetBtn:SetEnabled(SG.RunActive()) end
  if labelEdit and not labelEdit:HasFocus() then
    labelEdit:SetText(SG.session.label or GetFarmLabel())
  end
  if breakdownFS then
    local function line(list)
      local parts = {}
      for _, p in ipairs(list) do
        parts[#parts + 1] = ("%s %dg"):format(SG.PROF_LABEL[p], math.floor(SG.SessionByProf(p) / 10000))
      end
      return table.concat(parts, "   ")
    end
    breakdownFS:SetText(line({ "skinning", "mining", "herbalism" }) .. "\n" ..
                        line({ "tailoring", "fishing", "money", "drops" }))
  end

  -- Tab B (banked / liquidated only)
  if scopeBtn then scopeBtn:SetText(SG.ScopeLabel and SG.ScopeLabel() or "This character") end
  if todayFS then todayFS:SetText(SG.Money(SG.LiquidatedDay(date("%Y-%m-%d")))) end
  if weekFS  then weekFS:SetText(SG.Money(SG.LiquidatedWeek())) end
  if allFS   then allFS:SetText(SG.Money(SG.LiquidatedAllTime())) end
  if bestRunFS then
    bestRunFS:SetTextColor(T.base[1], T.base[2], T.base[3])
    local best = SG.BestRunSince and SG.BestRunSince(time() - 7 * 86400)
    if best then
      bestRunFS:SetText(("|cff" .. T.goldHex .. "Best run this week:|r %s - %s net"):format(
        best.label or "Run", SG.Money(best.net or 0)))
    else
      bestRunFS:SetText("|cff" .. T.dimHex .. "No runs logged this week yet.|r")
    end
  end
  if bars then
    local days, maxV = {}, 1
    for i = 1, 7 do
      local t = time() - (7 - i) * 86400
      local coin, vend, ah, tot = SG.DayBuckets(date("%Y-%m-%d", t))
      days[i] = { coin = coin, vend = vend, ah = ah, tot = tot, t = t }
      if tot > maxV then maxV = tot end
    end
    local maxH = 160
    for i = 1, 7 do
      local b, dd = bars[i], days[i]
      b.coin:SetHeight(math.max(0.01, dd.coin / maxV * maxH))
      b.vend:SetHeight(math.max(0.01, dd.vend / maxV * maxH))
      b.ah:SetHeight(math.max(0.01, dd.ah / maxV * maxH))
      b.lbl:SetText(date("%a", dd.t):sub(1, 2))
      b.val:SetText(dd.tot > 0 and ("%dg"):format(math.floor(dd.tot / 10000)) or "")
    end
  end

  RefreshTicker()   -- keep the floating widget's state in sync (start/stop from the big panel)
  RefreshJournal()  -- Tab C run list
  RefreshGains()    -- Tab D vendor / AH goods lists
end

function SG.Toggle()
  if not frame then SG.InitUI() end
  if frame:IsShown() then frame:Hide() else frame:Show(); if not activeTab then SelectTab(1) end; SG.RefreshUI() end
end

-- Open the main window straight to the Gains tab (the sell interface). Used by /tim sell
-- and the merchant auto-open. `manual` prints a note when there's nothing to vendor.
function SG.OpenSellTab(manual)
  if not frame then SG.InitUI() end
  frame:Show(); SelectTab(4); RefreshGains()
  if manual then
    local r = SG.ScanSellables and SG.ScanSellables()
    if r and #r.vendor == 0 then
      SG.Print("Nothing to vendor right now (no greys, old-expansion BoP, or unsellable BoEs).")
    end
  end
end

-- Merchant open/close hook (called from Sell.lua). Auto-jumps to the Gains tab when there's
-- a vendor pile and the setting is on; always refreshes so the Sell/Undo buttons re-enable.
function SG.OnMerchant(open)
  if open and (not SG.SellWindowEnabled or SG.SellWindowEnabled()) then
    local r = SG.ScanSellables and SG.ScanSellables()
    if r and #r.vendor > 0 then
      if not frame then SG.InitUI() end
      frame:Show(); SelectTab(4)
    end
  end
  if frame and frame:IsShown() and activeTab == 4 then RefreshGains() end
end

-- Auction House open/close hook (called from AuctionHouse.lua). Jumps to the Gains tab so you
-- can see the scanned market prices on the AH column; refreshes as scan results come in.
function SG.OnAuctionHouse(open)
  if open then
    if not frame then SG.InitUI() end
    frame:Show(); SelectTab(4)
  end
  if frame and frame:IsShown() and activeTab == 4 then RefreshGains() end
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
SLASH_TIMEISMONEY1 = "/tim"
SLASH_TIMEISMONEY2 = "/timeismoney"
SlashCmdList["TIMEISMONEY"] = function(msg)
  msg = msg or ""
  local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")  -- keep arg's case for item links
  cmd = (cmd or ""):lower()
  if cmd == "reset" then
    StaticPopup_Show("TIMEISMONEY_RESET")
  elseif cmd == "run" then
    SG.ToggleRun()
  elseif cmd == "pause" then
    SG.PauseRun()
  elseif cmd == "ticker" or cmd == "timer" then
    SG.ToggleTicker()
  elseif cmd == "runs" or cmd == "journal" then
    SG.PrintRuns()
  elseif cmd == "undorun" then
    SG.UndoLastRun()
  elseif cmd == "delrun" then
    SG.DeleteRun(arg)
  elseif cmd == "scope" then
    SG.ToggleScope()
  elseif cmd == "theme" then
    if arg and arg ~= "" then
      -- match a theme name case-insensitively (e.g. /tim theme amber, /tim theme class color)
      local want = arg:lower()
      local pick
      for _, n in ipairs(SG.ThemeList()) do if n:lower() == want then pick = n end end
      if pick then SG.SetTheme(pick)
      else SG.Print("Themes: " .. table.concat(SG.ThemeList(), ", ")) end
    else
      SG.CycleTheme()
    end
  elseif cmd == "scale" then
    SG.SetUIScale(arg)
  elseif cmd == "labelprompt" then
    SG.ToggleRunLabelPrompt()
  elseif cmd == "autostart" then
    SG.ToggleAutoStart()
  elseif cmd == "drops" then
    SG.ToggleDrops()
  elseif cmd == "pricing" then
    SG.SetPriceMode(arg)
  elseif cmd == "pricetest" then
    SG.PriceTest(arg)
  elseif cmd == "ah" then
    SG.SetItemRule("ah", arg)
  elseif cmd == "vendor" then
    SG.SetItemRule("vendor", arg)
  elseif cmd == "exclude" then
    SG.SetItemRule("exclude", arg)
  elseif cmd == "clearrule" then
    SG.ClearItemRule(arg)
  elseif cmd == "rules" then
    SG.ListItemRules()
  elseif cmd == "salerate" then
    SG.SetSaleRate(arg)
  elseif cmd == "sellpreview" then
    SG.SellPreview()
  elseif cmd == "sell" then
    if SG.ShowSellWindow then SG.ShowSellWindow(true) end
  elseif cmd == "ahscan" then
    if not (SG.AtAuctionHouse and SG.AtAuctionHouse()) then
      SG.Print("Open the Auction House first, then /tim ahscan.")
    elseif SG.AHScan then SG.AHScan() end
  elseif cmd == "undercut" then
    local n = tonumber(arg)
    if n and n >= 0 and n <= 90 then
      TimeIsMoneyDB.settings.ahUndercut = n
      SG.Print(("AH post price = |cffffd200%d%%|r under the current lowest."):format(n))
      if SG.RefreshUI then SG.RefreshUI() end
    else
      SG.Print(("Usage: /tim undercut <0-90>   (currently %d%% under lowest)"):format(TimeIsMoneyDB.settings.ahUndercut or 5))
    end
  elseif cmd == "sellwindow" then
    SG.ToggleSellWindow()
  elseif cmd == "sellconfirm" then
    SG.ToggleSellConfirm()
  elseif cmd == "skipgreys" then
    SG.ToggleSkipGreys()
  elseif cmd == "sellilvl" then
    SG.SetSellGearIlvl(arg)
  elseif cmd == "selllog" then
    SG.PrintSellLog()
  elseif cmd == "debug" then
    SG.ToggleDebug()
  elseif cmd == "config" or cmd == "options" then
    SG.ToggleConfig()
  else
    SG.Toggle()
  end
end
