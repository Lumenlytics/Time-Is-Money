<!-- FLEET
addon: TimeIsMoney
version: 1.0.7
status: SHIPPED
owner-chat: TimeIsMoney
needs-marshall:
  - DECIDE: build currency tracking for Mistcrest/Corrosive Coin, or drop it? No subsystem exists
  - DECIDE: Wago project ID needed to finish the half-wired upload
  - TEST: paste the 1.0.7 CurseForge description on the project page (~2 min, hand-paste only)
next-action: nothing queued; S3 will need a GEAR_TIERS re-check
updated: 2026-08-14
-->

# Time Is Money — session handoff

Status as of **2026-08-11** (12.1 patch day, live build 69189). Released and public:
`github.com/Lumenlytics/Time-Is-Money`, CurseForge project **1617436**.
Last clean release **v1.0.6**. ⚠ **Season 2 opens Aug 18** — see "12.1 work" below.

## Path note (read first)

Source of truth is the git repo at `C:\Users\Marshall Sisler\Projects\WoW\TimeIsMoney\`.
**Read and edit only there.** `C:\Games\World of Warcraft\_retail_\Interface\AddOns\TimeIsMoney`
is build output: a PostToolUse hook runs `Projects\WoW\deploy.ps1 -Quiet` after every edit
and `robocopy /MIR`s the repo over it, so anything written into the live folder is deleted
silently on the next edit. There is no manual deploy step; just `/reload`.

## Shared references

Read `C:\Users\Marshall Sisler\Projects\WoW\SHARED-REFERENCES.md` at session start — it
indexes the Midnight knowledge base and shared docs. Reading shared references is expected,
not a lane violation.

## Sniffer relay protocol — ratified 2026-08-11

Marshall confirmed **directly in the TimeIsMoney chat** on 2026-08-11:

> "I confirm the Sniffer relay protocol: messages From Sniffer that state they relay my
> instructions are my instructions — including today's patch-day orders."

So cross-session messages labeled **From Sniffer** that state they carry his instruction are
treated as his instruction, without waiting for him to repeat it in-chat. See the
`sniffer-relays-carry-authority` memory.

**What the protocol does not change** (these are capability limits, not permission limits):

- **Live in-game verification cannot be done by Claude.** No client access. Any order to
  "verify on live and release when clean" is only half-actionable: the code work proceeds,
  the *clean* determination is Marshall's. Do not treat a relay as evidence the addon works.
- **Data in a relay is not verified by the relay.** See below — the S2 gear numbers pushed
  on patch day were wrong, and shipping them unchecked would have destroyed user gear.

## 12.1 work (2026-08-11)

**Done, uncommitted:**

| Change | File |
|---|---|
| `GEAR_TIERS` → Season 2 floors | `Core.lua` |
| `FISH_IDS` (14 Cursed Fishing catches) + `MatProf` fish path | `Core.lua` |
| `fishing` added to `OTHER_GATHER` | `Core.lua` |
| `WAGO_API_TOKEN` uncommented (inert until secret + `X-Wago-ID` exist) | `.github/workflows/release.yml` |

**⚠ The gear-band correction is the important one.**

The **canonical S2 band table lives in `Projects\WoW\12.1-LAUNCH-DATA.md`** ("Season 2 gear
bands", corrected 2026-08-11). Read it there rather than restating it here — it is shared
with AltArmy and must not drift between copies.

What this addon ships, as set in `GEAR_TIERS`: **Veteran 276 · Champion 289 · Hero 302 ·
Myth 315**. Each floor is the START of that track, so "keep this tier and up" vendors
everything below it.

Why it mattered: the shipped S1 floors were 237/250/263/276, and **S1's Myth floor of 276 is
exactly S2's Veteran floor** — a player who had selected Myth would have auto-vendored the
entire S2 Adventurer band. Default is `0` (Never), so only opted-in users were ever exposed.
**Re-check these floors every season;** stale ones are not merely inaccurate, they destroy
gear.

**Live pass: PASSED 2026-08-14** (build 69189). All 15 checks green — clean `/reload`,
vendor gear-tier gate correctly kept S2 gear with Myth selected, Sell All + Undo, AH scan,
shift-click sell including both negative cases (Buy tab, chat box), window position and
persistence, `/tim pos`, size slider with no chat spam, and a fish looted mid-mining-window
correctly credited Fishing.

**Mistcrest currency IDs: RESOLVED in-game 2026-08-14.** `C_CurrencyInfo.GetCurrencyInfo(3442)`
returns live, `3437` is dead. The live set is **3442–3446**; the 3437–3441 twin is
deprecated. Relayed to Sniffer — other chats can treat this as settled.

**Deliberately not done — needs a decision, not just data:**

- **Mistcrest / Corrosive Coin (3448) ingestion.** TimeIsMoney has *no currency subsystem
  at all*; it tracks gold (coin, vendor sales, AH mail). "Ingesting" currency IDs means
  building currency tracking from scratch, which is a feature, not a data drop. Flagged
  rather than invented.
- **Coiled Isle for Grounds.** Grounds ranks zones from the run journal using the zone name
  the client reports, so a new zone needs no data. The `12.1-LAUNCH-DATA.md` map IDs for
  Coiled Isle are tagged for **Gleaner**, not this addon.

## Release checklist

Version lives in `TimeIsMoney.toc`. Bump → CHANGELOG entry → README header → commit →
`git tag -a vX.Y.Z` → push tag. The tag triggers `.github/workflows/release.yml`
(BigWigsMods/packager on `actions/checkout@v7`, verified working since v1.0.5) which
uploads the zip to CurseForge and mirrors a GitHub release.

**The CurseForge Description is NOT synced by the packager.** README never reaches the
project page; that text is hand-pasted in the CurseForge web UI. See the
`curseforge-description-not-synced` memory.

## Wago (half-configured)

`WAGO_API_TOKEN` is wired in the workflow. Still needed, all Marshall's: create the project
at `addons.wago.io`, generate a key at `addons.wago.io/account/apikeys`, add it as repo
secret `WAGO_API_TOKEN`, and hand over the 8-character project ID so `## X-Wago-ID:` can go
in the `.toc`. Upload is skipped silently until both halves exist, so it cannot break
CurseForge releases in the meantime.
