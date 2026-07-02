local ADDON, ns = ...
local SG = ns

----------------------------------------------------------------------
-- #14 Stage 2: merchant "review before selling" window
-- Lists the would-vendor pile (from SG.ScanSellables); left-click a row to KEEP it
-- (excluded from the sale, stays in your bag); "Sell All" vendors the rest.
----------------------------------------------------------------------

local ROW_H    = 24
local MAX_ROWS = 10
local WIN_W    = 380

StaticPopupDialogs["TIMEISMONEY_SELLALL"] = {
  text = "Sell these items?",
  button1 = SELL or "Sell",
  button2 = CANCEL or "Cancel",
  timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
  OnAccept = function() end,
}

local win, scroll, rows, totalFS, noteFS, sellBtn, undoBtn
local atMerchant = false
local scan                 -- last SG.ScanSellables() result being shown
local kept = {}            -- key "bag:slot" -> true: rows the user clicked to keep

local function KeyOf(e) return e.bag .. ":" .. e.slot end

-- Total + count of the items that WOULD actually sell (vendor pile minus kept rows).
local function SellTotal()
  local total, n = 0, 0
  if scan then
    for _, e in ipairs(scan.vendor) do
      if not kept[KeyOf(e)] then total, n = total + e.value, n + 1 end
    end
  end
  return total, n
end

local function UpdateList()
  if not win then return end
  local items = scan and scan.vendor or {}
  FauxScrollFrame_Update(scroll, #items, MAX_ROWS, ROW_H)
  local offset = FauxScrollFrame_GetOffset(scroll)
  for i = 1, MAX_ROWS do
    local row = rows[i]
    local e   = items[i + offset]
    row.e = e
    if e then
      row.icon:SetTexture(select(10, C_Item.GetItemInfo(e.link)) or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.name:SetText(e.link)
      row.info:SetText(("x%d   %s   |cff808080%s|r"):format(e.count, SG.Money(e.value), e.reason))
      local isKept = kept[KeyOf(e)] and true or false
      row.tag:SetShown(isKept)
      row:SetAlpha(isKept and 0.45 or 1)
      row:Show()
    else
      row:Hide()
    end
  end
  local total, n = SellTotal()
  totalFS:SetText(("Will sell |cffffffff%d|r item(s) for ~|cff8fd694%s|r"):format(n, SG.Money(total)))
  if sellBtn then
    sellBtn:SetEnabled(atMerchant and n > 0)
    sellBtn:SetText(atMerchant and "Sell All" or "Visit a merchant")
  end
  if undoBtn then
    local bb = (GetNumBuybackItems and GetNumBuybackItems()) or 0
    undoBtn:SetEnabled(atMerchant and bb > 0)
  end
end

local function Rescan()
  scan = SG.ScanSellables()
  UpdateList()
end
SG.RefreshSellWindow = function() if win and win:IsShown() then Rescan() end end

-- The items that would actually sell now (vendor pile minus kept rows), plus whether the
-- pile is "risky" (includes anything beyond plain greys -> worth a confirm).
local function CollectToSell()
  local list, total, risky = {}, 0, false
  if scan then
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

local function SellList(list)
  local sold, gold = 0, 0
  for _, e in ipairs(list) do
    -- Guard: only sell if that exact item is still in that slot (bags can shift).
    if C_Container.GetContainerItemLink(e.bag, e.slot) == e.link then
      C_Container.UseContainerItem(e.bag, e.slot)
      SG.LogSale(e.link, e.count, e.value)
      sold, gold = sold + 1, gold + e.value
    end
  end
  SG.Print(("Sold |cffffffff%d|r item(s) for ~%s.  |cff808080(/tim selllog to review; /tim sell to reopen and Undo)|r"):format(sold, SG.Money(gold)))
  if win then win:Hide() end   -- close after Sell All; reopen with /tim sell (buyback/Undo still available)
end

local function DoSellAll()
  if not atMerchant then SG.Print("Visit a merchant to sell."); return end
  local list, total, risky = CollectToSell()
  if #list == 0 then return end
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
local function UndoLast()
  if not atMerchant then SG.Print("Visit a merchant to buy back."); return end
  local n = (GetNumBuybackItems and GetNumBuybackItems()) or 0
  if n < 1 then SG.Print("Nothing in the merchant's buyback to undo."); return end
  local link = (GetBuybackItemLink and GetBuybackItemLink(n)) or "the last item"
  BuybackItem(n)
  SG.Print(("Bought back %s."):format(link))
  C_Timer.After(0.3, function() if win and win:IsShown() then Rescan() end end)
end

-- Right-click a row -> set a persistent per-item rule (clearly labeled).
local function ShowRuleMenu(row)
  local e = row.e
  if not e then return end
  local itemID = tonumber(e.link:match("|Hitem:(%d+):"))
  if not itemID then return end
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    SG.Print("Rule menu needs a newer client. Use /tim vendor | exclude | ah + shift-click.")
    return
  end
  MenuUtil.CreateContextMenu(row, function(_, root)
    root:CreateTitle(e.link)
    root:CreateButton("Always vendor this item",   function() SG.SetItemRuleByID("vendor", itemID, e.link);  Rescan() end)
    root:CreateButton("Never sell (always keep)",  function() SG.SetItemRuleByID("exclude", itemID, e.link); Rescan() end)
    root:CreateButton("Keep for the Auction House", function() SG.SetItemRuleByID("ah", itemID, e.link);     Rescan() end)
    root:CreateDivider()
    root:CreateButton("Clear rule for this item",   function() SG.ClearItemRuleByID(itemID, e.link);          Rescan() end)
  end)
end

local function BuildWindow()
  if win then return end
  win = CreateFrame("Frame", "TimeIsMoneySellFrame", UIParent, "BackdropTemplate")
  win:SetSize(WIN_W, 168 + MAX_ROWS * ROW_H)   -- 64 header + rows(MAX_ROWS*ROW_H) + ~104 footer
  win:SetPoint("CENTER", 120, 0)
  win:SetFrameStrata("HIGH")
  win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetClampedToScreen(true)
  win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  win:SetBackdropColor(0.06, 0.06, 0.07, 0.96)
  win:SetBackdropBorderColor(0.20, 0.50, 0.30, 1)
  win:Hide()

  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -9)
  title:SetText("|cff8fd694Sell|r  -  review before selling")

  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 14, -34); hint:SetPoint("TOPRIGHT", -14, -34)
  hint:SetJustifyH("LEFT")
  hint:SetText("|cffffffffLeft-click|r = keep this visit.   |cffffffffRight-click|r = set a rule (always vendor / never sell / keep for AH).")

  scroll = CreateFrame("ScrollFrame", "TimeIsMoneySellScroll", win, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -64)
  scroll:SetPoint("BOTTOMRIGHT", -30, 100)        -- 100px reserved footer below the list
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, UpdateList)
  end)

  rows = {}
  for i = 1, MAX_ROWS do
    local row = CreateFrame("Button", nil, win)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT", 2, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 6); row.name:SetWidth(210); row.name:SetJustifyH("LEFT")
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.info:SetPoint("LEFT", row.icon, "RIGHT", 5, -6); row.info:SetJustifyH("LEFT")
    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.tag:SetPoint("RIGHT", -4, 0); row.tag:SetText("|cffff7070KEEP|r"); row.tag:Hide()

    row:SetScript("OnClick", function(self, button)
      if not self.e then return end
      if button == "RightButton" then ShowRuleMenu(self); return end
      local k = KeyOf(self.e)
      kept[k] = (not kept[k]) or nil
      UpdateList()
    end)
    row:SetScript("OnEnter", function(self)
      if self.e then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.e.link); GameTooltip:Show() end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
  end

  -- Footer, stacked top-to-bottom with clear gaps: note -> total -> buttons.
  noteFS = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  noteFS:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -6)
  noteFS:SetPoint("TOPRIGHT", scroll, "BOTTOMRIGHT", 0, -6)
  noteFS:SetJustifyH("LEFT"); noteFS:SetJustifyV("TOP"); noteFS:SetHeight(28)

  totalFS = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  totalFS:SetPoint("TOPLEFT", noteFS, "BOTTOMLEFT", 0, -4)

  sellBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  sellBtn:SetSize(110, 22)
  sellBtn:SetPoint("BOTTOMRIGHT", -12, 12)
  sellBtn:SetText("Sell All")
  sellBtn:SetScript("OnClick", DoSellAll)

  undoBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  undoBtn:SetSize(90, 22)
  undoBtn:SetPoint("RIGHT", sellBtn, "LEFT", -6, 0)
  undoBtn:SetText("Undo last")
  undoBtn:SetScript("OnClick", UndoLast)
end

function SG.ShowSellWindow(manual)
  BuildWindow()
  wipe(kept)
  Rescan()
  local note = SG.UnpricedBoENote(scan.unjudgedBoE)
  noteFS:SetText(note and ("|cffff7070" .. note .. "|r") or "")
  if manual and #scan.vendor == 0 then
    SG.Print("Nothing to vendor right now (no greys, old-expansion BoP, or unsellable BoEs).")
    return
  end
  win:Show()
end

function SG.HideSellWindow() if win then win:Hide() end end

-- Own event frame so we don't touch Core's handler. Auto-open at a merchant when there's
-- something to vendor and the setting is on.
local ef = CreateFrame("Frame")
ef:RegisterEvent("MERCHANT_SHOW")
ef:RegisterEvent("MERCHANT_CLOSED")
ef:SetScript("OnEvent", function(_, event)
  if event == "MERCHANT_SHOW" then
    atMerchant = true
    if SG.SellWindowEnabled and SG.SellWindowEnabled() then
      BuildWindow(); wipe(kept); Rescan()
      if #scan.vendor > 0 then
        local note = SG.UnpricedBoENote(scan.unjudgedBoE)
        noteFS:SetText(note and ("|cffff7070" .. note .. "|r") or "")
        win:Show()
      end
    end
  elseif event == "MERCHANT_CLOSED" then
    atMerchant = false
    if win then win:Hide() end
  end
end)
