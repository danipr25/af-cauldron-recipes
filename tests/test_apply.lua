-- Contract of applying a recipe to a cauldron: which slots keep their filter, which are cleared and set (and in what
-- order), that the panel is checked before anything is touched.
local lu = require("luaunit")
local apply = require("apply")

local function slot(filter, items)
  return { filter = filter, items = items or 0 }
end

-- A fake cauldron component: records every NetCommandSetFilterName call and keeps the filters, with a stand-in for the
-- mod's discovery hook (the game reports a recipe only when every slot has a filter).
local function fakeComponent(slots, onComplete)
  local component = { calls = {} }
  local held = setmetatable({}, {
    __len = function()
      return #slots
    end,
  })
  for number, one in ipairs(slots) do
    held[number] = { SlotFilterName = one.filter or "None", ItemStack = one.items }
  end
  component.FacilityContainer = { Slots = held }
  function component:NetCommandSetFilterName(number, name)
    self.calls[#self.calls + 1] = { number, name }
    held[number + 1].SlotFilterName = name
    local complete = true
    for index = 1, #slots do
      if held[index].SlotFilterName == "None" then
        complete = false
      end
    end
    if complete and onComplete then
      onComplete(#self.calls)
    end
  end
  return component
end

-- Everything an applier needs, with `defer` queueing the work in `queue` (run it with flush) and a panel that stays
-- open unless `open.value` is set to false.
local function setup(component)
  local queue, shown, logged, said = {}, { count = 0 }, {}, {}
  local open = { value = true }
  local info = {
    component = component,
    isCurrent = function()
      return open.value
    end,
    showGame = function()
      shown.count = shown.count + 1
    end,
  }
  local applier = apply.new({
    api = {
      defer = function(fn)
        queue[#queue + 1] = fn
      end,
    },
    log = function(line)
      logged[#logged + 1] = line
    end,
    text = function(value)
      return value
    end,
    fname = function(name)
      return name
    end,
  })
  local ui = {
    message = function(text)
      said[#said + 1] = text
    end,
  }
  local function flush()
    while #queue > 0 do
      table.remove(queue, 1)()
    end
  end
  return {
    info = info,
    applier = applier,
    ui = ui,
    flush = flush,
    open = open,
    shown = shown,
    logged = logged,
    said = said,
  }
end

local COKE = { product = "Coke", inputs = { "Charcoal", "Flax", "Sand" } }

return {
  TestPlan = {
    testChangingSlotsAreClearedThenSetAndKeptOnesStay = function()
      -- Flax is kept in slot 3 (its 2 items stay); slots 1 and 2 change, their 5 items go back.
      local plan = apply.plan({ slot("Wood", 5), slot("Limestone"), slot("Flax", 2) }, COKE.inputs)
      lu.assertEquals(plan.clear, { 0, 1 })
      lu.assertEquals(plan.set, { { 0, "Charcoal" }, { 1, "Sand" } })
      lu.assertEquals(plan.items, 5)
      lu.assertEquals(plan.held, 7) -- every slot, for the log
    end,
    testOrderDoesNotMatter = function()
      lu.assertTrue(apply.plan({ slot("Sand"), slot("Clay"), slot("Wood") }, { "Wood", "Sand", "Clay" }).same)
    end,
    testEmptySlotsAreSetWithoutClearing = function()
      local plan = apply.plan({ slot("Sand"), slot(nil), slot(nil) }, { "Sand", "Clay", "Wood" })
      lu.assertEquals(plan.clear, {})
      lu.assertEquals(plan.set, { { 1, "Clay" }, { 2, "Wood" } })
      lu.assertEquals(plan.items, 0)
    end,
    testRepeatedInputsAreUsedOnceEach = function()
      local plan = apply.plan({ slot("Sand"), slot("Wood", 3), slot("Clay") }, { "Sand", "Sand", "Clay" })
      lu.assertEquals(plan.clear, { 1 })
      lu.assertEquals(plan.set, { { 1, "Sand" } })
      lu.assertEquals(plan.items, 3)
      -- A surplus copy of a filter changes.
      plan = apply.plan({ slot("Sand"), slot("Sand"), slot("Clay") }, { "Sand", "Wood", "Clay" })
      lu.assertEquals(plan.set, { { 1, "Wood" } })
    end,
    testSlotCountMustMatchTheRecipe = function()
      lu.assertEquals(apply.plan({ slot("A"), slot("B") }, { "A", "B", "C" }), { ok = false, reason = "slots" })
      lu.assertEquals(apply.plan({ slot("A"), slot("B"), slot("C") }, { "A", "B" }), { ok = false, reason = "slots" })
    end,
  },
  TestApplier = {
    testEmptyCauldronAppliesAtOnceAndNeverCompletesAPartialRecipe = function()
      local completed = {}
      local component = fakeComponent({ slot("Wood"), slot("Limestone"), slot("Flax") }, function(calls)
        completed[#completed + 1] = calls
      end)
      local run = setup(component)
      run.applier:request(run.info, "normal", COKE, run.ui)
      lu.assertEquals(component.calls, {}) -- nothing inside the click itself
      run.flush()
      -- Flax stays. The two changing slots are cleared, then set: only the last call completes a recipe.
      lu.assertEquals(component.calls, { { 0, "None" }, { 1, "None" }, { 0, "Charcoal" }, { 1, "Sand" } })
      lu.assertEquals(completed, { 4 })
      lu.assertEquals(run.said, {})
      lu.assertEquals(run.shown.count, 1)
      lu.assertEquals(#run.logged, 1)
    end,
    testItemsAreNotAskedAboutAndAreLogged = function()
      local component = fakeComponent({ slot("Wood", 30), slot("Limestone", 15), slot("Flax", 9) })
      local run = setup(component)
      run.applier:request(run.info, "normal", COKE, run.ui)
      run.flush()
      lu.assertEquals(#component.calls, 4)
      lu.assertEquals(run.shown.count, 1)
      lu.assertStrContains(run.logged[1], "54 items were in the cauldron")
    end,
    testABurstOfClicksAppliesOnce = function()
      local component = fakeComponent({ slot("Wood"), slot("Limestone"), slot("Flax") })
      local run = setup(component)
      run.applier:request(run.info, "normal", COKE, run.ui)
      run.applier:request(run.info, "normal", COKE, run.ui)
      run.flush()
      lu.assertEquals(#component.calls, 4)
      lu.assertEquals(run.shown.count, 1)
    end,
    testClosedPanelMeansNothingHappens = function()
      local component = fakeComponent({ slot("Wood"), slot("Limestone"), slot("Flax") })
      local run = setup(component)
      run.applier:request(run.info, "normal", COKE, run.ui)
      run.open.value = false -- closed before the deferred work runs
      run.flush()
      lu.assertEquals(component.calls, {})
      lu.assertEquals({ run.said, run.logged }, { {}, {} })
      lu.assertEquals(run.shown.count, 0)
    end,
    testSameRecipeAndWrongSlotCountAreSaidPlainly = function()
      local same = setup(fakeComponent({ slot("Sand"), slot("Flax"), slot("Charcoal") }))
      same.applier:request(same.info, "normal", COKE, same.ui)
      same.flush()
      lu.assertEquals(same.said, { "That recipe is already set on this cauldron." })
      lu.assertEquals(same.shown.count, 0)

      local advanced = fakeComponent({ slot("A"), slot("B") })
      local wrong = setup(advanced)
      wrong.applier:request(wrong.info, "advanced", COKE, wrong.ui)
      wrong.flush()
      lu.assertEquals(advanced.calls, {})
      lu.assertStrContains(wrong.said[1], "2 slots")
      lu.assertStrContains(wrong.said[1], "not 3")
    end,
    testAFailingCallIsReportedAndStops = function()
      local component = fakeComponent({ slot("Wood"), slot("Limestone"), slot("Flax") })
      component.NetCommandSetFilterName = function()
        error("boom")
      end
      local run = setup(component)
      run.applier:request(run.info, "normal", COKE, run.ui)
      run.flush()
      lu.assertEquals(#run.said, 1)
      lu.assertStrContains(run.said[1], "partly set")
      lu.assertEquals(run.shown.count, 0)
    end,
  },
}
