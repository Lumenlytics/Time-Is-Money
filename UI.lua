local ADDON, ns = ...
local SG = ns

local frame, tabs, content, activeTab, ticker
-- Tab A (Run detail)
local timerFS, gphFS, sessFS, coinFS, repairFS, netFS, durFS, breakdownFS, labelEdit, runBtn, pauseBtn, resetBtn
-- Tab B (Weekly)
local todayFS, weekFS, allFS, bars, chartLabel, bestRunFS, scopeBtn

local TABS = { "Run", "Weekly", "Farm", "Sell" }
local WIN_W, WIN_H = 400, 420   -- ALL tabs share one size (no jarring resize)

----------------------------------------------------------------------
-- Theme (dark / light)
----------------------------------------------------------------------
local THEMES = {
  dark = {
    shadow = true, outline = true,
    bg = { 0.06, 0.06, 0.07, 0.94 }, border = { 0.20, 0.50, 0.30 },
    base = { 0.90, 0.90, 0.90 }, label = { 1.00, 0.82, 0.00 }, dim = { 0.55, 0.55, 0.55 }, accent = { 0.56, 0.84, 0.58 },
    baseHex = "ffffff", accentHex = "8fd694", goldHex = "ffd200", dimHex = "808080", redHex = "ff7070",
    tabOn = { 0.20, 0.50, 0.30, 0.85 }, tabOff = { 0.12, 0.12, 0.13, 0.90 }, tabOnText = { 1, 1, 1 }, tabOffText = { 0.7, 0.7, 0.7 },
  },
  light = {
    shadow = false, outline = false,
    bg = { 0.90, 0.88, 0.82, 0.98 }, border = { 0.42, 0.34, 0.18 },
    base = { 0.13, 0.13, 0.13 }, label = { 0.42, 0.32, 0.05 }, dim = { 0.38, 0.38, 0.38 }, accent = { 0.10, 0.48, 0.24 },
    baseHex = "1c1c1c", accentHex = "1a7a3c", goldHex = "8a5a00", dimHex = "555555", redHex = "a01818",
    tabOn = { 0.50, 0.40, 0.22, 0.95 }, tabOff = { 0.80, 0.77, 0.70, 0.95 }, tabOnText = { 1, 1, 1 }, tabOffText = { 0.30, 0.30, 0.30 },
  },
}

function SG.Theme()
  local t = TimeIsMoneyDB and TimeIsMoneyDB.settings and TimeIsMoneyDB.settings.theme
  return THEMES[t == "light" and "light" or "dark"]
end

-- Register a FontString for theming with a role: "base" | "label" | "dim" | "accent".
local themedFS = {}
local function TFS(fs, role) themedFS[#themedFS + 1] = { fs = fs, role = role or "base" }; return fs end

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
  if timerFS then timerFS:SetFont(STANDARD_TEXT_FONT, 40, T.outline and "OUTLINE" or "") end
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
  if SG.RefreshUI then SG.RefreshUI() end
end
SG.ApplyTheme = ApplyTheme

function SG.ToggleTheme()
  local s = TimeIsMoneyDB.settings
  s.theme = (s.theme == "light") and "dark" or "light"
  ApplyTheme()
  if SG.RefreshConfig then SG.RefreshConfig() end
  SG.Print("Theme = |cff8fd694" .. s.theme .. "|r")
end

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

StaticPopupDialogs["TIMEISMONEY_RESET"] = {
  text = "Time Is Money: clear all tracked data?",
  button1 = YES, button2 = NO,
  OnAccept = function() SG.ResetData() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Run Journal (#16): label-this-run prompt on Stop Run.
StaticPopupDialogs["TIMEISMONEY_LABELRUN"] = {
  text = "Name this run (for your farm journal):",
  button1 = SAVE or "Save",
  button2 = "Skip",
  hasEditBox = true, editBoxWidth = 260,
  OnShow = function(self, data)
    self.editBox:SetText((data and data._prefill) or "")
    self.editBox:HighlightText(); self.editBox:SetFocus()
  end,
  OnAccept = function(self, data)
    if data then data.label = self.editBox:GetText(); SG.SaveRun(data) end
  end,
  OnCancel = function(self, data) if data then SG.SaveRun(data) end end,  -- "Skip" saves with the default label
  EditBoxOnEnterPressed = function(self, data)
    data = data or (self:GetParent() and self:GetParent().data)
    if data then data.label = self:GetText(); SG.SaveRun(data) end
    StaticPopup_Hide("TIMEISMONEY_LABELRUN")
  end,
  EditBoxOnEscapePressed = function() StaticPopup_Hide("TIMEISMONEY_LABELRUN") end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function SG.PromptRunLabel(rec)
  local pre = rec.label   -- what the user typed in the Run Label field, if anything
  if not pre or pre == "" then pre = SG.SuggestRunLabel and SG.SuggestRunLabel(rec) end
  if not pre or pre == "" then pre = (rec.zone ~= "" and rec.zone) or "Run" end
  rec._prefill = pre
  StaticPopup_Show("TIMEISMONEY_LABELRUN", nil, nil, rec)
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function StatRow(parent, label, y)
  local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  l:SetPoint("TOPLEFT", 12, y)
  l:SetText(label); TFS(l, "label")
  local v = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  v:SetPoint("TOPRIGHT", -12, y)
  v:SetJustifyH("RIGHT"); TFS(v, "base")
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
  ticker.runBtn:SetText(SG.RunActive() and "Stop" or "Start")
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

  ticker.runBtn = CreateFrame("Button", nil, ticker, "UIPanelButtonTemplate")
  ticker.runBtn:SetSize(80, 20); ticker.runBtn:SetPoint("BOTTOMLEFT", 6, 6)
  ticker.runBtn:SetText("Start"); ticker.runBtn:SetScript("OnClick", function() SG.ToggleRun() end)
  ticker.pauseBtn = CreateFrame("Button", nil, ticker, "UIPanelButtonTemplate")
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
  for i = 1, #TABS do
    local t = CreateFrame("Button", nil, frame)
    t:SetSize(72, 22)
    t:SetPoint("TOPLEFT", 8 + (i - 1) * 74, -28)
    local bg = t:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.12, 0.12, 0.13, 0.90)
    local fs = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fs:SetAllPoints(); fs:SetText(TABS[i])
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

  local instBtn = CreateFrame("Button", nil, cA, "UIPanelButtonTemplate")
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

  local tickBtn = CreateFrame("Button", nil, cA, "UIPanelButtonTemplate")
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
  timerFS:SetPoint("TOP", 0, -38)
  timerFS:SetFont(STANDARD_TEXT_FONT, 40, "OUTLINE")
  timerFS:SetText("0:00"); TFS(timerFS, "base")

  gphFS    = StatRow(cA, "Gold / hour",    -96)
  sessFS   = StatRow(cA, "This run (est)", -118)
  coinFS   = StatRow(cA, "Coin",           -140)
  repairFS = StatRow(cA, "Repairs",        -162)
  netFS    = StatRow(cA, "Net",            -184)
  durFS    = StatRow(cA, "Durability",     -206)

  breakdownFS = cA:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  breakdownFS:SetPoint("TOPLEFT", 12, -226); breakdownFS:SetPoint("TOPRIGHT", -12, -226)
  breakdownFS:SetJustifyH("CENTER"); breakdownFS:SetSpacing(3); TFS(breakdownFS, "dim")

  -- Run controls grouped together along the bottom.
  runBtn = CreateFrame("Button", nil, cA, "UIPanelButtonTemplate")
  runBtn:SetSize(84, 22); runBtn:SetPoint("BOTTOMLEFT", 4, 4)
  runBtn:SetText("Start Run"); runBtn:SetScript("OnClick", function() SG.ToggleRun() end)
  pauseBtn = CreateFrame("Button", nil, cA, "UIPanelButtonTemplate")
  pauseBtn:SetSize(72, 22); pauseBtn:SetPoint("LEFT", runBtn, "RIGHT", 6, 0)
  pauseBtn:SetText("Pause"); pauseBtn:SetScript("OnClick", function() SG.PauseRun() end)
  resetBtn = CreateFrame("Button", nil, cA, "UIPanelButtonTemplate")
  resetBtn:SetSize(64, 22); resetBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 6, 0)
  resetBtn:SetText("Reset"); resetBtn:SetScript("OnClick", function() SG.ResetRun() end)
  local optBtn = CreateFrame("Button", nil, cA, "UIPanelButtonTemplate")
  optBtn:SetSize(72, 22); optBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)
  optBtn:SetText("Options"); optBtn:SetScript("OnClick", function() SG.ToggleConfig() end)

  ------------------------------------------------------------------
  -- Tab B: weekly / lifetime + liquidated chart
  ------------------------------------------------------------------
  local cB = content[2]
  scopeBtn = CreateFrame("Button", nil, cB, "UIPanelButtonTemplate")
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

  local chartW, chartH = 364, 188
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
  -- Tab C / D: stubs (built in later phases)
  ------------------------------------------------------------------
  local cCtext = TFS(content[3]:CreateFontString(nil, "OVERLAY", "GameFontDisable"), "dim")
  cCtext:SetPoint("TOPLEFT", 12, -12); cCtext:SetPoint("TOPRIGHT", -12, -12); cCtext:SetJustifyH("LEFT")
  cCtext:SetText("Farm intel - coming soon:\n\n- AH Hot Commodity (what's selling, supply-depth based)\n- Previous Farm Locations (filterable, from the Run Journal)\n- Professions (current character) vs what's selling\n- Reset All Data")

  local cDtext = TFS(content[4]:CreateFontString(nil, "OVERLAY", "GameFontDisable"), "dim")
  cDtext:SetPoint("TOPLEFT", 12, -12); cDtext:SetPoint("TOPRIGHT", -12, -12); cDtext:SetJustifyH("LEFT")
  cDtext:SetText("Sell review - opens automatically at a merchant (or /tim sell).\n\nA later phase mirrors that window here as a tab.")
  local cDbtn = CreateFrame("Button", nil, content[4], "UIPanelButtonTemplate")
  cDbtn:SetSize(140, 22); cDbtn:SetPoint("TOP", 0, -90)
  cDbtn:SetText("Open Sell window")
  cDbtn:SetScript("OnClick", function() if SG.ShowSellWindow then SG.ShowSellWindow(true) end end)

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
  if runBtn then runBtn:SetText(SG.RunActive() and "Stop Run" or "Start Run") end
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
end

function SG.Toggle()
  if not frame then SG.InitUI() end
  if frame:IsShown() then frame:Hide() else frame:Show(); if not activeTab then SelectTab(1) end; SG.RefreshUI() end
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
    SG.ToggleTheme()
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
