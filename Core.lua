local ADDON, ns = ...
local SG = ns

----------------------------------------------------------------------
-- Professions tracked
----------------------------------------------------------------------
-- "money" is a pseudo-profession: raw coin looted in the field. It flows through
-- the same buckets as the gathering professions, so it shows up in every total,
-- the session breakdown, the daily chart, and the GPH figure automatically.
SG.PROFS = { "skinning", "mining", "herbalism", "tailoring", "money", "drops" }
SG.PROF_LABEL = { skinning = "Skinning", mining = "Mining", herbalism = "Herbalism", tailoring = "Tailoring", money = "Coin", drops = "Drops" }

local SKILL_LINE = { [393] = "skinning", [186] = "mining", [182] = "herbalism" }

-- Fallback cast-name -> profession (English; extend via /tim debug if a locale differs)
local FALLBACK_NAMES = {
  ["Skinning"]       = "skinning",
  ["Mining"]         = "mining",
  ["Herbalism"]      = "herbalism",
  ["Herb Gathering"] = "herbalism",
}

-- Modern retail prefixes the gather spell with the expansion, e.g. "Midnight Mining",
-- so exact-name matching misses everything but Skinning. Match on the keyword instead.
-- Plain (non-pattern) substring search, checked in this order. English-centric, same
-- as FALLBACK_NAMES above.
local PROF_KEYWORDS = {
  { "skinning",       "skinning"  },
  { "mining",         "mining"    },
  { "herbalism",      "herbalism" },
  { "herb gathering", "herbalism" },
}

local function ProfFromName(name)
  local low = name:lower()
  for _, pair in ipairs(PROF_KEYWORDS) do
    if low:find(pair[1], 1, true) then return pair[2] end
  end
  return nil
end

----------------------------------------------------------------------
-- Saved-data defaults
----------------------------------------------------------------------
local DEFAULTS = {
  days      = {},  -- ["YYYY-MM-DD"] = { skinning={value,count}, mining=..., herbalism=... }
  items     = {},  -- [itemID] = { name, count, value, prof }
  totals    = {},  -- prof -> {value,count}
  itemRules = {},  -- [itemID] = "ah" | "vendor" | "exclude" (per-item override of the pricing mode)
  settings = {
    window    = 2.0,            -- seconds: loot attributed to a gather after its cast
    debug     = false,
    gphWindow = 10,             -- minutes: rolling window for the Gold/hour figure
    tsmSource = "DBMarket",     -- TSM price string used when TSM is installed
    minValue  = 0,              -- copper: ignore items whose per-unit value is below this
    autoStartRun = true,        -- begin a run automatically on the first gather/coin
    countDrops   = false,       -- count incidental run loot (greys/BoEs) into a "drops" source
    priceMode    = "sells",     -- "vendor" | "sells" (AH if it sells) | "ah" (AH always)
    saleRateMin  = 0.5,         -- "sells" mode: TSM region sold-per-day below this -> vendor price
    sellWindow   = true,        -- auto-open the sell-review window at a merchant (#14)
    sellConfirm  = true,        -- confirm before vendoring gear/BoP or a large pile (#14)
    sellSkipGreys = false,      -- leave greys for another trash-seller (e.g. RyrinQoL) (#14)
    sellGearMaxIlvl = 220,      -- auto-vendor old-expansion BoP gear at/below this ilvl; 0 = never (#14)
    profs     = { skinning = true, mining = true, herbalism = true, tailoring = true, money = true },
  },
}

SG.session = { active = false, paused = false, start = nil, pausedAccum = 0, pauseStart = nil, lastActivity = 0, repairs = 0, startMissing = 0, data = {}, events = {} }  -- the current run

local GPH_FLOOR  = 120   -- seconds: minimum denominator, so an opening burst can't read absurdly high

local castToProf   = {}
local lastGatherAt = 0
local lastGatherProf
local settings
local warnedNoSource = false
local atMerchant, lastRepairCost, lastMissing = false, 0, 0   -- repair tracking (#6 net profit)
local atMailbox = false   -- true while the mailbox is open (AH-sale income capture)
local lastMoney   -- wallet snapshot; used to detect vendor-sale + AH-sale income (liquidated)

----------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------
local function Print(msg) print("|cff8fd694Time Is Money|r: " .. tostring(msg)) end
SG.Print = Print

local function Today() return date("%Y-%m-%d") end

local function Money(copper)
  copper = math.floor(copper or 0)
  if GetCoinTextureString then return GetCoinTextureString(copper) end
  return string.format("%dg", math.floor(copper / 10000))
end
SG.Money = Money

-- Compact money for chat summaries: trims trailing denominations on big numbers
-- (gold-only past 1000g, gold+silver past 1g) so a run total reads "923g 32s",
-- not "923g 32s 59c". Keeps the coin icons, just drops the noise.
local function MoneyShort(copper)
  copper = math.floor(copper or 0)
  local g = math.floor(copper / 10000)
  if g >= 1000 then copper = g * 10000
  elseif g >= 1 then copper = copper - (copper % 100) end
  if GetCoinTextureString then return GetCoinTextureString(copper) end
  return string.format("%dg", g)
end
SG.MoneyShort = MoneyShort

-- A continuation line with NO "Time Is Money:" prefix, for clean multi-line output.
local function PrintRaw(msg) print(tostring(msg)) end
SG.PrintRaw = PrintRaw

local function Bucket(t, key)
  if not t[key] then t[key] = { value = 0, count = 0 } end
  return t[key]
end

local function MergeDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      MergeDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

-- Sum of missing durability points across equipped gear. Works anywhere (unlike
-- GetRepairAllCost, which only returns a value at a merchant), so we can baseline it
-- at run start and charge a run only for the wear IT caused, not a pre-existing bill.
local function MissingDurability()
  local missing = 0
  for slot = 1, 18 do
    local cur, max = GetInventoryItemDurability(slot)
    if cur and max and max > 0 then missing = missing + (max - cur) end
  end
  return missing
end

-- Current equipped durability as a percentage (nil if no gear reports durability).
function SG.DurabilityPct()
  local cur, max = 0, 0
  for slot = 1, 18 do
    local c, m = GetInventoryItemDurability(slot)
    if c and m and m > 0 then cur = cur + c; max = max + m end
  end
  if max == 0 then return nil end
  return cur / max * 100
end

----------------------------------------------------------------------
-- Run framing: a bounded farm run, distinct from the persistent ledger
----------------------------------------------------------------------
-- SG.session holds the *current run* - its per-source totals, value events (for
-- GPH) and start time. The day/totals/items tables are the persistent all-time
-- ledger and are written regardless of whether a run is active.
local function FmtDuration(sec)
  sec = math.floor(sec or 0)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then return ("%dh %02dm"):format(h, m) end
  if m > 0 then return ("%dm %02ds"):format(m, s) end
  return ("%ds"):format(s)
end
SG.FmtDuration = FmtDuration

local function StartRun(auto)
  SG.session.active       = true
  SG.session.paused       = false
  SG.session.start        = GetTime()
  SG.session.pausedAccum  = 0
  SG.session.pauseStart   = nil
  SG.session.lastActivity = GetTime()
  SG.session.repairs      = 0
  SG.session.startMissing = MissingDurability()
  wipe(SG.session.data)
  wipe(SG.session.events)
  Print(auto and "Run started automatically. Stop any time with /tim run."
              or  "Run started.")
  if SG.RefreshUI then SG.RefreshUI() end
end

local function StopRun()
  if not SG.session.active then Print("No run is active."); return end

  local dur     = SG.RunElapsed()
  SG.session.active = false
  SG.session.paused = false
  local total   = SG.SessionValue()
  local repairs = SG.session.repairs or 0
  local net     = total - repairs
  local gph     = net / (math.max(dur, GPH_FLOOR) / 3600)
  SG.session.finalGPH = gph          -- freeze: the panel shows this until the next run, no decay

  local SEP = "  |cff5a5a5a·|r  "   -- subtle gray middot between fields
  if repairs > 0 then
    Print(("|cffffd200Run ended|r" .. SEP .. "%s" .. SEP .. "%s gross - %s repairs = |cff8fd694%s net|r" .. SEP .. "|cffffd200%s/hr|r"):format(
      FmtDuration(dur), MoneyShort(total), MoneyShort(repairs), MoneyShort(net), MoneyShort(gph)))
  else
    Print(("|cffffd200Run ended|r" .. SEP .. "%s" .. SEP .. "|cff8fd694%s|r made" .. SEP .. "|cffffd200%s/hr|r"):format(
      FmtDuration(dur), MoneyShort(total), MoneyShort(gph)))
  end
  local parts = {}
  for _, p in ipairs(SG.PROFS) do
    local v = SG.SessionByProf(p)
    if v > 0 then parts[#parts + 1] = ("|cffb0b0b0%s|r %s"):format(SG.PROF_LABEL[p], MoneyShort(v)) end
  end
  if #parts > 0 then PrintRaw("    " .. table.concat(parts, SEP)) end
  if SG.RefreshUI then SG.RefreshUI() end
end

-- Called by the recorders: make sure a run is live so the loot has somewhere to go.
local function EnsureRun()
  if SG.session.active then return not SG.session.paused end
  if settings and settings.autoStartRun then StartRun(true); return true end
  return false
end

function SG.ToggleRun()
  if SG.session.active then StopRun() else StartRun(false) end
end
function SG.RunActive() return SG.session.active end
function SG.RunPaused() return SG.session.active and SG.session.paused end

function SG.RunElapsed()
  if not SG.session.active then return 0 end
  local e = GetTime() - (SG.session.start or GetTime()) - (SG.session.pausedAccum or 0)
  if SG.session.paused and SG.session.pauseStart then
    e = e - (GetTime() - SG.session.pauseStart)
  end
  return math.max(0, e)
end

function SG.PauseRun()
  if not SG.session.active then Print("No run is active."); return end
  if SG.session.paused then
    SG.session.pausedAccum = (SG.session.pausedAccum or 0) + (GetTime() - (SG.session.pauseStart or GetTime()))
    SG.session.paused      = false
    SG.session.pauseStart  = nil
    Print("Run resumed.")
  else
    SG.session.paused     = true
    SG.session.pauseStart = GetTime()
    Print("Run paused.")
  end
  if SG.RefreshUI then SG.RefreshUI() end
end

function SG.ResetRun()
  SG.session.start        = GetTime()
  SG.session.lastActivity = GetTime()
  SG.session.paused       = false
  SG.session.pausedAccum  = 0
  SG.session.pauseStart   = nil
  SG.session.repairs      = 0
  SG.session.startMissing = MissingDurability()
  wipe(SG.session.data)
  wipe(SG.session.events)
  Print("Run reset.")
  if SG.RefreshUI then SG.RefreshUI() end
end

-- Repairs (#6 net profit): booked from the merchant Repair-All hook (see events).
-- Only counts while a run is active so it nets against that run's income.
local function RecordRepair(copper)
  if not copper or copper <= 0 then return end
  if not (SG.session.active and not SG.session.paused) then return end
  SG.session.repairs = (SG.session.repairs or 0) + copper
  if settings and settings.debug then Print(("repair: -%s (net adjusted)"):format(Money(copper))) end
  if SG.RefreshUI then SG.RefreshUI() end
end
SG.RecordRepair = RecordRepair

function SG.SessionRepairs() return SG.session.repairs or 0 end
function SG.SessionNet()     return SG.SessionValue() - (SG.session.repairs or 0) end

----------------------------------------------------------------------
-- Detect which gathering professions this character has
----------------------------------------------------------------------
local function RefreshGathering()
  wipe(castToProf)
  for _, idx in pairs({ GetProfessions() }) do
    local name, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
    local key = name and SKILL_LINE[skillLine]
    if key then castToProf[name] = key end
  end
  for nm, key in pairs(FALLBACK_NAMES) do
    if castToProf[nm] == nil then castToProf[nm] = key end
  end
end

----------------------------------------------------------------------
-- Valuation: Auction House via TSM / Auctionator, vendor as fallback
----------------------------------------------------------------------
-- TSM region "sold per day" if available (needs the TSM Desktop App sync); nil otherwise.
local function TSMSoldPerDay(link)
  if not (TSM_API and TSM_API.ToItemString and TSM_API.GetCustomPriceValue) then return nil end
  local ok, itemString = pcall(TSM_API.ToItemString, link)
  if not ok or not itemString then return nil end
  local ok2, spd = pcall(TSM_API.GetCustomPriceValue, "DBRegionSoldPerDay", itemString)
  if ok2 and type(spd) == "number" then return spd end
  return nil
end

-- "Will this actually sell on the AH?" Greys can't be auctioned. Random weapons/
-- armor rarely sell at their listed "market" price, so they use vendor unless TSM
-- region sale data clears the bar. Mats and everything else default to AH. Works
-- with no TSM region data (the quality/class rule); sale data only refines gear.
local function SellsOnAH(link)
  local _, _, quality, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(link)
  if quality == 0 then return false end                 -- poor (grey): not auctionable
  if classID == 2 or classID == 4 then                  -- weapon / armor (gear)
    local spd = TSMSoldPerDay(link)
    return type(spd) == "number" and spd >= (settings.saleRateMin or 0.5)
  end
  return true                                           -- mats / trade goods / misc
end

local function AHValue(link, itemID)
  local vendor = select(11, C_Item.GetItemInfo(link)) or 0

  -- Per-item override (your /tim ah | /tim vendor rules) wins over the pricing mode.
  local rule = itemID and TimeIsMoneyDB.itemRules and TimeIsMoneyDB.itemRules[itemID]
  if rule == "vendor" then return vendor, "vendor (rule)" end
  local mode = (rule == "ah") and "ah" or (settings.priceMode or "sells")

  -- A) Vendor only: never use AH prices.
  if mode == "vendor" then
    return vendor, "vendor"
  end

  -- B) "AH if it sells": greys aren't auctionable and random gear rarely sells at
  -- its listed price, so those fall back to vendor. Mats use AH. (See SellsOnAH.)
  if mode == "sells" and not SellsOnAH(link) then
    return vendor, "vendor (won't sell)"
  end

  -- AH price: TSM market -> Auctionator -> vendor fallback.
  if TSM_API and TSM_API.ToItemString then
    local ok, itemString = pcall(TSM_API.ToItemString, link)
    if ok and itemString then
      local ok2, v = pcall(TSM_API.GetCustomPriceValue, settings.tsmSource or "DBMarket", itemString)
      if ok2 and v and v > 0 then return v, "TSM" end
    end
  end
  if itemID and Auctionator and Auctionator.API and Auctionator.API.v1
     and Auctionator.API.v1.GetAuctionPriceByItemID then
    local v = Auctionator.API.v1.GetAuctionPriceByItemID(ADDON, itemID)
    if v and v > 0 then return v, "Auctionator" end
  end
  if vendor > 0 then return vendor, "vendor" end
  return 0, "none"
end

----------------------------------------------------------------------
-- Sell workflow (#14): disposition engine + non-destructive preview
----------------------------------------------------------------------
-- Current expansion id. NOTE: expansionID is UNRELIABLE for "is this current" - some
-- current items report an older expac. So gear is never auto-sold on this tag alone; it's
-- only a secondary gate behind the item-level floor (see the BoP-gear branch).
local CURRENT_EXPANSION = _G.LE_EXPANSION_LEVEL_CURRENT or 99

-- Do we have a real AH price for this item (TSM market or Auctionator)? If so it's listable.
local function HasAHPrice(link, itemID)
  if TSM_API and TSM_API.ToItemString then
    local ok, itemString = pcall(TSM_API.ToItemString, link)
    if ok and itemString then
      local ok2, v = pcall(TSM_API.GetCustomPriceValue, settings.tsmSource or "DBMarket", itemString)
      if ok2 and v and v > 0 then return true end
    end
  end
  if itemID and Auctionator and Auctionator.API and Auctionator.API.v1
     and Auctionator.API.v1.GetAuctionPriceByItemID then
    local v = Auctionator.API.v1.GetAuctionPriceByItemID(ADDON, itemID)
    if v and v > 0 then return true end
  end
  return false
end

-- Is a price-source addon (TSM or Auctionator) even loaded? Distinguishes "no source at all"
-- from "source present but hasn't seen this item yet" for clearer guidance.
local function HasPriceSourceInstalled()
  if TSM_API and TSM_API.ToItemString then return true end
  if Auctionator and Auctionator.API and Auctionator.API.v1
     and Auctionator.API.v1.GetAuctionPriceByItemID then return true end
  return false
end

-- BoE AH-gate, three-state: "sells" | "wont" | "unknown". CRITICAL: "unknown" must NOT be
-- treated as "wont" - without a price source we can't tell, so the caller keeps it (never
-- auto-vendors a BoE we can't judge). Only grey + a confident low TSM sale-rate are "wont".
local function AHSellability(link, itemID)
  local _, _, quality, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(link)
  if quality == 0 then return "wont" end                  -- grey: not auctionable
  if HasAHPrice(link, itemID) then return "sells" end     -- real AH price = listable
  if classID == 2 or classID == 4 then                    -- gear: needs TSM region data to judge
    local spd = TSMSoldPerDay(link)
    if type(spd) == "number" then
      return (spd >= (settings.saleRateMin or 0.5)) and "sells" or "wont"
    end
    return "unknown"                                       -- gear, no price, no sale data
  end
  return "sells"                                           -- mats/recipes/etc w/o price: assume listable -> keep
end

-- Disposition for one item: "keep" | "vendor" | "auction", plus a plain-language reason.
-- Reuses SellsOnAH (the BoE AH-gate) and the vendor sell price already used in valuation.
-- Gathered mats fall through to "keep" - this clears junk, it never vendors your farm goods.
local function ItemDisposition(link)
  if not link then return "keep", "empty slot" end
  local itemID = tonumber(link:match("|Hitem:(%d+):"))
  local _, _, quality, ilvl, _, _, _, _, equipLoc, _, vendor, classID, _, bindType, expacID = C_Item.GetItemInfo(link)
  if quality == nil then return "keep", "not cached yet" end
  vendor = vendor or 0

  -- Your per-item rules win over the auto-logic. "exclude" is a hard never-sell.
  local rule = itemID and TimeIsMoneyDB.itemRules and TimeIsMoneyDB.itemRules[itemID]
  if rule == "exclude" then return "keep", "excluded (your rule)" end

  if classID == 12 or vendor <= 0 then return "keep", "not vendor-sellable" end  -- quest / no sell price

  if rule == "vendor" then return "vendor", "vendor (your rule)" end
  if rule == "ah"     then return "auction", "keep for AH (your rule)" end

  if quality == 0 then                                                           -- grey: no AH market
    if settings.sellSkipGreys then return "keep", "grey (left for your trash-seller)" end
    return "vendor", "grey"
  end

  local equippable = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP"
  -- Low ITEM LEVEL is the reliable "old junk gear" signal. expansionID is unreliable in both
  -- directions (current items can report an older expac, old items the current one), and the
  -- squish means current gear sits well above a sane floor - so we gate purely on ilvl, no
  -- expac test. Applies to equippable gear only (BoP and unpriceable BoE alike).
  local gearFloor  = settings.sellGearMaxIlvl or 0
  local belowFloor = equippable and gearFloor > 0 and (ilvl or 0) > 0 and ilvl <= gearFloor

  if bindType == 2 then                                                          -- Bind on Equip
    local s = AHSellability(link, itemID)
    if s == "sells" then return "auction", "BoE, sells on AH" end
    if s == "wont"  then return "vendor", "BoE, won't sell on AH" end
    if belowFloor  then return "vendor", ("old BoE, ilvl %d (no AH price)"):format(ilvl) end
    return "keep", "BoE, no price source - kept (can't judge)"                   -- safe default
  end

  if bindType == 1 and equippable then                                           -- Bind on Pickup gear
    if belowFloor then return "vendor", ("old BoP gear, ilvl %d"):format(ilvl) end
    return "keep", "BoP gear (kept; set /tim sellilvl or right-click to vendor)"
  end

  return "keep", "keep"
end
SG.ItemDisposition = ItemDisposition

-- Scan all bags and categorize by disposition. Pure data, sells nothing. Shared by the
-- text preview and the merchant review window. Returns:
--   vendor = { {bag, slot, link, count, reason, value}, ... }  (the would-vendor pile)
--   auction, keep, unjudgedBoE = counts;  totalVendor = copper
function SG.ScanSellables()
  local r = { vendor = {}, auction = 0, keep = 0, unjudgedBoE = 0, totalVendor = 0 }
  if not (C_Container and C_Container.GetContainerNumSlots) then return r end
  for bag = 0, 5 do
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link then
        local disp, reason = ItemDisposition(link)
        if disp == "vendor" then
          local info  = C_Container.GetContainerItemInfo(bag, slot)
          local count = (info and info.stackCount) or 1
          local each  = select(11, C_Item.GetItemInfo(link)) or 0
          r.totalVendor = r.totalVendor + each * count
          r.vendor[#r.vendor + 1] = { bag = bag, slot = slot, link = link, count = count, reason = reason, value = each * count }
        elseif disp == "auction" then
          r.auction = r.auction + 1
        else
          r.keep = r.keep + 1
          if reason:find("^BoE") then r.unjudgedBoE = r.unjudgedBoE + 1 end
        end
      end
    end
  end
  return r
end

-- One-line guidance about BoEs we couldn't price (nil if none). Reused by preview + window.
function SG.UnpricedBoENote(unjudgedBoE)
  if (unjudgedBoE or 0) <= 0 then return nil end
  if HasPriceSourceInstalled() then
    return ("%d BoE(s) kept - your AH addon has no recorded price for them yet. Open/scan the Auction House so the gate can judge them."):format(unjudgedBoE)
  end
  return ("%d BoE(s) kept - no AH price source. Install Auctionator (or TSM) so the gate can vendor BoEs that truly won't sell."):format(unjudgedBoE)
end

-- Print what WOULD be sold. Non-destructive.
local PREVIEW_CAP = 20
function SG.SellPreview()
  local r = SG.ScanSellables()
  Print(("|cff8fd694Sell preview|r - would VENDOR %d item(s) for ~%s (nothing is sold):"):format(#r.vendor, Money(r.totalVendor)))
  for i = 1, math.min(#r.vendor, PREVIEW_CAP) do
    local e = r.vendor[i]
    Print(("  %s x%d  %s  |cff808080(%s)|r"):format(e.link, e.count, Money(e.value), e.reason))
  end
  if #r.vendor > PREVIEW_CAP then Print(("  ... +%d more"):format(#r.vendor - PREVIEW_CAP)) end
  Print(("|cffffff00Hold for AH:|r %d BoE(s) that should sell.   |cff808080Keep:|r %d other item(s)."):format(r.auction, r.keep))
  local note = SG.UnpricedBoENote(r.unjudgedBoE)
  if note then Print("|cffff7070Note:|r " .. note) end
end

function SG.SellWindowEnabled() return settings.sellWindow ~= false end
function SG.ToggleSellWindow()
  settings.sellWindow = (settings.sellWindow == false) and true or false
  Print("Sell-review window auto-open = " .. (settings.sellWindow ~= false and "|cff8fd694on|r" or "|cff808080off|r"))
end

function SG.SellConfirmEnabled() return settings.sellConfirm ~= false end
function SG.ToggleSellConfirm()
  settings.sellConfirm = (settings.sellConfirm == false) and true or false
  Print("Confirm before selling gear/big piles = " .. (settings.sellConfirm ~= false and "|cff8fd694on|r" or "|cff808080off|r"))
end

function SG.ToggleSkipGreys()
  settings.sellSkipGreys = not settings.sellSkipGreys
  Print("Skip greys (leave them for another trash-seller) = " .. (settings.sellSkipGreys and "|cff8fd694on|r" or "|cff808080off|r"))
end

-- Item-level floor for auto-vendoring old BoP gear. 0 = never auto-vendor gear (default,
-- safe: gear is always kept unless you right-click it). Gear is never sold on the expansion
-- tag alone because that tag is unreliable for current items.
function SG.SetSellGearIlvl(arg)
  local n = tonumber(arg)
  if not n then
    Print(("Auto-vendor old BoP gear at/below ilvl: |cffffd200%d|r  (0 = never; e.g. /tim sellilvl 450)"):format(settings.sellGearMaxIlvl or 0))
    return
  end
  settings.sellGearMaxIlvl = math.max(0, math.floor(n))
  if settings.sellGearMaxIlvl == 0 then
    Print("BoP gear auto-vendor |cff808080OFF|r - gear is always kept (right-click an item to vendor specific pieces).")
  else
    Print(("Will auto-vendor old-expansion BoP gear at/below |cffffd200ilvl %d|r."):format(settings.sellGearMaxIlvl))
  end
end

-- Set/clear a per-item rule by itemID (used by the sell window's right-click menu).
local RULE_LABEL = { vendor = "always vendor", exclude = "never sell", ah = "keep for AH" }
function SG.SetItemRuleByID(rule, itemID, link)
  if not itemID then return end
  TimeIsMoneyDB.itemRules = TimeIsMoneyDB.itemRules or {}
  TimeIsMoneyDB.itemRules[itemID] = rule
  Print(("Rule set: %s -> |cff8fd694%s|r"):format(link or ("item:" .. itemID), RULE_LABEL[rule] or rule))
end
function SG.ClearItemRuleByID(itemID, link)
  if not itemID then return end
  if TimeIsMoneyDB.itemRules then TimeIsMoneyDB.itemRules[itemID] = nil end
  Print(("Rule cleared: %s"):format(link or ("item:" .. itemID)))
end

-- Session sell log: what the sell window vendored this session. Buyback only holds the last
-- 12 items, so this is the record of what to re-buy if you sold something by mistake.
SG.sellLog = {}
function SG.LogSale(link, count, value)
  local t = SG.sellLog
  t[#t + 1] = { link = link, count = count, value = value }
  if #t > 60 then table.remove(t, 1) end
end
function SG.PrintSellLog()
  local t = SG.sellLog
  if #t == 0 then Print("No sales recorded this session."); return end
  local from = math.max(1, #t - 14)
  Print(("|cff8fd694Sell log|r (this session, showing %d of %d):"):format(#t - from + 1, #t))
  for i = from, #t do
    local e = t[i]
    Print(("  %s x%d  %s"):format(e.link, e.count, Money(e.value)))
  end
end

----------------------------------------------------------------------
-- Recording loot
----------------------------------------------------------------------
local function RecordLoot(prof, link, qty)
  qty = qty or 1
  local itemID = tonumber(link:match("|Hitem:(%d+):"))
  if itemID and TimeIsMoneyDB.itemRules and TimeIsMoneyDB.itemRules[itemID] == "exclude" then
    if settings.debug then Print(("skip (excluded): %s"):format(link)) end
    return
  end
  local unitVal, source = AHValue(link, itemID)

  if source == "none" and not warnedNoSource then
    if HasPriceSourceInstalled() then
      -- Source IS installed - the item just has no recorded price yet (and no vendor value).
      Print("Some looted items have no recorded price yet (and no vendor value) - open/scan the Auction House so your price addon can value them. Counting those at 0 until then.")
    else
      Print("No price source found - install TradeSkillMaster or Auctionator for AH values. Using vendor price for now.")
    end
    warnedNoSource = true
  end

  local total = unitVal * qty

  if (settings.minValue or 0) > 0 and unitVal < settings.minValue then
    if settings.debug then Print(("skip (under min): %s @ %s/ea"):format(link, Money(unitVal))) end
    return
  end

  local today = Today()

  local day = TimeIsMoneyDB.days[today]
  if not day then day = {}; TimeIsMoneyDB.days[today] = day end
  local db = Bucket(day, prof)
  db.value = db.value + total
  db.count = db.count + qty

  local tb = Bucket(TimeIsMoneyDB.totals, prof)
  tb.value = tb.value + total
  tb.count = tb.count + qty

  if itemID then
    local it = TimeIsMoneyDB.items[itemID]
    if not it then
      it = { name = (C_Item.GetItemInfo(link)) or link, count = 0, value = 0, prof = prof }
      TimeIsMoneyDB.items[itemID] = it
    end
    it.count = it.count + qty
    it.value = it.value + total
  end

  if EnsureRun() then
    local sb = Bucket(SG.session.data, prof)
    sb.value = sb.value + total
    sb.count = sb.count + qty
    SG.session.events[#SG.session.events + 1] = { t = GetTime(), v = total }
    SG.session.lastActivity = GetTime()
  end

  if settings.debug then
    Print(("%s: %dx %s = %s (%s)"):format(prof, qty, link, Money(total), source))
  end

  if SG.RefreshUI then SG.RefreshUI() end
end

----------------------------------------------------------------------
-- Recording coin (looted gold)
----------------------------------------------------------------------
-- CHAT_MSG_MONEY carries a localized money string ("You loot 1 Gold, 20 Silver").
-- Build patterns from the game's own format globals so it stays locale-safe, the
-- same way the item-loot patterns below do.
local function AmountPattern(fmt) return (fmt or "%d"):gsub("%%d", "(%%d+)") end
local GOLD_PAT   = AmountPattern(GOLD_AMOUNT)     -- "(%d+) Gold"
local SILVER_PAT = AmountPattern(SILVER_AMOUNT)   -- "(%d+) Silver"
local COPPER_PAT = AmountPattern(COPPER_AMOUNT)   -- "(%d+) Copper"

local function ParseMoney(text)
  local g = tonumber(text:match(GOLD_PAT))   or 0
  local s = tonumber(text:match(SILVER_PAT)) or 0
  local c = tonumber(text:match(COPPER_PAT)) or 0
  return g * 10000 + s * 100 + c
end

local function RecordMoney(copper)
  if not copper or copper <= 0 then return end

  local today = Today()
  local day = TimeIsMoneyDB.days[today]
  if not day then day = {}; TimeIsMoneyDB.days[today] = day end
  local db = Bucket(day, "money")
  db.value = db.value + copper
  db.count = db.count + 1

  local tb = Bucket(TimeIsMoneyDB.totals, "money")
  tb.value = tb.value + copper
  tb.count = tb.count + 1

  if EnsureRun() then
    local sb = Bucket(SG.session.data, "money")
    sb.value = sb.value + copper
    sb.count = sb.count + 1
    SG.session.events[#SG.session.events + 1] = { t = GetTime(), v = copper }
    SG.session.lastActivity = GetTime()
  end

  if settings.debug then Print(("money: +%s"):format(Money(copper))) end
  if SG.RefreshUI then SG.RefreshUI() end
end

-- Realized vendor-sale gold -> the daily "sold" bucket. Deliberately kept OUT of the PROF
-- sources and the estimate totals (This run / Today / All-time / GPH), so those keep showing
-- the live *estimate*; only the daily chart reads liquidated gold (coin + sold). Not run-gated.
local function RecordSale(copper)
  if not copper or copper <= 0 then return end
  local today = Today()
  local day = TimeIsMoneyDB.days[today]
  if not day then day = {}; TimeIsMoneyDB.days[today] = day end
  local b = Bucket(day, "sold")
  b.value = b.value + copper
  b.count = b.count + 1
  if settings.debug then Print(("sold: +%s (liquidated)"):format(Money(copper))) end
  if SG.RefreshUI then SG.RefreshUI() end
end

-- Realized AH-sale gold -> the daily "ahSold" bucket (money received at the mailbox). Like
-- vendor sales, kept out of the estimate totals; feeds liquidated. Captured via PLAYER_MONEY
-- positive delta while the mailbox is open (see events) - simple + robust; for a farmer nearly
-- all mailbox income is auction gold. (Precise "Auction successful" subject-matching later.)
local function RecordAHSale(copper)
  if not copper or copper <= 0 then return end
  local today = Today()
  local day = TimeIsMoneyDB.days[today]
  if not day then day = {}; TimeIsMoneyDB.days[today] = day end
  local b = Bucket(day, "ahSold")
  b.value = b.value + copper
  b.count = b.count + 1
  if settings.debug then Print(("AH sale: +%s (liquidated)"):format(Money(copper))) end
  if SG.RefreshUI then SG.RefreshUI() end
end

----------------------------------------------------------------------
-- Loot-message parsing (locale-safe)
----------------------------------------------------------------------
local PAT_MULTI  = "^" .. LOOT_ITEM_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
local PAT_SINGLE = "^" .. LOOT_ITEM_SELF:gsub("%%s", "(.+)") .. "$"

-- Tailoring has no gather cast - tailors simply loot cloth from (mostly humanoid)
-- kills. So we identify cloth by item class (Trade Goods > Cloth) and credit it to
-- tailoring whenever no gather cast is currently active.
local function IsCloth(itemID)
  if not itemID then return false end
  local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
  return classID == 7 and subClassID == 5   -- Trade Goods > Cloth
end

-- Incidental run loot (greys, BoEs, BoP gear, mob drops). Only quest items are
-- skipped (unsellable). BoP gear IS counted - farmers vendor it (this run's pile
-- sold for 132g). A "keep these" blacklist + quality floor come with #10; the
-- actual vendor-sale reconciliation is Stage 2.
local function IsCountableDrop(link, itemID)
  if not itemID then return false end
  local classID = select(12, C_Item.GetItemInfo(link))
  if classID == 12 then return false end   -- Quest item (unsellable)
  return true
end

local function OnLoot(msg)
  local link, qty = msg:match(PAT_MULTI)
  if not link then link = msg:match(PAT_SINGLE); qty = 1 end
  if not link then return end

  local itemID = tonumber(link:match("|Hitem:(%d+):"))
  local prof
  if lastGatherProf and (GetTime() - lastGatherAt) <= (settings.window or 2.0) then
    -- A gather (skinning/mining/herbalism) just happened; this loot belongs to it.
    prof = lastGatherProf
  elseif settings.profs and settings.profs.tailoring and IsCloth(itemID) then
    -- No active gather: cloth picked up off a kill counts as tailoring farming.
    prof = "tailoring"
  elseif settings.countDrops and IsCountableDrop(link, itemID) then
    -- Incidental loot (greys, BoEs, etc.) -> the "drops" source. Always counts toward
    -- the lifetime ledger (Today/All-time); the run only captures it while active, via
    -- RecordLoot's EnsureRun. So lifetime tracking never depends on a run being started.
    prof = "drops"
  end

  if not prof then return end
  RecordLoot(prof, link, tonumber(qty) or 1)
end

----------------------------------------------------------------------
-- Spell name lookup
----------------------------------------------------------------------
local function SpellName(spellID)
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(spellID)
    return info and info.name
  end
  -- Legacy fallback only: the global GetSpellInfo was removed on retail 12.x, so guard it
  -- (feature-detect) rather than call a nil. Present only on classic builds.
  if GetSpellInfo then return (GetSpellInfo(spellID)) end
  return nil
end

----------------------------------------------------------------------
-- Public helpers used by the UI
----------------------------------------------------------------------
local function SumDay(day)
  local d, s = TimeIsMoneyDB.days[day], 0
  if d then for _, p in ipairs(SG.PROFS) do if d[p] then s = s + d[p].value end end end
  return s
end
SG.SumDay = SumDay

-- Liquidated gold that actually hit your wallet that day: looted coin + realized vendor
-- sales + realized AH sales. (No estimated item value.) Used by the chart AND the totals.
function SG.LiquidatedDay(day)
  local d = TimeIsMoneyDB.days[day]
  if not d then return 0 end
  local coin = d.money  and d.money.value  or 0
  local sold = d.sold   and d.sold.value   or 0
  local ah   = d.ahSold and d.ahSold.value or 0
  return coin + sold + ah
end

function SG.LiquidatedWeek()
  local s = 0
  for i = 0, 6 do s = s + SG.LiquidatedDay(date("%Y-%m-%d", time() - i * 86400)) end
  return s
end

-- Banked total across every recorded day (coin + vendor + AH). Iterating days is fine -
-- the table is bounded by how long you've played.
function SG.LiquidatedAllTime()
  local s = 0
  for day in pairs(TimeIsMoneyDB.days) do s = s + SG.LiquidatedDay(day) end
  return s
end

function SG.TodayValue() return SumDay(Today()) end

function SG.WeekValue()
  local s = 0
  for i = 0, 6 do s = s + SumDay(date("%Y-%m-%d", time() - i * 86400)) end
  return s
end

function SG.AllTimeValue()
  local s = 0
  for _, p in ipairs(SG.PROFS) do
    local t = TimeIsMoneyDB.totals[p]; if t then s = s + t.value end
  end
  return s
end

function SG.SessionValue()
  local s = 0
  for _, p in ipairs(SG.PROFS) do
    local b = SG.session.data[p]; if b then s = s + b.value end
  end
  return s
end

-- Reset dungeon instances (clear lockouts so you can re-run a farm). Guards for the cases
-- the game refuses, so the user gets a plain message instead of a silent no-op.
function SG.ResetInstances()
  if InCombatLockdown() then Print("Can't reset instances in combat."); return end
  if IsInInstance() then Print("Leave the instance first, then reset."); return end
  if IsInGroup() and not UnitIsGroupLeader("player") then
    Print("Only the group leader can reset instances."); return
  end
  ResetInstances()
  Print("Reset instances requested. (Dungeon lockouts cleared; saved raids are unaffected. Blizzard limits resets per hour.)")
end

function SG.SessionByProf(prof)
  local b = SG.session.data[prof]
  return b and b.value or 0
end

function SG.SessionGPH()
  local s = SG.session
  if not s.start then return 0 end
  if not s.active then return s.finalGPH or 0 end   -- run stopped: show the frozen final rate, don't let the rolling window decay
  if s.paused then return s.liveGPH or 0 end         -- paused: hold the rate as of the pause, don't decay while idle
  local now, ev = GetTime(), s.events
  local window = (settings and settings.gphWindow or 10) * 60

  -- drop events older than the window (oldest sit at the front)
  while ev[1] and (now - ev[1].t) > window do
    table.remove(ev, 1)
  end

  local recent = 0
  for i = 1, #ev do recent = recent + ev[i].v end
  if recent == 0 then return 0 end

  local elapsed = SG.RunElapsed()
  if elapsed <= 0 then elapsed = now - s.start end
  local span  = math.min(elapsed, window)
  local denom = math.max(span, GPH_FLOOR)
  s.liveGPH = recent / (denom / 3600)   -- cache so pause can hold this value
  return s.liveGPH
end

function SG.ResetData()
  TimeIsMoneyDB.days   = {}
  TimeIsMoneyDB.items  = {}
  TimeIsMoneyDB.totals = {}
  SG.session.active = false
  SG.session.paused = false
  SG.session.pausedAccum = 0
  SG.session.pauseStart  = nil
  SG.session.repairs = 0
  SG.session.startMissing = 0
  SG.session.start  = nil
  SG.session.data   = {}
  SG.session.events = {}
  if SG.RefreshUI then SG.RefreshUI() end
  Print("All tracked data cleared.")
end

function SG.ToggleDebug()
  TimeIsMoneyDB.settings.debug = not TimeIsMoneyDB.settings.debug
  Print("debug = " .. tostring(TimeIsMoneyDB.settings.debug))
end

function SG.ToggleAutoStart()
  settings.autoStartRun = not settings.autoStartRun
  Print("Auto-start runs = " .. (settings.autoStartRun and "|cff8fd694on|r" or "|cff808080off|r"))
  if SG.RefreshConfig then SG.RefreshConfig() end
end

function SG.ToggleDrops()
  settings.countDrops = not settings.countDrops
  Print("Count looted drops = " .. (settings.countDrops and "|cff8fd694on|r" or "|cff808080off|r"))
  if SG.RefreshConfig then SG.RefreshConfig() end
end

function SG.SetPriceMode(arg)
  arg = (arg or ""):lower()
  if arg ~= "vendor" and arg ~= "sells" and arg ~= "ah" then
    Print("Item pricing is '" .. (settings.priceMode or "sells") .. "'. Use: /tim pricing vendor | sells | ah")
    return
  end
  settings.priceMode = arg
  Print("Item pricing = |cff8fd694" .. arg .. "|r")
  if SG.RefreshConfig then SG.RefreshConfig() end
  if SG.RefreshUI then SG.RefreshUI() end
end

function SG.SetSaleRate(arg)
  local n = tonumber(arg)
  if not n or n < 0 then
    Print(("Sale-rate threshold is %.2f sales/day. Set with: /tim salerate 0.5"):format(settings.saleRateMin or 0.5))
    return
  end
  settings.saleRateMin = n
  Print(("Sale-rate threshold = %.2f sales/day (items selling slower use vendor price)."):format(n))
end

-- Diagnostic: shift-click an item after the command to see exactly what TSM returns.
function SG.PriceTest(arg)
  if not arg or arg == "" then
    Print("Usage: /tim pricetest <shift-click an item into chat>")
    return
  end
  if not (TSM_API and TSM_API.ToItemString and TSM_API.GetCustomPriceValue) then
    Print("TSM is not installed - can't query sale data.")
    return
  end
  local ok, itemString = pcall(TSM_API.ToItemString, arg)
  if not ok or not itemString then Print("Couldn't resolve that item."); return end
  Print("pricetest |cffffd100" .. tostring(itemString) .. "|r")
  for _, src in ipairs({ "DBMarket", "DBRegionSoldPerDay", "DBRegionSaleRate", "DBRegionSalePercent" }) do
    local ok2, v = pcall(TSM_API.GetCustomPriceValue, src, itemString)
    Print(("  %s = %s  (ok=%s)"):format(src, tostring(v), tostring(ok2)))
  end
end

----------------------------------------------------------------------
-- Per-item pricing rules (whitelist / blacklist): force AH, force vendor, or
-- exclude a specific item, overriding the pricing mode. Add by shift-clicking.
----------------------------------------------------------------------
local function RuleItemID(arg)
  return arg and tonumber(tostring(arg):match("Hitem:(%d+):"))
end

function SG.SetItemRule(rule, arg)
  local itemID = RuleItemID(arg)
  if not itemID then
    Print(("Usage: /tim %s <shift-click an item into chat>"):format(rule))
    return
  end
  TimeIsMoneyDB.itemRules = TimeIsMoneyDB.itemRules or {}
  TimeIsMoneyDB.itemRules[itemID] = rule
  local name = (C_Item.GetItemInfo(itemID)) or ("item:" .. itemID)
  Print(("Pricing rule: %s -> |cff8fd694%s|r"):format(name, rule))
  if SG.RefreshUI then SG.RefreshUI() end
end

function SG.ClearItemRule(arg)
  local itemID = RuleItemID(arg)
  if not itemID then Print("Usage: /tim clearrule <shift-click an item>"); return end
  if TimeIsMoneyDB.itemRules then TimeIsMoneyDB.itemRules[itemID] = nil end
  local name = (C_Item.GetItemInfo(itemID)) or ("item:" .. itemID)
  Print(("Pricing rule cleared: %s"):format(name))
  if SG.RefreshUI then SG.RefreshUI() end
end

function SG.ListItemRules()
  local r = TimeIsMoneyDB.itemRules or {}
  Print("Item pricing rules (override the pricing mode):")
  local n = 0
  for itemID, rule in pairs(r) do
    n = n + 1
    local name = (C_Item.GetItemInfo(itemID)) or ("item:" .. itemID)
    Print(("  %s = |cff8fd694%s|r"):format(name, rule))
  end
  if n == 0 then Print("  (none) - add with /tim ah | /tim vendor | /tim exclude + shift-click an item") end
end

----------------------------------------------------------------------
-- One-time import of older addon data (GatherGold, then SkinnerGold)
----------------------------------------------------------------------
local function ImportNewStructure(src)
  for day, d in pairs(src.days or {}) do
    if type(d) == "table" then
      local nd = TimeIsMoneyDB.days[day] or {}
      for _, p in ipairs(SG.PROFS) do
        if type(d[p]) == "table" then
          local b = Bucket(nd, p)
          b.value = b.value + (d[p].value or 0)
          b.count = b.count + (d[p].count or 0)
        end
      end
      TimeIsMoneyDB.days[day] = nd
    end
  end
  for _, p in ipairs(SG.PROFS) do
    if type(src.totals) == "table" and type(src.totals[p]) == "table" then
      local t = Bucket(TimeIsMoneyDB.totals, p)
      t.value = t.value + (src.totals[p].value or 0)
      t.count = t.count + (src.totals[p].count or 0)
    end
  end
end

local function ImportFlatSkinning(src)
  for day, d in pairs(src.days or {}) do
    if type(d) == "table" and type(d.value) == "number" then
      local nd = TimeIsMoneyDB.days[day] or {}
      local b = Bucket(nd, "skinning")
      b.value = b.value + d.value
      b.count = b.count + (d.count or 0)
      TimeIsMoneyDB.days[day] = nd
    end
  end
  if type(src.totalValue) == "number" then
    local t = Bucket(TimeIsMoneyDB.totals, "skinning")
    t.value = t.value + src.totalValue
    t.count = t.count + (src.totalCount or 0)
  end
end

local function MigrateOldData()
  if TimeIsMoneyDB.__migrated then return end
  if type(GatherGoldDB) == "table" then
    ImportNewStructure(GatherGoldDB)
    Print("Imported your previous GatherGold data.")
  elseif type(SkinnerGoldDB) == "table" then
    ImportFlatSkinning(SkinnerGoldDB)
    Print("Imported your previous SkinnerGold data.")
  end
  TimeIsMoneyDB.__migrated = true
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local f = CreateFrame("Frame")
SG.eventFrame = f
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("SKILL_LINES_CHANGED")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:RegisterEvent("CHAT_MSG_LOOT")
f:RegisterEvent("CHAT_MSG_MONEY")
f:RegisterEvent("PLAYER_MONEY")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
f:RegisterEvent("MAIL_SHOW")
f:RegisterEvent("MAIL_CLOSED")
f:RegisterEvent("UPDATE_INVENTORY_DURABILITY")

-- Book repair spending: keep the live repair cost while at a merchant, then record
-- it when Repair All runs (skip guild-bank-funded repairs - those cost you nothing).
if type(RepairAllItems) == "function" then
  hooksecurefunc("RepairAllItems", function(guildBankRepair)
    if guildBankRepair then return end                       -- flag says guild; trust it as a fast path
    local missing = lastMissing or 0
    if missing <= 0 then return end
    -- Don't trust the flag alone (some auto-repair addons guild-repair without setting it).
    -- Ground truth: snapshot gold now, re-check next frame - guild/free repairs leave your
    -- wallet untouched, so paid <= 0 means it cost YOU nothing, record nothing.
    local before   = GetMoney()
    local d0       = SG.session.startMissing or 0
    local runShare = math.max(0, missing - d0) / missing     -- charge only run-caused wear
    C_Timer.After(0, function()
      local paid = before - GetMoney()                       -- personal gold actually spent
      if paid > 0 then
        RecordRepair(paid * runShare)
        SG.session.startMissing = 0                           -- baseline reset only on a real repair
      end
    end)
  end)
end

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... == ADDON then
      TimeIsMoneyDB = TimeIsMoneyDB or {}
      MergeDefaults(TimeIsMoneyDB, DEFAULTS)
      settings = TimeIsMoneyDB.settings
      MigrateOldData()
      -- One-time: adopt the 220 gear floor for DBs that predate the setting (saved as 0,
      -- which MergeDefaults can't overwrite). Runs once; after this the user can set 0.
      if not TimeIsMoneyDB.didGearFloorMigration then
        if (settings.sellGearMaxIlvl or 0) == 0 then settings.sellGearMaxIlvl = 220 end
        TimeIsMoneyDB.didGearFloorMigration = true
      end
    end

  elseif event == "PLAYER_LOGIN" then
    RefreshGathering()
    lastMoney = GetMoney()
    if SG.InitUI then SG.InitUI() end
    if SG.RefreshUI then SG.RefreshUI() end

  elseif event == "SKILL_LINES_CHANGED" then
    RefreshGathering()

  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellID = ...
    if unit == "player" then
      local nm  = SpellName(spellID)
      local key = nm and (castToProf[nm] or ProfFromName(nm))
      if key and settings and settings.profs and settings.profs[key] then
        lastGatherAt = GetTime(); lastGatherProf = key
      end
      if settings and settings.debug and nm then
        Print(("cast %s (%s)%s"):format(nm, tostring(spellID), key and " -> " .. key or ""))
      end
    end

  elseif event == "CHAT_MSG_LOOT" then
    OnLoot((...))

  elseif event == "CHAT_MSG_MONEY" then
    if settings and settings.profs and settings.profs.money then
      RecordMoney(ParseMoney((...)))
    end

  elseif event == "PLAYER_MONEY" then
    local now = GetMoney()
    if lastMoney ~= nil then
      local delta = now - lastMoney
      -- Positive change tells us realized income, categorized by WHERE it happened:
      --   at a merchant -> vendor sale;  at the mailbox -> AH sale.
      -- Looted coin fires in the field (neither flag) via CHAT_MSG_MONEY, so no double
      -- count. Negative deltas (repairs/purchases/buyback/postage) are ignored here.
      if delta > 0 then
        if atMerchant then RecordSale(delta)
        elseif atMailbox then RecordAHSale(delta) end
      end
    end
    lastMoney = now

  elseif event == "MERCHANT_SHOW" then
    atMerchant = true
    lastRepairCost = (GetRepairAllCost and GetRepairAllCost()) or 0
    lastMissing = MissingDurability()

  elseif event == "MERCHANT_CLOSED" then
    atMerchant = false

  elseif event == "MAIL_SHOW" then
    atMailbox = true

  elseif event == "MAIL_CLOSED" then
    atMailbox = false

  elseif event == "UPDATE_INVENTORY_DURABILITY" then
    if atMerchant then
      lastRepairCost = (GetRepairAllCost and GetRepairAllCost()) or 0
      lastMissing = MissingDurability()
    end
  end
end)
