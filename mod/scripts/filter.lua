-- Filters recipes by the ingredients the player picked. Pure Lua (tests/test_filter.lua). Recipes are the whole
-- numbers made by index.pack; `wanted` is a list of ingredient positions, which may repeat.
local indexModule = require("index")

local filter = {}

-- How many times each position is wanted: { [position] = times }.
local function countWanted(wanted)
  local counts = {}
  for _, position in ipairs(wanted) do
    counts[position] = (counts[position] or 0) + 1
  end
  return counts
end

-- Does the recipe hold every wanted position at least as many times as it is wanted?
local function holds(packed, counts)
  local first, second, third = indexModule.unpack(packed)
  for position, times in pairs(counts) do
    local has = (first == position and 1 or 0) + (second == position and 1 or 0) + (third == position and 1 or 0)
    if has < times then
      return false
    end
  end
  return true
end

-- True when the recipe holds every wanted position at least as many times as it is wanted (no wanted: always).
function filter.matches(packed, wanted)
  return holds(packed, countWanted(wanted))
end

-- A new list with the recipes that match, in the same order. nil (the index is not ready) stays nil.
function filter.apply(list, wanted)
  if list == nil then
    return nil
  end
  local counts = countWanted(wanted)
  local kept = {}
  for _, packed in ipairs(list) do
    if holds(packed, counts) then
      kept[#kept + 1] = packed
    end
  end
  return kept
end

-- The positions that could still be added to `wanted`: for each recipe that matches, what is left after taking the
-- wanted ones out once each. Takes any number of lists (nil ones are skipped). Returns { [position] = true }.
function filter.ingredients(wanted, ...)
  local counts = countWanted(wanted)
  local found = {}
  for number = 1, select("#", ...) do
    for _, packed in ipairs((select(number, ...)) or {}) do
      if holds(packed, counts) then
        local first, second, third = indexModule.unpack(packed)
        local left = {}
        for position, times in pairs(counts) do
          left[position] = times
        end
        for _, position in ipairs({ first, second, third }) do
          if left[position] and left[position] > 0 then
            left[position] = left[position] - 1
          else
            found[position] = true
          end
        end
      end
    end
  end
  return found
end

return filter
