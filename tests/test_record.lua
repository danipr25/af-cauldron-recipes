-- Contract of the record: what is shown for each product after discovering recipes and running the commands.
local lu = require("luaunit")
local record = require("record")

local function new()
  return record.new("World_1")
end

-- What the player sees for a product: its discovered recipes, and its other recipes.
local function shown(rec, product)
  return { discovered = rec:discoveredVisible(product), other = rec:otherVisible(product) }
end

return {
  TestRecordVisibility = {
    testNothingIsShownAtFirst = function()
      local rec = new()
      lu.assertEquals(shown(rec, "Clay"), { discovered = true, other = false })
      lu.assertFalse(rec:hasDiscovered("advanced", "Clay"))
    end,

    testADiscoveredRecipeIsShownAndKeptOnce = function()
      local rec = new()
      lu.assertTrue(rec:addDiscovered("advanced", { "Gentian", "GentianNectar" }, "Clay", "filter"))
      -- The same recipe with the ingredients in another order is the same recipe.
      lu.assertFalse(rec:addDiscovered("advanced", { "GentianNectar", "Gentian" }, "Clay", "filter"))
      lu.assertEquals(#rec:discoveredFor("advanced", "Clay"), 1)
      lu.assertEquals(#rec:discoveredFor("normal", "Clay"), 0)
    end,

    -- Each case: a list of steps, then what the product "Clay" shows (discovered recipes, other recipes).
    testCommandSequences = function()
      local cases = {
        { name = "unlockall", steps = { "unlockall" }, expect = { discovered = true, other = true } },
        { name = "unlock one", steps = { "unlock" }, expect = { discovered = true, other = true } },
        {
          name = "locked is ignored while all is false",
          steps = { "safeLock" },
          expect = { discovered = true, other = false },
        },
        {
          name = "unlockall then lock",
          steps = { "unlockall", "lock" },
          expect = { discovered = false, other = false },
        },
        {
          name = "unlockall then safe-lock keeps the discovered ones",
          steps = { "unlockall", "safeLock" },
          expect = { discovered = true, other = false },
        },
        {
          name = "lockall hides all",
          steps = { "unlockall", "lockall" },
          expect = { discovered = false, other = false },
        },
        {
          name = "safe-lockall keeps the discovered ones",
          steps = { "unlockall", "safeLockall" },
          expect = { discovered = true, other = false },
        },
        {
          name = "unlock after lock shows everything again",
          steps = { "lock", "unlock" },
          expect = { discovered = true, other = true },
        },
      }
      local run = {
        unlockall = function(rec)
          rec:unlockAll()
        end,
        lockall = function(rec)
          rec:lockAll()
        end,
        safeLockall = function(rec)
          rec:safeLockAll()
        end,
        unlock = function(rec)
          rec:unlock("Clay")
        end,
        lock = function(rec)
          rec:lock("Clay")
        end,
        safeLock = function(rec)
          rec:safeLock("Clay")
        end,
      }
      for _, case in ipairs(cases) do
        local rec = new()
        rec:addDiscovered("advanced", { "Gentian", "GentianNectar" }, "Clay", "filter")
        for _, step in ipairs(case.steps) do
          run[step](rec)
        end
        lu.assertEquals(shown(rec, "Clay"), case.expect, case.name)
      end
    end,

    testALoadScanAfterLockallKeepsTheProductHidden = function()
      local rec = new()
      rec:addDiscovered("advanced", { "Gentian", "GentianNectar" }, "Clay", "filter")
      rec:lockAll()
      -- The same recipe found again at the next load.
      rec:addDiscovered("advanced", { "Gentian", "GentianNectar" }, "Clay", "load")
      lu.assertFalse(rec:discoveredVisible("Clay"))
    end,

    testAFilterChangeAfterLockallShowsTheProductAgain = function()
      local rec = new()
      rec:addDiscovered("advanced", { "Gentian", "GentianNectar" }, "Clay", "filter")
      rec:lockAll()
      lu.assertTrue(rec:addDiscovered("advanced", { "Gentian", "GentianNectar" }, "Clay", "filter"))
      lu.assertTrue(rec:discoveredVisible("Clay"))
    end,

    testSnapshotsTellWhetherAnythingVisibleChanged = function()
      local rec = new()
      rec:addDiscovered("advanced", { "Gentian", "GentianNectar" }, "Clay", "filter")
      local products = { "Clay", "GoldDust5" }
      local before = rec:snapshot(products)
      rec:safeLockAll() -- nothing was hidden: no change
      lu.assertFalse(record.visibleChanged(before, rec:snapshot(products)))
      rec:lock("GoldDust5") -- a product with nothing discovered and nothing unlocked: no change either
      lu.assertFalse(record.visibleChanged(before, rec:snapshot(products)))
      rec:lock("Clay")
      lu.assertTrue(record.visibleChanged(before, rec:snapshot(products)))
    end,
  },

  TestRecordFile = {
    testRoundTrip = function()
      local rec = new()
      rec:addDiscovered("normal", { "SilverCoin", "GoldCoin", "CopperCoin" }, "GoldDust5", "load")
      rec:addDiscovered("advanced", { "Gentian", "GentianNectar" }, "Clay", "filter")
      rec:unlock("Wood")
      rec:lock("Clay")
      local back = assert(record.decode(rec:toTable(), "World_1"))
      lu.assertEquals(back:toTable(), rec:toTable())
      lu.assertEquals(back:discoveredFor("normal", "GoldDust5")[1].inputs, { "CopperCoin", "GoldCoin", "SilverCoin" })
    end,

    testAVersion1FileLoadsWithoutFavoritesAndIgnoresAFavoritesField = function()
      local data = {
        version = 1,
        world = "World_1",
        discovered = { { mode = "advanced", inputs = { "A", "B" }, product = "C", seen = "load" } },
        favorites = { { mode = "advanced", inputs = { "A", "B" }, product = "C" } },
      }
      local rec = assert(record.decode(data, "World_1"))
      lu.assertEquals(#rec.discovered, 1)
      lu.assertEquals(#rec.favorites, 0)
      lu.assertEquals(rec:toTable().version, record.VERSION)
    end,

    testFavoritesRoundTripAndDuplicatesCollapse = function()
      local rec = new()
      rec:toggleFavorite("advanced", { "GentianNectar", "Gentian" }, "Clay")
      rec:toggleFavorite("normal", { "SilverCoin", "GoldCoin", "CopperCoin" }, "GoldDust5")
      local data = rec:toTable()
      lu.assertEquals(data.favorites[1].inputs, { "Gentian", "GentianNectar" })
      local back = assert(record.decode(data, "World_1"))
      lu.assertEquals(back:toTable(), data)
      -- The same recipe twice in the file (other order of inputs) is one favorite.
      data.favorites[3] = { mode = "advanced", inputs = { "GentianNectar", "Gentian" }, product = "Clay" }
      lu.assertEquals(#assert(record.decode(data, "World_1")).favorites, 2)
    end,

    testUnusableDataIsRefused = function()
      local bad = {
        "text",
        { version = 3, world = "W" },
        { version = 1 },
        { version = 1, world = "W", discovered = { { mode = "normal", inputs = { "A", "B" }, product = "C" } } },
        { version = 1, world = "W", unlocked = { 5 } },
        { version = 2, world = "W", favorites = "Clay" },
        { version = 2, world = "W", favorites = { { mode = "advanced", inputs = { "A" }, product = "C" } } },
        { version = 2, world = "W", favorites = { { mode = "advanced", inputs = { "A", 7 }, product = "C" } } },
        { version = 2, world = "W", favorites = { { mode = "other", inputs = { "A", "B" }, product = "C" } } },
      }
      for index, data in ipairs(bad) do
        lu.assertNil(record.decode(data, "W"), "case " .. index)
      end
    end,

    testEntriesWithUnknownItemsAreKeptButNotShown = function()
      local rec = new()
      rec:addDiscovered("advanced", { "Gentian", "Gone" }, "Clay", "filter")
      rec:addDiscovered("advanced", { "Gentian", "GentianNectar" }, "Clay", "filter")
      local known = { Gentian = true, GentianNectar = true }
      local changed, unknown = rec:revalidate(function(name)
        return known[name] == true
      end, function(name)
        return name == "Clay" or name == "Coke"
      end, function()
        return "Coke" -- the game now gives another product
      end)
      lu.assertTrue(changed)
      lu.assertEquals(unknown, 1)
      lu.assertEquals(#rec.discovered, 2) -- still in the file
      lu.assertEquals(#rec:discoveredFor("advanced", "Coke"), 1)
      lu.assertEquals(#rec:toTable().discovered, 2)
    end,
  },

  TestRecordFavorites = {
    testToggleStarsAndUnstarsAndTheKeyIgnoresTheProduct = function()
      local rec = new()
      lu.assertFalse(rec:isFavorite("advanced", { "Gentian", "GentianNectar" }))
      lu.assertTrue(rec:toggleFavorite("advanced", { "GentianNectar", "Gentian" }, "Clay"))
      lu.assertTrue(rec:isFavorite("advanced", { "Gentian", "GentianNectar" }))
      lu.assertFalse(rec:isFavorite("normal", { "Gentian", "GentianNectar", "Wood" }))
      -- Another product name for the same ingredients is the same recipe: it unstars.
      lu.assertFalse(rec:toggleFavorite("advanced", { "Gentian", "GentianNectar" }, "Coke"))
      lu.assertEquals(#rec.favorites, 0)
    end,

    testAFavoriteIsShownOnlyWhereItsRecipeWouldBe = function()
      local rec = new()
      rec:addDiscovered("advanced", { "Gentian", "GentianNectar" }, "Clay", "filter")
      rec:toggleFavorite("advanced", { "Gentian", "GentianNectar" }, "Clay") -- discovered
      rec:toggleFavorite("advanced", { "Wood", "Coke" }, "Clay") -- not discovered
      lu.assertEquals(#rec:favoritesFor("advanced", "Clay"), 1) -- the discovered one only
      rec:unlock("Clay")
      lu.assertEquals(#rec:favoritesFor("advanced", "Clay"), 2)
      lu.assertEquals(#rec:favoritesFor("normal"), 0)
      rec:lock("Clay") -- locked: hidden, not deleted
      lu.assertEquals(#rec:favoritesFor("advanced"), 0)
      lu.assertEquals(#rec.favorites, 2)
      rec:unlock("Clay")
      lu.assertEquals(#rec:favoritesFor("advanced"), 2)
    end,

    testRevalidateCountsAndRefreshesFavorites = function()
      local rec = new()
      rec:toggleFavorite("advanced", { "Gentian", "Gone" }, "Clay")
      rec:toggleFavorite("advanced", { "Gentian", "GentianNectar" }, "Clay")
      local known = { Gentian = true, GentianNectar = true }
      local changed, unknown, unknownFavorites = rec:revalidate(function(name)
        return known[name] == true
      end, function(name)
        return name == "Clay" or name == "Coke"
      end, function()
        return "Coke"
      end)
      lu.assertTrue(changed)
      lu.assertEquals({ unknown, unknownFavorites }, { 0, 1 })
      lu.assertEquals(#rec.favorites, 2) -- the unknown one stays in the file
      lu.assertEquals(rec.favorites[2].product, "Coke")
      lu.assertEquals(#rec:favoritesFor("advanced"), 0) -- neither is shown: the usable one is not visible here
    end,
  },
}
