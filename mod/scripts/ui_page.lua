-- The Cauldron Recipes tab: Normal and Advanced buttons, a search box, a grid of products, and the recipes of the
-- product the player clicks. Game-facing through the AF Mod Loader API's page widgets: checked in game.
local indexModule = require("index")
local listing = require("listing")
local names = require("names")

local ui = {}

local Ui = {}
Ui.__index = Ui

local PAGE_SIZE = 20
local MODE_LABEL = { normal = "Normal", advanced = "Advanced" }

-- deps:
--   api: the AF Mod Loader API handle
--   log(text)
--   session: the session (session.lua)
--   discover: the discoverer (discover.lua)
function ui.new(deps)
  local self = setmetatable({}, Ui)
  self.deps = deps
  self.tab = nil
  self.building = false
  self.generation = nil
  self.model = nil
  self.current = {} -- what the page that was built last shows: { progress = text handle or nil }
  return self
end

local function freshModel()
  return { mode = "normal", view = "grid", search = "", selected = nil, pageIndex = 1 }
end

-- Adds the tab. Call it while the mod's entrypoint runs.
function Ui:install()
  self.tab = self.deps.api.tabs.add({
    id = "recipes",
    title = "Cauldron Recipes",
    build = function(page)
      self.building = true
      local ok, problem = pcall(self.build, self, page)
      self.building = false
      if not ok then
        error(problem, 0)
      end
    end,
  })
end

-- Builds the page again, unless it is being built right now (then it already shows the latest data).
function Ui:refresh()
  if self.tab and not self.building then
    self.tab:refresh()
  end
end

-- The index advanced. Only the line of the page built last is touched, and only while it is on the page.
function Ui:onProgress(percent)
  local handle = self.current.progress
  if handle then
    handle:set(string.format("Indexing... %d%%", percent))
  end
end

function Ui:build(page)
  local session = self.deps.session
  self.current = {}
  local world, rec = session:current()
  if not world or not rec then
    self.model = nil
    page:text("Load a save to see recipes.")
    return
  end
  if self.generation ~= world.generation or not self.model then
    self.generation = world.generation
    self.model = freshModel()
  end
  self.deps.discover:onTabBuild(world)
  local catalog, index = session.catalog, session.index
  if not catalog or not index then
    page:text("Reading the game's items. This page updates by itself.")
    return
  end
  if rec.readOnly then
    page:text("Recipes cannot be saved for this world, see UE4SS.log. Discovered recipes are not tracked.")
  end
  if self.model.view == "recipes" and self.model.selected then
    self:buildRecipes(page, rec, catalog, index)
  else
    self.model.view = "grid"
    self:buildGrid(page, rec, catalog, index)
  end
end

-- The line that says the index is still being built (or that it failed). Returns its handle or nil.
function Ui:indexLine(page, index)
  if index:isFailed() then
    page:text("Not every recipe could be listed, see UE4SS.log.")
  elseif not index:isDone() then
    local handle = page:text(string.format("Indexing... %d%%", index:progress()))
    self.current.progress = handle
    return handle
  end
  return nil
end

-- Is there a recipe of this product to show in this mode?
local function productVisible(rec, index, mode, product)
  if rec:hasDiscovered(mode, product) and rec:discoveredVisible(product) then
    return true
  end
  return rec:otherVisible(product) and index:recipes(mode, product) ~= nil
end

function Ui:buildGrid(page, rec, catalog, index)
  local model = self.model
  local function modeButton(row, mode)
    local label = MODE_LABEL[mode]
    if model.mode == mode then
      label = "[ " .. label .. " ]"
    end
    row:button(label, function()
      model.mode = mode
      self:refresh()
    end)
  end
  local top = page:row()
  modeButton(top, "normal")
  modeButton(top, "advanced")

  local visible = {}
  for _, product in ipairs(catalog.products) do
    if productVisible(rec, index, model.mode, product) then
      visible[#visible + 1] = product
    end
  end

  local grid
  local status
  local function fill()
    grid:clear()
    local wanted = names.fold(model.search)
    local shown = 0
    for _, product in ipairs(visible) do
      if wanted == "" or names.fold(catalog.display(product)):find(wanted, 1, true) then
        shown = shown + 1
        grid:tile(product, {
          onClick = function(clicked)
            model.selected = clicked
            model.view = "recipes"
            model.pageIndex = 1
            self:refresh()
          end,
        })
      end
    end
    if #visible > 0 and shown == 0 then
      status:set("Nothing matches the search.")
    else
      status:set("")
    end
  end

  local input = page:input({
    hint = "Search",
    onChange = function(text)
      model.search = text
      fill()
    end,
  })
  input:set(model.search)
  status = page:text("")
  if #visible == 0 then
    page:text("No recipes discovered yet in this world.")
    page:text("Set the filters of a cauldron,")
    page:text("or use recipes.unlock <item> in the console.")
  end
  if rec:anyUnlocked() then
    self:indexLine(page, index)
  end
  grid = page:grid()
  fill()
end

-- The recipes of the selected product, one page.
function Ui:buildRecipes(page, rec, catalog, index)
  local model = self.model
  local product, mode = model.selected, model.mode

  local discovered = {}
  if rec:discoveredVisible(product) then
    for _, entry in ipairs(rec:discoveredFor(mode, product)) do
      local positions = {}
      for place, name in ipairs(entry.inputs) do
        positions[place] = catalog.ingredientIndex[name]
      end
      discovered[#discovered + 1] = indexModule.pack(positions[1], positions[2], positions[3])
    end
  end
  local indexed = nil
  if rec:otherVisible(product) then
    indexed = index:recipes(mode, product)
  end
  local result = listing.page(discovered, indexed, model.pageIndex, PAGE_SIZE)
  model.pageIndex = result.page

  local nav = page:row()
  nav:button(result.page == 1 and "Previous (first page)" or "Previous", function()
    if model.pageIndex > 1 then
      model.pageIndex = model.pageIndex - 1
      self:refresh()
    end
  end)
  nav:text(string.format(" page %d of %d ", result.page, result.pages))
  nav:button(result.page == result.pages and "Next (last page)" or "Next", function()
    if model.pageIndex < result.pages then
      model.pageIndex = model.pageIndex + 1
      self:refresh()
    end
  end)
  nav:button("Back", function()
    model.view = "grid"
    self:refresh()
  end)

  page:text(string.format("%s: %s recipes", catalog.display(product), MODE_LABEL[mode]))
  self:indexLine(page, index)
  if result.total == 0 then
    page:text("No recipes to show for this item yet.")
  end

  local list = page:list()
  for _, item in ipairs(result.items) do
    local row = list:row()
    local first, second, third = indexModule.unpack(item.packed)
    local positions = { first, second, third }
    for place, position in ipairs(positions) do
      if place > 1 then
        row:text(" + ")
      end
      row:item(catalog.ingredients[position], 1)
    end
    row:text(" = ")
    row:item(product, 1)
    if item.discovered then
      row:text("  discovered")
    end
  end
end

return ui
