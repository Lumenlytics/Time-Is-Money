local ADDON, ns = ...
local SG = ns

----------------------------------------------------------------------
-- #12 self-contained AH price source (STAGE 1: scan-only, no posting).
-- When the Auction House opens, scan the current lowest buyout for JUST the
-- AH-goods sitting in your bags (a small, targeted set - not a full AH scan),
-- and cache it. Needs NO TSM/Auctionator. Posting itself is Stage 2.
--
-- The AH rate-limits searches hard: firing many queries back-to-back gets most
-- of them silently dropped. So we send ONE query at a time, only when
-- C_AuctionHouse.IsThrottledMessageSystemReady() is true, and let the
-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY event re-drive the queue.
----------------------------------------------------------------------

local AH = C_AuctionHouse

local atAH = false
local lowest = {}          -- itemID -> { unit = copper, isComm = bool, t = GetTime() }
local queue  = {}          -- itemIDs still to scan this visit
local pending = nil        -- itemID we're currently waiting on results for
local scanning = false
local total, matched = 0, 0

local function S() return TimeIsMoneyDB.settings end

function SG.AtAuctionHouse() return atAH end
function SG.AHScanning()     return scanning end

-- Scanned lowest unit price for an item (nil = unknown / not scanned / no listings).
function SG.AHLowest(itemID)
  local e = itemID and lowest[itemID]
  return e and e.unit
end

-- Suggested post price: undercut the scanned lowest by the configured percent.
-- nil when we have no market data (caller falls back / skips - never post blind).
function SG.AHPostPrice(itemID)
  local unit = SG.AHLowest(itemID)
  if not unit or unit <= 0 then return nil end
  local pct = (S().ahUndercut or 5) / 100
  return math.max(1, math.floor(unit * (1 - pct)))
end

-- One-shot capability report so we can see exactly what the live 12.x AH API exposes.
local diagShown = false
local function Diag(extra)
  local function has(n) return (AH and AH[n]) and "y" or "|cffff7070NO|r" end
  SG.Print("|cffffd200AH diag|r  MakeItemKey=" .. has("MakeItemKey")
    .. " SendSearchQuery=" .. has("SendSearchQuery")
    .. " GetCommoditySearchResultInfo=" .. has("GetCommoditySearchResultInfo")
    .. " GetItemSearchResultInfo=" .. has("GetItemSearchResultInfo")
    .. " IsThrottledReady=" .. has("IsThrottledMessageSystemReady"))
  SG.Print("|cffffd200AH diag|r  SortOrder.Price="
    .. tostring(Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price)
    .. (extra and ("  " .. extra) or ""))
end

-- Item key + whether the item is a commodity (mats/consumables) vs a unique item (gear).
local function KeyAndCommodity(itemID)
  if not (AH and AH.MakeItemKey) then return nil, false end
  local ok, key = pcall(AH.MakeItemKey, itemID)
  if not ok or not key then return nil, false end
  local isComm = true
  if AH.GetItemKeyInfo then
    local ok2, info = pcall(AH.GetItemKeyInfo, key)
    if ok2 and info and info.isCommodity ~= nil then isComm = info.isCommodity end
  end
  return key, isComm
end

-- Sort commodities/items cheapest-first when the enum is available; empty (server default)
-- otherwise. NOTE: the sort field is `reverseSort`, not `reverse` (12.x arg validation is strict).
local function PriceSorts()
  if Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price then
    return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  end
  return {}
end

-- Read the cheapest listing AND the supply depth (total quantity listed, # of price points)
-- for an item after its search results arrive. Depth is the #15 "competition" signal.
local function ReadResult(itemID)
  if not itemID then return end
  local e = lowest[itemID]; if not e then e = {}; lowest[itemID] = e end
  local got, qty, listings = nil, 0, 0
  if e.isComm and AH.GetCommoditySearchResultInfo then
    local ok, info = pcall(AH.GetCommoditySearchResultInfo, itemID, 1)   -- sorted asc: index 1 = cheapest
    if ok and info and info.unitPrice and info.unitPrice > 0 then got = info.unitPrice end
    local num = (AH.GetNumCommoditySearchResults and AH.GetNumCommoditySearchResults(itemID)) or 0
    listings = num
    for i = 1, math.min(num, 100) do                                     -- sum listed quantity (cap 100 rows)
      local ok2, ri = pcall(AH.GetCommoditySearchResultInfo, itemID, i)
      if ok2 and ri and ri.quantity then qty = qty + ri.quantity end
    end
  elseif AH.GetItemSearchResultInfo and AH.MakeItemKey then
    local key = AH.MakeItemKey(itemID)
    local ok, info = pcall(AH.GetItemSearchResultInfo, key, 1)
    if ok and info then got = info.buyoutAmount or info.bidAmount end
    listings = (AH.GetNumItemSearchResults and AH.GetNumItemSearchResults(key)) or 0
    qty = listings
  end
  if got and got > 0 then
    if not e.unit then matched = matched + 1 end
    e.unit, e.t = got, GetTime()
    e.qty, e.listings = qty, listings
    if S().debug then SG.Print(("  AH %s = %s  (%d listed, %d rows)"):format(tostring(itemID), SG.Money(got), qty, listings)) end
  end
end

local ef = CreateFrame("Frame")

-- Queue driver: send the next query when the throttle system is ready and nothing is pending.
local function Step()
  if not atAH then scanning = false; return end
  if pending then return end                       -- waiting on a result already
  if #queue == 0 then
    if scanning then
      scanning = false
      SG.Print(("AH scan complete: got live prices for |cffffd200%d|r of %d item(s)."):format(matched, total))
      if matched == 0 and total > 0 and not diagShown then diagShown = true; Diag() end
      if SG.RefreshUI then SG.RefreshUI() end
    end
    return
  end
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
    return                                          -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY will re-drive us
  end
  local itemID = table.remove(queue, 1)
  local key, isComm = KeyAndCommodity(itemID)
  if not key then
    if not diagShown then diagShown = true; Diag("first item " .. tostring(itemID) .. ": no item key") end
    return Step()
  end
  local e = lowest[itemID]; if not e then e = {}; lowest[itemID] = e end
  e.isComm = isComm
  pending = itemID
  local ok, err = pcall(AH.SendSearchQuery, key, PriceSorts(), true)
  if not ok then
    if not diagShown then diagShown = true; Diag("SendSearchQuery err: " .. tostring(err)) end
    pending = nil; return Step()
  end
  -- Watchdog: if no result event lands (e.g. item with zero listings), don't stall the queue.
  C_Timer.After(3.0, function() if pending == itemID then pending = nil; Step() end end)
end

-- Build the queue from the AH-goods in your bags and start scanning.
local function StartScan()
  if not (AH and atAH) then return end
  wipe(queue); pending = nil; matched = 0; diagShown = false
  local seen = {}
  local r = SG.ScanSellables and SG.ScanSellables()
  if r and r.ah then
    for _, entry in ipairs(r.ah) do
      local itemID = tonumber((entry.link or ""):match("|Hitem:(%d+):"))
      if itemID and not seen[itemID] then
        seen[itemID] = true; queue[#queue + 1] = itemID
        local e = lowest[itemID]; if not e then e = {}; lowest[itemID] = e end
        e.link = entry.link                       -- remember the link for the Market view
      end
    end
  end
  total = #queue
  scanning = total > 0
  if scanning then
    SG.Print(("Scanning AH prices for %d item(s)..."):format(total))
    Step()
  end
end
SG.AHScan = StartScan

-- #15 hot-commodity: the scanned items ranked by "worth farming" = high value, thin supply.
-- Score = unit price / (quantity listed + 1), so a pricey mat with little competition floats up.
function SG.AHMarket()
  local out = {}
  for itemID, e in pairs(lowest) do
    if e.unit and e.unit > 0 and e.link then
      out[#out + 1] = { itemID = itemID, link = e.link, unit = e.unit, qty = e.qty or 0, listings = e.listings or 0 }
    end
  end
  table.sort(out, function(a, b) return (a.unit / (a.qty + 1)) > (b.unit / (b.qty + 1)) end)
  return out
end

----------------------------------------------------------------------
-- #15 category market search. One browse query returns a WHOLE trade-good category with each
-- item's supply (totalQuantity) + min price - so you can spot under-supplied mats you AREN'T
-- holding. Sorted price-desc so the first page is the valuable items; we rank client-side by
-- worth-farming = value / supply. Self-contained; no TSM.
----------------------------------------------------------------------
local CATEGORIES = {
  { key = "herbs",   label = "Herbs",   classID = 7, subClassID = 9 },
  { key = "ore",     label = "Ore",     classID = 7, subClassID = 7 },
  { key = "leather", label = "Leather", classID = 7, subClassID = 6 },
  { key = "cloth",   label = "Cloth",   classID = 7, subClassID = 5 },
  { key = "cooking", label = "Cooking", classID = 7, subClassID = 8 },
}
SG.AHCategories = CATEGORIES

-- The market categories the CURRENT character can actually gather, keyed by profession skill-line
-- ID (locale-independent, unlike profession names). Lets the Market view flag "your" categories,
-- so a skinner instantly sees Leather is theirs. Herbalism->herbs, Mining->ore, Skinning->leather,
-- Fishing/Cooking->cooking, Tailoring->cloth.
local SKILL_TO_CAT = { [182] = "herbs", [186] = "ore", [393] = "leather", [356] = "cooking", [185] = "cooking", [197] = "cloth" }
function SG.GatherCategories()
  local cats = {}
  if not (GetProfessions and GetProfessionInfo) then return cats end
  local function add(idx)
    if not idx then return end
    local skillLine = select(7, GetProfessionInfo(idx))   -- 7th return = skill-line ID
    local cat = skillLine and SKILL_TO_CAT[skillLine]
    if cat then cats[cat] = true end
  end
  local p1, p2, _, fishing, cooking = GetProfessions()
  add(p1); add(p2); add(fishing); add(cooking)
  return cats
end

local browseResults, browseCategory = {}, nil
local rawBrowse = {}          -- unfiltered {itemID, name, minPrice, qty} straight from the browse
local finalizeScheduled = false
function SG.AHBrowseCategory() return browseCategory end
function SG.AHBrowseResults() return browseResults end
function SG.SetAHBrowseBags() browseCategory = nil; if SG.RefreshUI then SG.RefreshUI() end end

function SG.AHBrowse(catKey)
  if not (AH and atAH and AH.SendBrowseQuery) then SG.Print("Open the Auction House first."); return end
  local cat
  for _, c in ipairs(CATEGORIES) do if c.key == catKey then cat = c; break end end
  if not cat then return end
  browseCategory = catKey
  wipe(browseResults); wipe(rawBrowse)
  local invType = (Enum and Enum.InventoryType and Enum.InventoryType.IndexNonEquipType) or 0
  local query = {
    searchString = "", minLevel = 0, maxLevel = 0, filters = {},
    itemClassFilters = { { classID = cat.classID, subClassID = cat.subClassID, inventoryType = invType } },
    sorts = {},                                          -- no sort: we fetch the whole category and rank ourselves
  }
  local ok, err = pcall(AH.SendBrowseQuery, query)
  if not ok then SG.Print("Browse failed: " .. tostring(err)); return end
  SG.Print(("Browsing |cffffd200%s|r on the AH..."):format(cat.label))
  if SG.RefreshUI then SG.RefreshUI() end
end

-- Rebuild browseResults from rawBrowse: drop greys (quality 0, the troll-listed vendor trash)
-- and extreme price outliers, then rank by worth-farming = value / supply. Quality needs the
-- item cached; uncached items are requested and this re-runs on GET_ITEM_INFO_RECEIVED, so the
-- greys drop out as their data loads. Items whose quality is still unknown are held back (not
-- shown) so an unfiltered grey never flashes into the list.
local function FinalizeBrowse()
  local tmp = {}
  for _, e in ipairs(rawBrowse) do
    local quality = select(3, C_Item.GetItemInfo(e.itemID))
    if quality == nil then
      if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(e.itemID) end   -- load, refilter later
    elseif quality > 0 then                                                                  -- keep non-grey only
      tmp[#tmp + 1] = { itemID = e.itemID, name = e.name, quality = quality, minPrice = e.minPrice, qty = e.qty }
    end
  end

  wipe(browseResults)
  local median = 0
  if #tmp > 4 then
    local prices = {}
    for _, e in ipairs(tmp) do prices[#prices + 1] = e.minPrice end
    table.sort(prices)
    median = prices[math.ceil(#prices / 2)] or 0
  end
  local cap = median * 100
  for _, e in ipairs(tmp) do
    -- Outlier guard: a price far above the category norm on a thin stack = troll listing.
    if not (median > 0 and e.minPrice > cap and e.qty < 20) then
      browseResults[#browseResults + 1] = e
    end
  end
  table.sort(browseResults, function(a, b) return (a.minPrice / (a.qty + 1)) > (b.minPrice / (b.qty + 1)) end)
  if SG.RefreshUI then SG.RefreshUI() end
end

-- Fires on AUCTION_HOUSE_BROWSE_RESULTS_UPDATED. Collect the page; if the category has more
-- pages, fetch them (we want the whole category to rank correctly), else finalize.
local function ReadBrowse()
  wipe(rawBrowse)
  local list = (AH.GetBrowseResults and AH.GetBrowseResults()) or {}
  for _, br in ipairs(list) do
    local itemID = br.itemKey and br.itemKey.itemID
    if itemID and br.minPrice and br.minPrice > 0 then
      local name
      if AH.GetItemKeyInfo then
        local ok, info = pcall(AH.GetItemKeyInfo, br.itemKey)
        if ok and info then name = info.itemName end
      end
      rawBrowse[#rawBrowse + 1] = { itemID = itemID, name = name, minPrice = br.minPrice, qty = br.totalQuantity or 0 }
    end
  end
  if AH.HasFullBrowseResults and not AH.HasFullBrowseResults() and AH.RequestMoreBrowseResults then
    AH.RequestMoreBrowseResults()      -- another BROWSE_RESULTS_UPDATED will follow
    return
  end
  FinalizeBrowse()
end
SG.ReadBrowse = ReadBrowse

-- Re-run the grey/outlier filter as item data loads in (debounced).
function SG.OnItemInfoReceived()
  if browseCategory and #rawBrowse > 0 and not finalizeScheduled then
    finalizeScheduled = true
    C_Timer.After(0.2, function() finalizeScheduled = false; FinalizeBrowse() end)
  end
end

-- NOTE: one-click AH posting is NOT possible in this game version - C_AuctionHouse.PostCommodity/
-- PostItem are protected and trip ADDON_ACTION_BLOCKED even from a real button click (confirmed
-- by an addon-isolation test). So Time Is Money is a PRICE HELPER: SG.AHPostPrice (above) gives
-- the undercut price to list at, shown on the Gains AH column, and you post by hand via
-- Blizzard's Auction House. The posting engine was removed rather than shipped disabled.

ef:RegisterEvent("AUCTION_HOUSE_SHOW")
ef:RegisterEvent("AUCTION_HOUSE_CLOSED")
ef:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
ef:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
ef:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
ef:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
ef:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ef:SetScript("OnEvent", function(_, event, arg1)
  if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    ReadBrowse()
    return
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if SG.OnItemInfoReceived then SG.OnItemInfoReceived() end
    return
  end
  if event == "AUCTION_HOUSE_SHOW" then
    atAH = true
    if S().ahAutoScan ~= false then C_Timer.After(0.5, StartScan) end
    if SG.OnAuctionHouse then SG.OnAuctionHouse(true) end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    atAH, scanning, pending, browseCategory = false, false, nil, nil
    wipe(queue)
    if SG.OnAuctionHouse then SG.OnAuctionHouse(false) end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if scanning and not pending then Step() end     -- ready to send the next query
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local itemID = arg1
    ReadResult(itemID)
    if pending == itemID then pending = nil; Step() end
    if SG.RefreshUI then SG.RefreshUI() end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local itemID = (type(arg1) == "table" and arg1.itemID) or pending   -- arg1 is an itemKey
    ReadResult(itemID)
    if pending == itemID then pending = nil; Step() end
    if SG.RefreshUI then SG.RefreshUI() end
  end
end)
