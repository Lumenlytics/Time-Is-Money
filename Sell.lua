local ADDON, ns = ...
local SG = ns

----------------------------------------------------------------------
-- #14 Stage 2: merchant "review before selling" window
-- Lists the would-vendor pile (from SG.ScanSellables); left-click a row to KEEP it
-- (excluded from the sale, stays in your bag); "Sell All" vendors the rest.
----------------------------------------------------------------------

local ROW_H    = 24
local MAX_ROWS = 12
local WIN_W    = 360

local win, scroll, rows, totalFS, noteFS, sellBtn
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
end

local function Rescan()
  scan = SG.ScanSellables()
  UpdateList()
end
SG.RefreshSellWindow = function() if win and win:IsShown() then Rescan() end end

local function DoSellAll()
  if not atMerchant then SG.Print("Visit a merchant to sell."); return end
  if not scan then return end
  local sold, gold = 0, 0
  for _, e in ipairs(scan.vendor) do
    if not kept[KeyOf(e)] then
      -- Guard: only sell if that exact item is still in that slot (bags can shift).
      if C_Container.GetContainerItemLink(e.bag, e.slot) == e.link then
        C_Container.UseContainerItem(e.bag, e.slot)
        sold, gold = sold + 1, gold + e.value
      end
    end
  end
  SG.Print(("Sold |cffffffff%d|r item(s) for ~%s."):format(sold, SG.Money(gold)))
  C_Timer.After(0.3, function() if win and win:IsShown() then Rescan() end end)
end

local function BuildWindow()
  if win then return end
  win = CreateFrame("Frame", "TimeIsMoneySellFrame", UIParent, "BackdropTemplate")
  win:SetSize(WIN_W, 104 + MAX_ROWS * ROW_H)
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
  title:SetPoint("TOP", 0, -10)
  title:SetText("|cff8fd694Sell|r  - review before selling")

  local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 14, -32)
  hint:SetText("Left-click an item to KEEP it (won't be sold).")

  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  scroll = CreateFrame("ScrollFrame", "TimeIsMoneySellScroll", win, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -48)
  scroll:SetPoint("BOTTOMRIGHT", -30, 54)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, UpdateList)
  end)

  rows = {}
  for i = 1, MAX_ROWS do
    local row = CreateFrame("Button", nil, win)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -(i - 1) * ROW_H)

    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT", 2, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 6); row.name:SetWidth(210); row.name:SetJustifyH("LEFT")
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.info:SetPoint("LEFT", row.icon, "RIGHT", 5, -6); row.info:SetJustifyH("LEFT")
    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.tag:SetPoint("RIGHT", -4, 0); row.tag:SetText("|cffff7070KEEP|r"); row.tag:Hide()

    row:SetScript("OnClick", function(self)
      if not self.e then return end
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

  totalFS = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  totalFS:SetPoint("BOTTOMLEFT", 14, 30)

  noteFS = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  noteFS:SetPoint("BOTTOMLEFT", 14, 14)
  noteFS:SetPoint("BOTTOMRIGHT", -14, 14)
  noteFS:SetJustifyH("LEFT")

  sellBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  sellBtn:SetSize(110, 22)
  sellBtn:SetPoint("BOTTOMRIGHT", -12, 26)
  sellBtn:SetText("Sell All")
  sellBtn:SetScript("OnClick", DoSellAll)
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
