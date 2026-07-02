local ADDON, ns = ...
local SG = ns

local frame, tabs, content, activeTab, ticker
-- Tab A (Run detail)
local timerFS, gphFS, sessFS, coinFS, repairFS, netFS, durFS, breakdownFS, labelEdit, runBtn, pauseBtn, resetBtn
-- Tab B (Weekly)
local todayFS, weekFS, allFS, bars, chartLabel

local TABS = { "Run", "Weekly", "Farm", "Sell" }
local WIN_W, WIN_H = 470, 420   -- ALL tabs share one size (no jarring resize)

StaticPopupDialogs["TIMEISMONEY_RESET"] = {
  text = "Time Is Money: clear all tracked data?",
  button1 = YES, button2 = NO,
  OnAccept = function() SG.ResetData() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function StatRow(parent, label, y)
  local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  l:SetPoint("TOPLEFT", 12, y)
  l:SetText(label)
  local v = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  v:SetPoint("TOPRIGHT", -12, y)
  v:SetJustifyH("RIGHT")
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
  if not SG.RunActive() then txt = "|cff808080" .. txt .. "|r" end
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
  ticker.timer:SetText(FmtClock(SG.RunElapsed()))
  ticker.info:SetText(("|cff8fd694%s|r   |cff808080%s|r"):format(Short(SG.SessionValue()), GPHText()))
  ticker.runBtn:SetText(SG.RunActive() and "Stop" or "Start")
  ticker.pauseBtn:SetText(SG.RunPaused() and "Resume" or "Pause")
  ticker.pauseBtn:SetEnabled(SG.RunActive())
end

local function BuildTicker()
  if ticker then return end
  ticker = CreateFrame("Frame", "TimeIsMoneyTicker", UIParent, "BackdropTemplate")
  ticker:SetSize(176, 92)
  ticker:SetFrameStrata("FULLSCREEN_DIALOG")   -- always-on-top HUD widget
  ticker:SetToplevel(true)
  local pos = TimeIsMoneyDB and TimeIsMoneyDB.settings and TimeIsMoneyDB.settings.tickerPos
  if pos then ticker:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else ticker:SetPoint("TOP", 0, -220) end
  ticker:SetMovable(true); ticker:EnableMouse(true); ticker:RegisterForDrag("LeftButton")
  ticker:SetScript("OnDragStart", ticker.StartMoving)
  ticker:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveTickerPos() end)
  ticker:SetClampedToScreen(true)
  ticker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  ticker:SetBackdropColor(0.06, 0.06, 0.07, 0.92)
  ticker:SetBackdropBorderColor(0.20, 0.50, 0.30, 1)

  ticker.timer = ticker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ticker.timer:SetPoint("TOP", 0, -6); ticker.timer:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
  ticker.info = ticker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ticker.info:SetPoint("TOP", ticker.timer, "BOTTOM", 0, -3)

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
  for j = 1, #TABS do
    content[j]:SetShown(j == i)
    if j == i then
      tabs[j].bg:SetColorTexture(0.20, 0.50, 0.30, 0.85); tabs[j].fs:SetTextColor(1, 1, 1)
    else
      tabs[j].bg:SetColorTexture(0.12, 0.12, 0.13, 0.90); tabs[j].fs:SetTextColor(0.7, 0.7, 0.7)
    end
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
  frame:SetBackdropColor(0.06, 0.06, 0.07, 0.94)
  frame:SetBackdropBorderColor(0.20, 0.50, 0.30, 1)
  frame:Hide()

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("|cff8fd694Time Is Money|r")

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
  timerFS:SetText("0:00")

  gphFS    = StatRow(cA, "Gold / hour",    -96)
  sessFS   = StatRow(cA, "This run (est)", -118)
  coinFS   = StatRow(cA, "Coin",           -140)
  repairFS = StatRow(cA, "Repairs",        -162)
  netFS    = StatRow(cA, "Net",            -184)
  durFS    = StatRow(cA, "Durability",     -206)

  breakdownFS = cA:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  breakdownFS:SetPoint("TOPLEFT", 12, -232); breakdownFS:SetPoint("TOPRIGHT", -12, -232); breakdownFS:SetJustifyH("LEFT")

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
  local bHdr = cB:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  bHdr:SetPoint("TOPLEFT", 12, -6); bHdr:SetPoint("TOPRIGHT", -12, -6); bHdr:SetJustifyH("LEFT")
  bHdr:SetText("|cff8fd694Gold banked|r - what actually hit your wallet (coin + vendor + AH sales)")
  todayFS = StatRow(cB, "Today",       -28)
  weekFS  = StatRow(cB, "Last 7 days", -50)
  allFS   = StatRow(cB, "All-time",    -72)

  chartLabel = cB:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  chartLabel:SetPoint("TOPLEFT", 12, -104)
  chartLabel:SetText("Banked per day - last 7 days")

  local chartW, chartH = 436, 224
  local chart = CreateFrame("Frame", nil, cB)
  chart:SetSize(chartW, chartH); chart:SetPoint("TOPLEFT", 12, -122)
  bars = {}
  local n, gap = 7, 10
  local bw = (chartW - gap * (n - 1)) / n
  for i = 1, n do
    local b = chart:CreateTexture(nil, "ARTWORK")
    b:SetColorTexture(0.32, 0.72, 0.45, 0.95)
    b:SetWidth(bw)
    b:SetPoint("BOTTOMLEFT", (i - 1) * (bw + gap), 16)
    local lbl = chart:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lbl:SetPoint("TOP", b, "BOTTOM", 0, -2)
    local val = chart:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    val:SetPoint("BOTTOM", b, "TOP", 0, 1)
    bars[i] = { tex = b, lbl = lbl, val = val }
  end

  ------------------------------------------------------------------
  -- Tab C / D: stubs (built in later phases)
  ------------------------------------------------------------------
  local cCtext = content[3]:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  cCtext:SetPoint("TOPLEFT", 12, -12); cCtext:SetPoint("TOPRIGHT", -12, -12); cCtext:SetJustifyH("LEFT")
  cCtext:SetText("Farm intel - coming soon:\n\n- AH Hot Commodity (what's selling, supply-depth based)\n- Previous Farm Locations (filterable, from the Run Journal)\n- Professions (current character) vs what's selling\n- Reset All Data")

  local cDtext = content[4]:CreateFontString(nil, "OVERLAY", "GameFontDisable")
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
end

function SG.RefreshUI()
  if not frame then return end

  -- Tab A
  if gphFS   then gphFS:SetText(GPHText()) end
  if sessFS  then sessFS:SetText(Short(SG.SessionValue())) end
  if coinFS  then coinFS:SetText(Short(SG.SessionByProf("money"))) end
  if repairFS then
    local r = SG.SessionRepairs()
    repairFS:SetText(r > 0 and ("|cffff7070-" .. Short(r) .. "|r") or Short(0))
  end
  if netFS   then netFS:SetText("|cff8fd694" .. Short(SG.SessionNet()) .. "|r") end
  if durFS then
    local d = SG.DurabilityPct and SG.DurabilityPct()
    if not d then durFS:SetText("|cff808080-|r")
    else
      local c = (d < 30) and "|cffff4040" or (d < 60) and "|cffffd200" or "|cff8fd694"
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
  if labelEdit and not labelEdit:HasFocus() and labelEdit:GetText() == "" then
    labelEdit:SetText(GetFarmLabel())
  end
  if breakdownFS then
    local parts = {}
    for _, p in ipairs(SG.PROFS) do
      parts[#parts + 1] = ("%s %dg"):format(SG.PROF_LABEL[p], math.floor(SG.SessionByProf(p) / 10000))
    end
    breakdownFS:SetText(table.concat(parts, "   "))
  end

  -- Tab B (banked / liquidated only)
  if todayFS then todayFS:SetText(SG.Money(SG.LiquidatedDay(date("%Y-%m-%d")))) end
  if weekFS  then weekFS:SetText(SG.Money(SG.LiquidatedWeek())) end
  if allFS   then allFS:SetText(SG.Money(SG.LiquidatedAllTime())) end
  if bars then
    local vals, maxV = {}, 1
    for i = 1, 7 do
      local t = time() - (7 - i) * 86400
      local v = SG.LiquidatedDay(date("%Y-%m-%d", t))
      vals[i] = { v = v, t = t }
      if v > maxV then maxV = v end
    end
    local maxH = 200
    for i = 1, 7 do
      local b = bars[i]
      b.tex:SetHeight(math.max(1, (vals[i].v / maxV) * maxH))
      b.lbl:SetText(date("%a", vals[i].t):sub(1, 2))
      b.val:SetText(vals[i].v > 0 and ("%dg"):format(math.floor(vals[i].v / 10000)) or "")
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
