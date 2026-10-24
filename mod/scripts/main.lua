-- Cauldron Recipes: entrypoint. Adds the Recipes tab to the V menu (item catalog), a Cauldron section to its item
-- sheet and the recipes.* console commands, using only the public calls of the AF Mod Loader API. See the README for
-- what it changes.
local api = AF.require("af-modloader-api").use(AF)
local apply = require("apply")
local catalog = require("catalog")
local cauldronTab = require("cauldron_tab")
local commands = require("commands")
local discover = require("discover")
local session = require("session")
local sheet = require("sheet")
local store = require("store")
local uiPage = require("ui_page")

local VERSION = "0.1.4"

-- The real file functions for the store (Lua's io and os, as the loader documents for AF.dataDir).
local files = {
  read = function(path)
    local file = io.open(path, "rb")
    if not file then
      return nil
    end
    local content = file:read("a")
    file:close()
    return content
  end,
  write = function(path, content)
    local file, problem = io.open(path, "wb")
    if not file then
      return nil, problem
    end
    local ok, writeProblem = file:write(content)
    local closed, closeProblem = file:close()
    if not ok then
      return nil, writeProblem
    end
    if not closed then
      return nil, closeProblem
    end
    return true
  end,
  remove = os.remove,
  rename = os.rename,
}

local recordStore = store.new({ dir = AF.dataDir, files = files, json = AF.json, log = AF.log })

local ui, discoverer, panelTab
local current = session.new({
  api = api,
  log = AF.log,
  store = recordStore,
  onReady = function(world)
    discoverer:install()
    discoverer:scanSoon(world)
  end,
  onRefresh = function()
    ui:refresh()
  end,
  onProgress = function(percent)
    ui:onProgress(percent)
    panelTab:onProgress(percent)
  end,
})
discoverer = discover.new({
  api = api,
  log = AF.log,
  session = current,
  later = session.later,
  onFirstScan = function(world)
    current:afterFirstScan(world)
  end,
  onChange = function()
    ui:refresh()
  end,
})
ui = uiPage.new({ api = api, log = AF.log, session = current, discover = discoverer })

ui:install()
panelTab = cauldronTab.new({
  api = api,
  log = AF.log,
  session = current,
  applier = apply.new({ api = api, log = AF.log, text = catalog.text, fname = FName }),
})
panelTab:install()
sheet.new({ api = api, log = AF.log, session = current, ui = ui }):install()
commands.install({
  api = api,
  session = current,
  onChange = function()
    ui:refresh()
  end,
})
api.world.onEnter(function(world)
  ui:reset()
  current:enter(world)
end)
discoverer:install()

AF.log("Cauldron Recipes " .. VERSION .. " loaded")
