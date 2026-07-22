local ADDON, ns = ...
local SG = ns

local cfg
local refreshers = {}
local themedTexts = {}   -- {fs, role} - recolored per theme so the panel is readable in light mode

local function S() return TimeIsMoneyDB.settings end

-- Register a fontstring for theming with a role (base/label/dim/accent).
local function CT(fs, role) if fs then themedTexts[#themedTexts + 1] = { fs = fs, role = role or "base" } end; return fs end

-- Recolor the whole panel (backdrop + every registered text) to the current theme, dropping
-- font shadows in light mode where they read as fuzz. Runs on open + on theme toggle.
local function ApplyConfigTheme()
  if not cfg then return end
  local T = SG.Theme()
  cfg:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], T.bg[4] or 0.96)
  cfg:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
  local sa = T.shadow and 0.9 or 0
  local sx, sy = (T.shadow and 1 or 0), (T.shadow and -1 or 0)
  for _, e in ipairs(themedTexts) do
    local c = T[e.role] or T.base
    e.fs:SetTextColor(c[1], c[2], c[3])
    e.fs:SetShadowColor(0, 0, 0, sa); e.fs:SetShadowOffset(sx, sy)
  end
end

local function Label(parent, x, y, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return CT(fs, "label")
end

-- A small grey help line (plain-language explanation under a control).
local function Help(parent, x, y, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return CT(fs, "dim")
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
  local fs = CT(parent:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "base")
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
  if low  then low:SetText(("%.1f"):format(lo)); CT(low, "dim") end
  if high then high:SetText(("%.1f"):format(hi)); CT(high, "dim") end
  if text then text:SetText(label); CT(text, "dim") end
  local val = CT(parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "base")
  val:SetPoint("LEFT", s, "RIGHT", 12, 0)
  s:SetScript("OnValueChanged", function(self, v) set(v); val:SetText(("%.2fx"):format(v)) end)
  refreshers[#refreshers + 1] = function() s:SetValue(get()); val:SetText(("%.2fx"):format(get())) end
  return s
end

function SG.RefreshConfig()
  for _, fn in ipairs(refreshers) do fn() end
  ApplyConfigTheme()
end

function SG.InitConfig()
  if cfg then return end

  cfg = CreateFrame("Frame", "TimeIsMoneyConfigFrame", UIParent, "BackdropTemplate")
  cfg:SetSize(446, 736)
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

  local title = CT(cfg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), "accent")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("Time Is Money Options")

  local close = CreateFrame("Button", nil, cfg, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local themeBtn = CreateFrame("Button", nil, cfg, "UIPanelButtonTemplate")
  themeBtn:SetSize(96, 20); themeBtn:SetPoint("TOPRIGHT", -30, -9)
  themeBtn:SetScript("OnClick", function() SG.CycleTheme() end)
  themeBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Color theme")
    GameTooltip:AddLine("Click to cycle: Seafoam, Amethyst, Amber, Crimson, Steel, Class Color.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  themeBtn:SetScript("OnLeave", GameTooltip_Hide)
  refreshers[#refreshers + 1] = function()
    themeBtn:SetText(S().theme or "Seafoam")
  end

  -- ===== Track income sources =====
  Label(cfg, 16, -48, "Track income sources  |cff808080(per character)|r", "GameFontHighlight")
  Checkbox(cfg, 14,  -72, "Skinning",
    function() return S().profs.skinning end, function(v) S().profs.skinning = v end,
    "Count leather you gather as income.")
  Checkbox(cfg, 100, -72, "Mining",
    function() return S().profs.mining end, function(v) S().profs.mining = v end,
    "Count ore and stone you gather as income.")
  Checkbox(cfg, 176, -72, "Herbalism",
    function() return S().profs.herbalism end, function(v) S().profs.herbalism = v end,
    "Count herbs you gather as income.")
  Checkbox(cfg, 274, -72, "Tailoring",
    function() return S().profs.tailoring end, function(v) S().profs.tailoring = v end,
    "Count cloth looted off kills (tailoring has no gather cast).")
  Checkbox(cfg, 358, -72, "Fishing",
    function() return S().profs.fishing end, function(v) S().profs.fishing = v end,
    "Count fish you catch as income.")
  Checkbox(cfg, 14,  -100, "Coin (looted gold)",
    function() return S().profs.money end, function(v) S().profs.money = v end,
    "Count raw gold you loot from mobs and objects.")
  Checkbox(cfg, 200, -100, "Auto-start runs",
    function() return S().autoStartRun end, function(v) S().autoStartRun = v end,
    "Begin a run the moment you gather or loot something - no need to press Start.")
  Checkbox(cfg, 14,  -128, "Count looted drops (greys / BoEs picked up on a run)",
    function() return S().countDrops end, function(v) S().countDrops = v end,
    "Also value greys, BoEs and other mob drops - not just gathered mats.")

  -- ===== Item pricing =====
  Segmented(cfg, 16, -168, "Item pricing", {
    { text = "Vendor",       value = "vendor", w = 60, tip = "Always value items at their vendor sell price." },
    { text = "AH if sells",  value = "sells",  w = 84, tip = "Use AH price for mats/things that sell; vendor price for greys and random gear." },
    { text = "AH always",    value = "ah",     w = 78, tip = "Always use the AH price when one is available." },
  }, function() return S().priceMode end, function(v) SG.SetPriceMode(v) end)

  -- ===== TSM price source =====
  Segmented(cfg, 16, -234, "TSM price source (only used if TradeSkillMaster is installed)", {
    { text = "Market",     value = "DBMarket",          w = 60, tip = "TSM market value (a typical going rate). The usual choice." },
    { text = "MinBuyout",  value = "DBMinBuyout",        w = 76, tip = "The lowest current buyout - aggressive; can chase undercutters down." },
    { text = "RegionMkt",  value = "DBRegionMarketAvg",  w = 76, tip = "Region-wide average market value (needs TSM's Desktop App data)." },
    { text = "RegionSale", value = "DBRegionSaleAvg",    w = 76, tip = "Region-wide average price items actually SOLD for (needs TSM Desktop App)." },
  }, function() return S().tsmSource end, function(v) S().tsmSource = v end)

  -- ===== Minimum value filter =====
  Segmented(cfg, 16, -300, "Ignore items worth less than (per item)", {
    { text = "Off", value = 0,      w = 44 },
    { text = "1g",  value = 10000,  w = 40 },
    { text = "5g",  value = 50000,  w = 40 },
    { text = "10g", value = 100000, w = 44 },
    { text = "25g", value = 250000, w = 44 },
  }, function() return S().minValue end, function(v) S().minValue = v end)

  -- ===== Selling (at a merchant) =====
  Label(cfg, 16, -368, "Selling (at a merchant)", "GameFontHighlight")
  Checkbox(cfg, 14,  -392, "Auto-open sell window",
    function() return S().sellWindow ~= false end, function(v) S().sellWindow = v end,
    "When you talk to a merchant, jump to the Gains tab listing what would be vendored.")
  Checkbox(cfg, 210, -392, "Confirm big / gear sells",
    function() return S().sellConfirm ~= false end, function(v) S().sellConfirm = v end,
    "Ask before vendoring gear/BoP or a large pile, so nothing valuable goes by accident.")
  Checkbox(cfg, 14,  -418, "Skip greys (leave for another trash-seller)",
    function() return S().sellSkipGreys end, function(v) S().sellSkipGreys = v end,
    "Leave grey (poor) items in your bags for another addon to handle.")

  local gearOpts = {}
  for _, t in ipairs(SG.GEAR_TIERS or {}) do
    gearOpts[#gearOpts + 1] = {
      text = t.label, value = t.floor, w = (t.floor == 0 and 54 or 66),
      tip = (t.floor == 0) and "Never auto-vendor gear."
            or ("Keep " .. t.label .. "-track gear and better; vendor anything below it (item level " .. t.floor .. " and under)."),
    }
  end
  Segmented(cfg, 16, -454, "Auto-vendor BoP gear below upgrade tier (keeps that tier and up)", gearOpts,
    function() return S().sellGearMaxIlvl or 0 end, function(v) SG.SetCharOpt("sellGearMaxIlvl", v) end)
  Help(cfg, 18, -498, "Per character. Vendors old bind-on-pickup gear below the chosen tier. Tier item levels are for the current season - hover a button for the number.")

  -- ===== Auction House undercut =====
  Segmented(cfg, 16, -538, "Auction House undercut (the price to list mats at, under the lowest)", {
    { text = "Match",  value = 0,  w = 60, tip = "Post at the current lowest price (no undercut)." },
    { text = "2%",     value = 2,  w = 40, tip = "Post 2% under the current lowest." },
    { text = "5%",     value = 5,  w = 40, tip = "Post 5% under the current lowest (default)." },
    { text = "10%",    value = 10, w = 44, tip = "Post 10% under the current lowest - sells faster, less each." },
    { text = "15%",    value = 15, w = 44, tip = "Post 15% under the current lowest." },
  }, function() return S().ahUndercut or 5 end, function(v) S().ahUndercut = v; if SG.RefreshUI then SG.RefreshUI() end end)

  -- ===== Sounds =====
  Label(cfg, 16, -594, "Sounds", "GameFontHighlight")
  Checkbox(cfg, 14, -618, "Enabled",
    function() local c = SG.SoundCfg and SG.SoundCfg(); return c and c.master end,
    function(v) local c = SG.SoundCfg and SG.SoundCfg(); if c then c.master = v end end,
    "Master switch for all Time Is Money sounds (played on the SFX channel).")
  local sx = 116
  for _, e in ipairs(SG.SoundEvents or {}) do
    local key = e.key
    Checkbox(cfg, sx, -618, e.label,
      function() local c = SG.SoundCfg and SG.SoundCfg(); return c and c.events[key] and c.events[key].on end,
      function(v) local c = SG.SoundCfg and SG.SoundCfg(); if c and c.events[key] then c.events[key].on = v end end,
      "Play a cue on " .. e.label:lower() .. ". Pick your own sound with /tim sound.")
    sx = sx + 108
  end
  Help(cfg, 18, -642, "Hunt a sound with /tim sound <id>, then assign it: /tim sound set runstart <id>")

  -- ===== Floating timer size =====
  Label(cfg, 16, -672, "Floating timer size", "GameFontHighlight")
  Slider(cfg, 24, -694, "smaller  -  larger", 0.6, 2.0, 0.05,
    function() return S().tickerScale or 1.0 end,
    function(v) SG.SetTickerScale(v) end)

  local note = CT(cfg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "dim")
  note:SetPoint("BOTTOMLEFT", 16, 10)
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
