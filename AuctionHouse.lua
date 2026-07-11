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

-- Read the cheapest listing for an item after its search results arrive.
local function ReadResult(itemID)
  if not itemID then return end
  local e = lowest[itemID]; if not e then e = {}; lowest[itemID] = e end
  local got
  if e.isComm and AH.GetCommoditySearchResultInfo then
    local ok, info = pcall(AH.GetCommoditySearchResultInfo, itemID, 1)   -- sorted asc: index 1 = cheapest
    if ok and info and info.unitPrice and info.unitPrice > 0 then got = info.unitPrice end
  elseif AH.GetItemSearchResultInfo and AH.MakeItemKey then
    local ok, info = pcall(AH.GetItemSearchResultInfo, AH.MakeItemKey(itemID), 1)
    if ok and info then got = info.buyoutAmount or info.bidAmount end
  end
  if got and got > 0 then
    if not e.unit then matched = matched + 1 end
    e.unit, e.t = got, GetTime()
    if S().debug then SG.Print(("  AH price %s = %s"):format(tostring(itemID), SG.Money(got))) end
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
      if itemID and not seen[itemID] then seen[itemID] = true; queue[#queue + 1] = itemID end
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

ef:RegisterEvent("AUCTION_HOUSE_SHOW")
ef:RegisterEvent("AUCTION_HOUSE_CLOSED")
ef:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
ef:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
ef:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
ef:SetScript("OnEvent", function(_, event, arg1)
  if event == "AUCTION_HOUSE_SHOW" then
    atAH = true
    if S().ahAutoScan ~= false then C_Timer.After(0.5, StartScan) end
    if SG.OnAuctionHouse then SG.OnAuctionHouse(true) end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    atAH, scanning, pending = false, false, nil
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
