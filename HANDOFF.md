<!-- FLEET
addon: TimeIsMoney
version: 1.0.7
status: SHIPPED
owner-chat: TimeIsMoney
needs-marshall: none
next-action: nothing queued; S3 will need a GEAR_TIERS re-check in Core.lua
broadcast-read: 2026-08-29
updated: 2026-08-29
-->

# Time Is Money — session handoff

Status as of **2026-08-29**. Released and public: `github.com/Lumenlytics/Time-Is-Money`,
CurseForge project **1617436**, Wago **mNw7EBNo**. Shipped release **v1.0.7** (Season 2 gear
floors, Cursed Fishing IDs), live-verified on a 15-point in-game pass 2026-08-14.
Season 2 opened Aug 18; the 2026-08-29 news sweep found **no API changes** and nothing
affecting this addon.

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

**STANDING RULE (Marshall, 2026-08-15): re-read `Projects\WoW\BROADCAST.md` before acting on
anything he asks in chat**, not just once at session start. Act on `[ALL]` / `[TimeIsMoney]`
entries dated after the `broadcast-read:` value in the FLEET block above, then bump that
date. The file moves while this chat is idle, so a session-start read goes stale — and
cross-session push messages are retired *and* unreliable in both directions, which makes
this file the only channel that actually works.

**Lint with `luacheck .` from the repo root, not just `luac -p`.** Every repo has a
`.luacheckrc` and the shared Blizzard API surface lives in `../wow-globals.lua`.
Baseline here: **0 errors, 7 style warnings** (unused `ADDON` ×4, two shadowed `T` in
`UI.lua`, verified 2026-08-15). A NEW warning is a regression; those 7 are not.

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

**Shipped in v1.0.7:**

| Change | File |
|---|---|
| `GEAR_TIERS` → Season 2 floors | `Core.lua` |
| `FISH_IDS` (14 Cursed Fishing catches) + `MatProf` fish path | `Core.lua` |
| `fishing` added to `OTHER_GATHER` | `Core.lua` |
| `WAGO_API_TOKEN` wired (now live — Publisher added `X-Wago-ID` in `1724911`) | `.github/workflows/release.yml` |

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

**Decided, closed:**

- **Mistcrest / Corrosive Coin (3448) currency tracking — DROPPED** by Marshall 2026-08-15.
  TimeIsMoney tracks gold only (coin, vendor sales, AH mail) and has no currency subsystem;
  building one is a feature, not a data ingest. Don't re-propose it from a relay.
- **Hardcoded fish vendor values — NOT NEEDED,** verified 2026-08-15. A broadcast entry
  called this an "outstanding fish-data gap", but `Core.lua` already reads vendor price from
  `select(11, C_Item.GetItemInfo(link))` at runtime, so the client supplies it for the new
  fish like any other item. A hardcoded table would duplicate the API and go stale on any
  Blizzard retune.
- **Coiled Isle for Grounds.** Grounds ranks zones from the run journal using the zone name
  the client reports, so a new zone needs no data. The `12.1-LAUNCH-DATA.md` map IDs for
  Coiled Isle are tagged for **Gleaner**, not this addon.

## Release checklist — Publisher owns tagging since 2026-08-15

This chat bumps `## Version` in `TimeIsMoney.toc`, writes the CHANGELOG entry and the README
header, and commits. **It no longer tags or pushes tags.** Declare `ready at N` in the FLEET
block; **Publisher** runs `publish.ps1 -Addon TimeIsMoney -Version N`, which preflights, tags,
and lets the GitHub Action drive the packager to CurseForge / Wago / GitHub Release.

Release plumbing — `.github/`, `.pkgmeta`, the `X-Curse-Project-ID` / `X-Wago-ID` `.toc` lines,
the `.env` guard — is **Publisher's lane**. If it needs changing, post a `[Publisher] ASK`
rather than editing it here.

**The CurseForge Description is NOT synced by the packager.** README never reaches the project
page; that text is a separate browser job. Ask Publisher for it after a README change. See the
`curseforge-description-not-synced` memory.

**The CurseForge Description is NOT synced by the packager.** README never reaches the
project page; that text is hand-pasted in the CurseForge web UI. See the
`curseforge-description-not-synced` memory.

## Wago — configured 2026-08-29

Fully wired. Project ID **mNw7EBNo** is in the `.toc` as `## X-Wago-ID`, added by **Publisher**
in commit `1724911`, and `WAGO_API_TOKEN` is a GitHub repo secret Marshall set himself. No key
exists on this PC and none ever should — see `Projects\WoW\Publisher\SECRETS.md` §1.

Tag pushes now publish to CurseForge and Wago together.
