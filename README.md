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

- **Scan prices:** open the auction house, stay on the **Buy** tab, leave the search box
  empty and click **Search**. Auctioneer reads every page and saves the prices. A full scan
  takes a little while; do one now and then to keep prices fresh.
- **Tooltips:** item tooltips show the prices from your scans.
- **Deal finder:** after a scan, a panel next to the auction house lists items posted
  below their usual price.
- **Selling:** on the **Sell** tab, put an item in the slot. The **Valuer** panel shows
  its price history and a **vendor check**: whether the auction pays more than a vendor
  after the auction house's 5% cut, the deposit you lose if it doesn't sell, and the
  lowest price that beats the vendor.
- **Swapping the sell item:** drop a different item on the sell slot and the old one
  simply stays in your bags.
- The auction house window can be dragged around.

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
- the vendor check and the sell-slot swap;
- a cleanup of files the game never loaded.

Licensed under the GNU GPL v2, see [`LICENSE`](LICENSE).

### For developers

The specs in `spec/` run with [busted](https://lunarmodules.github.io/busted/) on Lua 5.1:
`spec/run.sh` (Docker), or build `spec/Dockerfile` and run it with the repository mounted at `/src`.
