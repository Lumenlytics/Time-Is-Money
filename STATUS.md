# Time Is Money — Build Status (living doc)

Last updated: 2026-07-01. Shipped features are in git; this tracks what's IN PROGRESS and PENDING.

## Committed & shipped (on `main`)
- v0.12.0 money correctness (repair pro-rating, guild-repair fix, clear-all)
- #14 farm-loot sell workflow (Stages 1-3: disposition, review window, safety harness)
- Reliable ilvl gear gate (self-healing 220 floor) + liquidated-gold chart + price-source note
- GPH freeze-on-stop, Reset Instances button, chat cleanup, GetSpellInfo guard

## In progress — the tabbed UI rework (from the mockup)
**Phase 1 — tabbed shell + Tab A + floating timer — BUILT, in testing, NOT committed.**
- Fixed-size 4-tab window (Run / Weekly / Farm / Sell), no resize.
- Tab A: detailed run info + Run Label (auto-zone) + Reset Instances + controls.
- Tab B: Today/7d/All-time + liquidated chart.
- Tab C / Tab D: stubs.
- Detachable "Floating Timer" widget: timer + run gold + GPH + Start/Pause, always-on-top,
  saves position/shown state.
- → ACTION: confirm it's good, then commit.

## Pending phases (not started)
- **Phase 2 — Run Journal backend + stacked-by-category chart + most-profitable-run.**
  Persistent per-run log {label, time, duration, per-source, liquidated, location}. Tab B chart
  becomes STACKED by realized category (Coin=gold FFD700, Vendor=grey 9d9d9d, AH=blue 0070dd).
  "Most profitable run this week" line.
- **Phase 3 — AH-sale-mail capture (#8).** Read mailbox "Auction successful", count net gold once
  on collection → feeds liquidated totals + Tab B AH trends. (Currently AH sales are NOT tracked
  anywhere — neither the bars nor the Today line include them.)
- **Phase 4 — Tab C farm intel (#15).** AH Hot Commodity (supply-depth via C_AuctionHouse /
  Auctionator, no TSM), Previous Farm Locations (filterable, from the journal), Professions
  (current char, ALL professions incl. Engineering/Cooking/Fishing/Archaeology), Reset All Data.
- **Phase 5 — Sell window → Tab D** (integrate #14's window as the tab; keep merchant auto-pop).

## Pending nitpicks / smaller items
- [ ] **GPH window presets** in Options: "World farming (steady, ~8m)" vs "Dungeon/Raid (bursty,
      ~20m)" checkboxes that set the smoothing window; keep a custom-minutes advanced fallback.
- [ ] **Add Fishing** as a tracked gather source (cast + fish-loot detection). Cooking = crafting,
      NOT tracked as income (would double-count mats). Archaeology = niche, optional later.
- [ ] **Weekly-tab clarity (DECISION PENDING):** show BOTH "banked" (liquidated) and "gathered"
      (estimate) per line, labeled, + a one-line legend — vs. switching lines to banked-only.
      Root of the "Today 2475g but bar 543g" confusion = estimate vs liquidated, unlabeled.
- [ ] **Options-panel checkboxes** for the sell settings (currently slash-only: `/tim sellconfirm`,
      `/tim skipgreys`, `/tim sellilvl`, `/tim sellwindow`).

## Open decisions waiting on user
1. Weekly tab: show both metrics labeled (recommended) vs banked-only.
2. GPH preset default minutes (proposed 8m world / 20m dungeon-raid — OK?).
3. Archaeology: track its loot eventually, or leave out?
