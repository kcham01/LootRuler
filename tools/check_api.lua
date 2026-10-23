-- Checks the addon only uses what the TBC Anniversary client has, against Blizzard's own interface code
-- (github.com/Gethe/wow-ui-source, branch classic_anniversary):
--  1. every method the test stand-in (tests/wow/mock.lua) gives a widget is in the client's API
--     documentation for that widget type, so the UI tests can't pass on a method the game lacks;
--  2. every global the addon reads is a Lua built-in, a documented client function, something the
--     client's interface code defines, or the addon's own.
-- lua5.1 tools/check_api.lua <wow-ui-source checkout>
local src = assert(arg[1], "usage: lua5.1 tools/check_api.lua <wow-ui-source>")
local docsDir = src .. "/Interface/AddOns/Blizzard_APIDocumentationGenerated"

local docs = {}
local function loadDocs()
  local p = io.popen('ls "' .. docsDir .. '"')
  for f in p:lines() do
    if f:match("%.lua$") then
      local chunk = loadfile(docsDir .. "/" .. f)
      if chunk then
        local captured
        local env = setmetatable({ APIDocumentation = { AddDocumentationTable = function(_, t) captured = t end } }, { __index = function() return nil end })
        setfenv(chunk, env)
        pcall(chunk)
        if captured then docs[#docs + 1] = captured end
      end
    end
  end
  p:close()
end
loadDocs()

local byName, globals = {}, {}
for _, d in ipairs(docs) do
  if d.Name then byName[d.Name] = d end
  for _, fn in ipairs(d.Functions or {}) do
    if d.Type ~= "ScriptObject" then
      if d.Namespace then globals[d.Namespace] = true else globals[fn.Name] = true end
    end
  end
end
local function methods(...)
  local out = {}
  for _, n in ipairs({ ... }) do
    local d = byName[n]
    if d then for _, fn in ipairs(d.Functions or {}) do out[fn.Name] = true end end
  end
  return out
end

local REGION = { "SimpleObjectAPI", "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleRegionAPI", "SimpleFrameScriptObjectAPI" }
local function with(base, ...) local t = {} for _, x in ipairs(base) do t[#t + 1] = x end for _, x in ipairs({ ... }) do t[#t + 1] = x end return t end
local FRAME = with(REGION, "SimpleFrameAPI")
local KINDS = {
  Frame = FRAME, Button = with(FRAME, "SimpleButtonAPI"), CheckButton = with(FRAME, "SimpleButtonAPI", "SimpleCheckboxAPI"),
  EditBox = with(FRAME, "SimpleEditBoxAPI"), ScrollFrame = with(FRAME, "SimpleScrollFrameAPI"), Slider = with(FRAME, "SimpleSliderAPI"),
  GameTooltip = with(FRAME, "FrameAPITooltip"), PlayerModel = with(FRAME, "SimpleModelAPI", "FrameAPICharacterModelBase"),
  DressUpModel = with(FRAME, "SimpleModelAPI", "FrameAPICharacterModelBase", "FrameAPIDressUpModel"),
  Texture = with(REGION, "SimpleTextureBaseAPI", "SimpleTextureAPI"), FontString = with(REGION, "SimpleFontStringAPI"),
}
-- methods that templates add (BackdropTemplateMixin) rather than the widget itself
local MIXIN = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true, ApplyBackdrop = true }

-- GameTooltip's own methods aren't in the generated documentation; these are ones Blizzard's code calls on tooltips
local TOOLTIP_OK = { SetOwner = true, SetHyperlink = true, AddLine = true, AddDoubleLine = true, ClearLines = true, NumLines = true,
  SetSpellByID = true, SetInventoryItem = true, SetMinimumWidth = true, SetText = true }
local failures = 0
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local M = require("mock")
local G = M.env({})
for kind, list in pairs(KINDS) do
  local api = methods(unpack(list))
  local n = 0
  for _ in pairs(api) do n = n + 1 end
  if n == 0 then print("no documentation found for " .. kind) failures = failures + 1 end
  local obj = (kind == "Texture" or kind == "FontString") and (kind == "Texture" and G.UIParent:CreateTexture() or G.UIParent:CreateFontString()) or M.CreateFrame(kind, nil, G.UIParent)
  -- walk the stand-in's method tables for this kind
  local mt = getmetatable(obj)
  local seen = {}
  for _, probe in ipairs({ "SetPoint", "Show", "SetScript", "SetText", "SetTexture", "SetFontObject", "SetScrollChild", "SetValue", "SetOwner", "SetUnit", "TryOn", "SetAutoFocus", "SetChecked" }) do
    seen[probe] = true
  end
  -- the stand-in keeps its methods in upvalue tables; list them by trying every documented name and every name it defines
  local defined = M.methodNames(kind)
  for name in pairs(defined) do
    if not api[name] and not MIXIN[name] and not (kind == "GameTooltip" and TOOLTIP_OK[name]) then
      print(("%s:%s is in the stand-in but not in the client's API"):format(kind, name))
      failures = failures + 1
    end
  end
  void = mt
end

-- globals the addon reads
local builtins = {}
for k in pairs(_G) do builtins[k] = true end
for _, k in ipairs({ "strsplit", "wipe", "tinsert", "tremove", "format", "strtrim", "floor", "ceil", "max", "min", "abs", "sqrt", "random", "strlower",
  "strupper", "strlen", "strsub", "strfind", "strmatch", "gsub", "strrep", "strbyte", "strchar", "sort", "tconcat", "date", "time", "bit", "debugprofilestop", "geterrorhandler", "seterrorhandler",
  -- set up by the chat frame code at start-up
  "SlashCmdList" }) do builtins[k] = true end

-- names the client's interface code defines (functions, tables, constants, named frames and templates)
local defined = {}
p = io.popen('grep -rhoE "^[A-Za-z_][A-Za-z0-9_]* *=|^function [A-Za-z_][A-Za-z0-9_]*|name=\\"[A-Za-z_][A-Za-z0-9_]*\\"" "' .. src .. '/Interface" --include=*.lua --include=*.xml')
for line in p:lines() do
  local n = line:match('^name="([%w_]+)"') or line:match("^function ([%w_]+)") or line:match("^([%w_]+) *=")
  if n then defined[n] = true end
end
p:close()

-- functions Blizzard's own code calls (the C side has them even when the documentation doesn't list them)
local called, calledMethods = {}, {}
p = io.popen('grep -rhoE "[:.]?[A-Za-z_][A-Za-z0-9_]*\\(" "' .. src .. '/Interface" --include=*.lua')
for w in p:lines() do
  local sep, name = w:match("^([:.]?)([%w_]+)%($")
  if name then
    if sep == ":" then calledMethods[name] = true elseif sep == "" then called[name] = true end
  end
end
p:close()

local own = { TBCrushCalcDB = true, SLASH_TBCRUSHCALC1 = true, SLASH_TBCRUSHCALC2 = true, TBCrushCalcFrame = true }
local files = {}
for line in io.lines("TBCrushCalc/TBCrushCalc.toc") do
  line = line:gsub("\r", "")
  if line:match("%.lua$") and not line:match("^Data") then files[#files + 1] = "TBCrushCalc/" .. line:gsub("\\", "/") end
end
local used = {}
for _, f in ipairs(files) do
  local out = io.popen("luac5.1 -p -l " .. f .. " 2>&1")
  for line in out:lines() do
    local g = line:match("GETGLOBAL.-; ([%w_]+)")
    if g then used[g] = used[g] or f end
  end
  out:close()
end
local names = {}
for g in pairs(used) do names[#names + 1] = g end
table.sort(names)
for _, g in ipairs(names) do
  if not (builtins[g] or globals[g] or defined[g] or called[g] or own[g] or g:match("^TBCrushCalc")) then
    print(("global %s (in %s) is not something the client has"):format(g, used[g]))
    failures = failures + 1
  end
end
print(("checked %d widget types and %d globals; problems %d"):format(#KINDS == 0 and 11 or 11, #names, failures))
if failures > 0 then os.exit(1) end
