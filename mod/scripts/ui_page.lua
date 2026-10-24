-- The Recipes tab (in the V menu, the item catalog), in two columns: on the left a mode button, a search box and a
-- grid of products; on the right the recipes of the product the player clicked, in pages, a few recipes to a list row
-- (listing.PER_ROW: two in Normal, three in Advanced; small buttons, arrows and status lines keep it compact), each
-- followed by a star that marks it as a favorite. A Favorites button in the left pane swaps the right pane for all the
-- favorites of the mode, grouped by product. A click on the right only rebuilds the right pane, so the product grid
-- keeps its scroll; switching the mode rebuilds both panes in place. Game-facing through the AF Mod Loader API's page
-- widgets (page:columns, pane:clear, dividers; see its docs/api.md and docs/widgets.md for what is verified in game):
-- this look has not run in game with this mod yet.
local filterModule = require("filter")
local indexModule = require("index")
local listing = require("listing")
local names = require("names")
local record = require("record")
local style = require("style")

local ui = {}

local Ui = {}
Ui.__index = Ui

local MODE_LABEL = { normal = "Normal cauldron", advanced = "Advanced cauldron" }
local OTHER_MODE = { normal = "advanced", advanced = "normal" }
local SWITCH_LABEL = { normal = "Show advanced", advanced = "Show normal" }
local FAVORITES_LABEL = "Favorites"
local BACK_LABEL = "Back to recipes"
local STAR_ON, STAR_OFF = "★", "☆"
-- A small gap between a label and the buttons next to it in a row (they touched in game).
local ROW_GAP = 8

local dark = style.dark

local function plural(count, word)
  return string.format("%d %s%s", count, word, count == 1 and "" or "s")
end

-- Every sentence wraps at the edge of its pane (or the panel's). `target` is the page or a pane. Returns the text
-- handle.
local function sentence(target, text)
  return dark(target:text(text, { wrap = true }))
end

-- A short status line in small text (a small text cannot wrap). Returns the text handle.
local function smallLine(target, text)
  return dark(target:text(text, { size = "small" }))
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
  -- The panes of the page built last, so a click can rebuild just them.
  self.left = nil
  self.right = nil
  self.favoritesButton = nil -- the left pane's Favorites button of the page built last (nil in a read-only world)
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
        self.left = nil
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
  self.left = nil
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
  self.left = nil
  self.right = nil
  self.favoritesButton = nil
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
    sentence(
      page,
      "Recipes cannot be saved for this world. See UE4SS.log. "
        .. "Discovered recipes are not tracked and favorites are not available."
    )
  end
  local left, right = table.unpack(page:columns({ 1, 2 }, { divider = true }))
  self.left = left
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

-- Rebuilds both panes in place (the mode changed), without building the whole page again (that flickers). Same
-- fallback as rebuildRight.
function Ui:rebuildPanes()
  self.current.left = nil
  self.current.right = nil
  local session = self.deps.session
  local world, rec = session:current()
  local catalog, index = session.catalog, session.index
  local left, right = self.left, self.right
  if
    not (left and right and world and rec and catalog and index and self.model and world.generation == self.generation)
  then
    self:refresh()
    return
  end
  left:clear()
  right:clear()
  self.favoritesButton = nil
  self.noProducts = nil -- set by buildLeft; must not keep the previous mode's value if it fails
  local ok, result = xpcall(self.buildLeft, debug.traceback, self, left, rec, catalog, index)
  if ok then
    self.current.left = result
  else
    self.deps.log("could not build the left side of the Recipes page: " .. tostring(result))
    sentence(left, "This part of the page could not be shown. See UE4SS.log.")
  end
  ok, result = xpcall(self.buildRight, debug.traceback, self, right, rec, catalog, index)
  if ok then
    self.current.right = result
  else
    self.deps.log("could not build the right side of the Recipes page: " .. tostring(result))
    sentence(right, "This part of the page could not be shown. See UE4SS.log.")
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
  dark(pane:text(MODE_LABEL[model.mode]))
  local top = pane:row()
  top:button(SWITCH_LABEL[model.mode], function()
    -- The visible products change, so both panes are built again (not the page: that flickers). What is shown on the
    -- right starts over. `rec` and `index` are the ones of this build: safe, because the index changing ends in a
    -- full refresh.
    model.mode = OTHER_MODE[model.mode]
    model.filter = {}
    model.pageIndex = 1
    if model.view ~= "favorites" then
      model.view = "recipes" -- the Favorites view stays, now for the other mode
    end
    if model.selected and not productVisible(rec, index, model.mode, model.selected) then
      model.selected = nil
    end
    self:rebuildPanes()
  end, { small = true })
  if not rec.readOnly then
    top:space(ROW_GAP)
    local button
    button = top:button(model.view == "favorites" and BACK_LABEL or FAVORITES_LABEL, function()
      model.view = model.view == "favorites" and "recipes" or "favorites"
      model.pageIndex = 1
      button:set(model.view == "favorites" and BACK_LABEL or FAVORITES_LABEL)
      self:rebuildRight()
    end, { small = true })
    self.favoritesButton = button
  end
  pane:divider()

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
            if self.favoritesButton then
              self.favoritesButton:set(FAVORITES_LABEL)
            end
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

-- The lists as the page shows them: the filter applied to all three. The fourth value is the number of recipes before
-- the filter, or nil when no ingredient is chosen.
local function filteredLists(rec, catalog, index, mode, product, wanted)
  local favorites, discovered, indexed = recipeLists(rec, catalog, index, mode, product)
  if #wanted == 0 then
    return favorites, discovered, indexed, nil
  end
  local counts = listing.counts(favorites, discovered, indexed)
  return filterModule.apply(favorites, wanted),
    filterModule.apply(discovered, wanted),
    filterModule.apply(indexed, wanted),
    counts.favorite + counts.discovered + counts.other
end

-- The ingredient positions that can still be added to the filter, as a set (see filter.ingredients).
function Ui:candidates(rec, catalog, index)
  local model = self.model
  local favorites, discovered, indexed = recipeLists(rec, catalog, index, model.mode, model.selected)
  return filterModule.ingredients(model.filter, favorites, discovered, indexed)
end

-- One row: "Filter:", the chosen ingredients, + Add (while there is a slot left and something to add) and Clear.
function Ui:buildFilterRow(pane, rec, catalog, index)
  local model = self.model
  local row = pane:row()
  dark(row:text("Filter:", { size = "small" }))
  row:space(ROW_GAP)
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
  if model.view == "favorites" and not rec.readOnly then
    return self:buildFavorites(pane, rec, catalog)
  end
  if not model.selected then
    if self.noProducts then
      return nil
    end
    dark(pane:text("Pick a product on the left"))
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
  dark(pane:text("Add an ingredient"))
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
  local favorites, discovered, indexed, unfiltered = filteredLists(rec, catalog, index, mode, product, wanted)
  local pageSize = listing.PAGE_SIZE[mode]
  local result = listing.page(favorites, discovered, indexed, model.pageIndex, pageSize)
  model.pageIndex = result.page
  local counts = listing.counts(favorites, discovered, indexed)
  local waiting = rec:otherVisible(product) and finding(index)

  local head = pane:row()
  head:item(product, 1)
  dark(head:text(catalog.display(product)))

  local function statusLine(total, all, percent)
    local count = plural(all or total, "recipe")
    if all then
      count = string.format("%d of %s", total, count)
    end
    local base = count .. string.format(", %d discovered", counts.allDiscovered)
    return statusText(base, waiting and percent or nil)
  end
  local status = smallLine(pane, statusLine(result.total, unfiltered, index:progress()))

  local pageText, following, pageLabel = self:buildNav(pane, result.page, result.pages)

  local onProgress = nil
  if waiting then
    -- The pages and the total as they are now (the index adds recipes while it runs).
    local function live()
      local starred, now, later, all = filteredLists(rec, catalog, index, mode, product, wanted)
      local current = listing.page(starred, now, later, 1, pageSize)
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
  pane:divider()
  self:buildFilterRow(pane, rec, catalog, index)
  if result.total == 0 then
    local text = #wanted > 0 and "No recipes with these ingredients" or "No recipes to show for this item"
    sentence(pane, text .. (waiting and " yet." or "."))
  end

  pane:divider()
  local list = pane:list()
  for _, entry in ipairs(listing.rows(result.items, listing.PER_ROW[mode])) do
    if entry.heading then
      local row = list:row()
      if entry.kind == "favorite" then
        dark(row:text(string.format("Favorites (%d)", counts.favorite)))
      elseif entry.kind == "discovered" then
        dark(row:text(string.format("Discovered (%d)", counts.discovered)))
      else
        local suffix = waiting and " so far" or ""
        dark(row:text(string.format("Other recipes (%d%s)", counts.other, suffix)))
      end
    else
      self:recipeRow(list, rec, catalog, mode, product, entry.recipes)
    end
  end
  return onProgress
end

-- The page arrows and "page / pages" in one compact row. Returns the page text, the next arrow and a function that
-- makes the label for a page count (the index adds pages while it runs).
function Ui:buildNav(pane, current, pages)
  local model = self.model
  local nav = pane:row()
  local previous = nav:arrow("previous", function()
    if model.pageIndex > 1 then
      model.pageIndex = model.pageIndex - 1
      self:rebuildRight()
    end
  end)
  local function pageLabel(count)
    return string.format("%d / %d", current, count)
  end
  nav:space(ROW_GAP)
  local pageText = dark(nav:text(pageLabel(pages), { size = "small" }))
  nav:space(ROW_GAP)
  local following = nav:arrow("next", function()
    model.pageIndex = model.pageIndex + 1 -- the listing keeps it in range
    self:rebuildRight()
  end)
  self:setEnabled(previous, current > 1)
  -- While recipes are still being found, a page that does not exist yet is not offered.
  self:setEnabled(following, current < pages)
  return pageText, following, pageLabel
end

-- One list row of recipes (`recipes` are packed), each followed by its star unless the record is read only.
function Ui:recipeRow(list, rec, catalog, mode, product, recipes)
  local row = list:row()
  for number, packed in ipairs(recipes) do
    if number > 1 then
      row:divider()
    end
    local first, second, third = indexModule.unpack(packed)
    local inputs = {}
    for place, position in ipairs({ first, second, third }) do
      if place > 1 then
        dark(row:text(" + "))
      end
      inputs[place] = catalog.ingredients[position]
      row:item(inputs[place], 1)
    end
    if not rec.readOnly then
      local star
      star = dark(row:mark(rec:isFavorite(mode, inputs) and STAR_ON or STAR_OFF, function()
        self:toggleFavorite(star, mode, inputs, product)
      end))
    end
  end
end

-- A click on a star: toggles the favorite in the record, saves, and changes the star in place (the pane is not
-- rebuilt, so nothing jumps; the order follows on the next page, product, filter or mode change). If the record
-- could not be saved at all the star goes back; if only the last step failed, the new state is kept (the finished
-- copy is used at the next load) and the next save tries again.
function Ui:toggleFavorite(star, mode, inputs, product)
  local world, rec = self.deps.session:current()
  if not world or not rec or rec.readOnly then
    return
  end
  local was = rec:isFavorite(mode, inputs)
  local now, position = rec:toggleFavorite(mode, inputs, product)
  local saved, stage = self.deps.session:save()
  if not saved and stage == "pending" then
    self.deps.log("could not finish saving the favorite. The star stays and saving is retried at the next change")
  elseif not saved then
    if was then
      rec:addFavorite(mode, inputs, product, position) -- back where it was
    else
      rec:toggleFavorite(mode, inputs, product)
    end
    star:set(was and STAR_ON or STAR_OFF)
    self.deps.log("could not save the favorite, so the star was put back. See the lines above in UE4SS.log")
    return
  end
  star:set(now and STAR_ON or STAR_OFF)
end

-- The Favorites view: the favorites of the current mode that are visible, grouped by product. Returns nil (no
-- progress to show).
function Ui:buildFavorites(pane, rec, catalog)
  local model = self.model
  local mode = model.mode
  local groups = listing.favoriteGroups(rec, catalog, mode, catalog.display)
  local result = listing.favoritePage(groups, model.pageIndex, listing.PAGE_SIZE[mode], listing.PER_ROW[mode])
  model.pageIndex = result.page
  dark(pane:text("Favorites"))
  if result.total == 0 then
    if #rec.favorites > 0 then
      sentence(
        pane,
        string.format(
          "No favorites to show for the %s. Favorites of hidden recipes come back when their recipes are shown again.",
          MODE_LABEL[mode]:lower()
        )
      )
    else
      sentence(pane, "No favorites yet. Click the star next to a recipe to add it here.")
    end
    return nil
  end
  smallLine(pane, plural(result.total, "favorite recipe"))
  self:buildNav(pane, result.page, result.pages)
  pane:divider()
  local list = pane:list()
  for _, entry in ipairs(result.rows) do
    if entry.title then
      local row = list:row()
      row:item(entry.title, 1)
      dark(row:text(catalog.display(entry.title)))
    else
      self:recipeRow(list, rec, catalog, mode, entry.product, entry.recipes)
    end
  end
  return nil
end

return ui
