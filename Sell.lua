local ADDON, ns = ...
local SG = ns

----------------------------------------------------------------------
-- #14 sell workflow — the ENGINE. The UI now lives in the main window's
-- "Gains" tab (UI.lua); this file owns the scan-aware keep set, the actual
-- vendoring, buyback undo, the per-item rule menu, and merchant-state
-- tracking. All destructive actions keep the original safety harness:
-- confirm on risky/large piles, a sell log, and buyback undo.
----------------------------------------------------------------------

local atMerchant = false
local kept = {}                       -- key "bag:slot" -> true: rows toggled "keep this visit"

local function KeyOf(e) return e.bag .. ":" .. e.slot end

function SG.AtMerchant()    return atMerchant end
function SG.SellIsKept(e)   return (e and kept[KeyOf(e)]) and true or false end
function SG.SellClearKept() wipe(kept) end
function SG.SellToggleKeep(e)
  if not e then return end
  local k = KeyOf(e)
  kept[k] = (not kept[k]) or nil
end

-- Count + gold of what WOULD sell right now (vendor pile minus kept rows) from a scan.
function SG.SellSummary(scan)
  local total, n = 0, 0
  if scan and scan.vendor then
    for _, e in ipairs(scan.vendor) do
      if not kept[KeyOf(e)] then total, n = total + e.value, n + 1 end
    end
  end
  return n, total
end

-- The items that would actually sell now (vendor pile minus kept), + whether the pile is
-- "risky" (anything beyond plain greys -> worth a confirm).
local function CollectToSell(scan)
  local list, total, risky = {}, 0, false
  if scan and scan.vendor then
    for _, e in ipairs(scan.vendor) do
      if not kept[KeyOf(e)] then
        list[#list + 1] = e
        total = total + e.value
        if e.reason ~= "grey" then risky = true end   -- gear / BoP / BoE / your-rule vendor
      end
    end
  end
  return list, total, risky
end

-- Selling many items in one frame gets throttled by the client (only the first few
-- UseContainerItem calls land), which is why a single Sell All used to leave a pile behind.
-- So we sell ONE item per short tick until the list is exhausted - one press clears it all.
local function SellList(list)
  local i, sold, gold = 0, 0, 0
  local function step()
    i = i + 1
    local e = list[i]
    if not e then
      SG.Print(("Sold |cffffffff%d|r item(s) for ~%s.  |cff808080(/tim selllog to review; Undo last on the Gains tab)|r"):format(sold, SG.Money(gold)))
      if sold > 0 and SG.PlayEventSound then SG.PlayEventSound("sell") end
      if SG.RefreshUI then SG.RefreshUI() end
      return
    end
    -- Guard: only sell if that exact item is still in that slot, and we're still at a merchant.
    if atMerchant and C_Container.GetContainerItemLink(e.bag, e.slot) == e.link then
      C_Container.UseContainerItem(e.bag, e.slot)
      SG.LogSale(e.link, e.count, e.value)
      sold, gold = sold + 1, gold + e.value
    end
    C_Timer.After(0.1, step)
  end
  step()
end

StaticPopupDialogs["TIMEISMONEY_SELLALL"] = {
  text = "Sell these items?",
  button1 = SELL or "Sell",
  button2 = CANCEL or "Cancel",
  timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
  OnAccept = function() end,
}

function SG.SellAll()
  if not atMerchant then SG.Print("Visit a merchant to sell."); return end
  local scan = SG.ScanSellables()
  local list, total, risky = CollectToSell(scan)
  if #list == 0 then SG.Print("Nothing to vendor right now."); return end
  -- Confirm when the pile includes gear/BoP/BoE or is large; plain small grey dumps skip it.
  if SG.SellConfirmEnabled() and (risky or #list >= 10) then
    local dlg = StaticPopupDialogs["TIMEISMONEY_SELLALL"]
    dlg.text = ("Sell %d item(s) for ~%s?\n\nThis pile includes gear/BoP. Selling can only be undone via the merchant's buyback (last 12 items)."):format(#list, SG.Money(total))
    dlg.OnAccept = function() SellList(list) end
    StaticPopup_Show("TIMEISMONEY_SELLALL")
  else
    SellList(list)
  end
end

-- Undo the most recent sale by buying it back from the merchant's buyback tab.
function SG.SellUndoLast()
  if not atMerchant then SG.Print("Visit a merchant to buy back."); return end
  local n = (GetNumBuybackItems and GetNumBuybackItems()) or 0
  if n < 1 then SG.Print("Nothing in the merchant's buyback to undo."); return end
  local link = (GetBuybackItemLink and GetBuybackItemLink(n)) or "the last item"
  BuybackItem(n)
  SG.Print(("Bought back %s."):format(link))
  if SG.RefreshUI then C_Timer.After(0.3, SG.RefreshUI) end
end

-- Right-click a row -> set a persistent per-item rule (clearly labeled).
function SG.SellRuleMenu(anchor, link)
  local itemID = link and tonumber(link:match("|Hitem:(%d+):"))
  if not itemID then return end
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    SG.Print("Rule menu needs a newer client. Use /tim vendor | exclude | ah + shift-click.")
    return
  end
  local function refresh() if SG.RefreshUI then SG.RefreshUI() end end
  MenuUtil.CreateContextMenu(anchor, function(_, root)
    root:CreateTitle(link)
    root:CreateButton("Always vendor this item",    function() SG.SetItemRuleByID("vendor", itemID, link);  refresh() end)
    root:CreateButton("Never sell (always keep)",   function() SG.SetItemRuleByID("exclude", itemID, link); refresh() end)
    root:CreateButton("Keep for the Auction House",  function() SG.SetItemRuleByID("ah", itemID, link);      refresh() end)
    root:CreateDivider()
    root:CreateButton("Clear rule for this item",    function() SG.ClearItemRuleByID(itemID, link);          refresh() end)
  end)
end

-- Back-compat + slash entry: the sell UI now lives in the Gains tab.
function SG.ShowSellWindow(manual) if SG.OpenSellTab then SG.OpenSellTab(manual) end end
function SG.HideSellWindow() end   -- no separate window anymore

-- Merchant state. Own event frame (independent of Core's repair/sale tracking).
local ef = CreateFrame("Frame")
ef:RegisterEvent("MERCHANT_SHOW")
ef:RegisterEvent("MERCHANT_CLOSED")
ef:SetScript("OnEvent", function(_, event)
  if event == "MERCHANT_SHOW" then
    atMerchant = true
    wipe(kept)                       -- keeps are per-visit
    if SG.OnMerchant then SG.OnMerchant(true) end
  elseif event == "MERCHANT_CLOSED" then
    atMerchant = false
    if SG.OnMerchant then SG.OnMerchant(false) end
  end
end)
