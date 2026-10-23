-- Developer tool: copies the Cauldron Recipes mod from this repository into a game that already has AF Mod Loader
-- and AF Mod Loader API, so it can be tested without a release. Never shipped. It runs on the developer's machine,
-- so it may use os.execute.
-- Usage (from the repository root): lua scripts/dev-install.lua [game folder] [--force]
local HELP = [[
Usage: lua scripts/dev-install.lua [game folder] [--force]

Run it from the repository root, with the game closed.

  game folder  Alchemy Factory install folder. Default: the AF_GAME_DIR environment variable, then
               C:\Program Files (x86)\Steam\steamapps\common\Alchemy Factory
  --force      Replace the mod folder even if mod.json there has a different id (it is never replaced otherwise)

It replaces <game>\mods\af-cauldron-recipes with the contents of mod\. AF Mod Loader and AF Mod Loader API must
already be installed (the scripts/dev-install.lua of those repositories do that). It does not touch any other mod,
and it does not touch the recipe records in <game>\mods\.data.]]

local STEAM_DEFAULT = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Alchemy Factory"
local GAME_EXES = { "AlchemyFactory-Win64-Shipping.exe", "AlchemyFactory.exe" }
local MOD_SOURCE = "mod"
local MOD_FOLDER = "af-cauldron-recipes"
local MOD_ID = "af-cauldron-recipes"
local API_FOLDER = "af-modloader-api"

local function fail(message)
  print("Error: " .. message)
  os.exit(1)
end

local function say(message)
  print(message)
end

-- Runs a command. The tool name goes first and unquoted, or cmd.exe would mis-handle the quotes around the paths.
local function run(command, what)
  say("  " .. command)
  local ok = os.execute(command)
  if ok ~= true then
    fail(what .. " failed")
  end
end

local function dirExists(path)
  return os.execute('if exist "' .. path .. '\\" (exit 0) else (exit 1)') == true
end

local function readFile(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local text = file:read("a")
  file:close()
  return text
end

local function isRunning(exe)
  local output = assert(io.popen('tasklist /FI "IMAGENAME eq ' .. exe .. '" /NH')):read("a")
  return output:lower():find(exe:lower(), 1, true) ~= nil
end

local gameDir, force
for _, argument in ipairs(arg) do
  if argument == "--help" or argument == "-h" then
    print(HELP)
    os.exit(0)
  elseif argument == "--force" then
    force = true
  elseif argument:sub(1, 2) == "--" then
    fail("unknown option " .. argument .. ". Run with --help to see the options")
  elseif not gameDir then
    gameDir = argument
  else
    fail("only one game folder can be given")
  end
end
gameDir = (gameDir or os.getenv("AF_GAME_DIR") or STEAM_DEFAULT):gsub("/", "\\"):gsub("\\+$", "")

if not readFile(MOD_SOURCE .. "\\mod.json") then
  fail("run this from the repository root (" .. MOD_SOURCE .. "\\mod.json was not found)")
end

say("Game folder: " .. gameDir)
for _, exe in ipairs(GAME_EXES) do
  if isRunning(exe) then
    fail(exe .. " is running. Close the game first")
  end
end

local modsDir = gameDir .. "\\mods"
assert(modsDir:lower():sub(-5) == "\\mods", "the mod must go inside the game's mods folder")
if not dirExists(modsDir) then
  fail(modsDir .. " does not exist. Install AF Mod Loader first (scripts/dev-install.lua in af-modloader)")
end
if not dirExists(modsDir .. "\\" .. API_FOLDER) then
  fail(modsDir .. "\\" .. API_FOLDER .. " does not exist. Install AF Mod Loader API first (af-modloader-api)")
end

local target = modsDir .. "\\" .. MOD_FOLDER
if dirExists(target) then
  local manifest = readFile(target .. "\\mod.json")
  local id = manifest and manifest:match('"id"%s*:%s*"([^"]+)"')
  if id ~= MOD_ID and not force then
    fail(target .. " is not the " .. MOD_ID .. " mod (its mod.json id is " .. tostring(id) .. "), so it was left alone")
  end
  say("Removing " .. target)
  run('rmdir /S /Q "' .. target .. '"', "removing " .. MOD_FOLDER)
  if dirExists(target) then
    fail("could not remove " .. target .. " (is a file in it open?)")
  end
end

say("Copying " .. MOD_SOURCE .. " to " .. target)
run('xcopy "' .. MOD_SOURCE .. '" "' .. target .. '" /E /I /Y /Q', "copying " .. MOD_FOLDER)

say("Done. Start the game and look for '[af-cauldron-recipes] Cauldron Recipes 0.1.1 loaded' in UE4SS.log.")
