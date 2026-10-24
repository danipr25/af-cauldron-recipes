-- The recipes the cauldron panel's Recipes tab offers for one cauldron mode: the visible favorites first, and with
-- "Show discovered" the discovered recipes too, with no recipe twice, filtered by a search text. Pure Lua with no game
-- access (tests/test_recipe_list.lua).
local names = require("names")
local record = require("record")

local recipeList = {}

-- Most rows the page shows. The player narrows the list with the search box.
recipeList.LIMIT = 40

local function keyOf(entry)
  return table.concat(entry.inputs, ",")
end

-- Can the panel set this recipe? Its product and every input must be known to the game's data now, and it must have
-- as many inputs as the cauldron has slots.
local function usable(catalog, mode, entry)
  if #entry.inputs ~= record.SLOTS[mode] or not entry.product or not catalog.productSet[entry.product] then
    return false
  end
  for _, name in ipairs(entry.inputs) do
    if catalog.ingredientIndex[name] == nil then
      return false
    end
  end
  return true
end

-- Does the search text (already folded; "" matches all) appear in the display name of the product or of an input?
local function matches(wanted, catalog, entry)
  if wanted == "" then
    return true
  end
  if names.fold(catalog.display(entry.product)):find(wanted, 1, true) then
    return true
  end
  for _, name in ipairs(entry.inputs) do
    if names.fold(catalog.display(name)):find(wanted, 1, true) then
      return true
    end
  end
  return false
end

-- rec: the world's record; catalog: the item catalog (ingredientIndex, productSet, display(name)); mode: "normal" or
-- "advanced". options: { showDiscovered = boolean, search = text }.
-- Returns { rows, base, total }: `rows` are { product, inputs } (inputs sorted by name), at most LIMIT; `base` is how
-- many recipes there are before the search, `total` how many match it.
function recipeList.build(rec, catalog, mode, options)
  local seen, all = {}, {}
  local function add(entries)
    for _, entry in ipairs(entries) do
      local key = keyOf(entry)
      if not seen[key] and usable(catalog, mode, entry) then
        seen[key] = true
        all[#all + 1] = entry
      end
    end
  end
  add(rec:favoritesFor(mode))
  if options.showDiscovered then
    local shown = {}
    for _, entry in ipairs(rec:discoveredFor(mode)) do
      if rec:discoveredVisible(entry.product) then
        shown[#shown + 1] = entry
      end
    end
    add(shown)
  end
  local wanted = names.fold(options.search or "")
  local rows, total = {}, 0
  for _, entry in ipairs(all) do
    if matches(wanted, catalog, entry) then
      total = total + 1
      if #rows < recipeList.LIMIT then
        rows[#rows + 1] = { product = entry.product, inputs = entry.inputs }
      end
    end
  end
  return { rows = rows, base = #all, total = total }
end

return recipeList
