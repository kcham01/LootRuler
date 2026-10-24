#!/bin/bash
# Builds and checks the addon (run by .github/workflows/build.yml): the session rules, a whole raid of
# clients, Gargul's own importer reading the export, the API check against Blizzard's interface code, the
# clicked-through window, the screen pictures, and the zip to install.
set -eo pipefail      # a failing test fails the build, even piped into tee
mkdir -p build out
exec > >(tee build/build.log) 2>&1
VERSION="$(grep -m1 '^## Version:' LootRuler/LootRuler.toc | sed 's/## Version: *//' | tr -d '\r')"
echo "== LootRuler $VERSION, build ${GITHUB_RUN_NUMBER:-?}"

echo "== the session rules and the loot data"
lua5.1 tests/session.lua | tee build/session.log

echo "== the rules of rolling for loot"
lua5.1 tests/rolls.lua | tee build/rolls.log

echo "== a whole raid: the leader, raiders with the addon, a pug whispering, a guild member outside the group"
lua5.1 tests/raid.lua | tee build/raid.log

echo "== a whole raid rolling out loot: roll windows, reserved items, ties, hard reserves, master loot"
lua5.1 tests/loot.lua | tee build/loot.log

echo "== a guild raid: the guild book, raid points and boosted rolls"
lua5.1 tests/guild.lua | tee build/guild.log

echo "== a GDKP raid: auctions, the pot and payouts"
lua5.1 tests/gdkp.lua | tee build/gdkp.log

echo "== Gargul reading LootRuler's reserves"
GARGUL=gargul lua5.1 tests/gargul.lua | tee build/gargul.log

echo "== only what the TBC Anniversary client has"
lua5.1 tools/check_api.lua wowui | tee build/api.log

echo "== the window, clicked through"
lua5.1 tests/ui.lua | tee build/ui.log
ICONS=1 node tools/render.mjs build/shots

echo "== the zip"
rm -rf out/pkg && mkdir -p out/pkg
cp -r LootRuler out/pkg/
cp LICENSE out/pkg/LootRuler/
(cd out/pkg && zip -qr ../LootRuler.zip LootRuler)
cp out/LootRuler.zip "out/LootRuler-$VERSION.zip"
ls -la out
