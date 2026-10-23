#!/bin/bash
# Puts the addon zip, screen pictures and logs on the "results" branch
mkdir -p results
cp out/LootRuler.zip results/ 2>/dev/null || true
mkdir -p results/shots && cp build/shots/*.png results/shots/ 2>/dev/null || true
cp build/*.log results/ 2>/dev/null || true
echo "build $GITHUB_RUN_NUMBER of $GITHUB_SHA" > results/RUN.txt
[ -f out/LootRuler.zip ] && echo "zip built" >> results/RUN.txt || echo "no zip" >> results/RUN.txt
cd results
git init -q
git checkout -q -b results
git add -A
git -c user.name="LootRuler build" -c user.email="build@users.noreply.github.com" commit -qm "Results of build $GITHUB_RUN_NUMBER"
git push -qf "https://x-access-token:$TOKEN@github.com/$GITHUB_REPOSITORY" results
