-- The Recipes tab: a mode button, a search box, a grid of products, and the recipes of the product the
-- player clicks, in pages (small buttons, arrows and status lines keep it compact). Game-facing through the
-- AF Mod Loader API's page widgets: checked in game.
local indexModule = require("index")
local listing = require("listing")
local names = require("names")

local ui = {}

local Ui = {}
Ui.__index = Ui

local PAGE_SIZE = 20
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

-- Every sentence on the page wraps at the panel's edge. Returns the text handle.
local function sentence(page, text, color)
  local handle = page:text(text, { wrap = true })
  if color then
    handle:color(color[1], color[2], color[3])
  end
  return handle
end

-- A short muted status line in small text (a small text cannot wrap). Returns the text handle.
local function smallLine(page, text)
  local handle = page:text(text, { size = "small" })
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

local function failedLine(page, index)
  if index:isFailed() then
    sentence(page, "Not every recipe could be listed. See UE4SS.log.")
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
  -- What the page built last lets progress touch: { onProgress = function(percent) } (set by the view that needs it)
  self.current = {}
  return self
end

local function freshModel()
  return { mode = "normal", view = "grid", search = "", selected = nil, pageIndex = 1 }
end

-- Adds the tab. Call it while the mod's entrypoint runs.
function Ui:install()
  self.tab = self.deps.api.tabs.add({
    id = "recipes",
    title = "Recipes",
    build = function(page)
      self.building = true
      local ok, problem = xpcall(self.build, debug.traceback, self, page)
      self.building = false
      if not ok then
        self.current = {}
        error(problem, 0)
      end
    end,
  })
end

-- A world was entered: nothing from the page of the previous world is touched any more.
function Ui:reset()
  self.current = {}
  self.model = nil
  self.generation = nil
end

-- Builds the page again, unless it is being built right now (then it already shows the latest data).
function Ui:refresh()
  if self.tab and not self.building then
    self.tab:refresh()
  end
end

-- The index advanced. Only the status line of the page built last is touched, and only while it is on the page.
-- The page is not built again for it: only when the index is done (session onDone).
function Ui:onProgress(percent)
  local onProgress = self.current.onProgress
  if onProgress then
    onProgress(percent)
  end
end

function Ui:build(page)
  local session = self.deps.session
  self.current = {}
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
  if self.model.view == "recipes" and self.model.selected then
    self:buildRecipes(page, rec, catalog, index)
  else
    self.model.view = "grid"
    self:buildGrid(page, rec, catalog, index)
  end
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
  page:text(MODE_LABEL[model.mode]):color(GOLD[1], GOLD[2], GOLD[3])
  local top = page:row()
  top:button(SWITCH_LABEL[model.mode], function()
    model.mode = OTHER_MODE[model.mode]
    self:refresh()
  end, { small = true })

  local visible = {}
  for _, product in ipairs(catalog.products) do
    if productVisible(rec, index, model.mode, product) then
      visible[#visible + 1] = product
    end
  end
  local waiting = rec:anyUnlocked() and finding(index)

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
            self:refresh()
          end,
        })
      end
    end
    if status then
      status:set(statusLine(index:progress()))
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
  -- The line exists only when it has something to say: an empty one would leave a gap above the grid.
  if #visible > 0 or waiting then
    status = smallLine(page, "")
    if waiting then
      self.current.onProgress = function(percent)
        status:set(statusLine(percent))
      end
    end
  end
  if #visible == 0 and not waiting then
    sentence(
      page,
      string.format("No recipes discovered yet for the %s. ", MODE_LABEL[model.mode]:lower())
        .. "Set the filters of a cauldron, or use recipes.unlock <item> in the console."
    )
  end
  if rec:anyUnlocked() then
    failedLine(page, index)
  end
  grid = page:grid()
  fill()
end

-- Enables or disables a button. A failure is logged and the button stays as it is.
function Ui:setEnabled(button, on)
  local ok, problem = pcall(button.enable, button, on)
  if not ok then
    self.deps.log("could not enable or disable a button: " .. tostring(problem))
  end
end

-- The two lists behind a product's recipes: the discovered ones in the order to show them, and the index's.
local function recipeLists(rec, catalog, index, mode, product)
  local discovered = {}
  if rec:discoveredVisible(product) then
    for _, entry in ipairs(rec:discoveredFor(mode, product)) do
      local positions = {}
      for place, name in ipairs(entry.inputs) do
        positions[place] = catalog.ingredientIndex[name]
      end
      if #positions == #entry.inputs then -- an ingredient the game no longer lists is skipped
        discovered[#discovered + 1] = indexModule.pack(positions[1], positions[2], positions[3])
      end
    end
  end
  local indexed = nil
  if rec:otherVisible(product) then
    indexed = index:recipes(mode, product)
  end
  return discovered, indexed
end

-- The recipes of the selected product, one page.
function Ui:buildRecipes(page, rec, catalog, index)
  local model = self.model
  local product, mode = model.selected, model.mode

  local discovered, indexed = recipeLists(rec, catalog, index, mode, product)
  local result = listing.page(discovered, indexed, model.pageIndex, PAGE_SIZE)
  model.pageIndex = result.page
  local counts = listing.counts(discovered, indexed)
  local waiting = rec:otherVisible(product) and finding(index)

  -- One compact row: Back, the page arrows and "page / pages".
  local nav = page:row()
  nav:button("Back", function()
    model.view = "grid"
    self:refresh()
  end, { small = true })
  local previous = nav:arrow("previous", function()
    if model.pageIndex > 1 then
      model.pageIndex = model.pageIndex - 1
      self:refresh()
    end
  end)
  local function pageLabel(pages)
    return string.format("%d / %d", result.page, pages)
  end
  local pageText = nav:text(pageLabel(result.pages), { size = "small" })
  local following = nav:arrow("next", function()
    model.pageIndex = model.pageIndex + 1 -- listing.page keeps it in range
    self:refresh()
  end)
  self:setEnabled(previous, result.page > 1)
  -- While recipes are still being found, a page that does not exist yet is not offered.
  self:setEnabled(following, result.page < result.pages)

  page:row():item(product, 1)
  sentence(page, catalog.display(product), GOLD)

  local function statusLine(total, percent)
    return statusText(MODE_LABEL[mode] .. ", " .. plural(total, "recipe"), waiting and percent or nil)
  end
  local status = smallLine(page, statusLine(result.total, index:progress()))
  if waiting then
    -- The pages and the total as they are now (the index adds recipes while it runs).
    local function live()
      local now, later = recipeLists(rec, catalog, index, mode, product)
      local current = listing.page(now, later, 1, PAGE_SIZE)
      return current.pages, current.total
    end
    local shownPages = result.pages
    self.current.onProgress = function(percent)
      local pages, total = live()
      status:set(statusLine(total, percent))
      if pages > shownPages then
        shownPages = pages
        pageText:set(pageLabel(pages))
        self:setEnabled(following, result.page < pages)
      end
    end
  end
  if rec:otherVisible(product) then
    failedLine(page, index)
  end
  if result.total == 0 then
    sentence(page, waiting and "No recipes to show for this item yet." or "No recipes to show for this item.")
  end

  local list = page:list()
  local heading = nil -- "Discovered" or "Other recipes": the heading last written (headings are not recipes)
  for _, item in ipairs(result.items) do
    local wanted = item.discovered and "Discovered" or "Other recipes"
    if wanted ~= heading then
      heading = wanted
      if item.discovered then
        local text = list:row():text(string.format("Discovered (%d)", counts.discovered))
        text:color(GOLD[1], GOLD[2], GOLD[3])
      else
        local suffix = waiting and " so far" or ""
        local text = list:row():text(string.format("Other recipes (%d%s)", counts.other, suffix))
        text:color(MUTED[1], MUTED[2], MUTED[3])
      end
    end
    local row = list:row()
    local first, second, third = indexModule.unpack(item.packed)
    local positions = { first, second, third }
    for place, position in ipairs(positions) do
      if place > 1 then
        row:text(" + ")
      end
      row:item(catalog.ingredients[position], 1)
    end
  end
end

return ui
