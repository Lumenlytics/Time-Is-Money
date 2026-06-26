local ADDON, ns = ...
local SG = ns

local frame, gphFS, sessFS, todayFS, weekFS, allFS, breakdownFS, bars, runStatusFS, runBtn, pauseBtn, resetBtn

StaticPopupDialogs["TIMEISMONEY_RESET"] = {
  text = "Time Is Money: clear all tracked data?",
  button1 = YES, button2 = NO,
  OnAccept = function() SG.ResetData() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function StatRow(label, y)
  local l = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  l:SetPoint("TOPLEFT", 16, y)
  l:SetText(label)
  local v = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  v:SetPoint("TOPRIGHT", -16, y)
  v:SetJustifyH("RIGHT")
  return v
end

local function RunStatus()
  if not SG.RunActive() then return "|cff808080Run stopped|r" end
  if SG.RunPaused() then return "|cffffff00Run paused|r  " .. SG.FmtDuration(SG.RunElapsed()) end
  return "|cff8fd694Run live|r  " .. SG.FmtDuration(SG.RunElapsed())
end

function SG.InitUI()
  if frame then return end

  frame = CreateFrame("Frame", "TimeIsMoneyFrame", UIParent, "BackdropTemplate")
  frame:SetSize(290, 360)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  frame:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  frame:SetBackdropColor(0.06, 0.06, 0.07, 0.94)
  frame:SetBackdropBorderColor(0.20, 0.50, 0.30, 1)
  frame:Hide()

  frame:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then StaticPopup_Show("TIMEISMONEY_RESET") end
  end)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -10)
  title:SetText("|cff8fd694Time Is Money|r")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  gphFS   = StatRow("Gold / hour (10m)", -42)
  sessFS  = StatRow("This run",     -62)
  todayFS = StatRow("Today",        -82)
  weekFS  = StatRow("Last 7 days",  -102)
  allFS   = StatRow("All-time",     -122)

  runStatusFS = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  runStatusFS:SetPoint("TOPLEFT", 16, -26)

  breakdownFS = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  breakdownFS:SetPoint("TOPLEFT", 16, -146)
  breakdownFS:SetPoint("TOPRIGHT", -16, -146)
  breakdownFS:SetJustifyH("LEFT")

  frame:SetScript("OnUpdate", function(self, elapsed)
    self._t = (self._t or 0) + elapsed
    if self._t > 1 then
      self._t = 0
      gphFS:SetText(SG.Money(SG.SessionGPH()) .. "/hr")
      if runStatusFS then runStatusFS:SetText(RunStatus()) end
    end
  end)

  local chartLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  chartLabel:SetPoint("TOPLEFT", 16, -172)
  chartLabel:SetText("Daily value (last 7 days)")

  local chartW, chartH = 258, 120
  local chart = CreateFrame("Frame", nil, frame)
  chart:SetSize(chartW, chartH)
  chart:SetPoint("TOPLEFT", 16, -188)

  bars = {}
  local n, gap = 7, 8
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

  local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOM", 0, 30)
  footer:SetText("/tim  -  right-click clears ALL data")

  local opt = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  opt:SetSize(64, 20)
  opt:SetPoint("BOTTOMRIGHT", -10, 6)
  opt:SetText("Options")
  opt:SetScript("OnClick", function() SG.ToggleConfig() end)

  runBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  runBtn:SetSize(70, 20)
  runBtn:SetPoint("BOTTOMLEFT", 10, 6)
  runBtn:SetText("Start Run")
  runBtn:SetScript("OnClick", function() SG.ToggleRun() end)

  pauseBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  pauseBtn:SetSize(58, 20)
  pauseBtn:SetPoint("LEFT", runBtn, "RIGHT", 4, 0)
  pauseBtn:SetText("Pause")
  pauseBtn:SetScript("OnClick", function() SG.PauseRun() end)

  resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  resetBtn:SetSize(54, 20)
  resetBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 4, 0)
  resetBtn:SetText("Reset")
  resetBtn:SetScript("OnClick", function() SG.ResetRun() end)
end

function SG.RefreshUI()
  if not frame then return end
  gphFS:SetText(SG.Money(SG.SessionGPH()) .. "/hr")
  sessFS:SetText(SG.Money(SG.SessionValue()))
  todayFS:SetText(SG.Money(SG.TodayValue()))
  weekFS:SetText(SG.Money(SG.WeekValue()))
  allFS:SetText(SG.Money(SG.AllTimeValue()))

  if runBtn   then runBtn:SetText(SG.RunActive() and "Stop Run" or "Start Run") end
  if pauseBtn then
    pauseBtn:SetText(SG.RunPaused() and "Resume" or "Pause")
    if SG.RunActive() then pauseBtn:Enable() else pauseBtn:Disable() end
  end
  if resetBtn then
    if SG.RunActive() then resetBtn:Enable() else resetBtn:Disable() end
  end
  if runStatusFS then runStatusFS:SetText(RunStatus()) end

  local parts = {}
  for _, p in ipairs(SG.PROFS) do
    parts[#parts + 1] = ("%s %dg"):format(SG.PROF_LABEL[p], math.floor(SG.SessionByProf(p) / 10000))
  end
  breakdownFS:SetText("Run:  " .. table.concat(parts, "   "))

  local vals, maxV = {}, 1
  for i = 1, 7 do
    local t = time() - (7 - i) * 86400
    local v = SG.SumDay(date("%Y-%m-%d", t))
    vals[i] = { v = v, t = t }
    if v > maxV then maxV = v end
  end
  local maxH = 86
  for i = 1, 7 do
    local b = bars[i]
    b.tex:SetHeight(math.max(1, (vals[i].v / maxV) * maxH))
    b.lbl:SetText(date("%a", vals[i].t):sub(1, 2))
    b.val:SetText(vals[i].v > 0 and ("%dg"):format(math.floor(vals[i].v / 10000)) or "")
  end
end

function SG.Toggle()
  if not frame then SG.InitUI() end
  if frame:IsShown() then frame:Hide() else frame:Show(); SG.RefreshUI() end
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
  elseif cmd == "debug" then
    SG.ToggleDebug()
  elseif cmd == "config" or cmd == "options" then
    SG.ToggleConfig()
  else
    SG.Toggle()
  end
end
