-- Loads LootRuler's files in TOC order into an environment, the way the game does (each file gets the
-- addon name and the shared namespace table as `...`).
local M = {}

function M.files(root)
  local files = {}
  for line in io.lines(root .. "/LootRuler/LootRuler.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") then files[#files + 1] = (line:gsub("\\", "/")) end
  end
  return files
end

--- loads the addon into env (a stand-in global table); returns its namespace
function M.load(root, env, want)
  local LR = {}
  for _, f in ipairs(M.files(root)) do
    if not want or want(f) then
      local chunk, err = loadfile(root .. "/LootRuler/" .. f)
      if not chunk then error(err) end
      setfenv(chunk, env)
      chunk("LootRuler", LR)
    end
  end
  return LR
end

return M
