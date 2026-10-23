-- The recipes of one product as pages: favorites first, then discovered recipes, then the rest of the index, with no
-- recipe twice (a favorite that was also discovered counts as a favorite). Pure Lua (tests/test_listing.lua). Recipes
-- are the whole numbers made by index.pack.
local indexModule = require("index")

local listing = {}

-- Recipes per list row, and recipes per page, by cauldron mode. Each page size is a whole number of rows: Normal 2
-- per row (40 is 20 rows), Advanced 3 per row (42 is 14 rows), because three Advanced recipes fit the pane's width.
-- Each kind (Favorites, Discovered, Other recipes) starts a new row, so a page can end on a short row of each.
listing.PER_ROW = { normal = 2, advanced = 3 }
listing.PAGE_SIZE = { normal = 40, advanced = 42 }

-- The packed recipe of a record entry, or nil when one of its inputs is not an ingredient now (gone, or a liquid).
local function packEntry(catalog, entry)
  local positions = {}
  for place, name in ipairs(entry.inputs) do
    positions[place] = catalog.ingredientIndex[name]
    if positions[place] == nil then
      return nil
    end
  end
  return indexModule.pack(positions[1], positions[2], positions[3])
end

-- The three lists behind a product's recipes in one mode, with the player's visibility settings applied: the
-- favorites and the discovered ones in the order to show them, and the index's (nil while there is none, or when the
-- other recipes of the product are not shown). rec is a record, catalog the item catalog, index the recipe index.
function listing.recipeLists(rec, catalog, index, mode, product)
  local favorites, discovered = {}, {}
  for _, entry in ipairs(rec:favoritesFor(mode, product)) do
    local packed = packEntry(catalog, entry)
    if packed then
      favorites[#favorites + 1] = packed
    end
  end
  if rec:discoveredVisible(product) then
    for _, entry in ipairs(rec:discoveredFor(mode, product)) do
      local packed = packEntry(catalog, entry)
      if packed then -- an input that is not an ingredient now is skipped
        discovered[#discovered + 1] = packed
      end
    end
  end
  local indexed = nil
  if rec:otherVisible(product) then
    indexed = index:recipes(mode, product)
  end
  return favorites, discovered, indexed
end

-- How many recipes there are under each heading across every page: { favorite, discovered, other, allDiscovered }.
-- A recipe is counted under the first kind that has it (favorite, discovered, other); `allDiscovered` counts every
-- discovered recipe, favorites included. Same arguments as listing.page.
function listing.counts(favorites, discovered, indexed)
  local seen = {}
  for _, packed in ipairs(favorites) do
    seen[packed] = true
  end
  local counts = { favorite = #favorites, discovered = 0, other = 0, allDiscovered = #discovered }
  for _, packed in ipairs(discovered) do
    if not seen[packed] then
      seen[packed] = true
      counts.discovered = counts.discovered + 1
    end
  end
  for _, packed in ipairs(indexed or {}) do
    if not seen[packed] then
      counts.other = counts.other + 1
    end
  end
  return counts
end

-- favorites, discovered: lists of packed recipes in the order to show them
-- indexed: list of packed recipes from the index (any order), or nil while there is none yet
-- Returns { total, pages, page, items }: `page` is the requested page kept between 1 and `pages`, and `items` are
-- the entries of that page as { packed = number, kind = "favorite" | "discovered" | "other" }.
function listing.page(favorites, discovered, indexed, requested, size)
  local seen = {}
  local all = {} -- every entry, in the order to show them
  local function add(list, kind)
    for _, packed in ipairs(list or {}) do
      if not seen[packed] then
        seen[packed] = true
        all[#all + 1] = { packed = packed, kind = kind }
      end
    end
  end
  add(favorites, "favorite")
  add(discovered, "discovered")
  add(indexed, "other")
  local total = #all
  local pages = math.max(1, (total + size - 1) // size)
  local page = math.min(math.max(requested, 1), pages)
  local items = {}
  for position = (page - 1) * size + 1, math.min(total, page * size) do
    items[#items + 1] = all[position]
  end
  return { total = total, pages = pages, page = page, items = items }
end

-- Lays the items of a page out as list rows: each heading ("Favorites", "Discovered", "Other recipes") alone in its
-- row, then the recipes `perRow` to a row. A row never mixes the kinds, and a kind that ends with an odd recipe leaves
-- a short row. `items` are the entries of listing.page. Returns a list of { heading = true, kind = string } and
-- { recipes = { packed, ... }, kind = string }.
function listing.rows(items, perRow)
  local rows = {}
  local open = nil -- the recipe row being filled
  local kind = nil -- the kind of the last item
  for _, item in ipairs(items) do
    if item.kind ~= kind then
      kind = item.kind
      open = nil
      rows[#rows + 1] = { heading = true, kind = kind }
    end
    if not open then
      open = { recipes = {}, kind = kind }
      rows[#rows + 1] = open
    end
    open.recipes[#open.recipes + 1] = item.packed
    if #open.recipes == perRow then
      open = nil
    end
  end
  return rows
end

-- The visible favorites of a mode grouped by product, for the Favorites view: a list of { product, name, recipes =
-- { packed, ... } }, the products by display name and the recipes of a product by their ingredients. Entries that use
-- an item that is not an ingredient now are left out. `display(name)` is the name shown in game.
function listing.favoriteGroups(rec, catalog, mode, display)
  local byProduct, groups = {}, {}
  for _, entry in ipairs(rec:favoritesFor(mode)) do
    local packed = packEntry(catalog, entry)
    if packed then
      local group = byProduct[entry.product]
      if not group then
        group = { product = entry.product, name = display(entry.product), recipes = {} }
        byProduct[entry.product] = group
        groups[#groups + 1] = group
      end
      group.recipes[#group.recipes + 1] = { packed = packed, key = table.concat(entry.inputs, ",") }
    end
  end
  table.sort(groups, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.product < b.product
  end)
  for _, group in ipairs(groups) do
    table.sort(group.recipes, function(a, b)
      return a.key < b.key
    end)
    for index, recipe in ipairs(group.recipes) do
      group.recipes[index] = recipe.packed
    end
  end
  return groups
end

-- One page of the Favorites view as list rows: `size` recipes per page (counted over all groups), each group on the
-- page with a title row { title = product } and its recipes `perRow` to a row as { recipes = {...}, product }. A group
-- cut by a page break repeats its title on the next page. Returns { total, pages, page, rows }.
function listing.favoritePage(groups, requested, size, perRow)
  local total = 0
  for _, group in ipairs(groups) do
    total = total + #group.recipes
  end
  local pages = math.max(1, (total + size - 1) // size)
  local page = math.min(math.max(requested, 1), pages)
  local first, last = (page - 1) * size, page * size -- recipes before this page, and up to its end
  local rows = {}
  local position = 0
  for _, group in ipairs(groups) do
    local titled, open = false, nil
    for _, packed in ipairs(group.recipes) do
      position = position + 1
      if position > first and position <= last then
        if not titled then
          titled = true
          rows[#rows + 1] = { title = group.product }
        end
        if not open then
          open = { recipes = {}, product = group.product }
          rows[#rows + 1] = open
        end
        open.recipes[#open.recipes + 1] = packed
        if #open.recipes == perRow then
          open = nil
        end
      end
    end
  end
  return { total = total, pages = pages, page = page, rows = rows }
end

return listing
