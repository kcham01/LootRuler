-- Which parts of the addon the tests reach: runs every test file with a line hook, then lists the functions no test
-- runs at all, file by file (build/coverage.txt). A function counts as reached when any line inside it runs.
--   lua5.1 tools/coverage.lua            (all the tests)
--   lua5.1 tools/coverage.lua loot ui    (some)
local TESTS = { "session", "rolls", "raid", "loot", "party", "guild", "gdkp", "gargul", "ui" }
if #arg > 0 then TESTS = arg end
os.execute("mkdir -p build && rm -f build/coverage.lines")

-- each test runs in its own Lua, with a hook that notes "file:line" for the addon's own files and writes them out at exit
local HOOK = [[
local seen, cache = {}, {}
debug.sethook(function(_, line)
  local src = debug.getinfo(2, "S").source
  local f = cache[src]
  if f == nil then f = src:match("LootRuler/(Core/[%w_]+%.lua)$") or src:match("LootRuler/(UI/[%w_]+%.lua)$") or false cache[src] = f end
  if f then seen[f .. ":" .. line] = true end
end, "l")
local exit = os.exit
os.exit = function(...)
  debug.sethook()
  local out = io.open("build/coverage.lines", "a")
  for k in pairs(seen) do out:write(k, "\n") end
  out:close()
  exit(...)
end
]]
local hookFile = io.open("build/coverage_hook.lua", "w")
hookFile:write(HOOK)
hookFile:close()
for _, t in ipairs(TESTS) do
  io.write("running ", t, "... ")
  io.flush()
  local ok = os.execute(("lua5.1 -e 'dofile(\"build/coverage_hook.lua\")' tests/%s.lua > /dev/null 2>&1"):format(t))
  print(ok == 0 and "ok" or "(it failed: the report may miss lines)")
end

local ran = {}
for l in io.lines("build/coverage.lines") do ran[l] = true end

-- the functions in each file: from "function" to the "end" at the same indent
local files = {}
for line in io.lines("LootRuler/LootRuler.toc") do
  local l = line:gsub("\r", ""):gsub("\\", "/")
  local f = l:match("^(Core/[%w_]+%.lua)$") or l:match("^(UI/[%w_]+%.lua)$")
  if f then files[#files + 1] = f end
end
local out, missing, total = {}, 0, 0
for _, f in ipairs(files) do
  local lines = {}
  for l in io.lines("LootRuler/" .. f) do lines[#lines + 1] = l end
  local unreached = {}
  for i, l in ipairs(lines) do
    local indent, name = l:match("^(%s*)local function ([%w_%.:]+)")
    if not name then indent, name = l:match("^(%s*)function ([%w_%.:]+)") end
    if not name then indent, name = l:match("^(%s*)([%w_%.]+) = function") end
    if name and not l:find("end%s*$") then
      local stop = #lines
      for j = i + 1, #lines do
        if lines[j]:match("^" .. indent .. "end") then stop = j break end
      end
      local hit = false
      for j = i + 1, stop - 1 do if ran[f .. ":" .. j] then hit = true break end end
      total = total + 1
      if not hit then missing = missing + 1 unreached[#unreached + 1] = ("  %s:%d  %s"):format(f, i, name) end
    end
  end
  if #unreached > 0 then out[#out + 1] = f .. " (" .. #unreached .. " not reached)" for _, u in ipairs(unreached) do out[#out + 1] = u end end
end
local report = ("%d of %d functions reached by the tests (%d not)\n\n"):format(total - missing, total, missing) .. table.concat(out, "\n") .. "\n"
local r = io.open("build/coverage.txt", "w")
r:write(report)
r:close()
print(report)
