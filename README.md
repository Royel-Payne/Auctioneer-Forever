# Auctioneer for WoW: Forever

Auction house prices and selling help for **World of Warcraft: Forever**. It works
inside the normal auction house window, with no extra window to manage.

## Install

1. Open the [**Releases**](../../releases/latest) page and download
   **`Auctioneer-Forever-<version>.zip`** under *Assets*.
   (Not "Source code", that's for developers.)
2. Close WoW.
3. Unzip it. You get 9 folders: `!Swatter`, `Auctioneer`, `Auctioneer_Stats_OverTime`,
   `Auctioneer_Util_DealFinder`, `Auctioneer_Util_Valuer`, `Enchantrix`, `Informant`,
   `SlideBar` and `Stubby`.
4. Move all 9 into your AddOns folder:
   `World of Warcraft\_forever_\Interface\AddOns\`
   (usually `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`).
   If Windows asks, replace the existing files.
5. Start WoW. If the addons show as out of date on the character screen, click
   **AddOns** and tick **Load out of date AddOns**.

To update, do the same with a newer zip.

## Using it

- **Scan prices:** happens by itself. When you open the auction house and the prices are
  over an hour old, Auctioneer scans once and says so in chat. To rescan by hand, clear
  the search box, category and filters: the **Search** button then reads **Scan**
  (hover it to see when the last scan was). Auctioneer never searches on a timer.
- **Tooltips:** item tooltips show the prices from your scans.
- **Separate prices per auction house:** your faction's house and the neutral goblin
  houses (Booty Bay, Gadgetzan, Everlook) keep separate prices, and so does each ruleset
  (Normal, PvP, RP, RP-PvP). Each house is scanned on its own. Away from the auction
  house, tooltips show your faction's house. Version .25 deleted the prices saved before
  it, because they mixed every house together.
- **Deal finder:** after a scan, a panel next to the auction house lists items posted
  below their usual price or below what a vendor pays. Hover a row for the numbers behind
  the deal; click it to find the item on the Buy tab.
- **Selling:** on the **Sell** tab, put an item in the slot. The **Valuer** panel shows
  its price history (with when it was last seen at auction) and a **vendor check**: whether the auction pays more than a vendor
  after the auction house's 5% cut, the deposit you lose if it doesn't sell, and the
  lowest price that beats the vendor.
- **Items with a suffix** ("Cloak of the Monkey"): Blizzard's list on the Sell tab mixes
  in every variant and prices yours like the cheapest of them, which can be far too low.
  Auctioneer looks up your exact item, lists only those auctions under the Valuer, and
  sets your price to the cheapest of them (or from its price history if none are listed).
  It never overwrites a price you typed; click a row to use its price.
- **Undercut:** set an amount in the settings and, when the price comes from the cheapest
  listing (Blizzard's pick or the exact match), Auctioneer posts that much below it. Not
  when the cheapest is yours, and never over a price you typed. The vendor check shows the undercut,
  and the Deal finder counts it in what you'd make reselling.
- **Swapping the sell item:** drop a different item on the sell slot and the old one
  simply stays in your bags.
- The auction house window can be dragged around.

**Settings:** *Options > AddOns > Auctioneer*, or type `/auc`. Turn the scan on opening
on or off and choose how old prices must be first (1 to 24 hours), set the Deal finder's
minimum discount and profit, set the undercut, and switch the Scan label, the vendor check, exact-name
pricing for suffix items and the sell-slot swap on or off.

Don't care about disenchanting? Untick **Enchantrix** in the AddOns list. Keep `Stubby`,
`SlideBar` and `!Swatter` on: the others need them.

## Problems

If a Lua error box pops up, please
[open an issue](../../issues) with the text from the box (it has a "Select All" to copy it).

## About this version

Auctioneer is Norganna's addon ([official source](https://gitlab.com/norganna-wow/auctioneer)).
This copy is based on [profdumbbelldore's 12.x fork](https://github.com/profdumbbelldore/Auctioneer-12.x.BETA)
and [NoobyGains' Forever port](https://github.com/NoobyGains/Auctioneer-Forever), which made it run on
the Forever client. This fork adds:

- fixes from the open pull requests on the Forever port: Enchantrix and SlideBar errors,
  faster scans, tooltip prices for linked and random-suffix ("of the Bear") items, and
  Deal finder / Valuer bug fixes;
- the vendor check, exact-name pricing for suffix items, the undercut, the Scan label
  and the sell-slot swap;
- prices kept per auction house and ruleset;
- a cleanup of files the game never loaded.

Licensed under the GNU GPL v2, see [`LICENSE`](LICENSE).

### For developers

The specs in `spec/` run with [busted](https://lunarmodules.github.io/busted/) on Lua 5.1:
`spec/run.sh` (Docker), or build `spec/Dockerfile` and run it with the repository mounted at `/src`.
