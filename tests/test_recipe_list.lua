-- Contract of the cauldron panel's recipe list: favorites first, discovered next, the index's recipes last, no recipe
-- twice, only the cauldron's mode, the V menu's visibility rules, a search over the display names of the product and
-- the inputs, and an early stop so the whole index is never walked.
local lu = require("luaunit")
local indexModule = require("index")
local record = require("record")
local recipeList = require("recipe_list")

local DISPLAY = { Sand = "Fine Sand", Gem = "Ruby Gem" }

local function newCatalog()
  return {
    ingredients = { "Sand", "Clay", "Wood", "Ruby" },
    ingredientIndex = { Sand = 1, Clay = 2, Wood = 3, Ruby = 4 },
    products = { "Coke", "Gem" },
    productSet = { Coke = true, Gem = true },
    display = function(name)
      return DISPLAY[name] or name
    end,
  }
end

-- An index with the given lists: { normal = { Coke = { packed, ... } }, advanced = { ... } }.
local function fakeIndex(byMode)
  return {
    recipes = function(_, mode, product)
      return (byMode[mode] or {})[product]
    end,
  }
end

local function world()
  local rec = record.new("test")
  rec.all = true -- every recipe is shown
  return rec
end

local function productsOf(result)
  local list = {}
  for _, row in ipairs(result.rows) do
    list[#list + 1] = row.product
  end
  return list
end

return {
  TestRecipeList = {
    testFavoritesThenDiscoveredThenTheIndexWithoutDuplicates = function()
      local rec = world()
      rec:addDiscovered("normal", { "Sand", "Clay", "Wood" }, "Coke", "filter")
      rec:addDiscovered("normal", { "Ruby", "Clay", "Wood" }, "Gem", "filter")
      rec:addFavorite("normal", { "Ruby", "Clay", "Wood" }, "Gem")
      local index = fakeIndex({
        normal = {
          Coke = { indexModule.pack(1, 2, 3), indexModule.pack(1, 1, 2) },
          Gem = { indexModule.pack(2, 3, 4), indexModule.pack(3, 3, 3) },
        },
      })
      local result = recipeList.build(rec, newCatalog(), index, "normal", {})
      -- Favorite Gem, discovered Coke, then the index by product name (Coke, Gem) without the two already listed.
      lu.assertEquals(productsOf(result), { "Gem", "Coke", "Coke", "Gem" })
      lu.assertEquals(result.rows[3].inputs, { "Sand", "Sand", "Clay" })
      lu.assertEquals(result.rows[4].inputs, { "Wood", "Wood", "Wood" })
      lu.assertFalse(result.more)
    end,
    testOnlyTheCauldronsModeAndUsableEntries = function()
      local rec = world()
      rec:addFavorite("advanced", { "Sand", "Clay" }, "Coke")
      rec:addFavorite("normal", { "Sand", "Clay", "Wood" }, "Coke")
      rec:addFavorite("normal", { "Sand", "Gone", "Wood" }, "Coke") -- an input the game no longer has
      rec:addFavorite("normal", { "Sand", "Clay", "Ruby" }, "Unknown") -- a product the game no longer has
      local index = fakeIndex({ advanced = { Gem = { indexModule.pack(3, 4) } } })
      lu.assertEquals(#recipeList.build(rec, newCatalog(), index, "normal", {}).rows, 1)
      local advanced = recipeList.build(rec, newCatalog(), index, "advanced", {})
      lu.assertEquals(advanced.rows[1].inputs, { "Sand", "Clay" })
      lu.assertEquals(advanced.rows[2].inputs, { "Wood", "Ruby" })
    end,
    testVisibilityFollowsTheLocks = function()
      local rec = world()
      rec.all = false
      rec:addDiscovered("normal", { "Sand", "Clay", "Wood" }, "Coke", "filter")
      local index =
        fakeIndex({ normal = { Coke = { indexModule.pack(2, 3, 4) }, Gem = { indexModule.pack(1, 2, 4) } } })
      local catalog = newCatalog()
      -- Only the discovered recipe: the others are not unlocked.
      lu.assertEquals(#recipeList.build(rec, catalog, index, "normal", {}).rows, 1)
      rec.unlocked.Gem = true
      lu.assertEquals(productsOf(recipeList.build(rec, catalog, index, "normal", {})), { "Coke", "Gem" })
      rec.hidden.Coke = true -- hides the discovered recipes of Coke
      lu.assertEquals(productsOf(recipeList.build(rec, catalog, index, "normal", {})), { "Gem" })
    end,
    testSearchUsesDisplayNamesOfProductAndInputsIgnoringCase = function()
      local rec = world()
      rec:addFavorite("normal", { "Sand", "Clay", "Wood" }, "Coke")
      local index = fakeIndex({
        normal = {
          Gem = { indexModule.pack(2, 3, 4), indexModule.pack(2, 2, 3) },
          Coke = { indexModule.pack(1, 3, 3) },
        },
      })
      -- { search, expected products }
      local cases = {
        { "", { "Coke", "Coke", "Gem", "Gem" } },
        { "RUBY", { "Gem", "Gem" } }, -- "Ruby Gem" is the product (and Ruby an input)
        { "fine sa", { "Coke", "Coke" } }, -- the display name of Sand, not its internal name
        { "coke", { "Coke", "Coke" } }, -- the product
        { "nothing", {} },
      }
      for _, case in ipairs(cases) do
        lu.assertEquals(
          productsOf(recipeList.build(rec, newCatalog(), index, "normal", { search = case[1] })),
          case[2],
          case[1]
        )
      end
    end,
    testStopsAtTheLimitWithoutWalkingTheWholeIndex = function()
      local reads = 0
      local big = setmetatable({}, {
        __len = function()
          return 100000
        end,
        __index = function(_, number)
          reads = reads + 1
          return indexModule.pack(1, 2, 3) + number -- distinct numbers, all valid enough for the list
        end,
      })
      local rec = world()
      local index = fakeIndex({ normal = { Coke = big } })
      local result = recipeList.build(rec, newCatalog(), index, "normal", {})
      lu.assertEquals(#result.rows, recipeList.LIMIT)
      lu.assertTrue(result.more)
      lu.assertTrue(reads <= recipeList.LIMIT + 1)
    end,
    testNoIndexYetStillListsFavorites = function()
      local rec = world()
      rec:addFavorite("normal", { "Sand", "Clay", "Wood" }, "Coke")
      lu.assertEquals(#recipeList.build(rec, newCatalog(), nil, "normal", {}).rows, 1)
    end,
  },
}
