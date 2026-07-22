# Time Is Money  (v0.19.0)

A clean, native-feeling **live farm & gold tracker** for WoW Retail (Midnight). It values what
you gather and loot, tracks your real gold/hour, remembers where you earn the most, and helps
you clear your bags and price your mats on the Auction House — all in one tidy four-tab window.
**No TSM or Auctionator required** (they're optional bonuses if you have them).

> **Tester build — thanks for helping!** This is an active work-in-progress beta. Please read
> the *Known limitations* and *Reporting bugs* sections below before filing anything.

---

## Install
1. Unzip so you have a folder named exactly **`TimeIsMoney`** (this name must not change).
2. Put it in `World of Warcraft\_retail_\Interface\AddOns\TimeIsMoney`.
3. Restart WoW (or `/reload`) and make sure **Time Is Money** is enabled on the AddOns list.
4. Type **`/tim`** in game to open the window.

No dependencies. Built for interface **120007** (Midnight).

---

## Getting started
Just go farm — a run **auto-starts** on your first gather or loot. The window has four tabs:

- **Grind** — your live run: run timer, **Gold/hour**, "This run" value, per-source breakdown
  (skinning / mining / herbalism / cloth / fishing / coin / drops), and **net after repairs**.
  A detachable **Floating Timer** lives here too.
- **Gold** — what you've actually **banked** (coin + vendor sales + AH mail), for Today / Last
  7 days / All-time, with a daily chart, your best run this week, and a This-character/Account toggle.
- **Grounds** — your run history and Auction House intel. Cycle **Runs → Locations → Market**:
  *Locations* ranks your zones by earnings; *Market* shows AH prices & supply for your mats, or
  **search a whole category** (Herbs/Ore/Leather/Cloth/Cooking) for under-supplied mats worth
  farming. **Left-click a Market item for a copyable Wowhead link** (where to farm it).
- **Gains** — sell & price. At a merchant: review the vendor pile, keep/rule items, **Sell All**
  (with confirm + undo). At the AH: each mat shows the recommended undercut **price to list at**.

`/tim config` opens options.

---

## How it values things
Gathered loot is attributed to the profession that produced it and valued using: your own
**self-contained AH scan** (on AH open) → **TSM** → **Auctionator** → vendor price. Coin is
tracked from loot only (vendor/repair/mail don't count). Banked totals count only realized gold
(coin + vendor sales + AH mail); the live "estimate" never mixes with the banked numbers.

---

## Useful commands  (`/tim` or `/timeismoney`)
- `/tim` — show / hide the window
*(In-game, `/tim help` prints this list.)*

- `/tim run` · `/tim pause` — start/stop · pause the run · `/tim ticker` — floating timer
- `/tim runs` · `/tim delrun <#>` · `/tim undorun` — run journal
- `/tim scope` — this character ⇄ account · `/tim theme [name]` — color theme · `/tim scale <n>` — window size
- `/tim sell` — open the sell/AH (Gains) tab · `/tim sellilvl <n>` — gear-sell floor (item level)
- `/tim pricing vendor|sells|ah` — pricing mode · `/tim ah|vendor|exclude` (+shift-click) — per-item rules · `/tim rules` · `/tim clearrule`
- `/tim ahscan` — rescan AH prices · `/tim undercut <0-90>` — AH undercut %
- `/tim drops` — count looted drops · `/tim selllog` — recent sales · `/tim sound` — sound options
- `/tim config` — options · `/tim reset` — clear this character's data

Color themes: **Seafoam · Amethyst · Amber · Crimson · Steel · Class Color** (cycle with `/tim theme` or the button in Options — no more light/dark).

---

## Known limitations (please read before reporting)
- **Auction House posting is manual.** The current game patch blocks addons from posting
  auctions directly. Time Is Money shows you the exact price to list at — you place the
  auction in Blizzard's own AH window. ("It won't post for me" is expected, not a bug.)
- **Data is per-character and starts empty** — it tracks going forward, no back-fill.
- **Same-patch:** built for Midnight (120007). On a different build it may show "out of date"
  (still loads if you tick *Load out of date AddOns*).
- Some Auction House / market features have only been tested on one setup, so other configs
  may surface edge cases — that's exactly what this beta is for.

---

## Reporting bugs
Please turn on error reporting so you can send useful details:
- Quick: `/console scriptErrors 1` (shows Lua errors on screen), **or**
- Better: install **BugSack** + **!BugGrabber** (they capture errors so you can copy them).

Copy the error text and what you were doing, and send it over. Feature ideas welcome too!

---

## Permissions & Data Use
By installing and running Time Is Money, you permit it to access the in-game information it
needs to do its job:

- **Your game data (read locally):** the items you loot, their values, your professions and
  spell casts, your bags at a merchant/AH, and the date/time — used only to calculate and
  display your farming income and prices.
- **Saved locally only:** tracked totals and settings are written to your own computer's WoW
  SavedVariables (`TimeIsMoneyDB`).
- **Optional third-party data:** if TradeSkillMaster or Auctionator is installed, item prices
  may be read from them. They are optional.
- **No network access. Nothing leaves your machine.** WoW addons have no internet access —
  there is no tracking, telemetry, or external reporting.
