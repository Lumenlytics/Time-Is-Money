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

local function Checkbox(parent, x, y, label, get, set)
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
  refreshers[#refreshers + 1] = function() c:SetChecked(get()) end
end

function SG.RefreshConfig()
  for _, fn in ipairs(refreshers) do fn() end
end

function SG.InitConfig()
  if cfg then return end

  cfg = CreateFrame("Frame", "TimeIsMoneyConfigFrame", UIParent, "BackdropTemplate")
  cfg:SetSize(380, 414)
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
  title:SetPoint("TOP", 0, -10)
  title:SetText("|cff8fd694Time Is Money|r  Options")

  local close = CreateFrame("Button", nil, cfg, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  -- Income sources
  Label(cfg, 16, -44, "Track income sources", "GameFontHighlight")
  Checkbox(cfg, 16, -62, "Skinning",
    function() return S().profs.skinning end, function(v) S().profs.skinning = v end)
  Checkbox(cfg, 102, -62, "Mining",
    function() return S().profs.mining end, function(v) S().profs.mining = v end)
  Checkbox(cfg, 182, -62, "Herbalism",
    function() return S().profs.herbalism end, function(v) S().profs.herbalism = v end)
  Checkbox(cfg, 280, -62, "Tailoring",
    function() return S().profs.tailoring end, function(v) S().profs.tailoring = v end)
  Checkbox(cfg, 16, -86, "Coin (looted gold)",
    function() return S().profs.money end, function(v) S().profs.money = v end)
  Checkbox(cfg, 200, -86, "Auto-start runs",
    function() return S().autoStartRun end, function(v) S().autoStartRun = v end)
  Checkbox(cfg, 16, -108, "Count looted drops (greys / BoEs picked up on a run)",
    function() return S().countDrops end, function(v) S().countDrops = v end)

  -- Item pricing
  Segmented(cfg, 16, -134, "Item pricing", {
    { text = "Vendor",      value = "vendor", w = 60 },
    { text = "AH if sells",  value = "sells",  w = 84 },
    { text = "AH always",    value = "ah",     w = 78 },
  }, function() return S().priceMode end, function(v) SG.SetPriceMode(v) end)

  -- GPH window
  Segmented(cfg, 16, -190, "Gold / hour window", {
    { text = "5m",  value = 5,  w = 40 },
    { text = "10m", value = 10, w = 44 },
    { text = "15m", value = 15, w = 44 },
    { text = "20m", value = 20, w = 44 },
  }, function() return S().gphWindow end, function(v) S().gphWindow = v end)

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
