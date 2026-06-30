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

  if repairs > 0 then
    Print(("Run ended - %s, %s gross - %s repairs = |cff8fd694%s net|r (%s/hr)"):format(
      FmtDuration(dur), Money(total), Money(repairs), Money(net), Money(gph)))
  else
    Print(("Run ended - %s, %s total (%s/hr)"):format(FmtDuration(dur), Money(total), Money(gph)))
  end
  local parts = {}
  for _, p in ipairs(SG.PROFS) do
    local v = SG.SessionByProf(p)
    if v > 0 then parts[#parts + 1] = ("%s %s"):format(SG.PROF_LABEL[p], Money(v)) end
  end
  if #parts > 0 then Print("   " .. table.concat(parts, "   ")) end
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
    Print("No price source found - install TradeSkillMaster or Auctionator for AH values. Using vendor price for now.")
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
  return (GetSpellInfo(spellID))
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

function SG.SessionByProf(prof)
  local b = SG.session.data[prof]
  return b and b.value or 0
end

function SG.SessionGPH()
  local s = SG.session
  if not s.start then return 0 end
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
  return recent / (denom / 3600)
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
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
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
    end

  elseif event == "PLAYER_LOGIN" then
    RefreshGathering()
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

  elseif event == "MERCHANT_SHOW" then
    atMerchant = true
    lastRepairCost = (GetRepairAllCost and GetRepairAllCost()) or 0
    lastMissing = MissingDurability()

  elseif event == "MERCHANT_CLOSED" then
    atMerchant = false

  elseif event == "UPDATE_INVENTORY_DURABILITY" then
    if atMerchant then
      lastRepairCost = (GetRepairAllCost and GetRepairAllCost()) or 0
      lastMissing = MissingDurability()
    end
  end
end)
