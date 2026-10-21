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

    testUnusableDataIsRefused = function()
      local bad = {
        "text",
        { version = 2, world = "W" },
        { version = 1 },
        { version = 1, world = "W", discovered = { { mode = "normal", inputs = { "A", "B" }, product = "C" } } },
        { version = 1, world = "W", unlocked = { 5 } },
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
}
