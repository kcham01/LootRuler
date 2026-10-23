-- LootRuler: soft reserves inside the game. The namespace every file shares (loaded first, see LootRuler.toc).
--
-- How it fits together:
--   Data/Loot.lua     the TBC raids, their bosses and what each drops (generated)
--   Core/Loot.lua     looking up raids and items, item names and icons from the game
--   Core/Session.lua  the rules of a soft reserve session (no game calls: tested on its own)
--   Core/Net.lua      keeping the leader and every raider with the addon in step over the addon channel
--   Core/Whisper.lua  "!lr <item>" whispers for raiders without the addon
--   Core/Gargul.lua   the reserves as a Gargul import, and handing them to Gargul
--   UI/*              the window
local ADDON, LR = ...
LR.NAME = ADDON
LR.PREFIX = "LootRuler"          -- addon message prefix (16 characters at most)
LR.TAG = "[LootRuler]"           -- starts every chat line the addon writes for other players
LR.VERSION = "1.0.0-beta"

_G.LootRuler = LR                -- for other addons (and /dump)
