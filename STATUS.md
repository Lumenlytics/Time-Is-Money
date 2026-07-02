# Time Is Money — Build Status (living doc)

Last updated: 2026-07-02.

## Recently shipped (verified in-game)
- Fishing source + Run Journal (#16) + stacked chart + Sell-All-closes. (72e7be2)
- **Per-character ledger** — data keyed by name-realm; "This character / Account" toggle
  (`/tim scope`, button on Weekly tab); one-time migration assigns old shared data to the
  current main; "Clear all data" is now per-character. Window slimmed 470->400, breakdown on
  two centered lines.

## Committed & shipped (on `main`)
- v0.12.0 money correctness; #14 sell workflow (Stages 1-3); ilvl gear gate; GPH freeze;
  Reset Instances; chat cleanup.
- Tabbed UI Phase 1 (fixed-size 4 tabs, detailed Tab A, detachable Floating Timer w/ Start/
  Pause). — commit 7c2a307
- AH-sale capture (mailbox) + banked-only Weekly totals + Tab A durability. — commit 1d71237

## Built, IN TESTING, not yet committed
- **Fishing** as a tracked gather source (cast keyword + fish-loot; 30s attribution window
  since fishing loot is delayed). Cooking/Archaeology deliberately NOT tracked.
- **Phase 2 — Run Journal + stacked chart + most-profitable-run:**
  - Persistent per-run log `TimeIsMoneyDB.runs` (capped 100): {label, time, dur, value, net,
    coin, repairs, gph, zone, itype}. Saved on Stop Run.
  - **Label-this-run popup** on Stop (pre-fills from the Run Label field / that zone's last
    label / the zone name); `zoneLabels` remembers per-zone. Toggle: `/tim labelprompt`.
  - Tab A Run Label field mirrors `session.label` (auto-zone; cleared each run start).
  - **Tab B chart is now STACKED by realized category** — coin (gold) / vendor (grey) /
    AH (blue), with a colour legend.
  - **"Best run this week"** line on Tab B (highest-net run in last 7 days).
  - `/tim runs` (alias `/tim journal`) prints the recent run log.

## Pending phases
- **Phase 4 — Tab C farm intel (#15):** AH Hot Commodity (supply-depth via C_AuctionHouse /
  Auctionator, no TSM), Previous Farm Locations (from the journal, filterable), Professions
  (current char, all incl. Fishing/Engineering/etc.), Reset All Data.
- **Phase 5 — Sell window -> Tab D** (mirror #14's window as the tab; keep merchant auto-pop).

## Pending nitpicks
- [ ] **GPH presets** in Options: World farming (~8m) vs Dungeon/Raid (~20m) smoothing, +
      custom-minutes fallback.
- [ ] **Sounds + goblin badging pass:** Sounds.lua (master + per-event toggles) + a
      `/tim sound <id>` / `/tim soundfile <id>` tester to hunt the goblin "Time is money,
      friend!" line; wire run-start/stop/sell sounds. Plus a coin/goblin icon + header badge.
      (Awaiting user's pick of which sounds.)
- [ ] **Options-panel checkboxes** for sell + new toggles (currently slash-only).

## Resolved
- Weekly logic = BANKED ONLY (coin + vendor + AH), per user. Estimate stays as the live
  run guide on Tab A + the floating widget.
