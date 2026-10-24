-- Contract of the cauldron panel's recipe list: favorites first, discovered ones only with the toggle, no recipe twice,
-- only recipes the cauldron's mode can set, and a search over the display names of the product and the inputs.
local lu = require("luaunit")
local record = require("record")
local recipeList = require("recipe_list")

local DISPLAY = { Sand = "Fine Sand", Gem = "Ruby Gem" }

local function newCatalog()
  return {
    ingredientIndex = { Sand = 1, Clay = 2, Wood = 3, Ruby = 4 },
    productSet = { Coke = true, Gem = true },
    display = function(name)
      return DISPLAY[name] or name
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
    testFavoritesFirstThenDiscoveredWithoutDuplicates = function()
      local rec = world()
      rec:addDiscovered("normal", { "Sand", "Clay", "Wood" }, "Coke", "filter")
      rec:addDiscovered("normal", { "Ruby", "Clay", "Wood" }, "Gem", "filter")
      rec:addFavorite("normal", { "Ruby", "Clay", "Wood" }, "Gem")
      local plain = recipeList.build(rec, newCatalog(), "normal", { showDiscovered = false })
      lu.assertEquals(productsOf(plain), { "Gem" })
      local both = recipeList.build(rec, newCatalog(), "normal", { showDiscovered = true })
      lu.assertEquals(productsOf(both), { "Gem", "Coke" }) -- the favorite once, and first
      lu.assertEquals(both.base, 2)
    end,
    testOnlyTheCauldronsModeAndUsableEntries = function()
      local rec = world()
      rec:addFavorite("advanced", { "Sand", "Clay" }, "Coke")
      rec:addFavorite("normal", { "Sand", "Clay", "Wood" }, "Coke")
      rec:addFavorite("normal", { "Sand", "Gone", "Wood" }, "Coke") -- an input the game no longer has
      rec:addFavorite("normal", { "Sand", "Clay", "Ruby" }, "Unknown") -- a product the game no longer has
      lu.assertEquals(#recipeList.build(rec, newCatalog(), "normal", {}).rows, 1)
      lu.assertEquals(recipeList.build(rec, newCatalog(), "advanced", {}).rows[1].inputs, { "Clay", "Sand" })
    end,
    testHiddenProductsAreNotListed = function()
      local rec = world()
      rec.all = false
      rec:addDiscovered("normal", { "Sand", "Clay", "Wood" }, "Coke", "filter")
      lu.assertEquals(recipeList.build(rec, newCatalog(), "normal", { showDiscovered = true }).base, 1)
      rec.hidden.Coke = true
      lu.assertEquals(recipeList.build(rec, newCatalog(), "normal", { showDiscovered = true }).base, 0)
    end,
    testSearchUsesDisplayNamesOfProductAndInputsIgnoringCase = function()
      local rec = world()
      rec:addFavorite("normal", { "Sand", "Clay", "Wood" }, "Coke")
      rec:addFavorite("normal", { "Ruby", "Clay", "Wood" }, "Gem")
      -- { search, expected products }
      local cases = {
        { "", { "Coke", "Gem" } },
        { "RUBY", { "Gem" } }, -- the input Ruby, and the product's display name "Ruby Gem"
        { "fine sa", { "Coke" } }, -- the display name of Sand, not its internal name
        { "coke", { "Coke" } },
        { "nothing", {} },
      }
      for _, case in ipairs(cases) do
        local result = recipeList.build(rec, newCatalog(), "normal", { search = case[1] })
        lu.assertEquals(productsOf(result), case[2], case[1])
        lu.assertEquals(result.base, 2)
      end
    end,
    testListIsLimitedButCountsAll = function()
      local rec = world()
      local catalog = newCatalog()
      for number = 1, recipeList.LIMIT + 5 do
        local extra = "Item" .. number
        catalog.ingredientIndex[extra] = 100 + number
        rec:addFavorite("normal", { extra, "Clay", "Wood" }, "Coke")
      end
      local result = recipeList.build(rec, catalog, "normal", {})
      lu.assertEquals(#result.rows, recipeList.LIMIT)
      lu.assertEquals(result.total, recipeList.LIMIT + 5)
    end,
  },
}
