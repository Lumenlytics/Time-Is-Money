# Time Is Money — Ideas & Roadmap

Scratchpad for future features. Nothing here is committed; it's a backlog so ideas
don't get lost. Rough feasibility tags: **Easy / Medium / Hard / Rabbit hole**.

---

## 1. Money ("coin") gather branch  — Easy
Track raw gold looted during a run, alongside the professions.

- Hook `CHAT_MSG_MONEY` (or diff `PLAYER_MONEY`) to capture coin loot.
- Feed it into the same session / today / week / all-time / GPH plumbing as a
  pseudo-profession `money` so it shows in the breakdown and the daily chart.
- Caveat: `PLAYER_MONEY` also fires for vendoring, repairs, mail, etc. Prefer
  `CHAT_MSG_MONEY` ("You loot X copper") so we only count *looted* coin, not
  every wallet change.

## 2. Run framing: Start/Stop a farm run  — Easy
Right now "session" = since login. A bounded run is more useful for GPH.

- `/tim run` to start/stop; or auto-start on first gather, auto-stop after N
  minutes idle.
- End-of-run summary: items, cloth, ore, herbs, coin, total AH value, GPH,
  minus repair/consumable costs = **net profit**.

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

## 6. Net-gold session record (with repair handling)  — Medium
A "record this session" mode that reports **net** profit: all gold in minus all
gold out, repairs included.

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

## 7. Gold-per-interval with a countdown timer  — Easy/Medium
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

## More ideas (mine)

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

## Safety rules for auto-sell features — N/A (parked)
No feature sells items anymore: #3 became a non-destructive estimate and #4 is
advisory. Nothing here ever modifies your bags. Keep these rules on hand **only if
an auto-sell feature is ever revived**: off by default, quality floor (grey only),
blacklist respected, dry-run mode, and a sell log (vendor buyback holds only 12).
