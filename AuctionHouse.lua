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
-- STAGE 2: one-click posting. Undercut the scanned lowest, throttled, with a
-- preview + confirm. Never posts an item we have no scanned price for (no blind posts).
----------------------------------------------------------------------

local function PostDuration()
  local d = S().ahDuration
  return (d == 1 or d == 2 or d == 3) and d or 2    -- 1 = 12h, 2 = 24h, 3 = 48h
end

-- Postable AH-goods that have a scanned price, each with its computed (undercut) post price.
local function BuildPostList()
  local list = {}
  local r = SG.ScanSellables and SG.ScanSellables()
  if not (r and r.ah) then return list end
  for _, e in ipairs(r.ah) do
    local itemID = tonumber((e.link or ""):match("|Hitem:(%d+):"))
    local price = itemID and SG.AHPostPrice(itemID)
    if price and price > 0 then
      local le = lowest[itemID]
      list[#list + 1] = { bag = e.bag, slot = e.slot, link = e.link, count = e.count,
                          itemID = itemID, unit = price, isComm = le and le.isComm }
    end
  end
  return list
end

-- Count + total gold of what Post All would list right now (for the footer readout).
function SG.PostSummary()
  local list = BuildPostList()
  local t = 0
  for _, x in ipairs(list) do t = t + x.unit * x.count end
  return #list, t
end

-- The pending post queue - persists across clicks so you can drain it a burst at a time.
local postQueue = {}
function SG.PostQueueCount() return #postQueue end

-- Post as many queued items as allowed. MUST run inside a hardware event (a real button
-- click): PostCommodity/PostItem are protected and blocked if called from a timer/callback.
-- So there is NO C_Timer here - we loop synchronously, stopping if the message system throttles.
local function DoPostBatch()
  local posted, gold, failed, firstErr = 0, 0, 0, nil
  while #postQueue > 0 do
    if not atAH then break end
    if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then break end
    local x = table.remove(postQueue, 1)
    if C_Container.GetContainerItemLink(x.bag, x.slot) == x.link then
      local loc = ItemLocation and ItemLocation:CreateFromBagAndSlot(x.bag, x.slot)
      if loc and loc:IsValid() then
        -- Called DIRECTLY (no pcall): PostCommodity/PostItem are hardware-event protected, and
        -- a pcall boundary strips the secure context, tripping ADDON_ACTION_BLOCKED.
        if x.isComm then
          AH.PostCommodity(loc, PostDuration(), x.count, x.unit)
        else
          AH.PostItem(loc, PostDuration(), x.count, x.unit, x.unit)   -- bid = buyout
        end
        posted = posted + 1; gold = gold + x.unit * x.count
      end
    end
  end
  if posted > 0 then SG.Print(("Posted |cffffffff%d|r listing(s) for ~%s."):format(posted, SG.Money(gold))) end
  if failed > 0 then SG.Print(("|cffff7070%d post(s) failed.|r First error: %s"):format(failed, tostring(firstErr))) end
  if #postQueue > 0 then SG.Print(("|cffffd200%d remaining|r - click Post All again to continue."):format(#postQueue)) end
  if SG.RefreshUI then SG.RefreshUI() end
end
SG.DoPostBatch = DoPostBatch

-- Two-click confirm, entirely on OUR button. StaticPopup's OnClick does NOT carry the
-- hardware-event flag into its OnAccept, so posting from a popup is blocked. Posting must
-- happen synchronously inside our own button's OnClick (a genuine hardware event), so the
-- confirm is: first click arms + previews, second click posts.
local armed, armTimer = false, nil
function SG.PostArmed() return armed end
local function Disarm()
  armed = false
  if armTimer then armTimer:Cancel(); armTimer = nil end
  if SG.RefreshUI then SG.RefreshUI() end
end

-- Auto-posting is blocked by the client's protected-function system in this build (calling
-- C_AuctionHouse.PostCommodity even from a real button click trips ADDON_ACTION_BLOCKED). Until
-- that's resolved, this stays a PRICE HELPER: the AH column shows the undercut price to post by
-- hand via Blizzard's AH. Kept as a stub so the button/slash don't call the blocked API.
function SG.PostAll()
  if not atAH then SG.Print("Open the Auction House to post."); return end
  SG.Print("Auto-posting is blocked by WoW's protection system in this build. Your |cffffd200undercut prices|r are on the AH column - post them via Blizzard's Auction House. (Pricing is fully working; one-click posting is on hold.)")
end

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
