# Time Is Money

Tracks the **value of everything you gather** — skinning, mining, herbalism, tailoring
(cloth) — **plus the raw coin you loot** — over time. It counts only what you pick up in
the field: vendor sales, mail, and AH activity are ignored, so flipping and other income
stay out of the numbers.

## How it works
When you complete a gathering cast (skin a beast, mine a node, pick an herb), any loot that
lands in the next ~2 seconds is attributed to that profession and valued using:

1. **TradeSkillMaster** (`DBMarket`) if installed
2. **Auctionator** if installed
3. Vendor price as a last-resort fallback

Raw **coin you loot** in the field is tracked too (via `CHAT_MSG_MONEY`, so vendoring,
repairs, and mail are not counted) and folded into every total as its own "Coin" source.

A **run** is a bounded farming session: it auto-starts on your first gather (or `/tim run`),
and the **This run** total and **Gold/hour** track that run. Stop it with `/tim run` (or the
Start/Stop button) to print an end-of-run summary. The Today / 7-day / All-time totals keep
accumulating regardless of runs.

The window shows combined **Gold/hour, This run, Today, Last 7 days, All-time**, a
per-source run breakdown, and a 7-day bar chart.

## Install
1. Drop the `TimeIsMoney` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
2. If you still have a `GatherGold` or `SkinnerGold` folder, leave it in place for this first
   login so its data imports (you'll see an "Imported ... data" message).
3. `/reload` or log in, then delete the old folder. Built for interface **120007** (patch 12.0.7).

## Commands
- `/tim` — show / hide the window
- `/tim run` — start / stop a farm run (auto-starts on your first gather; also the Start/Stop button on the panel)
- `/tim pause` — pause / resume the current run (also the Pause button; Reset button zeroes the run)
- `/tim autostart` — toggle auto-starting a run on your first gather (also a checkbox in options)
- `/tim config` — open the options window (also: the Options button on the panel)
- `/tim reset` — clear all tracked data (also: right-click the window)
- `/tim debug` — print each detected cast and recorded item

## Options
- Track income sources: turn skinning / mining / herbalism / tailoring / coin on or off
- Gold/hour window: 5 / 10 / 15 / 20 minutes
- TSM price source: Market / MinBuyout / RegionMarket / RegionSale (only used if TSM is installed)
- Ignore items worth less than: Off / 1g / 5g / 10g / 25g per item

## If a profession isn't being detected
Run `/tim debug`, gather one node/beast/herb, and note the printed line
(`cast <name> (<id>) -> <prof>`). If it shows no `-> prof`, send the name and it can be added.

## Permissions & Data Use
By installing and running Time Is Money, you permit it to access the in-game
information it needs to do its job. Specifically:

- **Your game data (read locally):** the items you loot, their values, your
  professions and spell casts, and the current date/time. This is used only to
  calculate and display your gathering income.
- **Saved locally only:** tracked totals and settings are written to this
  character's WoW SavedVariables (`TimeIsMoneyDB`) on your own computer.
- **Optional third-party data:** if **TradeSkillMaster** or **Auctionator** is
  installed, item prices are read from those addons. They are optional; without
  them, vendor prices are used.
- **No network access. Nothing leaves your machine.** Time Is Money does not (and
  cannot) send your data anywhere — WoW addons have no internet access. There is
  no tracking, telemetry, or external reporting.
