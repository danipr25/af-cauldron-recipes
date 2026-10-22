-- The Cauldron section of the V menu's item sheet (api.catalog.section): for a cauldron product, how many recipes
-- there are (and how many the player discovered) with a Recipes button that opens the Recipes tab on that product;
-- for a cauldron ingredient, how many recipes use it. Items that are neither show nothing.
-- The counts are pure functions of the record, the catalog and the index (sheet.productSummary, sheet.usedIn); the
-- section itself is game-facing through the AF Mod Loader API. Not verified in game yet.
local listing = require("listing")

local sheet = {}

local Sheet = {}
Sheet.__index = Sheet

local MODES = { "normal", "advanced" }
local GOLD = { 1.0, 0.75, 0.2 }
local MUTED = { 0.88, 0.82, 0.70 }

local function plural(count, word)
  return string.format("%d %s%s", count, word, count == 1 and "" or "s")
end

-- Will the index still add recipes? (False once it is done or has failed.)
local function finding(index)
  return not index:isDone() and not index:isFailed()
end

-- The recipes the Recipes tab would show for a product, over both modes, with the same visibility rules as the tab:
-- { total = recipes, discovered = how many of them the player discovered, mode = the mode to open: `preferred`
-- when it has recipes, else the other one with recipes, else `preferred` }.
function sheet.productSummary(rec, catalog, index, product, preferred)
  local total, discovered = 0, 0
  local withRecipes = {}
  for _, mode in ipairs(MODES) do
    local seen, indexed = listing.recipeLists(rec, catalog, index, mode, product)
    local counts = listing.counts(seen, indexed)
    total = total + counts.discovered + counts.other
    discovered = discovered + counts.discovered
    withRecipes[mode] = counts.discovered + counts.other > 0
  end
  local mode = preferred
  if not withRecipes[mode] then
    for _, other in ipairs(MODES) do
      if withRecipes[other] then
        mode = other
      end
    end
  end
  return { total = total, discovered = discovered, mode = mode }
end

-- How many cauldron recipes use an ingredient, in both modes, counting only what the player may see: the index's
-- recipes of the products whose other recipes are shown, plus the discovered recipes (visible) of the other
-- products. A recipe that uses the item twice counts once. Zero for an item that is not an ingredient.
function sheet.usedIn(rec, catalog, index, item)
  local position = catalog.ingredientIndex[item]
  if position == nil then
    return 0
  end
  local total = 0
  for product, count in pairs(index:usedIn(position)) do
    if catalog.productSet[product] and rec:otherVisible(product) then
      total = total + count
    end
  end
  for _, entry in ipairs(rec.discovered) do
    if not entry.unknown and rec:discoveredVisible(entry.product) and not rec:otherVisible(entry.product) then
      for _, name in ipairs(entry.inputs) do
        if name == item then
          total = total + 1
          break
        end
      end
    end
  end
  return total
end

-- deps:
--   api: the AF Mod Loader API handle
--   log(text)
--   session: the session (session.lua)
--   ui: the Recipes page (ui_page.lua), for ui:showProduct and the page's current mode
function sheet.new(deps)
  return setmetatable({ deps = deps }, Sheet)
end

-- Adds the section. Call it while the mod's entrypoint runs.
function Sheet:install()
  self.deps.api.catalog.section({
    id = "cauldron",
    build = function(section, item)
      self:build(section, item)
    end,
  })
end

function Sheet:build(section, item)
  local session = self.deps.session
  local world, rec = session:current()
  local catalog, index = session.catalog, session.index
  if not (world and rec and catalog and index) then
    return
  end
  if catalog.productSet[item] then
    local mode = self.deps.ui:currentMode()
    local summary = sheet.productSummary(rec, catalog, index, item, mode)
    if summary.total > 0 then
      local row = section:row()
      local soFar = rec:otherVisible(item) and finding(index) and " so far" or ""
      local text = row:text(
        string.format("Cauldron: %s%s (%d discovered)", plural(summary.total, "recipe"), soFar, summary.discovered),
        { size = "small" }
      )
      text:color(GOLD[1], GOLD[2], GOLD[3])
      row:button("Recipes", function()
        self.deps.ui:showProduct(item, summary.mode)
      end, { small = true })
    end
  end
  if catalog.ingredientIndex[item] ~= nil then
    local count = sheet.usedIn(rec, catalog, index, item)
    if count > 0 then
      local soFar = rec:anyUnlocked() and finding(index) and " so far" or ""
      local text =
        section:text(string.format("Used in %s%s", plural(count, "cauldron recipe"), soFar), { size = "small" })
      text:color(MUTED[1], MUTED[2], MUTED[3])
    end
  end
end

return sheet
