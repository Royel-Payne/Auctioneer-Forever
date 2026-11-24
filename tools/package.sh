#!/bin/sh
# Builds the player zip for a release: the 9 addon folders at the top level of the zip,
# from the committed tree (git archive), plus the license inside Auctioneer/.
# Usage: tools/package.sh            -> dist/Auctioneer-Forever-<version>.zip
set -e
cd "$(dirname "$0")/.."
FOLDERS='!Swatter Auctioneer Auctioneer_Stats_OverTime Auctioneer_Util_DealFinder Auctioneer_Util_Valuer Enchantrix Informant SlideBar Stubby'
VERSION=$(sed -n 's/^## Version: *//p' Auctioneer/Auctioneer.toc | tr -d '\r')
[ -n "$VERSION" ] || { echo "no version in Auctioneer.toc" >&2; exit 1; }
if [ -n "$(git status --porcelain -- $FOLDERS LICENSE)" ]; then
	echo "uncommitted changes in the addon folders; commit first" >&2; exit 1
fi
OUT="dist/Auctioneer-Forever-$VERSION.zip"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p dist
# shellcheck disable=SC2086
git archive --format=tar HEAD -- $FOLDERS | tar -x -C "$STAGE"
cp LICENSE "$STAGE/Auctioneer/LICENSE.txt"
rm -f "$OUT"
(cd "$STAGE" && zip -qr -X - $FOLDERS) > "$OUT"
echo "$OUT"
