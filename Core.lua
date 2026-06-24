local ADDON, ns = ...
local SG = ns

----------------------------------------------------------------------
-- Professions tracked
----------------------------------------------------------------------
SG.PROFS = { "skinning", "mining", "herbalism", "tailoring" }
SG.PROF_LABEL = { skinning = "Skinning", mining = "Mining", herbalism = "Herbalism", tailoring = "Tailoring" }

local SKILL_LINE = { [393] = "skinning", [186] = "mining", [182] = "herbalism" }

-- Fallback cast-name -> profession (English; extend via /gpg debug if a locale differs)
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
  days     = {},   -- ["YYYY-MM-DD"] = { skinning={value,count}, mining=..., herbalism=... }
  items    = {},   -- [itemID] = { name, count, value, prof }
  totals   = {},   -- prof -> {value,count}
  settings = {
    window    = 2.0,            -- seconds: loot attributed to a gather after its cast
    debug     = false,
    gphWindow = 10,             -- minutes: rolling window for the Gold/hour figure
    tsmSource = "DBMarket",     -- TSM price string used when TSM is installed
    minValue  = 0,              -- copper: ignore items whose per-unit value is below this
    profs     = { skinning = true, mining = true, herbalism = true, tailoring = true },
  },
}

SG.session = { start = nil, data = {}, events = {} }   -- data[prof]={value,count}; events={ {t,v} }

local GPH_FLOOR  = 120   -- seconds: minimum denominator, so an opening burst can't read absurdly high

local castToProf   = {}
local lastGatherAt = 0
local lastGatherProf
local settings
local warnedNoSource = false

----------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------
local function Print(msg) print("|cff8fd694GoldPerGather|r: " .. tostring(msg)) end
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
local function AHValue(link, itemID)
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
  local sell = select(11, C_Item.GetItemInfo(link))
  if sell and sell > 0 then return sell, "vendor" end
  return 0, "none"
end

----------------------------------------------------------------------
-- Recording loot
----------------------------------------------------------------------
local function RecordLoot(prof, link, qty)
  qty = qty or 1
  local itemID = tonumber(link:match("|Hitem:(%d+):"))
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

  local day = GoldPerGatherDB.days[today]
  if not day then day = {}; GoldPerGatherDB.days[today] = day end
  local db = Bucket(day, prof)
  db.value = db.value + total
  db.count = db.count + qty

  local tb = Bucket(GoldPerGatherDB.totals, prof)
  tb.value = tb.value + total
  tb.count = tb.count + qty

  if itemID then
    local it = GoldPerGatherDB.items[itemID]
    if not it then
      it = { name = (C_Item.GetItemInfo(link)) or link, count = 0, value = 0, prof = prof }
      GoldPerGatherDB.items[itemID] = it
    end
    it.count = it.count + qty
    it.value = it.value + total
  end

  if not SG.session.start then SG.session.start = GetTime() end
  local sb = Bucket(SG.session.data, prof)
  sb.value = sb.value + total
  sb.count = sb.count + qty
  SG.session.events[#SG.session.events + 1] = { t = GetTime(), v = total }

  if settings.debug then
    Print(("%s: %dx %s = %s (%s)"):format(prof, qty, link, Money(total), source))
  end

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

local function OnLoot(msg)
  local link, qty = msg:match(PAT_MULTI)
  if not link then link = msg:match(PAT_SINGLE); qty = 1 end
  if not link then return end

  local prof
  if lastGatherProf and (GetTime() - lastGatherAt) <= (settings.window or 2.0) then
    -- A gather (skinning/mining/herbalism) just happened; this loot belongs to it.
    prof = lastGatherProf
  elseif settings.profs and settings.profs.tailoring then
    -- No active gather: cloth picked up off a kill counts as tailoring farming.
    local itemID = tonumber(link:match("|Hitem:(%d+):"))
    if IsCloth(itemID) then prof = "tailoring" end
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
  local d, s = GoldPerGatherDB.days[day], 0
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
    local t = GoldPerGatherDB.totals[p]; if t then s = s + t.value end
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

  local span  = math.min(now - s.start, window)
  local denom = math.max(span, GPH_FLOOR)
  return recent / (denom / 3600)
end

function SG.ResetData()
  GoldPerGatherDB.days   = {}
  GoldPerGatherDB.items  = {}
  GoldPerGatherDB.totals = {}
  SG.session.start = nil
  SG.session.data  = {}
  SG.session.events = {}
  if SG.RefreshUI then SG.RefreshUI() end
  Print("All tracked data cleared.")
end

function SG.ToggleDebug()
  GoldPerGatherDB.settings.debug = not GoldPerGatherDB.settings.debug
  Print("debug = " .. tostring(GoldPerGatherDB.settings.debug))
end

----------------------------------------------------------------------
-- One-time import of older addon data (GatherGold, then SkinnerGold)
----------------------------------------------------------------------
local function ImportNewStructure(src)
  for day, d in pairs(src.days or {}) do
    if type(d) == "table" then
      local nd = GoldPerGatherDB.days[day] or {}
      for _, p in ipairs(SG.PROFS) do
        if type(d[p]) == "table" then
          local b = Bucket(nd, p)
          b.value = b.value + (d[p].value or 0)
          b.count = b.count + (d[p].count or 0)
        end
      end
      GoldPerGatherDB.days[day] = nd
    end
  end
  for _, p in ipairs(SG.PROFS) do
    if type(src.totals) == "table" and type(src.totals[p]) == "table" then
      local t = Bucket(GoldPerGatherDB.totals, p)
      t.value = t.value + (src.totals[p].value or 0)
      t.count = t.count + (src.totals[p].count or 0)
    end
  end
end

local function ImportFlatSkinning(src)
  for day, d in pairs(src.days or {}) do
    if type(d) == "table" and type(d.value) == "number" then
      local nd = GoldPerGatherDB.days[day] or {}
      local b = Bucket(nd, "skinning")
      b.value = b.value + d.value
      b.count = b.count + (d.count or 0)
      GoldPerGatherDB.days[day] = nd
    end
  end
  if type(src.totalValue) == "number" then
    local t = Bucket(GoldPerGatherDB.totals, "skinning")
    t.value = t.value + src.totalValue
    t.count = t.count + (src.totalCount or 0)
  end
end

local function MigrateOldData()
  if GoldPerGatherDB.__migrated then return end
  if type(GatherGoldDB) == "table" then
    ImportNewStructure(GatherGoldDB)
    Print("Imported your previous GatherGold data.")
  elseif type(SkinnerGoldDB) == "table" then
    ImportFlatSkinning(SkinnerGoldDB)
    Print("Imported your previous SkinnerGold data.")
  end
  GoldPerGatherDB.__migrated = true
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

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... == ADDON then
      GoldPerGatherDB = GoldPerGatherDB or {}
      MergeDefaults(GoldPerGatherDB, DEFAULTS)
      settings = GoldPerGatherDB.settings
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
  end
end)
