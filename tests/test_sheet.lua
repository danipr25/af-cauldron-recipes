-- Contract of the "Used in N cauldron recipes" count of the item sheet: only what the player may see.
local lu = require("luaunit")
local index = require("index")
local sheet = require("sheet")

-- A small world: ingredients Stone (1), Clay (2), Herb (3). Products A and B are products, X is not (a hidden or
-- unknown product the index may still report).
local catalog = { ingredientIndex = { Stone = 1, Clay = 2, Herb = 3 }, productSet = { A = true, B = true } }

local function fixture(options)
  local used = {}
  index.addUsage(used, "A", 1, 2, 3) -- A: Stone + Clay + Herb
  index.addUsage(used, "A", 1, 1, 3) -- A: Stone twice + Herb
  index.addUsage(used, "B", 1, 3, nil) -- B (Advanced): Stone + Herb
  index.addUsage(used, "X", 1, 2, nil)
  local fakeIndex = {
    usedIn = function(_, position)
      return used[position] or {}
    end,
  }
  local unlocked = options.unlocked or {}
  local rec = {
    discovered = options.discovered or {},
    otherVisible = function(_, product)
      return unlocked[product] == true
    end,
    discoveredVisible = function(_, product)
      return not (options.hidden or {})[product]
    end,
  }
  return rec, fakeIndex
end

-- The recipes of product A per mode, as the tab would list them.
local function summaryFixture(options)
  local rec = {
    discoveredVisible = function()
      return true
    end,
    otherVisible = function()
      return options.otherVisible == true
    end,
    discoveredFor = function(_, mode)
      local list = {}
      for _, entry in ipairs(options.discovered or {}) do
        if entry.mode == mode then
          list[#list + 1] = entry
        end
      end
      return list
    end,
  }
  local fakeIndex = {
    recipes = function(_, mode)
      return options.indexed and options.indexed[mode] or nil
    end,
  }
  return rec, fakeIndex
end

return {
  TestProductSummary = {
    testCountsPerModeAndAModeCanBeEmpty = function()
      local first, second = index.pack(1, 2, 3), index.pack(1, 1, 3)
      local advancedOnly = index.pack(1, 2)
      -- { description, options, expected }
      local cases = {
        { "nothing visible", {}, { normal = { total = 0, discovered = 0 }, advanced = { total = 0, discovered = 0 } } },
        {
          "discovered only, in one mode",
          { discovered = { { mode = "normal", inputs = { "Stone", "Clay", "Herb" } } } },
          { normal = { total = 1, discovered = 1 }, advanced = { total = 0, discovered = 0 } },
        },
        {
          "index recipes in both modes, one of them discovered",
          {
            otherVisible = true,
            indexed = { normal = { first, second }, advanced = { advancedOnly } },
            discovered = { { mode = "normal", inputs = { "Stone", "Clay", "Herb" } } },
          },
          { normal = { total = 2, discovered = 1 }, advanced = { total = 1, discovered = 0 } },
        },
        {
          "index recipes in one mode only",
          { otherVisible = true, indexed = { advanced = { advancedOnly } } },
          { normal = { total = 0, discovered = 0 }, advanced = { total = 1, discovered = 0 } },
        },
      }
      for _, case in ipairs(cases) do
        local rec, fakeIndex = summaryFixture(case[2])
        lu.assertEquals(sheet.productSummary(rec, catalog, fakeIndex, "A"), case[3], case[1])
      end
    end,
  },

  TestUsedIn = {
    testCountsOnlyWhatThePlayerMaySee = function()
      -- { description, options, item, expected }
      local cases = {
        { "locked save", {}, "Stone", 0 },
        { "product outside productSet is ignored", { unlocked = { X = true } }, "Clay", 0 },
        { "unlocked product", { unlocked = { A = true } }, "Clay", 1 },
        { "twice in one recipe counts once", { unlocked = { A = true } }, "Stone", 2 }, -- two A recipes, one each
        { "two products", { unlocked = { A = true, B = true } }, "Herb", 3 },
        {
          "discovered recipe of a product whose other recipes are hidden",
          { discovered = { { product = "B", inputs = { "Stone", "Stone", "Herb" } } } },
          "Stone",
          1,
        },
        {
          "discovered recipe that is not shown or unknown",
          {
            hidden = { B = true },
            discovered = {
              { product = "B", inputs = { "Stone", "Herb" } },
              { product = "A", inputs = { "Stone", "Herb" }, unknown = true },
            },
          },
          "Stone",
          0,
        },
        { "not an ingredient", { unlocked = { A = true } }, "Gold", 0 },
      }
      for _, case in ipairs(cases) do
        local rec, fakeIndex = fixture(case[2])
        lu.assertEquals(sheet.usedIn(rec, catalog, fakeIndex, case[3]), case[4], case[1])
      end
    end,
  },
}
