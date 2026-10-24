-- The Recipes side tab of the cauldron panel (api.panels.tab): a search box, a "Show discovered" button and the
-- recipes for this cauldron's mode, each with a Use mark that sets the recipe on the cauldron (apply.lua). Favorites
-- show by default, the discovered recipes too with the toggle. Game-facing through the API's page widgets: not
-- verified in game with this mod yet.
local recipeList = require("recipe_list")
local style = require("style")

local cauldronTab = {}

local Tab = {}
Tab.__index = Tab

local dark = style.dark
local TILE_SCALE, INPUT_SCALE = 0.8, 0.6
local ROW_GAP = 8

local MODE_NAME = { normal = "Normal", advanced = "Advanced" }

local function sentence(target, text)
  return dark(target:text(text, { wrap = true }))
end

local function plural(count, word)
  return string.format("%d %s%s", count, word, count == 1 and "" or "s")
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

-- Builds the page again after a click that changed what it says (the search text and the toggle are kept).
function Tab:refresh()
  self.refreshing = true
  local ok, problem = pcall(self.tab.refresh, self.tab)
  self.refreshing = false
  if not ok then
    self.deps.log("could not update the cauldron's Recipes tab: " .. tostring(problem))
  end
end

-- The line under the toggle: the count, or why the list is empty.
local function noteText(result, mode, showDiscovered)
  if result.base == 0 then
    if showDiscovered then
      return string.format("No favorite or discovered recipes for the %s cauldron yet.", MODE_NAME[mode]:lower())
    end
    return string.format(
      "No favorite recipes for the %s cauldron. Star recipes in the Recipes tab of the V menu, "
        .. "or turn on Show discovered.",
      MODE_NAME[mode]:lower()
    )
  end
  if result.total == 0 then
    return "Nothing matches the search."
  end
  if result.total > #result.rows then
    return string.format("Showing the first %d of %d recipes. Search to narrow the list.", #result.rows, result.total)
  end
  return plural(result.total, "recipe")
end

function Tab:build(page, info)
  if not self.refreshing then
    self.state = { search = "", showDiscovered = false }
  end
  local state = self.state
  local session = self.deps.session
  local world, rec = session:current()
  local catalog = session.catalog
  if not world or not rec or not catalog then
    sentence(page, "The game's items are still being read. Close the panel and open it again in a moment.")
    return
  end
  local mode = info.kind
  if state.message then
    sentence(page, state.message)
    state.message = nil
  end
  if state.pending then
    self:buildConfirm(page, info, mode, catalog)
    return
  end

  local input = page:input({
    hint = "Search",
    onChange = function(text)
      state.search = text
      self:fill(state, rec, catalog, mode, info)
    end,
  })
  input:set(state.search)
  local row = page:row()
  row:button(state.showDiscovered and "Hide discovered" or "Show discovered", function()
    state.showDiscovered = not state.showDiscovered
    self:refresh()
  end, { small = true })
  state.note = sentence(page, " ")
  state.list = page:list()
  self:fill(state, rec, catalog, mode, info)
end

-- Fills the list for the current search and toggle, and the line above it.
function Tab:fill(state, rec, catalog, mode, info)
  local result = recipeList.build(rec, catalog, mode, state)
  state.note:set(noteText(result, mode, state.showDiscovered))
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
      self.deps.applier:request(info, mode, entry, self:uiFor(state, entry))
    end))
  end
end

-- What the applier uses to talk to the player: it asks on the page, or says something there.
function Tab:uiFor(state, entry)
  return {
    confirm = function(items)
      state.pending = { items = items, entry = entry }
      self:refresh()
    end,
    message = function(text)
      state.message = text
      self:refresh()
    end,
  }
end

-- The question shown instead of the list when the cauldron holds items.
function Tab:buildConfirm(page, info, mode, catalog)
  local state = self.state
  local pending = state.pending
  local entry = pending.entry
  sentence(
    page,
    string.format(
      "%s to your inventory. What does not fit drops on the ground.",
      pending.items == 1 and "1 item goes back" or pending.items .. " items go back"
    )
  )
  sentence(page, "Set " .. catalog.display(entry.product) .. " on this cauldron?")
  local row = page:row()
  row:button("Apply", function()
    state.pending = nil
    self.deps.applier:confirm(info, mode, entry, self:uiFor(state, entry), pending.items)
  end, { small = true })
  row:space(ROW_GAP)
  row:button("Cancel", function()
    state.pending = nil
    self:refresh()
  end, { small = true })
end

return cauldronTab
