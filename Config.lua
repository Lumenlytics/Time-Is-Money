local ADDON, ns = ...
local SG = ns

local cfg
local refreshers = {}

local function S() return TimeIsMoneyDB.settings end

local function Label(parent, x, y, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

-- A small grey help line (plain-language explanation under a control).
local function Help(parent, x, y, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

-- Attach a hover tooltip (title + wrapped body) to any frame.
local function Tip(frame, title, body)
  if not frame or not body then return end
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 1, 1)
    GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", GameTooltip_Hide)
end

-- A row of buttons acting as a single-choice selector. The selected button is
-- disabled so it reads as "current"; clicking another switches the value.
local function Segmented(parent, x, y, label, options, get, set)
  Label(parent, x, y, label, "GameFontHighlight")
  local entries, bx = {}, x
  for _, opt in ipairs(options) do
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(opt.w or 56, 22)
    b:SetPoint("TOPLEFT", bx, y - 18)
    b:SetText(opt.text)
    b:SetScript("OnClick", function()
      set(opt.value)
      SG.RefreshConfig()
      if SG.RefreshUI then SG.RefreshUI() end
    end)
    if opt.tip then Tip(b, opt.text, opt.tip) end
    entries[#entries + 1] = { btn = b, value = opt.value }
    bx = bx + (opt.w or 56) + 4
  end
  refreshers[#refreshers + 1] = function()
    local cur = get()
    for _, e in ipairs(entries) do
      if e.value == cur then e.btn:Disable() else e.btn:Enable() end
    end
  end
end

local function Checkbox(parent, x, y, label, get, set, tip)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetPoint("TOPLEFT", x, y)
  c:SetSize(24, 24)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
  fs:SetText(label)
  c:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    if SG.RefreshUI then SG.RefreshUI() end
  end)
  if tip then Tip(c, label, tip) end
  refreshers[#refreshers + 1] = function() c:SetChecked(get()) end
end

local function Slider(parent, x, y, label, lo, hi, step, get, set)
  local nm = "TIMCfgSlider" .. (label:gsub("%W", ""))
  local s = CreateFrame("Slider", nm, parent, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", x, y); s:SetWidth(200)
  s:SetMinMaxValues(lo, hi); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
  local low  = s.Low  or _G[nm .. "Low"]
  local high = s.High or _G[nm .. "High"]
  local text = s.Text or _G[nm .. "Text"]
  if low  then low:SetText(("%.1f"):format(lo)) end
  if high then high:SetText(("%.1f"):format(hi)) end
  if text then text:SetText(label) end
  local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  val:SetPoint("LEFT", s, "RIGHT", 12, 0)
  s:SetScript("OnValueChanged", function(self, v) set(v); val:SetText(("%.2fx"):format(v)) end)
  refreshers[#refreshers + 1] = function() s:SetValue(get()); val:SetText(("%.2fx"):format(get())) end
  return s
end

function SG.RefreshConfig()
  for _, fn in ipairs(refreshers) do fn() end
end

function SG.InitConfig()
  if cfg then return end

  cfg = CreateFrame("Frame", "TimeIsMoneyConfigFrame", UIParent, "BackdropTemplate")
  cfg:SetSize(400, 520)
  cfg:SetPoint("CENTER", 60, 0)
  cfg:SetMovable(true)
  cfg:EnableMouse(true)
  cfg:RegisterForDrag("LeftButton")
  cfg:SetScript("OnDragStart", cfg.StartMoving)
  cfg:SetScript("OnDragStop", cfg.StopMovingOrSizing)
  cfg:SetClampedToScreen(true)
  cfg:SetFrameStrata("HIGH")
  cfg:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  cfg:SetBackdropColor(0.06, 0.06, 0.07, 0.96)
  cfg:SetBackdropBorderColor(0.20, 0.50, 0.30, 1)
  cfg:Hide()

  local title = cfg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("|cff8fd694Time Is Money|r  Options")

  local close = CreateFrame("Button", nil, cfg, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local themeBtn = CreateFrame("Button", nil, cfg, "UIPanelButtonTemplate")
  themeBtn:SetSize(96, 20); themeBtn:SetPoint("TOPRIGHT", -30, -9)
  themeBtn:SetScript("OnClick", function() SG.ToggleTheme() end)
  refreshers[#refreshers + 1] = function()
    themeBtn:SetText("Theme: " .. (S().theme == "light" and "Light" or "Dark"))
  end

  -- Income sources
  Label(cfg, 16, -44, "Track income sources", "GameFontHighlight")
  Checkbox(cfg, 12, -62, "Skinning",
    function() return S().profs.skinning end, function(v) S().profs.skinning = v end,
    "Count leather you gather as income.")
  Checkbox(cfg, 90, -62, "Mining",
    function() return S().profs.mining end, function(v) S().profs.mining = v end,
    "Count ore and stone you gather as income.")
  Checkbox(cfg, 164, -62, "Herbalism",
    function() return S().profs.herbalism end, function(v) S().profs.herbalism = v end,
    "Count herbs you gather as income.")
  Checkbox(cfg, 250, -62, "Tailoring",
    function() return S().profs.tailoring end, function(v) S().profs.tailoring = v end,
    "Count cloth looted off kills as income (tailoring has no gather cast).")
  Checkbox(cfg, 330, -62, "Fishing",
    function() return S().profs.fishing end, function(v) S().profs.fishing = v end,
    "Count fish you catch as income (loot arrives seconds after the cast).")
  Checkbox(cfg, 16, -86, "Coin (looted gold)",
    function() return S().profs.money end, function(v) S().profs.money = v end,
    "Count raw gold you loot from mobs and objects.")
  Checkbox(cfg, 200, -86, "Auto-start runs",
    function() return S().autoStartRun end, function(v) S().autoStartRun = v end,
    "Begin a run the moment you gather or loot something - no need to press Start.")
  Checkbox(cfg, 16, -108, "Count looted drops (greys / BoEs picked up on a run)",
    function() return S().countDrops end, function(v) S().countDrops = v end,
    "Also value greys, BoEs and other mob drops - not just gathered mats.")

  -- Item pricing
  Segmented(cfg, 16, -134, "Item pricing", {
    { text = "Vendor",       value = "vendor", w = 60, tip = "Always value items at their vendor sell price." },
    { text = "AH if sells",  value = "sells",  w = 84, tip = "Use AH price for mats/things that sell; vendor price for greys and random gear." },
    { text = "AH always",    value = "ah",     w = 78, tip = "Always use the AH price when one is available." },
  }, function() return S().priceMode end, function(v) SG.SetPriceMode(v) end)

  -- Gold/hour smoothing (intent presets + custom minutes)
  Segmented(cfg, 16, -186, "Gold/hour smoothing", {
    { text = "World ~8m",    value = 8,  w = 74, tip = "Steady world farming: a short window reacts quickly to your pace." },
    { text = "Dungeon ~20m", value = 20, w = 82, tip = "Bursty dungeon/raid loot: a longer window smooths the boss-kill spikes." },
    { text = "5m",  value = 5,  w = 36 },
    { text = "10m", value = 10, w = 40 },
    { text = "15m", value = 15, w = 40 },
  }, function() return S().gphWindow end, function(v) S().gphWindow = v end)
  Help(cfg, 18, -212, "How far back the Gold/hour average looks. Shorter reacts faster; longer is steadier.")

  -- TSM price source
  Segmented(cfg, 16, -240, "TSM price source (used only if TSM is installed)", {
    { text = "Market",     value = "DBMarket",          w = 60 },
    { text = "MinBuyout",  value = "DBMinBuyout",        w = 76 },
    { text = "RegionMkt",  value = "DBRegionMarketAvg",  w = 76 },
    { text = "RegionSale", value = "DBRegionSaleAvg",    w = 76 },
  }, function() return S().tsmSource end, function(v) S().tsmSource = v end)

  -- Minimum value filter
  Segmented(cfg, 16, -290, "Ignore items worth less than (per item)", {
    { text = "Off", value = 0,      w = 44 },
    { text = "1g",  value = 10000,  w = 40 },
    { text = "5g",  value = 50000,  w = 40 },
    { text = "10g", value = 100000, w = 44 },
    { text = "25g", value = 250000, w = 44 },
  }, function() return S().minValue end, function(v) S().minValue = v end)

  -- Selling (#14) - the merchant workflow toggles, formerly slash-only
  Label(cfg, 16, -336, "Selling (at a merchant)", "GameFontHighlight")
  Checkbox(cfg, 12, -354, "Auto-open sell window",
    function() return S().sellWindow ~= false end, function(v) S().sellWindow = v end,
    "When you talk to a merchant, pop the sell-review window listing what would be vendored.")
  Checkbox(cfg, 210, -354, "Confirm big / gear sells",
    function() return S().sellConfirm ~= false end, function(v) S().sellConfirm = v end,
    "Ask before vendoring gear/BoP or a large pile, so nothing valuable goes by accident.")
  Checkbox(cfg, 12, -378, "Skip greys (leave for another trash-seller)",
    function() return S().sellSkipGreys end, function(v) S().sellSkipGreys = v end,
    "Leave grey (poor) items in your bags for another addon to handle.")

  Segmented(cfg, 16, -404, "Auto-vendor old BoP gear at/below item level", {
    { text = "Never", value = 0,   w = 54, tip = "Never auto-vendor gear." },
    { text = "200",   value = 200, w = 44 },
    { text = "220",   value = 220, w = 44 },
    { text = "250",   value = 250, w = 44 },
    { text = "280",   value = 280, w = 44 },
  }, function() return S().sellGearMaxIlvl or 0 end, function(v) S().sellGearMaxIlvl = v end)
  Help(cfg, 18, -430, "Vendors old bind-on-pickup gear at or below this item level. Current-expansion gear is never touched.")

  -- Floating timer size
  Label(cfg, 16, -454, "Floating timer size", "GameFontHighlight")
  Slider(cfg, 24, -476, "smaller  -  larger", 0.6, 2.0, 0.05,
    function() return S().tickerScale or 1.0 end,
    function(v) SG.SetTickerScale(v) end)

  local note = cfg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("BOTTOMLEFT", 16, 12)
  note:SetText("Reopen any time with /tim config")

  SG.RefreshConfig()
end

function SG.ToggleConfig()
  if not cfg then SG.InitConfig() end
  if cfg:IsShown() then
    cfg:Hide()
  else
    SG.RefreshConfig()
    cfg:Show()
  end
end
