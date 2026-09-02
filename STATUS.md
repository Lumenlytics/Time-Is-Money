# Time Is Money — Build Status

**Superseded 2026-09-01.** This file was last accurate on 2026-07-02 and claimed features
as outstanding that shipped months ago (the Grounds farm-intel tab, the Gains sell tab,
self-contained AH pricing, the sounds pass, and the sell toggles that are now Options
checkboxes). Leaving it in place cost a reader real time.

**The live status document is `HANDOFF.md`** — version, FLEET block, what shipped, what is
open, and what needs Marshall. Read that instead.

Genuinely still open, carried across so it is not lost:

- **GPH presets.** `settings.gphWindow` (minutes, default 10) has no Options control — it is
  a saved-variable only. The idea was intent presets rather than a raw number: World farming
  (~8 min) vs Dungeon/Raid (~20 min) smoothing, keeping a custom value.
- **Profession-tagged income.** Gather-cast detection to split income by herb/mine/skin
  beyond the current item-type heuristic in `MatProf`.
