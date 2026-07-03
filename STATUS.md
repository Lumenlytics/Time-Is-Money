# Time Is Money — Build Status (living doc)

Last updated: 2026-07-02.

## Shipped & verified (on `main`)
- Core farm tracking: live GPH, per-source estimate, auto-start runs, repair netting.
- #14 sell workflow (disposition, review window, safety harness, ilvl gear gate).
- Tabbed UI (Run / Weekly / Farm / Sell), fixed-size, slimmed.
- Detachable Floating Timer (timer + run gold + GPH + Start/Pause + close-x).
- Banked-only Weekly totals + stacked-by-category chart (coin/vendor/AH) + Best-run.
- Run Journal (labeled runs, /tim runs) + AH-sale capture + Fishing source.
- Per-character ledger + This-character/Account scope toggle.
- Light/dark theme + window scaling (/tim scale) + Options widget-size slider.

## What's left to do

### Feature tabs (the two stubs)
- **Tab C — Farm intel (#15):** AH Hot Commodity (supply-depth via C_AuctionHouse /
  Auctionator, NO TSM), Previous Farm Locations (from the Run Journal, filterable),
  Professions (current character) vs what's selling, Reset All Data.
- **Tab D — Sell integration:** mirror the #14 sell-review window inside the tab
  (keep the merchant auto-pop).

### Polish / nitpicks
- **GPH presets:** reframe the Options "Gold/hour window" as intent presets —
  World farming (~8m) vs Dungeon/Raid (~20m) smoothing (keep custom minutes).
- **Sell settings in Options:** surface the slash-only toggles as checkboxes
  (/tim sellconfirm, skipgreys, sellilvl, sellwindow).
- **Theme the Sell + Options *windows*** for light mode (right now their backdrops
  stay dark; only the main window + widget are fully themed).
- **Chart colours in light mode:** the grey "vendor" bars read low-contrast on
  off-white - darken per-theme if wanted.
- **Sounds + badging pass:** Sounds.lua (master + per-event toggles) + a
  /tim sound <id> tester to hunt the goblin "Time is money, friend!" line; wire
  run-start / run-stop / sell sounds. (Goblin art dropped; badging TBD.)

### Bigger, later
- **#12 self-contained AH pricing** (own targeted scanner so it never needs TSM/Auctionator).
- **Profession-tagged income** (gather-cast detection -> herb/mine/etc. income split),
  the heuristic upgrade to the per-source breakdown.
