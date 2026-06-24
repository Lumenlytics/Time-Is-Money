# GoldPerGather

Tracks the **Auction House value of everything you gather** — skinning, mining, herbalism —
over time. Gathering income only: it never touches your gold balance, mail, or AH sales, so
flipping and other income stay out of the numbers.

## How it works
When you complete a gathering cast (skin a beast, mine a node, pick an herb), any loot that
lands in the next ~2 seconds is attributed to that profession and valued using:

1. **TradeSkillMaster** (`DBMarket`) if installed
2. **Auctionator** if installed
3. Vendor price as a last-resort fallback

The window shows combined **Gold/hour, This session, Today, Last 7 days, All-time**, a
per-profession session breakdown, and a 7-day bar chart.

## Install
1. Drop the `GoldPerGather` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
2. If you still have a `GatherGold` or `SkinnerGold` folder, leave it in place for this first
   login so its data imports (you'll see an "Imported ... data" message).
3. `/reload` or log in, then delete the old folder. Built for interface **120007** (patch 12.0.7).

## Commands
- `/gpg` — show / hide the window
- `/gpg config` — open the options window (also: the Options button on the panel)
- `/gpg reset` — clear all tracked data (also: right-click the window)
- `/gpg debug` — print each detected cast and recorded item

## Options
- Track professions: turn skinning / mining / herbalism on or off
- Gold/hour window: 5 / 10 / 15 / 20 minutes
- TSM price source: Market / MinBuyout / RegionMarket / RegionSale (only used if TSM is installed)
- Ignore items worth less than: Off / 1g / 5g / 10g / 25g per item

## If a profession isn't being detected
Run `/gpg debug`, gather one node/beast/herb, and note the printed line
(`cast <name> (<id>) -> <prof>`). If it shows no `-> prof`, send the name and it can be added.
