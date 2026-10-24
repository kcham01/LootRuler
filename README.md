<p align="center">
  <img src="docs/banner.png" alt="LootRuler: soft reserves inside World of Warcraft for TBC Anniversary raids" width="100%">
</p>

<p align="center">
  <a href="https://github.com/kcham01/LootRuler/raw/results/LootRuler.zip"><img alt="Download" src="https://img.shields.io/badge/Download-addon%20zip-a335ee?style=for-the-badge&logo=worldofwarcraft&logoColor=fff&labelColor=1a1020"></a>
  <a href="#install"><img alt="How to install" src="https://img.shields.io/badge/How%20to-install-ffd100?style=for-the-badge&logo=bookstack&logoColor=000&labelColor=1a1608"></a>
  <a href="#for-raid-leaders"><img alt="For raid leaders" src="https://img.shields.io/badge/For-raid%20leaders-ff8000?style=for-the-badge&labelColor=1a1008"></a>
  <br>
  <a href="https://github.com/kcham01/LootRuler/issues/new?title=Bug:%20&labels=bug"><img alt="Report a bug" src="https://img.shields.io/badge/Found%20a-bug-ff5a4a?style=for-the-badge&logo=github&logoColor=fff&labelColor=1a0b0b"></a>
  <a href="https://github.com/kcham01/LootRuler/issues/new?title=Idea:%20&labels=enhancement"><img alt="Suggest a feature" src="https://img.shields.io/badge/Got%20an-idea-1eff00?style=for-the-badge&logo=github&logoColor=000&labelColor=0b1a0b"></a>
  <a href="https://github.com/kcham01/LootRuler"><img alt="Star on GitHub" src="https://img.shields.io/github/stars/kcham01/LootRuler?style=for-the-badge&logo=github&label=Star&color=0070dd&labelColor=0b101a"></a>
</p>

# LootRuler

<p align="center">
  <img src="https://raw.githubusercontent.com/kcham01/LootRuler/results/shots/04-reserve.png" alt="Reserving" width="32%">
  <img src="https://raw.githubusercontent.com/kcham01/LootRuler/results/shots/09-reserves.png" alt="Everyone's reserves" width="32%">
  <img src="https://raw.githubusercontent.com/kcham01/LootRuler/results/shots/08-session.png" alt="Running the session" width="32%">
</p>

**Soft reserves inside World of Warcraft**, for the **TBC Anniversary** realms. No website, no spreadsheet, no copying names out of Discord: the raid leader picks the raid, how many soft reserves everyone gets and what's hard reserved; raiders pick their reserves from the raid's loot in the game, or type `!lr [item]` in raid chat if they don't have the addon; and when loot drops, everyone gets a **roll window** that knows who reserved it, and a **loot list** of everything that's dropped and who has it. Or send it all to **Gargul** with one click.

Type **/lr** in game.

> **Beta.** If something looks off or throws an error, please [say so](https://github.com/kcham01/LootRuler/issues/new?title=Bug:%20&labels=bug), with a screenshot if you can.

## Every raid up to Zul'Aman

Burning Crusade: **Karazhan, Gruul's Lair, Magtheridon's Lair, Serpentshrine Cavern, Tempest Keep, Mount Hyjal, Black Temple, Zul'Aman** and the Outland world bosses.
The original raids, still there in TBC: **Molten Core, Onyxia's Lair, Blackwing Lair, Zul'Gurub, Ruins of Ahn'Qiraj, Temple of Ahn'Qiraj** and the Azeroth world bosses.

Every boss's loot in kill order, with trash drops, patterns, books, tier tokens, boss heads (the right one for your faction) and Zul'Aman's timed chests: 1,446 items. Items show with the game's own icons, tooltips and quality colours, and every list can be searched, in one raid or all of them, with or without a session open. (Naxxramas isn't there: the original 40-player Naxxramas can't be entered in TBC.)

## For raid leaders

1. **Open reserves** on the Session tab: pick the raid, how many soft reserves each player gets, whether a player can put more than one on the same item (on by default), and whether to share the session with your guild so people can reserve before the group is even made.
2. **Hard reserve** anything: say who it's for and add a note if you like. Anyone who had soft reserved it gets that reserve back.
3. **Reserve yourself** on the Reserve tab, like everyone else.
4. **Post in raid chat** tells everyone how to reserve, addon or not.
5. **Watch it fill up** on the Reserves tab, by item or by player, with who in the group hasn't reserved yet. Take reserves away or add them for people who can't.
6. **Lock** when you're ready, and the reserves go into Gargul (if it's loaded). Or **Send to Gargul** any time, or **Copy for Gargul** to paste into Gargul's importer (`/gl sr`) on the character running loot.

Already used softres.it? **Import from softres.it** brings in its "Gargul Export".

**A raid LootRuler doesn't know yet** (a brand new one, or *World of Warcraft: Forever*'s): pick **Another raid** and name it. Any item can be reserved for it: shift-click the item into the search box, or whisper its link. For a raid it does know, **Any item** lets people reserve loot its lists don't have yet. Either way, it's the leader's addon that decides what can be reserved, so raiders with an older version of LootRuler can still reserve everything.

## For raiders

- **With the addon:** a message tells you when your leader opens reserves. Type **/lr**, click an item to reserve it, right-click to take it back. The list only shows what your class would wear unless you switch "For my class" off. If the leader is offline, your picks wait and go to them when they're back.
- **Without the addon:** type in raid chat, or whisper the leader. The answer comes by whisper.

| Type (raid chat or whisper) | Does |
| --- | --- |
| `!lr <item link or name>` | reserves it (several links in one whisper reserve each) |
| `!lr remove <item>` | takes a reserve back |
| `!lr clear` | takes all of them back |
| `!lr` | tells you what you have reserved |

(`!sr` is left alone: Gargul answers that one.)

## Rolling out loot

When it's time to hand out loot, LootRuler pops up a roll window for everyone, like the game's own Need/Greed window, and it knows who reserved what.

<p align="center">
  <img src="https://raw.githubusercontent.com/kcham01/LootRuler/results/shots/18-loot-master.png" alt="The loot master's panel and window" width="70%">
  <img src="https://raw.githubusercontent.com/kcham01/LootRuler/results/shots/19-roll-windows.png" alt="Roll windows" width="28%">
</p>

- **The loot master** opens a corpse with master loot on and LootRuler lists what's in it beside the loot window, with who reserved each item. Click one to roll it out (or type `/lr roll` and an item link).
- **Everyone with LootRuler** gets a roll window: the dice is main spec (`/roll`), the coin is off spec (`/roll 99`), the x passes. It shows the timer and the highest roll so far, then who won.
- **A soft reserved item** is only rolled for by the players who reserved it, and who are in the raid. Everyone else sees who reserved it, and their window won't let them roll. Once a reserve has won its item it's used up, so if a second one drops it goes to the next reserver.
- **A hard reserved item** isn't rolled for at all: the loot master gets a "Give to" button.
- **A tie** can be rolled again, just between the players who tied.
- **Players without the addon** are told in raid chat what to roll, and their `/roll`s count the same.
- **Giving it out:** the loot master's window lists every roll, best first, and the ones that don't count (wrong roll, didn't reserve it, too late) underneath. One click gives the item to the winner through master loot. The item, the winner and how they won it go on the Reserves tab's list of loot given out.

## The raid's loot list

The **Loot** tab lists everything that has dropped this raid, boss by boss, for the whole raid to see, with the game's icons, tooltips and quality colours: who reserved it, whether it's still on the corpse or being rolled for, who won it and how, and who has it now. Your own wins and reserves stand out. It's part of the soft reserves, so it's cleared when the session ends.

<p align="center">
  <img src="https://raw.githubusercontent.com/kcham01/LootRuler/results/shots/20-loot-tab.png" alt="The Loot tab" width="40%">
</p>

- **Roll now or at the end.** The loot master can roll an item out as soon as it drops, or give it to themselves, keep going, and roll it out from the Loot tab later. The game lets you trade raid loot for 2 hours after you loot it, so the list shows how long is left.
- **Trade help.** When the winner of an item the loot master is holding opens a trade (either of them can open it), LootRuler puts their item in the trade window. When the trade goes through, the list shows they have it. A "To trade" list shows the loot master what they still have to hand over. You can turn this off.
- **Any loot method.** With master loot the loot master's addon writes down each corpse's loot (opening a corpse again doesn't list it twice). With group loot the leader's addon writes down the epics people loot.
- **Mistakes:** the leader can right-click an item to take it off the list, or take an award off.

The loot master (or the raid leader, or an assistant) needs LootRuler; raiders don't, but it's nicer if they have it. `/lr test` shows a pretend roll window so you can drag it where you want it. The Session tab can turn roll windows off, or show them only for items you can roll on.

## Install

1. Download [LootRuler.zip](https://github.com/kcham01/LootRuler/raw/results/LootRuler.zip).
2. Unzip it into `World of Warcraft\_anniversary_\Interface\AddOns`, so you have a `LootRuler` folder there.
3. Restart the game (a new addon needs a full restart) and make sure it's ticked in the AddOns list.
4. Type `/lr` or click the note on the minimap.

Only the raid leader (and whoever runs loot) needs an up-to-date LootRuler. Older and newer versions work together, the addon says when someone has a newer one, and the Reserves tab shows the leader who in the group doesn't have LootRuler at all, so they know who'll whisper.

`/lr session` opens the Session tab, `/lr reserves` the list of everyone's reserves, `/lr roll <item>` rolls an item out, `/lr loot` the raid's loot, `/lr master` brings back the loot master's window, `/lr test` shows a pretend roll window, `/lr settings` opens the Settings tab (every option, each saying what it does), `/lr help` lists the commands, `/lr minimap` hides or shows the minimap button.

## How it's checked

Every build:

- checks the session rules (limits, doubling up, hard reserves, locking, changing the rules part way);
- runs a **whole raid of clients side by side** in a stand-in for the game: the leader, raiders on the same and other realms, a pug whispering, a guild member outside the group, the leader logging out and back in, people joining late, and messages from people who shouldn't be able to change things;
- runs the same raid **rolling out loot**: the loot master opens a corpse, raiders roll from their roll windows and a pug types `/roll`, reserved items are only rolled for by their reservers, ties are rolled again, hard reserved items are given straight out, someone is out of range, an assistant runs the loot, and every item goes to the right player through master loot; then the raid's loot list: what each corpse dropped, who has it, items kept to roll out later and handed over in trades, and group loot;
- loads **Gargul's own soft-reserve importer** and checks it reads LootRuler's reserves exactly (doubled reserves, classes, hard reserves, players from other realms);
- checks the addon only uses what the TBC Anniversary client has, against Blizzard's own interface code;
- clicks through every screen, checks nothing errors or leaks frames, and draws every screen.

The loot lists were made from AtlasLoot's raid tables and checked boss by boss against the cmangos TBC database; where they disagreed (Hakkar's off-hand Warblade really drops from Mandokir, for example) the database won. `tools/gen_loot.py` makes them again.

## Licence

GPL-2.0. See [LICENSE](LICENSE).

## Credits

| Software / data | Used for | Licence |
| --- | --- | --- |
| [AtlasLootClassic](https://github.com/Hoizame/AtlasLootClassic) | Which items each boss drops, in what order | GPL-2.0 |
| [cmangos tbc-db](https://github.com/cmangos/tbc-db) | Item names, quality and types; checking every loot list | GPL-2.0 |
| [Ace3](https://www.wowace.com/projects/ace3) (AceComm, CallbackHandler, LibStub, ChatThrottleLib) | Addon messages | BSD |
| [LibSerialize](https://github.com/rossnichols/LibSerialize) | Packing addon messages | MIT |
| [LibDeflate](https://github.com/SafeteeWoW/LibDeflate) | Compression for addon messages and Gargul strings | zlib |
| [Gargul](https://github.com/papa-smurf/Gargul) | Its importer is used in the tests (not shipped) | |
| [wowsims/tbc](https://github.com/wowsims/tbc) | Icon names for the test pictures (not shipped) | MIT |
| [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) | Checking the addon against the client's interface code (not shipped) | Blizzard's |

World of Warcraft and The Burning Crusade are trademarks or registered trademarks of Blizzard Entertainment, Inc. LootRuler is a fan-made addon and is not made, endorsed or supported by Blizzard Entertainment. Gargul is a separate addon by its own authors.
