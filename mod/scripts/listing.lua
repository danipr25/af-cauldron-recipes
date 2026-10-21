-- The recipes of one product as pages: discovered recipes first, then the rest of the index, with no recipe
-- twice. Pure Lua (tests/test_listing.lua). Recipes are the whole numbers made by index.pack.
local listing = {}

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

return listing
