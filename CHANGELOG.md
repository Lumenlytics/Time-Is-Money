# Changelog

## 1.0.7

Patch 12.1 / Season 2 pass. Verified on live build 69189.

### Fixes
- **Season 2 gear tiers.** The auto-vendor floors are now Veteran 276, Champion 289,
  Hero 302 and Myth 315, matching the Season 2 upgrade tracks. **If you use auto-vendor,
  this one matters:** the old Season 1 floors would have sold current-season gear, because
  Season 1's Myth floor (276) is exactly Season 2's Veteran floor. Anyone who had picked
  Myth would have watched the whole Season 2 Adventurer band go to the vendor. The setting
  defaults to "Never", so only people who turned it on were ever exposed.

### Additions
- **Cursed Fishing catches are now recognised on sight** — all 14 fish from Coiled Isle.
  Fish carry no distinct item subclass, so until now they were credited to Fishing only if
  the 30-second cast window was still open. At surge pools, where the catch often arrives
  well after the cast, that window had usually closed and the fish landed in the wrong
  source. It no longer depends on timing.
- A fish looted while another gather is running now credits **Fishing** rather than
  whatever you last mined or skinned. The mirror of this rule already existed for ore.

### Internal
- Wago Addons upload wired into the release workflow. Dormant until the project is
  configured, and it cannot affect CurseForge releases in the meantime.

## 1.0.6

### Additions
- **The main window opens in the upper left** instead of the middle of the screen. Mid-screen is
  where cooldown timers and unit frames usually sit on a modern UI, so the old default landed on
  top of them.
- **The window remembers where you drag it,** across reloads and across sessions. It previously
  re-centred every time you logged in, which the floating timer never did.
- **Window size slider in Options,** next to the floating timer's, under a new "Size" heading.
  Resizing the main window was previously only possible with `/tim scale`.
- **`/tim pos`** puts the window back to the default spot if it ends up somewhere awkward.

## 1.0.5

### Additions
- **Shift-click to sell at the Auction House:** with the AH open, shift-click an item in your
  bags and it loads straight into the Sell tab's auction slot — no dragging. You still set the
  price and press Create Auction yourself, so nothing is ever posted without you.
- **On by default, with an off switch** in Options ("Shift-click sell"). It only fires while a
  sell view is actually open, so a shift-click on the Buy tab is left alone, and shift-clicking
  into the chat box still links the item as normal.
- **`/tim ahdiag`** toggles a diagnostic trace of the Auction House sell path. If a future patch
  reshapes the AH and shift-click sell stops working, run it, shift-click a bag item, and paste
  the dump into a bug report.

### Internal
- The shortcut drives both the legacy Auction House layout (what the current patch ships) and
  the modern one, so it keeps working whichever Blizzard has live.

## 1.0.4

### Fixes
- **Coin no longer double-counts:** gold looted while a merchant is open is no longer also
  booked as a vendor sale.
- **Auction House income is precise:** only actual auction-sale mail counts as AH income (via a
  mail-invoice check), so gold from friends, quest mail or COD refunds is never miscounted.
- **Fishing:** ore / herb / leather / cloth looted during the (long) fishing window is credited
  to its own profession, not to Fishing.
- **Repairs:** the wear baseline resets only on a full repair, so a partial repair no longer
  over-charges the next one.
- The sell/price (Gains) tab now auto-opens at a merchant when you have **mats to sell**, not
  only when you have junk to vendor.

### Additions & polish
- **`/tim help`** prints the full command list in-game.
- The **Auction House undercut %** is now in the Options window (was slash-only).
- The Gains tab no longer rescans your bags when it isn't the visible tab (performance).
- TSM price-source options got explanations; assorted wording/label tidy-ups.

### Internal
- Removed a large block of disabled Auction House posting code and other dead leftovers.

## 1.0.3

- **Gains "Sell on AH":** the value now shows the **stack total** both away from and at the
  Auction House, so it no longer appears to shrink when you arrive at the AH (it was switching
  from stack-total to per-item). The per-item price you type when posting is now in the row's
  hover tooltip ("Post at X each").
- **Fix:** an item marked *Never sell (always keep)* now correctly drops out of the AH column
  (it was staying listed for trade goods).

## 1.0.2

- **Gains tab:** the stack count now shows first (`x24 Item name`) so it's never cut off when
  a long item name truncates.
- **Grounds tab:** the Runs / Locations / Market switcher is now a dropdown.

## 1.0.1

- **Grounds tab:** the Runs / Locations / Market views are now a three-button switcher with
  the active view highlighted, instead of a single button that cycled and labelled itself with
  the *next* view (which made it easy to lose track of which view you were on).

## 1.0.0

First public release. A live farm & gold tracker for WoW Retail (Midnight) — real-time
gold/hour, self-contained Auction House pricing, and a vendor/sell workflow, in one
four-tab window. **No TSM or Auctionator required.**

### Tracking
- Live **run tracking**: run timer, **gold/hour**, "this run" value, and a per-source
  breakdown (skinning, mining, herbalism, cloth, fishing, coin, looted drops).
- **Repairs netted** against the run, pro-rated to the wear that run actually caused;
  guild/free repairs correctly ignored.
- Gold/hour **smoothing is automatic** — a short window in the open world, a longer one in
  instances (bursty boss loot), chosen live.
- **Banked earnings** kept separate from the live estimate: coin looted + vendor sales +
  Auction House mail, shown Today / Last 7 days / All-time with a daily chart and your
  best run of the week.
- **Per-character ledger** with a This-character / Account view toggle.

### Farm intel
- **Run journal** with smart auto-naming (dungeon "run N", world "Zone farm (leather)"),
  per-run delete and undo.
- **Farm locations** — your runs folded per zone and ranked by earnings and gold/hour.
- **AH market intel** — scan your own mats, or **search a whole category** (Herbs, Ore,
  Leather, Cloth, Cooking) for under-supplied items worth farming, with a
  thin / moderate / saturated competition rating. Grey vendor-trash and troll price
  outliers are filtered out.
- **Left-click any market item for a Wowhead link** to see where it's farmed.
- Your own **gathering professions are highlighted**, tying the market data to your character.

### Selling & pricing
- **Self-contained Auction House pricing**: on AH open, Time Is Money scans live lowest
  prices and supply itself. TSM / Auctionator are optional extras, never required.
- **Sell workflow** at a merchant: review the vendor pile, click to keep an item for this
  visit, right-click to set a permanent rule (always vendor / never sell / keep for AH),
  then Sell All — with a confirm on gear/BoP and one-click buyback undo.
- **Auto-vendor old gear by upgrade tier** (Never / Veteran / Champion / Hero / Myth),
  set **per character**.
- Recommended **undercut price** shown per mat for posting by hand.

### Interface
- **Six color themes** — Seafoam, Amethyst, Amber, Crimson, Steel, and Class Color.
- Detachable **floating timer**, independent window and widget scaling.
- **Per-character settings** for tracked professions, theme, and the gear-sell tier.
- Hover tooltips throughout, including a one-line intro on every tab.
- **Sounds** — goblin voice cues on run start ("Time is money, friend!"), run end, and
  selling, with a master switch and per-event toggles.

### Known limitation
- **Auction House posting is manual.** The current game patch blocks addons from posting
  auctions directly, so Time Is Money gives you the exact price to list at and you place
  the auction in Blizzard's own AH window.
