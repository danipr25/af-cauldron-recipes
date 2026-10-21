-- Luacheck configuration. UE4SS runs Lua 5.4.
std = "lua54"
max_line_length = 120
-- .claude/ holds agent worktrees (other branches); luacheck does not read .gitignore.
exclude_files = { "tests/vendor/", ".claude/" }

-- Mods run inside the AF Mod Loader environment: AF and the UE4SS functions are globals they may read.
files["mod/"] = {
  read_globals = {
    "AF",
    "FName",
    "FindFirstOf",
    "FindAllOf",
    "StaticFindObject",
    "RegisterHook",
    "ExecuteInGameThread",
    "ExecuteWithDelay",
  },
}
