# Time Is Money — Ideas & Roadmap

Scratchpad for future features. Nothing here is committed; it's a backlog so ideas
don't get lost. Rough feasibility tags: **Easy / Medium / Hard / Rabbit hole**.

## Vision / North Star
A focused, **single-character live farm/gold mod** that answers *"how good is this farm
route right now?"* — real-time Gold/hour + valuation of what you gather. It:
- lets you **control exactly what's tracked**, with an **easy-to-read UI that feels
  native to WoW** — the anti-TSM: no spreadsheet sprawl, not overkill.
- is **self-contained**: gathers the price info we actually use itself, so it never
  *requires* TSM or Auctionator (they stay optional bonuses).

NOTE: the whole-account / multi-character dashboard ("who holds what gold, each char's
professions/income/spend over time") **moved to a separate addon, AltArmy** — see
`AddOns/AltArmy/HANDOFF.md`. Time Is Money stays the live, single-char farming tool.
Everything below serves that focused mission.

---

## 1. Money ("coin") gather branch  — Easy
Track raw gold looted during a run, alongside the professions.

- Hook `CHAT_MSG_MONEY` (or diff `PLAYER_MONEY`) to capture coin loot.
- Feed it into the same session / today / week / all-time / GPH plumbing as a
  pseudo-profession `money` so it shows in the breakdown and the daily chart.
- Caveat: `PLAYER_MONEY` also fires for vendoring, repairs, mail, etc. Prefer
  `CHAT_MSG_MONEY` ("You loot X copper") so we only count *looted* coin, not
  every wallet change.

## 2. Run framing: Start/Stop a farm run  — Easy — ✅ DONE
A bounded run, separate from the persistent all-time ledger.

- `/tim run` (or the Start/Stop button) toggles a run; auto-starts on first
  gather/coin (toggle in options). "This run" + Gold/hour track the active run.
- End-of-run summary printed on stop: duration, per-source totals, total, GPH.
- Pause/Resume (`/tim pause` or button) freezes the run clock so AFK time doesn't
  dilute GPH; the Reset button zeroes the current run without touching all-time data.
- DEFERRED: auto-stop after N idle minutes — idle detection has annoying edge
  cases (would stop you mid-run if you fight without looting). Own pass later.
- Net profit (minus repairs/consumables) arrives with #6 (net-gold session record).

## 3. "Vendor-everything" estimate  — Easy  — ✅ APPROVED (replaces auto-vendor)
Non-destructive. Sums the vendor sell price of items picked up this run and shows a
single figure: *"If you vendored everything, you'd get X."* Nothing is ever sold.

- Vendor price = `select(11, C_Item.GetItemInfo(link))` — the addon already uses
  this as its AH-value fallback. Sum it over the run's picked-up items.
- Toggle the readout on/off via an options checkbox and/or a keybind.
- Respects the blacklist (below): never-sell items (transmog, valuable BoEs) are
  excluded from the total, so it reflects what you'd *actually* vendor.
- ❌ The earlier auto-vendor/liquidation idea is **dropped** — too destructive for
  the payoff. This advisory number gives the useful part (what your junk is worth)
  with zero risk.

## 4. Vendor-vs-AH disposition (decision support)  — Medium — ✅ APPROVED
We already compute AH value via TSM / Auctionator in `AHValue()`. Use it to
*advise* rather than blindly vendor.

- For each looted item: compare vendor price vs AH value (× a haircut for cuts/
  undercut). Tag each as **Vendor**, **Auction**, or **Keep**.
- Purely advisory now (no auto-selling): the tags just tell you what's worth
  vendoring vs holding for the AH. Pairs naturally with #3's vendor-everything
  total.
- End-of-run: "X items worth ~Yg are better sold on the AH" report.

## 5. Auto-post to the Auction House  — Rabbit hole — ❌ DROPPED (defer to TSM/Auctionator)
Technically possible via `C_AuctionHouse.PostItem`, but:

- Requires the AH window open, is heavily rate-limited, and pricing/undercut
  logic is exactly what TSM/Auctionator already do well.
- Reinventing this is a large, fragile project. **Better:** stop at #4
  (disposition) and hand the "Auction" pile off to TSM groups / Auctionator's
  selling list. Let the specialists post.

## 6. Net-gold session record (repair handling)  — Medium — ✅ DONE (repairs only)
SCOPE NOTE: an experimental "all outgoing gold" spending tracker (AH/mail/trades via
`PLAYER_MONEY` deltas) was built then **removed** — that account-bookkeeping belongs in
the separate **AltArmy** addon's always-on per-character income/spend ledger, not in the
farm GPH (mailing a friend says nothing about how good a farm route is). Repairs STAY in
the run net because wear is a direct cost of the farming itself. So this run nets only
repairs against income.

✅ SHIPPED: repair cost during a run is captured (hook on `RepairAllItems` + live
`GetRepairAllCost()` while at a merchant) and netted against the run — end-of-run summary
shows gross − repairs = net, GPH is net, and the panel run-status line shows the running
deduction. **Pro-rated to the wear the run caused**: baseline missing-durability points at
run start (`MissingDurability()`, works anywhere), then charge a repair's cost × (current
missing − baseline)/current — so a pre-existing repair bill paid early in a run charges ~0,
not the whole thing. **Guild/free repairs are skipped robustly**: the hook snapshots
`GetMoney()` and re-checks next frame (`C_Timer.After(0)`), recording only if your personal
gold actually dropped — so an auto-repair addon that pulls guild funds without setting the
`guildBankRepair` arg no longer mis-charges the run. DEFERRED: consumables (food/flasks)
cost.

- On **start**: warn if gear isn't fully repaired ("repair before recording for a
  clean net"). Optionally capture starting durability.
- During the recorded session: tally **gold in** (looted coin, vendor sales) and
  **gold out** (repairs, purchases). Net = in − out.
- Repair cost — ✅ DECIDED: **value the durability lost during the session** via
  `GetRepairAllCost()` / durability delta (not actual repair spend). Charges you
  for wear-during-run even if you repair afterward, and ignores big pre-session
  repair bills.
- **UI note (required):** the option needs a plain-language explanation right by
  the checkbox, e.g. *"Counts the gear wear from this run as a cost — based on the
  repair price of the durability you lost — even if you repair later. Tip: start
  fully repaired for the cleanest number."*
- **Important nuance vs #1:** for the *per-profession coin branch* use
  `CHAT_MSG_MONEY` (looted coin only). But for *this* net ledger you actually
  WANT `PLAYER_MONEY` deltas — every wallet change in and out is the point. Two
  different features, two different events; don't cross them.

## 7. Gold-per-interval with a countdown timer  — ❌ DROPPED (redundant with runs)
Was built, but a separate start/stop interval timer sat too close to the run
controls and confused the panel. Removed in favor of run **Pause/Reset** (#2). The
"countdown" idea returns later only as the gold-goal countdown for the ticker/sound.

Original idea (kept for reference):
A fixed-window earnings timer, separate from the rolling GPH.

- Default 15 minutes, user-definable in options.
- Visible **countdown** to the end of the window; when it hits zero, snapshot
  "you earned Xg this 15:00" and (optionally) auto-restart for the next window.
- Contrast with current GPH, which is a continuous rolling average — this is a
  discrete bucket, more like a farming "challenge timer."

---

## 8. AH-sales (mailbox gold) tracking  — Medium — ✅ APPROVED
A checkbox to track gold collected from **Auction House sale mails** as its own
income source.

- Read the inbox via `GetInboxHeaderInfo(i)` (sender, subject, money). Match the
  subject against `AUCTION_SOLD_MAIL_SUBJECT` ("Auction successful: %s") to pick
  out AH-sale mail specifically.
- The mail money is the **net** you receive (sale price minus the AH cut), which is
  exactly the gold that matters.
- **Count on collection, not on sight.** Money sitting in the mailbox shouldn't
  count until taken — otherwise it double-counts every time the inbox refreshes.
  Track per-mail and record when its money is actually collected.
- **No clash with #1 (coin):** taking mail money does *not* fire `CHAT_MSG_MONEY`,
  so the looted-coin tracker won't see it. Different event paths.

Design decision — keep it OUT of the farm GPH:
- AH sales are **passive income**, not gold-per-hour-of-farming. Folding them into
  the gather GPH would wildly distort "how good is this farm route." So track AH
  sales as a **separate source/line** (its own total + breakdown entry), excluded
  from the gathering GPH. Default the toggle **off** — it's a different kind of
  income the user opts into.

---

## 9. Price source selector (TSM / Auctionator / Vendor)  — Easy — ✅ APPROVED
Today `AHValue()` is hardcoded TSM → Auctionator → vendor. Auctionator is already a
fallback; this just gives the user the choice.

- A **"Price source"** option: **Auto** (TSM → Auctionator → vendor, the default),
  **TSM**, **Auctionator**, **Vendor**.
- Auctionator's public API returns a single value
  (`Auctionator.API.v1.GetAuctionPriceByItemID`), so — unlike TSM — it has no
  sub-types; no extra selector for it. The existing TSM price-string picker only
  applies when TSM is the active source.
- Gray out / hide a source whose addon isn't installed.
- Credit TSM & Auctionator in the README (see note below).

---

## 10. Valuation policy — what actually counts toward your total  — Medium
Consolidates #3 (vendor estimate), #4 (vendor-vs-AH), #9 (price source) and the
blacklist into one coherent "how is each gathered item valued" system.

✅ SHIPPED: **Item pricing mode** selector (options panel + `/tim pricing
vendor|sells|ah`): Vendor-only, "AH if it sells", or AH-always. "If it sells" uses
a quality/class rule (greys + random weapon/armor → vendor; mats/trade goods → AH),
refined by TSM region sold-per-day when present — works WITHOUT TSM region data
(this tester had none; all DBRegion* sources returned nil). Fixed runaway GPH from
fantasy-priced junk gear (28k-gold unsellable swords wrecked the numbers).
`/tim pricetest <shift-click item>` diagnoses raw TSM values.
✅ ALSO SHIPPED: per-item rules (whitelist/blacklist) — `/tim ah|vendor|exclude`
+ shift-click forces an item to AH / vendor / excluded, overriding the mode; `/tim
rules` lists, `/tim clearrule` removes. Stored in TimeIsMoneyDB.itemRules.
STILL TODO: a visual list editor for the rules (comes with the tabbed-options
rework) + tooltips.

Today each gathered item is valued at its AH price (TSM/Auctionator) if available,
else vendor price; coin adds on top. This makes that explicit and controllable:

- **Count vendor value** (checkbox): include items at their vendor sell price.
- **Count AH value** (checkbox): include items at their AH price (TSM/Auctionator).
- **Sale-rate gate (TSM)** — the key refinement: only use the AH price for items
  that actually *sell* (TSM sale rate above a threshold). Items that rarely move
  fall back to vendor price (or are excluded), so an AH price you can't realize
  doesn't inflate your total. "Sells easily" → count AH; "dead listing" → vendor.
- **Per-item override / blacklist**: mark items Use-AH / Vendor-only / Exclude.
  Excluded items don't count toward the total at all. Shift-click to add +
  autocomplete (this *is* the blacklist/whitelist idea, applied to valuation).

Note: this is separate from tracking realized *income streams* (actual vendor
sales, AH-sale mail #8) — those stay opt-in and out of the farm GPH. #10 is purely
about how the stuff you GATHER is valued.

---

## 11. Count incidental run loot (greys, BoEs, mob drops)  — Medium — ✅ DONE (Stage 1)
Stage 1 shipped: "Count looted drops" toggle (`/tim drops` + options checkbox, off
by default). Non-gather loot → a "Drops" source, valued via the existing
AH-or-vendor logic. Only quest items are skipped; **BoP gear IS counted** (farmers
vendor it — a real test run's pile sold for 132g). **Decoupled from runs:** drops
(like gather/coin) always count toward lifetime Today/All-time; the run is purely a
timed lens that captures them while active. Lifetime tracking never needs a run.
STAGE 2 (next — user chose "Both"): capture the ACTUAL vendor-sale gold ("Sold junk
for X" / merchant `PLAYER_MONEY` delta) and reconcile it against the loot-time
estimate, so the total reflects realized gold rather than a guess — without
double-counting the two.
DEFERRED to #10: per-quality floor, keep-blacklist, TSM sale-rate gating.

The gap behind the "I vendored stuff and it wasn't tracked" question. Right now
ONLY gathered items (ore/herb/cloth/leather via a gather cast), tailoring cloth,
and coin are counted. The grey trash, BoE drops, and other loot that fills your
bags on a run are currently **ignored** — but that's real profit.

- Add a **"Count looted drops"** toggle: while a run is active, value everything
  else you loot and add it to a separate **"Drops"** source/line.
- Valuation per #10: greys/poor quality → vendor price (no AH market); higher
  quality → AH price if it sells (TSM sale-rate), else vendor.
- **Blacklist + quality floor**: exclude items you keep (gear you'll equip,
  transmog, quest items). "Soulbound and equippable" is a good auto-skip default.
- Off by default (some want pure gather numbers); shows as its own breakdown line
  so it never muddies the gather GPH unless you opt in.
- This is the foundation that makes #3 (vendor-everything) and #10 meaningful on
  trash, not just gathered mats. Mechanically: `OnLoot` currently drops anything
  without a recent gather cast — this adds a path for non-gather loot.

---

## 12. Self-contained pricing (built-in AH scanner)  — Hard — ✅ APPROVED (vision)
Goal: never *require* TSM/Auctionator — build our own local price source.
- On AH open, query prices for ONLY the items we actually value (gathered mats +
  drops we've seen) — a small targeted set, not the whole AH, so it's fast and
  within `C_AuctionHouse` rate limits. Cache lowest buyout / a rolling market avg
  per item in saved data.
- Use it as a first-class source in `AHValue()`; TSM/Auctionator stay optional.
- ✅ FEASIBLE: local market price (TSM "DBMarket" equivalent). Bounded, doable.
- ❌ NOT feasible locally: TSM's REGION sale-rate / sold-per-day — that needs their
  backend aggregating sales across players; a lone addon can't know it. We don't
  need it: the "sells" gate uses the quality/class rule, and we can track OUR OWN
  sell-through from AH-sale mail over time as a bonus signal. So we can be fully
  TSM-independent for everything this addon actually uses.

## 13. Warband / whole-account view  — ➡️ MOVED TO ALTARMY
The whole-account, multi-character dashboard (per-char gold "who holds what", professions,
income/spend over time) is now its own addon, **AltArmy** — see `AddOns/AltArmy/HANDOFF.md`.
It is NOT part of Time Is Money. Left here as a pointer so the idea isn't looked for in the
wrong place.

---

## 14. Farm-loot sell workflow (BoP auto-sell + BoE AH-gate)  — Medium — ✅ APPROVED
Closes the loop TIM already opens: it loots & VALUES drops (#11) — this REALIZES that gold
by selling the junk at a vendor. Lives in TIM (not AltArmy) because dungeon farming dumps a
ton of vendorable BoP boss-gear into your bags — selling it is part of the farm loop, and it
feeds #11 Stage 2 (reconcile actual "Sold junk for X" gold vs the loot-time estimate).
Consolidates #3 (vendor-everything estimate) + #4 (vendor-vs-AH disposition) into a real
action. **Revives auto-sell, which was parked as too-destructive — so the safety rules below
are now ACTIVE, not parked.**

Per-item facts from `C_Item.GetItemInfo(link)` (full async form; handle
`GET_ITEM_INFO_RECEIVED` for nils — `GetItemInfoInstant` does NOT return these):
- `bindType` (field 14): 1 = BoP, 2 = BoE.
- `expansionID` (field 15): the item's expansion → detect "old" loot vs the current
  expansion (constant; **verify the `< current` test in-game** — some current leveling greens
  report a lower expansionID).
- equippable = non-empty `itemEquipLoc`; quality = `itemQuality`.

Disposition (Keep / Vendor / Auction), all opt-in & OFF by default:
- **Old-expansion BoP gear → Vendor (auto-sell):** bindType==1 (or already soulbound) AND
  equippable AND `expansionID < current`. NEVER auto-sell current-expansion BoP (could be an
  upgrade).
- **BoE → AH-gate:** vendor ONLY if it won't sell on the AH; else tag Auction (Keep).
  Sellability source: TSM region sale-rate → Auctionator price-exists → quality/class
  heuristic. **Default KEEP when unsure** — never auto-vendor a listable BoE.
- **Greys/poor → Vendor**; everything else → Keep unless marked.

UI: a review window on `MERCHANT_SHOW` lists Vendor-tagged items (show bind + expansion so
you see WHY each is tagged); left-click a row toggles it to Keep; a **Sell All** button
vendors the rest via `C_Container.UseContainerItem(bag, slot)` (not protected). Pairs with
the merchant-visit QoL (auto-repair guild-first, etc.).

---

## UI / layout direction
As features grow, one fixed panel won't fit. Direction:

- **Tabbed main panel** as it expands: e.g. Session · History · Lists · Zones —
  each feature on its own surface instead of one crowded window.
- **The two pace tools, never both at once**: rolling-average GPH and the
  interval countdown (#7) answer different questions, so make them **toggleable
  modes of one widget**, not two always-on displays. Recommended over separate
  tabs *for these two* — they're glanceable readouts, so a quick toggle/cycle
  beats a tab switch.
- **Ticker shows one mode at a time**: the on-screen ticker is tiny, so it shows a
  single readout with **click-to-cycle** (run GPH → interval countdown →
  gold-goal countdown). No room for tabs on the ticker itself.

---

## Tooltips & inline help  — Easy — ✅ APPROVED
Discoverability problem (the auto-start checkbox was easy to miss). Add hover
tooltips to every option, plus short section intros once the panel is tabbed.

- `GameTooltip` on each control's OnEnter/OnLeave: one line of plain-language help
  (e.g. "Auto-start a run the moment you gather or loot something"). Cheap to add.
- This is also how we satisfy #6's required plain-language note by the durability
  option — a tooltip is the natural home for it.
- When the panel goes tabbed (see UI direction), give each tab/section a one-line
  intro so its purpose reads at a glance.
- Best built as one pass alongside the options/tabs rework, not piecemeal.

---

## More ideas (mine)

- **Price-source independence / optional self-scanner** — ✅ APPROVED (goal:
  never *require* TSM). Today pricing is TSM → Auctionator → vendor; TSM is already
  optional. The only TSM-exclusive bit is sale-rate gating (#10), which degrades to
  "has an AH price or not" without it. For true zero-dependency: a **targeted AH
  scanner** that fetches buyouts for ONLY the item types you gather (ore/herb/
  leather/cloth) when the AH is open — bounded scope, NOT a TSM clone — cached as a
  built-in price source. Tiers: (1) Auctionator-only [done], (2) vendor-only,
  (3) self-scan. Keep vendor price as the always-available floor.
- **Loot tally panel ("what dropped", done right)** — ✅ APPROVED. Replace the
  MoneyLooter-style chronological *feed* (one line per loot = instant clutter) with
  an aggregated *tally*: one row per item type, count + value updated in place, so
  it never grows unbounded. Sort by value (default) / count / recency; cap to top
  ~10-12 rows with a "+N more (Xg)" footer; reuse the min-value threshold to hide
  noise; quality-color item names; per-run scope with Today/All-time toggle; its
  own panel, off by default → natural "Loot" tab in the tabbed rework. Data already
  exists (the per-item `items` table) — this is mostly display.
- **Other professions (Engineering, etc.)** — debug showed an unmatched cast
  `Engineering (49383)`; correctly ignored today (not a gathering prof, no keyword
  match). TODO: decide whether any non-gather profession should contribute value —
  e.g. Engineering salvage/scrapping, or crafted-item value — or stay ignored.
  Needs scoping: what counts, and how to value it without double-counting mats.

- **True run-profit GPH** — ✅ APPROVED. coin + item value (best of AH-or-vendor
  per item, via #4) − repairs − consumables, all in one /hr number. The headline
  metric a gold farmer actually wants. (No "liquidated gold" line now that
  auto-vendor is dropped — value is potential, not realized.)
- **Per-zone / per-target stats** — ✅ APPROVED. which zone or mob gives the best
  GPH. Capture zone (`C_Map.GetBestMapForUnit`) and/or target name at loot time.
- **On-screen ticker** — ✅ APPROVED. tiny movable text showing live run gold +
  GPH, so you don't need the panel open while farming. Also on the ticker:
    - a **start/stop run timer**, and
    - a **countdown timer toward a gold goal** ("reach N gold") — shares the
      countdown engine with #7.
- **Item blacklist / whitelist** — ✅ APPROVED. Now feeds the *estimate*, not an
  auto-seller: blacklist = never-vendor (excluded from #3's total, tagged Keep in
  #4); whitelist = always count as vendor. Editable in options. Refinements:
    - **autocomplete item names as you type**, and
    - **shift-click an item** (bag slot or chat link) to drop it straight into the
      black/white list — the standard WoW "insert item reference" gesture.
- **Repair & consumable tracking** — folded into #6 (net-gold session record).
- **Disenchant awareness** — (idea, unranked) for greens, compare AH value vs
  typical mat value to suggest DE instead of vendor/AH (advisory only).

---

## Audio & polish — ✅ APPROVED (build alongside run framing / timers)
Make it feel ship-worthy with tasteful built-in WoW sounds. The namesake hook:
the goblin **"Time is money, friend!"** voiceover.

- **Signature line** on **run start** (#2) — thematic greeting. Maybe also when a
  gold goal is hit. Save the *voice* for "start / win" moments only.
- **Timer / countdown end** (#7): a distinct alert sound (alarm-like, not the
  voice).
- **Gold-goal reached**: a coin / cash-register style sound.

Implementation notes:
- Small `Sounds.lua`: one `Play(name)` entry point, an event→sound table, played
  on the **SFX channel** so it respects the player's sound settings.
- **Toggleable** — a master "addon sounds" checkbox, ideally per-event toggles.
  Some players hate addon audio; default on, easy to silence.
- **Don't spam** — debounce. The voice once per run start is plenty; never per loot.
- `PlaySound(soundKitID, "SFX")` for named kits; `PlaySoundFile(fileID, "SFX")` for
  a specific voice file.
- **Open question — exact IDs:** the goblin line + coin/alarm sounds need their
  SoundKit / FileData IDs confirmed in-game. Audition candidates via a temporary
  `/tim sound <id>` command, then lock the winners. "Time is money, friend!" is an
  NPC voiceover file, so probably `PlaySoundFile`, not a named kit.

## Safety rules for auto-sell features — ✅ ACTIVE (auto-sell revived by #14)
#14 (farm-loot sell workflow) revives auto-vendoring, so these are now REQUIRED, not
parked. Any feature that modifies bags MUST: be **off by default**; honor a **quality/ilvl
floor**; respect the **never-sell blacklist**; offer a **dry-run/preview** before the first
real sell; and keep a **sell log** (vendor buyback holds only the last 12 items, so a wrong
sell can be hard to undo). The BoE AH-gate additionally **defaults to Keep when uncertain**
so a listable BoE is never auto-vendored.
