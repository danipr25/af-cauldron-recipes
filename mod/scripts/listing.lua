-- The recipes of one product as pages: discovered recipes first, then the rest of the index, with no recipe
-- twice. Pure Lua (tests/test_listing.lua). Recipes are the whole numbers made by index.pack.
local indexModule = require("index")

local listing = {}

-- The two lists behind a product's recipes in one mode, with the player's visibility settings applied: the
-- discovered ones in the order to show them, and the index's (nil while there is none, or when the other recipes of
-- the product are not shown). rec is a record, catalog the item catalog, index the recipe index.
function listing.recipeLists(rec, catalog, index, mode, product)
  local discovered = {}
  if rec:discoveredVisible(product) then
    for _, entry in ipairs(rec:discoveredFor(mode, product)) do
      local positions, known = {}, true
      for place, name in ipairs(entry.inputs) do
        positions[place] = catalog.ingredientIndex[name]
        if positions[place] == nil then
          known = false
        end
      end
      if known then -- an input that is not an ingredient now (gone, or a liquid) is skipped
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

-- How many recipes there are under each heading across every page: { discovered, other }. A recipe that is in both
-- lists counts as discovered only. Same arguments as listing.page.
function listing.counts(discovered, indexed)
  local seen = {}
  for _, packed in ipairs(discovered) do
    seen[packed] = true
  end
  local other = 0
  for _, packed in ipairs(indexed or {}) do
    if not seen[packed] then
      other = other + 1
    end
  end
  return { discovered = #discovered, other = other }
end

-- discovered: list of packed recipes the player has seen, in the order to show them
-- indexed: list of packed recipes from the index (any order), or nil while there is none yet
-- Returns { total, pages, page, items }: `page` is the requested page kept between 1 and `pages`, and `items` are
-- the entries of that page as { packed = number, discovered = boolean }.
function listing.page(discovered, indexed, requested, size)
  indexed = indexed or {}
  local seen = {}
  for _, packed in ipairs(discovered) do
    seen[packed] = true
  end
  local overlap = 0
  for _, packed in ipairs(indexed) do
    if seen[packed] then
      overlap = overlap + 1
    end
  end
  local total = #discovered + #indexed - overlap
  local pages = math.max(1, (total + size - 1) // size)
  local page = math.min(math.max(requested, 1), pages)
  local first = (page - 1) * size -- entries before this page
  local items = {}
  local position = 0
  for _, packed in ipairs(discovered) do
    position = position + 1
    if position > first and #items < size then
      items[#items + 1] = { packed = packed, discovered = true }
    end
  end
  for _, packed in ipairs(indexed) do
    if #items >= size then
      break
    end
    if not seen[packed] then
      position = position + 1
      if position > first then
        items[#items + 1] = { packed = packed, discovered = false }
      end
    end
  end
  return { total = total, pages = pages, page = page, items = items }
end

-- Lays the items of a page out as list rows: each heading ("Discovered", "Other recipes") alone in its row, then the
-- recipes `perRow` to a row. A row never mixes the two kinds, and a kind that ends with an odd recipe leaves a short
-- row. `items` are the entries of listing.page. Returns a list of { heading = true, discovered = boolean } and
-- { recipes = { packed, ... }, discovered = boolean }.
function listing.rows(items, perRow)
  local rows = {}
  local open = nil -- the recipe row being filled
  local kind = nil -- the kind of the last item: true (discovered) or false (other)
  for _, item in ipairs(items) do
    if item.discovered ~= kind then
      kind = item.discovered
      open = nil
      rows[#rows + 1] = { heading = true, discovered = kind }
    end
    if not open then
      open = { recipes = {}, discovered = kind }
      rows[#rows + 1] = open
    end
    open.recipes[#open.recipes + 1] = item.packed
    if #open.recipes == perRow then
      open = nil
    end
  end
  return rows
end

return listing
