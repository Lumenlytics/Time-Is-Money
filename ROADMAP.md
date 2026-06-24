# GoldPerGather — Ideas & Roadmap

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

- `/gpg run` to start/stop; or auto-start on first gather, auto-stop after N
  minutes idle.
- End-of-run summary: items, cloth, ore, herbs, coin, total AH value, GPH,
  minus repair/consumable costs = **net profit**.

## 3. Liquidation mode — vendor junk at a merchant  — Medium
Toggle. While the mode is ON and a merchant window is open, auto-sell low-value
items and credit the gold to the run.

- `MERCHANT_SHOW` → scan bags → `C_Container.UseContainerItem` to sell.
- Default to **grey (poor) quality only**. Optional higher thresholds behind a
  separate, clearly-labeled toggle.
- Vendor buyback holds 12 slots, so accidental sells are partly recoverable —
  but treat this as destructive: see Safety below.

## 4. Vendor-vs-AH disposition (decision support)  — Medium — ✅ APPROVED
We already compute AH value via TSM / Auctionator in `AHValue()`. Use it to
*advise* rather than blindly vendor.

- For each looted item: compare vendor price vs AH value (× a haircut for cuts/
  undercut). Tag each as **Vendor**, **Auction**, or **Keep**.
- Liquidation mode (#3) then only vendors the "Vendor" items and leaves the
  "Auction" ones in your bags.
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

- **True run-profit GPH** — ✅ APPROVED. coin + item AH value + liquidated vendor
  gold − repairs − consumables, all in one /hr number. The headline metric a gold
  farmer actually wants.
- **Per-zone / per-target stats** — ✅ APPROVED. which zone or mob gives the best
  GPH. Capture zone (`C_Map.GetBestMapForUnit`) and/or target name at loot time.
- **On-screen ticker** — ✅ APPROVED. tiny movable text showing live run gold +
  GPH, so you don't need the panel open while farming. Also on the ticker:
    - a **start/stop run timer**, and
    - a **countdown timer toward a gold goal** ("reach N gold") — shares the
      countdown engine with #7.
- **Item blacklist / whitelist** — ✅ APPROVED. never-sell list (transmog,
  valuable BoEs) + always-sell list, editable in options. Refinements:
    - **autocomplete item names as you type**, and
    - **shift-click an item** (bag slot or chat link) to drop it straight into the
      black/white list — the standard WoW "insert item reference" gesture.
- **Repair & consumable tracking** — folded into #6 (net-gold session record).
- **Disenchant awareness** — (idea, unranked) for greens, compare AH value vs
  typical mat value to suggest DE instead of vendor/AH (advisory only).

---

## Safety rules for any auto-sell feature (#3, #4)
Selling items is destructive and hard to undo — bake these in from the start:

- **Off by default**, with a clear toggle and a one-time "are you sure" the first
  time it's enabled.
- **Quality floor** (grey only) unless explicitly raised.
- **Blacklist** respected before anything is sold.
- **Dry-run mode**: log "would have sold: …" without selling, so behavior can be
  verified before trusting it.
- **Sell log**: print/keep a record of what was auto-sold each run for review
  (vendor buyback only holds the last 12 items).
