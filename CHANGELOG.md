# Changelog

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
