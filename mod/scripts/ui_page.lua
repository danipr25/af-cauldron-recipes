-- The Recipes tab (in the V menu, the item catalog), in two columns: on the left a mode button, a search box and a
-- grid of products; on the right the recipes of the product the player clicked, in pages, two recipes to a list row
-- (small buttons, arrows and status lines keep it compact). A click on the right only rebuilds the right pane, so the
-- product grid keeps its scroll. Game-facing through the AF Mod Loader API's page widgets (page:columns, pane:clear,
-- space; see its docs/api.md and docs/widgets.md for what is verified in game): not yet checked with this mod in the
-- V menu.
local filterModule = require("filter")
local indexModule = require("index")
local listing = require("listing")
local names = require("names")
local record = require("record")

local ui = {}

local Ui = {}
Ui.__index = Ui

local PAGE_SIZE = 40 -- recipes per page: two to a list row
local PER_ROW = 2
-- The gap between the two recipes of a row. A probe in game (2026-10-23) showed that a gap of 32 does not separate
-- groups of tiles and that a row of three groups overflows the pane: tune this after looking at it in game.
local RECIPE_GAP = 64
local SECTION_GAP = 8
local MODE_LABEL = { normal = "Normal cauldron", advanced = "Advanced cauldron" }
local OTHER_MODE = { normal = "advanced", advanced = "normal" }
local SWITCH_LABEL = { normal = "Show advanced", advanced = "Show normal" }

-- Colors (red, green, blue). GOLD is the one verified in game. MUTED is a cream for status lines: a plain grey was
-- too close to white on the panel.
local GOLD = { 1.0, 0.75, 0.2 }
local MUTED = { 0.88, 0.82, 0.70 }

local function plural(count, word)
  return string.format("%d %s%s", count, word, count == 1 and "" or "s")
end

-- Every sentence wraps at the edge of its pane (or the panel's). `target` is the page or a pane. Returns the text
-- handle.
local function sentence(target, text, color)
  local handle = target:text(text, { wrap = true })
  if color then
    handle:color(color[1], color[2], color[3])
  end
  return handle
end

-- A short muted status line in small text (a small text cannot wrap). Returns the text handle.
local function smallLine(target, text)
  local handle = target:text(text, { size = "small" })
  handle:color(MUTED[1], MUTED[2], MUTED[3])
  return handle
end

-- "<base>, finding recipes 40%", or just one of them. `percent` is nil when the recipes are all found.
local function statusText(base, percent)
  if not percent then
    return base or ""
  end
  local finding = string.format("finding recipes %d%%", percent)
  if base and base ~= "" then
    return base .. ", " .. finding
  end
  return finding:sub(1, 1):upper() .. finding:sub(2)
end

-- Will the index still add recipes? (False once it is done or has failed.)
local function finding(index)
  return not index:isDone() and not index:isFailed()
end

local function failedLine(target, index)
  if index:isFailed() then
    sentence(target, "Not every recipe could be listed. See UE4SS.log.")
  end
end

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
  -- The right pane of the page built last, so a click there can rebuild just that pane.
  self.right = nil
  -- What each pane built last lets progress touch: { left = function(percent), right = function(percent) }, each set
  -- by the view that needs it.
  self.current = {}
  return self
end

local function freshModel()
  return { mode = "normal", view = "recipes", search = "", selected = nil, pageIndex = 1, filter = {}, pickSearch = "" }
end

-- Adds the tab to the V menu. Call it while the mod's entrypoint runs.
function Ui:install()
  self.tab = self.deps.api.tabs.add({
    id = "recipes",
    title = "Recipes",
    menu = "catalog",
    build = function(page)
      self.building = true
      local ok, problem = xpcall(self.build, debug.traceback, self, page)
      self.building = false
      if not ok then
        self.current = {}
        self.right = nil
        error(problem, 0)
      end
    end,
  })
end

-- Shows the recipes of a product in a mode (the mode buttons on the item sheet): sets the page's model, rebuilds
-- the page and selects the tab. Does nothing when no world is loaded. Unverified in game: tab:select().
function Ui:showProduct(product, mode)
  local world = self.deps.session:current()
  if not world then
    return
  end
  if self.generation ~= world.generation or not self.model then
    self.generation = world.generation
    self.model = freshModel()
  end
  local model = self.model
  model.mode = mode
  model.selected = product
  model.view = "recipes"
  model.search = "" -- the product must be in the grid on the left
  model.pageIndex = 1
  model.filter = {} -- a filter belongs to one product in one mode
  self:refresh()
  if self.tab then
    self.tab:select()
  end
end

-- A world was entered: nothing from the page of the previous world is touched any more.
function Ui:reset()
  self.current = {}
  self.right = nil
  self.model = nil
  self.generation = nil
end

-- Builds the page again, unless it is being built right now (then it already shows the latest data).
function Ui:refresh()
  if self.tab and not self.building then
    self.tab:refresh()
  end
end

-- The index advanced. Only the status lines of the page built last are touched, and only while they are on the page.
-- The page is not built again for it: only when the index is done (session onDone).
function Ui:onProgress(percent)
  local left, right = self.current.left, self.current.right
  if left then
    left(percent)
  end
  if right then
    right(percent)
  end
end

function Ui:build(page)
  local session = self.deps.session
  self.current = {}
  self.right = nil
  local world, rec = session:current()
  if not world or not rec then
    self.model = nil
    sentence(page, "Load a save to see recipes.")
    return
  end
  if self.generation ~= world.generation or not self.model then
    self.generation = world.generation
    self.model = freshModel()
  end
  self.deps.discover:onTabBuild(world)
  local catalog, index = session.catalog, session.index
  if not catalog or not index then
    sentence(page, "Reading the game's items. This page updates by itself.")
    return
  end
  if rec.readOnly then
    sentence(page, "Recipes cannot be saved for this world. See UE4SS.log. Discovered recipes are not tracked.")
  end
  local left, right = table.unpack(page:columns({ 1, 2 }))
  self.right = right
  self.current.left = self:buildLeft(left, rec, catalog, index)
  self.current.right = self:buildRight(right, rec, catalog, index)
end

-- Rebuilds only the right pane (the left one keeps its scroll). If the page cannot be trusted any more (no world, a
-- new world, nothing built), the whole page is built again instead.
function Ui:rebuildRight()
  self.current.right = nil
  local session = self.deps.session
  local world, rec = session:current()
  local catalog, index = session.catalog, session.index
  local pane = self.right
  if not (pane and world and rec and catalog and index and self.model and world.generation == self.generation) then
    self:refresh()
    return
  end
  pane:clear()
  local ok, result = xpcall(self.buildRight, debug.traceback, self, pane, rec, catalog, index)
  if ok then
    self.current.right = result -- only a pane that was built can be updated
  else
    self.deps.log("could not build the right side of the Recipes page: " .. tostring(result))
    sentence(pane, "This part of the page could not be shown. See UE4SS.log.")
  end
end

-- Is there a recipe of this product to show in this mode?
local function productVisible(rec, index, mode, product)
  if rec:hasDiscovered(mode, product) and rec:discoveredVisible(product) then
    return true
  end
  return rec:otherVisible(product) and index:recipes(mode, product) ~= nil
end

-- The left pane: the mode, the search and the grid of products. Returns the progress callback, or nil.
function Ui:buildLeft(pane, rec, catalog, index)
  local model = self.model
  pane:text(MODE_LABEL[model.mode]):color(GOLD[1], GOLD[2], GOLD[3])
  local top = pane:row()
  top:button(SWITCH_LABEL[model.mode], function()
    -- The visible products change, so the page is built again. What is shown on the right starts over. `rec` and
    -- `index` are the ones of this build: safe, because the index changing ends in a full refresh.
    model.mode = OTHER_MODE[model.mode]
    model.filter = {}
    model.pageIndex = 1
    model.view = "recipes"
    if model.selected and not productVisible(rec, index, model.mode, model.selected) then
      model.selected = nil
    end
    self:refresh()
  end, { small = true })

  local visible = {}
  for _, product in ipairs(catalog.products) do
    if productVisible(rec, index, model.mode, product) then
      visible[#visible + 1] = product
    end
  end
  local waiting = rec:anyUnlocked() and finding(index)
  self.noProducts = #visible == 0 and not waiting

  local grid
  local status
  local shown = 0
  local function statusLine(percent)
    local base
    if #visible > 0 then
      base = shown == 0 and "Nothing matches the search" or plural(shown, "product")
    end
    return statusText(base, waiting and percent or nil)
  end
  local function fill()
    grid:clear()
    local wanted = names.fold(model.search)
    shown = 0
    for _, product in ipairs(visible) do
      if wanted == "" or names.fold(catalog.display(product)):find(wanted, 1, true) then
        shown = shown + 1
        grid:tile(product, {
          onClick = function(clicked)
            model.selected = clicked
            model.view = "recipes"
            model.pageIndex = 1
            model.filter = {} -- a filter belongs to one product in one mode
            self:rebuildRight()
          end,
        })
      end
    end
    if status then
      status:set(statusLine(index:progress()))
    end
  end

  local input = pane:input({
    hint = "Search",
    onChange = function(text)
      model.search = text
      fill()
    end,
  })
  input:set(model.search)
  -- The line exists only when it has something to say: an empty one would leave a gap above the grid.
  local onProgress = nil
  if #visible > 0 or waiting then
    status = smallLine(pane, "")
    if waiting then
      onProgress = function(percent)
        status:set(statusLine(percent))
      end
    end
  end
  if #visible == 0 and not waiting then
    sentence(
      pane,
      string.format("No recipes discovered yet for the %s. ", MODE_LABEL[model.mode]:lower())
        .. "Set the filters of a cauldron, or use recipes.unlock <item> in the console."
    )
  end
  if rec:anyUnlocked() and not model.selected then
    failedLine(pane, index) -- with a product selected, the right pane says it
  end
  grid = pane:grid()
  fill()
  return onProgress
end

-- Enables or disables a button. A failure is logged and the button stays as it is.
function Ui:setEnabled(button, on)
  local ok, problem = pcall(button.enable, button, on)
  if not ok then
    self.deps.log("could not enable or disable a button: " .. tostring(problem))
  end
end

local recipeLists = listing.recipeLists

-- The lists as the page shows them: the filter applied to both. The third value is the number of recipes before the
-- filter, or nil when no ingredient is chosen.
local function filteredLists(rec, catalog, index, mode, product, wanted)
  local discovered, indexed = recipeLists(rec, catalog, index, mode, product)
  if #wanted == 0 then
    return discovered, indexed, nil
  end
  local counts = listing.counts(discovered, indexed)
  return filterModule.apply(discovered, wanted), filterModule.apply(indexed, wanted), counts.discovered + counts.other
end

-- The ingredient positions that can still be added to the filter, as a set (see filter.ingredients).
function Ui:candidates(rec, catalog, index)
  local model = self.model
  local discovered, indexed = recipeLists(rec, catalog, index, model.mode, model.selected)
  return filterModule.ingredients(model.filter, discovered, indexed)
end

-- One row: "Filter:", the chosen ingredients, + Add (while there is a slot left and something to add) and Clear.
function Ui:buildFilterRow(pane, rec, catalog, index)
  local model = self.model
  local row = pane:row()
  row:text("Filter:", { size = "small" })
  for i, position in ipairs(model.filter) do
    -- A click removes this one entry (the same ingredient twice loses one), then the list starts at page 1.
    row:item(catalog.ingredients[position], 1, {
      onClick = function()
        if model.filter[i] ~= position then
          return -- the filter changed since this row was built
        end
        table.remove(model.filter, i)
        model.pageIndex = 1
        self:rebuildRight()
      end,
    })
  end
  if #model.filter < record.SLOTS[model.mode] and next(self:candidates(rec, catalog, index)) then
    row:button("+ Add", function()
      model.view = "pick"
      model.pickSearch = ""
      self:rebuildRight()
    end, { small = true })
  end
  if #model.filter > 0 then
    row:button("Clear", function()
      model.filter = {}
      model.pageIndex = 1
      self:rebuildRight()
    end, { small = true })
  end
end

-- The right pane: what to do first, the recipes of the selected product, or the choice of an ingredient to add to
-- the filter. Returns the progress callback, or nil.
function Ui:buildRight(pane, rec, catalog, index)
  local model = self.model
  if not model.selected then
    if self.noProducts then
      return nil
    end
    pane:text("Pick a product on the left"):color(GOLD[1], GOLD[2], GOLD[3])
    sentence(pane, "Its recipes show here.")
    return nil
  end
  if model.view == "pick" then
    return self:buildPick(pane, rec, catalog, index)
  end
  return self:buildRecipes(pane, rec, catalog, index)
end

-- The view for choosing an ingredient to add to the filter.
function Ui:buildPick(pane, rec, catalog, index)
  local model = self.model
  pane:text("Add an ingredient"):color(GOLD[1], GOLD[2], GOLD[3])
  pane:row():button("Back", function()
    model.view = "recipes"
    self:rebuildRight()
  end, { small = true })
  local candidates = self:candidates(rec, catalog, index)
  local grid
  local function fill()
    grid:clear()
    local wanted = names.fold(model.pickSearch)
    for position, name in ipairs(catalog.ingredients) do
      if candidates[position] and (wanted == "" or names.fold(catalog.display(name)):find(wanted, 1, true)) then
        grid:tile(name, {
          onClick = function(clicked)
            model.filter[#model.filter + 1] = catalog.ingredientIndex[clicked]
            model.pageIndex = 1
            model.view = "recipes"
            self:rebuildRight()
          end,
        })
      end
    end
  end
  local input = pane:input({
    hint = "Search",
    onChange = function(text)
      model.pickSearch = text
      fill()
    end,
  })
  input:set(model.pickSearch)
  if rec:otherVisible(model.selected) and finding(index) then
    smallLine(pane, "Ingredients in the recipes found so far")
  end
  if next(candidates) == nil then
    sentence(pane, "No ingredient to add.")
  end
  grid = pane:grid()
  fill()
  return nil
end

-- The recipes of the selected product, one page. Returns the progress callback, or nil.
function Ui:buildRecipes(pane, rec, catalog, index)
  local model = self.model
  local product, mode = model.selected, model.mode

  local wanted = model.filter
  local discovered, indexed, unfiltered = filteredLists(rec, catalog, index, mode, product, wanted)
  local result = listing.page(discovered, indexed, model.pageIndex, PAGE_SIZE)
  model.pageIndex = result.page
  local counts = listing.counts(discovered, indexed)
  local waiting = rec:otherVisible(product) and finding(index)

  local head = pane:row()
  head:item(product, 1)
  head:text(catalog.display(product)):color(GOLD[1], GOLD[2], GOLD[3])

  local function statusLine(total, all, percent)
    local count = plural(all or total, "recipe")
    if all then
      count = string.format("%d of %s", total, count)
    end
    local base = MODE_LABEL[mode] .. ", " .. count
    base = base .. string.format(", %d discovered", counts.discovered)
    return statusText(base, waiting and percent or nil)
  end
  local status = smallLine(pane, statusLine(result.total, unfiltered, index:progress()))

  -- One compact row: the page arrows and "page / pages".
  local nav = pane:row()
  local previous = nav:arrow("previous", function()
    if model.pageIndex > 1 then
      model.pageIndex = model.pageIndex - 1
      self:rebuildRight()
    end
  end)
  local function pageLabel(pages)
    return string.format("%d / %d", result.page, pages)
  end
  local pageText = nav:text(pageLabel(result.pages), { size = "small" })
  local following = nav:arrow("next", function()
    model.pageIndex = model.pageIndex + 1 -- listing.page keeps it in range
    self:rebuildRight()
  end)
  self:setEnabled(previous, result.page > 1)
  -- While recipes are still being found, a page that does not exist yet is not offered.
  self:setEnabled(following, result.page < result.pages)

  local onProgress = nil
  if waiting then
    -- The pages and the total as they are now (the index adds recipes while it runs).
    local function live()
      local now, later, all = filteredLists(rec, catalog, index, mode, product, wanted)
      local current = listing.page(now, later, 1, PAGE_SIZE)
      return current.pages, current.total, all
    end
    local shownPages = result.pages
    onProgress = function(percent)
      local pages, total, all = live()
      status:set(statusLine(total, all, percent))
      if pages > shownPages then
        shownPages = pages
        pageText:set(pageLabel(pages))
        self:setEnabled(following, result.page < pages)
      end
    end
  end
  if rec:anyUnlocked() then
    failedLine(pane, index)
  end
  pane:space(SECTION_GAP)
  self:buildFilterRow(pane, rec, catalog, index)
  if result.total == 0 then
    local text = #wanted > 0 and "No recipes with these ingredients" or "No recipes to show for this item"
    sentence(pane, text .. (waiting and " yet." or "."))
  end

  pane:space(SECTION_GAP)
  local list = pane:list()
  for _, entry in ipairs(listing.rows(result.items, PER_ROW)) do
    local row = list:row()
    if entry.heading and entry.discovered then
      row:text(string.format("Discovered (%d)", counts.discovered)):color(GOLD[1], GOLD[2], GOLD[3])
    elseif entry.heading then
      local suffix = waiting and " so far" or ""
      row:text(string.format("Other recipes (%d%s)", counts.other, suffix)):color(MUTED[1], MUTED[2], MUTED[3])
    else
      for number, packed in ipairs(entry.recipes) do
        if number > 1 then
          row:space(RECIPE_GAP)
        end
        local first, second, third = indexModule.unpack(packed)
        for place, position in ipairs({ first, second, third }) do
          if place > 1 then
            row:text(" + ")
          end
          row:item(catalog.ingredients[position], 1)
        end
      end
    end
  end
  return onProgress
end

return ui
