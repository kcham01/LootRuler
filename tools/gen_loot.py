"""Builds LootRuler/Data/Loot.lua: the TBC raids, their bosses in kill order and what each one drops.

  python3 tools/gen_loot.py <AtlasLootClassic_DungeonsAndRaids/data-tbc.lua> <cmangos tbc-db dump .sql>

The loot lists come from AtlasLootClassic's TBC raid tables (GPL-2): which bosses, in which order, and which
items each one drops, including trash, patterns and Zul'Aman's timed chests. Tier set overviews and Kael'thas'
legendaries (they vanish when the fight ends) are left out.

Item names, quality, slot, item level and which classes can use them come from the cmangos TBC world database
(GPL-2). The same database checks the lists: every item a boss is listed with has to be in that boss's loot in
cmangos, and every epic the boss can drop in cmangos has to be listed. Anything that doesn't match fails the
build unless it's in KNOWN below, with the reason.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import sqlrows  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# AtlasLoot key -> what the addon calls the raid, a short name, raid size
RAIDS = [
    ('Karazhan', 'Karazhan', 'Kara', 10),
    ('GruulsLair', "Gruul's Lair", 'Gruul', 25),
    ('MagtheridonsLair', "Magtheridon's Lair", 'Mag', 25),
    ('SerpentshrineCavern', 'Serpentshrine Cavern', 'SSC', 25),
    ('TempestKeep', 'Tempest Keep', 'TK', 25),
    ('HyjalSummit', 'Mount Hyjal', 'Hyjal', 25),
    ('BlackTemple', 'Black Temple', 'BT', 25),
    ('ZulAman', "Zul'Aman", 'ZA', 10),
    ('SunwellPlateau', 'Sunwell Plateau', 'SWP', 25),
    ('WorldBossesBC', 'World Bosses', 'World', 40),
]
SKIP_BOSSES = {'Legendaries', 'Terokk'}   # Kael'thas' weapons vanish after the fight; Terokk is a Skettis summon

# where cmangos keeps a loot list AtlasLoot gives another npc (or no npc) for
SOURCES = {
    'Reliquary of the Lost': [('npc', 23420)],                 # the loot is on the Essence of Anger
    'Chess Event': [('object', 'Dust Covered Chest')],
}

# items AtlasLoot doesn't list for a boss that cmangos has it drop, and that raids reserve
EXTRA = {
    'Magtheridon': [32386],    # Magtheridon's Head for the Horde (AtlasLoot lists the Alliance one): one per kill
    # the Twins drop the same Sunwell tier tokens as Kalecgos, Brutallus and Felmyst
    'Eredar Twins': [34848, 34851, 34852, 34853, 34854, 34855, 34856, 34857, 34858],
}

# differences from cmangos that are right, with why
KNOWN = {
}

ALLIANCE, HORDE = 1101, 690    # race masks: human, dwarf, night elf, gnome, draenei / orc, undead, tauren, troll, blood elf
MIN_QUALITY = 2   # grey and white raid drops are quest items everyone loots for themselves
SKIP_ITEMS = {29434}   # Badge of Justice: everyone gets one


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def main():
    al_path, sql_path = sys.argv[1], sys.argv[2]
    al = json.loads(subprocess.check_output(['lua5.1', os.path.join(ROOT, 'tools/atlasloot_extract.lua'), al_path]))
    by_key = {r['key']: r for r in al}

    cols, rows = sqlrows.table(sql_path, 'item_template')
    ci = {c: i for i, c in enumerate(cols)}
    items = {int(r[ci['entry']]): r for r in rows}

    ccols, crows = sqlrows.table(sql_path, 'creature_template')
    cc = {c: i for i, c in enumerate(ccols)}
    loot_id = {int(r[cc['Entry']]): int(r[cc['LootId']]) for r in crows}

    # items that drop only for one faction (Magtheridon's Head): the loot row's condition says which
    kcols, krows = sqlrows.table(sql_path, 'conditions')
    ki = {c: i for i, c in enumerate(kcols)}
    team_of = {int(r[ki['condition_entry']]): {'469': ALLIANCE, '67': HORDE}[r[ki['value1']]]
               for r in krows if r[ki['type']] == '6' and r[ki['value1']] in ('469', '67')}
    faction = {}

    def loot_table(name):
        c, rs = sqlrows.table(sql_path, name)
        ix = {x: i for i, x in enumerate(c)}
        out = {}
        for r in rs:
            out.setdefault(int(r[ix['entry']]), []).append((int(r[ix['item']]), int(r[ix['mincountOrRef']])))
            team = team_of.get(int(r[ix['condition_id']]))
            if team:
                faction[int(r[ix['item']])] = team
        return out
    creature_loot = loot_table('creature_loot_template')
    reference_loot = loot_table('reference_loot_template')
    object_loot = loot_table('gameobject_loot_template')
    gcols, grows = sqlrows.table(sql_path, 'gameobject_template')
    gi = {c: i for i, c in enumerate(gcols)}
    object_loot_id = {}
    for r in grows:
        if r[gi['type']] == '3':     # chests: data1 is the loot id
            object_loot_id.setdefault(r[gi['name']], set()).add(int(r[gi['data1']]))

    ref_memo = {}

    def expand(rows, stack=()):
        found = set()
        for item, ref in rows:
            if ref < 0:
                r = -ref
                if r not in ref_memo:
                    ref_memo[r] = set() if r in stack else expand(reference_loot.get(r, []), stack + (r,))
                found |= ref_memo[r]
            else:
                found.add(item)
        return found

    def drops(kind, what):
        if kind == 'object':
            out = set()
            for lid in object_loot_id.get(what, ()):
                out |= expand(object_loot.get(lid, []))
            return out
        return expand(creature_loot.get(loot_id.get(what) or what, []))

    # how many different creature loot lists can drop each item: boss loot is in one or a few, world drops in hundreds
    droppers = {}
    for lid, rows_ in creature_loot.items():
        for item in expand(rows_):
            droppers[item] = droppers.get(item, 0) + 1

    problems, out_raids, used = [], [], set()
    for key, name, short, size in RAIDS:
        raid = by_key[key]
        bosses = []
        for b in raid['bosses']:
            if b['set'] or b['name'] in SKIP_BOSSES:
                continue
            ids = []
            for item in [i[1] for i in b['items']] + EXTRA.get(b['name'], []):
                if item not in items:
                    problems.append(f'{name} / {b["name"]}: item {item} is not in the cmangos item table')
                    continue
                if item not in ids and item not in SKIP_ITEMS and int(items[item][ci['Quality']]) >= MIN_QUALITY:
                    ids.append(item)
            if not ids:
                continue
            npcs = b['npc'] if isinstance(b['npc'], list) else ([b['npc']] if b['npc'] else [])
            sources = SOURCES.get(b['name']) or [('npc', n) for n in npcs]
            if sources:
                cm = set()
                for kind, what in sources:
                    cm |= drops(kind, what)
                for item in ids:
                    if item not in cm and (b['name'], item) not in KNOWN:
                        problems.append(f'{name} / {b["name"]}: {item} {items[item][ci["name"]]} isn\'t in its cmangos loot')
                for item in sorted(cm):
                    r = items.get(item)
                    if (r and int(r[ci['Quality']]) >= 4 and int(r[ci['class']]) != 12 and item not in ids and droppers.get(item, 0) <= 4
                            and (b['name'], item) not in KNOWN):
                        problems.append(f'{name} / {b["name"]}: cmangos has epic {item} {r[ci["name"]]} that isn\'t listed')
            used.update(ids)
            bosses.append({'name': b['name'], 'trash': b['extra'], 'items': ids})
        out_raids.append({'key': key, 'name': name, 'short': short, 'size': size, 'bosses': bosses})

    for p in problems:
        print('!!', p)

    lines = ['-- The TBC raids, their bosses in kill order and what each drops. Generated by tools/gen_loot.py from',
             "-- AtlasLootClassic's TBC raid tables and the cmangos TBC world database. Do not edit by hand.",
             'local _, LR = ...', '', 'LR.RAIDS = {']
    for r in out_raids:
        lines.append(f'  {{ key = {lua_str(r["key"])}, name = {lua_str(r["name"])}, short = {lua_str(r["short"])}, size = {r["size"]}, bosses = {{')
        for b in r['bosses']:
            lines.append(f'    {{ name = {lua_str(b["name"])},{" trash = true," if b["trash"] else ""} items = {{ {", ".join(map(str, b["items"]))} }} }},')
        lines.append('  } },')
    lines += ['}', '', '-- item id = { name (English), quality, inventory type, item class, subclass, item level,',
              '--   classes (bit mask, -1 = all), races (bit mask, -1 = all: some items differ for Alliance and Horde) }',
              'LR.ITEMS = {']
    for item in sorted(used):
        r = items[item]
        mask = int(r[ci['AllowableClass']])
        race = int(r[ci['AllowableRace']])
        race = faction.get(item) or (-1 if race in (0, -1) or race & 1791 == 1791 else race)
        lines.append(f'  [{item}] = {{ {lua_str(r[ci["name"]])}, {r[ci["Quality"]]}, {r[ci["InventoryType"]]}, {r[ci["class"]]}, '
                     f'{r[ci["subclass"]]}, {r[ci["ItemLevel"]]}, {mask if mask not in (0, 32767, -1) else -1}, {race} }},')
    lines.append('}')
    dest = os.path.join(ROOT, 'LootRuler/Data/Loot.lua')
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, 'w', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    total = sum(len(b['items']) for r in out_raids for b in r['bosses'])
    print(f'{len(out_raids)} raids, {sum(len(r["bosses"]) for r in out_raids)} loot lists, {total} entries, {len(used)} items; {len(problems)} problems')
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
