-- The recipes the cauldron panel's Recipes tab offers for one cauldron mode, like the V menu's Recipes tab: the visible
-- favorites first, then the discovered recipes, then every other recipe of the recipe index, with no recipe twice and
-- the same visibility rules (a locked product hides its recipes). A search keeps the recipes whose product or one of
-- whose ingredients has a display name containing the text. The list stops at LIMIT recipes: the index holds hundreds
-- of thousands, so it is never walked further than needed. Pure Lua with no game access (tests/test_recipe_list.lua).
local indexModule = require("index")
local names = require("names")
local record = require("record")

local recipeList = {}

-- Most rows the page shows. The player narrows the list with the search box.
recipeList.LIMIT = 40

local fold = names.fold

-- The set of positions (in catalog.ingredients) and of products whose display name contains the folded text.
local function matchingSets(catalog, wanted)
  local positions, products = {}, {}
  for position, name in ipairs(catalog.ingredients) do
    if fold(catalog.display(name)):find(wanted, 1, true) then
      positions[position] = true
    end
  end
  for _, product in ipairs(catalog.products) do
    if fold(catalog.display(product)):find(wanted, 1, true) then
      products[product] = true
    end
  end
  return positions, products
end

-- The products in a stable order: by display name, then by name.
local function productOrder(catalog)
  local order, shown = {}, {}
  for index, product in ipairs(catalog.products) do
    order[index] = product
    shown[product] = fold(catalog.display(product))
  end
  table.sort(order, function(a, b)
    if shown[a] ~= shown[b] then
      return shown[a] < shown[b]
    end
    return a < b
  end)
  return order
end

-- rec: the world's record; catalog: the item catalog (ingredients, ingredientIndex, products, productSet,
-- display(name)); index: the recipe index, or nil; mode: "normal" or "advanced". options: { search = text }.
-- Returns { rows, more }: `rows` are { product, inputs } (inputs are item names), at most LIMIT, and `more` is true
-- when there are further matching recipes. Recipes the index has not found yet are not in the list.
function recipeList.build(rec, catalog, index, mode, options)
  local wanted = fold(options.search or "")
  local positions, products = {}, {}
  if wanted ~= "" then
    positions, products = matchingSets(catalog, wanted)
  end
  local rows, seen, more = {}, {}, false
  local limit = recipeList.LIMIT

  -- Adds a recipe unless the list is full (then `more` is set and the walk stops). Returns false to stop.
  local function add(product, packed)
    if #rows == limit then
      more = true
      return false
    end
    local first, second, third = indexModule.unpack(packed)
    local inputs = { catalog.ingredients[first], catalog.ingredients[second] }
    if third then
      inputs[3] = catalog.ingredients[third]
    end
    rows[#rows + 1] = { product = product, inputs = inputs }
    return true
  end

  -- The favorites and the discovered recipes: few, so each is checked in full.
  local function early(entries)
    for _, entry in ipairs(entries) do
      local slots = #entry.inputs
      local ok = slots == record.SLOTS[mode] and entry.product ~= nil and catalog.productSet[entry.product]
      local ingredient = {}
      for place, name in ipairs(entry.inputs) do
        ingredient[place] = catalog.ingredientIndex[name]
        ok = ok and ingredient[place] ~= nil
      end
      if ok then
        local packed = indexModule.pack(ingredient[1], ingredient[2], ingredient[3])
        local hit = wanted == "" or products[entry.product]
        for place = 1, slots do
          hit = hit or positions[ingredient[place]]
        end
        if hit and not seen[packed] then
          seen[packed] = true
          if not add(entry.product, packed) then
            return false
          end
        end
      end
    end
    return true
  end

  local discovered = {}
  for _, entry in ipairs(rec:discoveredFor(mode)) do
    if rec:discoveredVisible(entry.product) then
      discovered[#discovered + 1] = entry
    end
  end
  if not (early(rec:favoritesFor(mode)) and early(discovered)) then
    return { rows = rows, more = more }
  end

  if index then
    for _, product in ipairs(productOrder(catalog)) do
      local list = rec:otherVisible(product) and index:recipes(mode, product)
      if list then
        local productHit = wanted == "" or products[product]
        for number = 1, #list do
          local packed = list[number]
          -- Integer checks only: this loop can run over every recipe of the game.
          if
            productHit
            or positions[packed // 65536]
            or positions[(packed // 256) % 256]
            or positions[packed % 256]
          then
            if not seen[packed] and not add(product, packed) then
              return { rows = rows, more = more }
            end
          end
        end
      end
    end
  end
  return { rows = rows, more = more }
end

return recipeList
