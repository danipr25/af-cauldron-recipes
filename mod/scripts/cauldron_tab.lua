-- The Recipes side tab of the cauldron panel (api.panels.tab): a search box and the recipes for this cauldron's mode,
-- like the V menu's Recipes tab (favorites, discovered, then every other recipe), each with a Use mark that sets the
-- recipe on the cauldron (apply.lua). Game-facing through the API's page widgets: not verified in game with this mod
-- yet. Lines are short because wrapped text did not wrap in this panel.
local recipeList = require("recipe_list")
local style = require("style")

local cauldronTab = {}

local Tab = {}
Tab.__index = Tab

local dark = style.dark
local TILE_SCALE, INPUT_SCALE = 0.8, 0.6

local function sentence(target, text)
  return dark(target:text(text, { wrap = true }))
end

-- deps:
--   api: the AF Mod Loader API handle
--   log(text)
--   session: the session (session.lua)
--   applier: an applier (apply.lua)
function cauldronTab.new(deps)
  return setmetatable({ deps = deps, state = nil, refreshing = false }, Tab)
end

-- Adds the tab. Call it while the mod's entrypoint runs.
function Tab:install()
  self.tab = self.deps.api.panels.tab({
    id = "recipes",
    panel = "cauldron",
    title = "Recipes",
    build = function(page, info)
      self:build(page, info)
    end,
  })
end

-- Builds the page again after a click that changed what it says (the search text is kept).
function Tab:refresh()
  self.refreshing = true
  local ok, problem = pcall(self.tab.refresh, self.tab)
  self.refreshing = false
  if not ok then
    self.deps.log("could not update the cauldron's Recipes tab: " .. tostring(problem))
  end
end

-- The recipe index line: how far it is, or that it is incomplete. Nil when there is nothing to say.
local function indexLine(index, percent)
  if not index then
    return "Finding recipes"
  end
  if index:isFailed() then
    return "Some recipes are missing. See UE4SS.log."
  end
  if not index:isDone() then
    return string.format("Finding recipes %d%%", percent or index:progress())
  end
  return nil
end

-- The line above the list.
local function noteText(result, search)
  if #result.rows == 0 then
    return search ~= "" and "Nothing matches the search." or "Star recipes or unlock some in the V menu."
  end
  if result.more then
    return string.format("Showing the first %d. Search to narrow.", #result.rows)
  end
  return #result.rows == 1 and "1 recipe" or #result.rows .. " recipes"
end

function Tab:build(page, info)
  if not self.refreshing then
    self.state = { search = "" }
  end
  local state = self.state
  local session = self.deps.session
  local world, rec = session:current()
  local catalog = session.catalog
  if not world or not rec or not catalog then
    sentence(page, "The game's items are still being read.")
    sentence(page, "Close the panel and open it again.")
    return
  end
  local mode = info.kind
  state.status = nil -- set again below, only when this build makes a line
  state.info = info
  if state.message then
    sentence(page, state.message)
    state.message = nil
  end
  local input = page:input({
    hint = "Search",
    onChange = function(text)
      state.search = text
      self:fill(state, rec, catalog, mode, info)
    end,
  })
  input:set(state.search)
  local line = indexLine(session.index)
  if line then
    state.status = dark(page:text(line, { size = "small" }))
  end
  state.note = sentence(page, " ")
  state.list = page:list()
  self:fill(state, rec, catalog, mode, info)
end

-- The status line of the page built last, while that page is the one showing: set on a dead handle is never tried.
function Tab:updateStatus(percent)
  local state = self.state
  if not (state and state.status and state.info and state.info.isCurrent()) then
    return
  end
  local line = indexLine(self.deps.session.index, percent) or "All recipes found."
  state.status:set(line)
end

-- The index advanced: only the status line changes.
function Tab:onProgress(percent)
  self:updateStatus(percent)
end

-- The index finished, failed or was replaced.
function Tab:onIndexChange()
  self:updateStatus(nil)
end

-- Fills the list for the current search, and the line above it.
function Tab:fill(state, rec, catalog, mode, info)
  local result = recipeList.build(rec, catalog, self.deps.session.index, mode, state)
  state.note:set(noteText(result, state.search))
  local list = state.list
  list:clear()
  for _, entry in ipairs(result.rows) do
    local row = list:row()
    row:item(entry.product, 1, { scale = TILE_SCALE })
    dark(row:text(catalog.display(entry.product)))
    for _, name in ipairs(entry.inputs) do
      row:item(name, 1, { scale = INPUT_SCALE })
    end
    dark(row:mark("Use", function()
      -- Going back to the Cauldron tab kills this page, and with it the status line.
      local wrapped = setmetatable({
        showGame = function()
          state.status = nil
          info.showGame()
        end,
      }, { __index = info })
      self.deps.applier:request(wrapped, mode, entry, self:uiFor(state))
    end))
  end
end

-- What the applier uses to talk to the player: it says something on the page.
function Tab:uiFor(state)
  return {
    message = function(text)
      if state ~= self.state then
        return
      end
      state.message = text
      self:refresh()
    end,
  }
end

return cauldronTab
