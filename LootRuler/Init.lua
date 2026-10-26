-- LootRuler: soft reserves inside the game. The namespace every file shares (loaded first, see LootRuler.toc).
--
-- How it fits together:
--   Data/Loot.lua     the TBC raids, their bosses and what each drops (generated)
--   Core/Loot.lua     looking up raids and items, item names and icons from the game
--   Core/Session.lua  the rules of a soft reserve session (no game calls: tested on its own)
--   Core/Net.lua      keeping the leader and every raider with the addon in step over the addon channel
--   Core/Whisper.lua  "!lr <item>" whispers for raiders without the addon
--   Core/Gargul.lua   the reserves as a Gargul import, and handing them to Gargul
--   Core/Roll.lua     the rules of rolling for an item (no game calls: tested on their own)
--   Core/Rolls.lua    rolling loot out: the loot master's roll, raiders following it, master loot
--   Core/Book.lua     the guild book: boosted roll points and priority lists (no game calls)
--   Core/Guild.lua    sharing the guild book with the guild; who may change it
--   Core/Prio.lua     priority lists in and out (Gargul's CSV, DFT, thatsmybis)
--   Core/Gdkp.lua     GDKP: auctions' pot, cuts and payouts (no game calls); Core/Pot.lua does it in the game
--   Core/History.lua  past raids: what each gave out, kept after it ends (and a GDKP's payouts)
--   UI/*              the window; UI/RollFrame.lua the roll windows, UI/Master.lua the loot master's,
--                     UI/ReserveStrip.lua who reserved the item being rolled for (LootRuler's rolls and Gargul's)
--   Core/Notes.lua    the loot master's notes on items ("Warrior > Rogue"), in and out as text
--                     UI/Lineup.lua raid setup (Core/Lineup.lua reads the list and works out the moves)
--                     UI/Timers.lua bars for the items I hold to roll out or trade, with the trade time left
local ADDON, LR = ...
LR.NAME = ADDON
LR.PREFIX = "LootRuler"          -- addon message prefix (16 characters at most)
LR.TAG = "[LootRuler]"           -- starts every chat line the addon writes for other players
LR.VERSION = "1.0.0-beta"
LR.LOGO = "Interface\\AddOns\\LootRuler\\Media\\Logo"   -- Media/Logo.tga (drawn by tools/art.mjs)

_G.LootRuler = LR                -- for other addons (and /dump)
