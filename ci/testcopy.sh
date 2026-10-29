#!/bin/bash
# The test copy (run by ci/build.sh): the same addon in its own folder, LootRulerTest, saving to its own file, so a
# branch can be tried in the game beside the real LootRuler without touching its sessions or settings. It talks to
# the raid as LootRuler. Turn on only one of the two in the AddOns list (both on, the test copy says so in chat).
set -eo pipefail
rm -rf out/test && mkdir -p out/test
cp -r LootRuler out/test/LootRulerTest
cp LICENSE NOTICE.txt out/test/LootRulerTest/
cd out/test/LootRulerTest
mv LootRuler.toc LootRulerTest.toc
sed -i \
  -e 's/^## Title:.*/## Title: |cffffd100LootRuler|r |cffff8000test|r/' \
  -e 's/^## Notes:.*/## Notes: A test copy of LootRuler, with its own sessions and settings. Turn on only one of LootRuler and LootRuler test./' \
  -e 's/^## SavedVariables:.*/## SavedVariables: LootRulerTestDB/' \
  -e 's/AddOns\\LootRuler\\/AddOns\\LootRulerTest\\/' \
  LootRulerTest.toc
grep -q '^## SavedVariables: LootRulerTestDB' LootRulerTest.toc
grep -q 'AddOns\\LootRulerTest\\Media' LootRulerTest.toc
cd ..
zip -qr ../LootRulerTest.zip LootRulerTest
