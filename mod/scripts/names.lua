-- Finds the item a player means in a console command or a search. Pure Lua with no game access, so it is tested
-- without the game (tests/test_names.lua).
local names = {}

-- Lowercases the letters A to Z only. The game's names can hold other letters, and their case rules are not ours
-- to guess, so those are compared as they are.
function names.fold(text)
  return (
    text:gsub("%u", function(letter)
      if letter:byte() < 128 then
        return string.char(letter:byte() + 32)
      end
      return letter
    end)
  )
end
local fold = names.fold

-- source:
--   items: list of every item's internal name, in the game's order
--   display(name): the localized name
--   isProduct(name): true when a cauldron can make the item
-- Returns the internal name of the product, or nil and why:
--   "empty": nothing typed
--   "unknown": no item matches
--   "not-product": the item exists but no cauldron makes it (and the item's name)
--   "ambiguous": several products match (and their internal names, in the game's order)
-- The first of these steps that finds any item decides: the exact internal name, the exact localized name, then
-- part of either. Case is ignored.
function names.resolve(text, source)
  local wanted = fold(text or "")
  if wanted == "" then
    return nil, "empty"
  end
  local steps = {
    function(name)
      return fold(name) == wanted
    end,
    function(name)
      return fold(source.display(name)) == wanted
    end,
    function(name)
      return fold(name):find(wanted, 1, true) ~= nil or fold(source.display(name)):find(wanted, 1, true) ~= nil
    end,
  }
  for _, matches in ipairs(steps) do
    local found, products = {}, {}
    for _, name in ipairs(source.items) do
      if matches(name) then
        found[#found + 1] = name
        if source.isProduct(name) then
          products[#products + 1] = name
        end
      end
    end
    if #products == 1 then
      return products[1]
    elseif #products > 1 then
      return nil, "ambiguous", products
    elseif #found > 0 then
      return nil, "not-product", found[1]
    end
  end
  return nil, "unknown"
end

return names
