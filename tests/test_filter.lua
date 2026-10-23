-- Contract of the ingredient filter: a recipe must hold every wanted ingredient as many times as it is wanted.
local lu = require("luaunit")
local filter = require("filter")
local index = require("index")

local pack = index.pack

return {
  TestFilter = {
    testMatches = function()
      local mortarCopper = pack(3, 7, 9)
      local cases = {
        { recipe = mortarCopper, wanted = { 7 }, want = true },
        { recipe = mortarCopper, wanted = { 8 }, want = false },
        { recipe = mortarCopper, wanted = { 9, 3 }, want = true },
        { recipe = mortarCopper, wanted = { 3, 8 }, want = false },
        { recipe = pack(3, 3, 9), wanted = { 3, 3 }, want = true },
        { recipe = mortarCopper, wanted = { 3, 3 }, want = false }, -- the same twice needs two copies
        { recipe = mortarCopper, wanted = {}, want = true },
        { recipe = pack(3, 7), wanted = { 7, 3 }, want = true }, -- Advanced: two ingredients
        { recipe = pack(3, 7), wanted = { 9 }, want = false },
      }
      for _, case in ipairs(cases) do
        lu.assertEquals(filter.matches(case.recipe, case.wanted), case.want)
      end
    end,

    testApplyKeepsOrderAndNil = function()
      local list = { pack(5, 6, 7), pack(1, 2, 3), pack(2, 6, 9), pack(2, 4) }
      lu.assertEquals(filter.apply(list, { 2 }), { pack(1, 2, 3), pack(2, 6, 9), pack(2, 4) })
      lu.assertEquals(filter.apply(list, { 2, 6 }), { pack(2, 6, 9) })
      lu.assertEquals(filter.apply(list, {}), list)
      lu.assertNil(filter.apply(nil, { 2 }))
    end,

    testIngredientsOfTheMatchingRecipes = function()
      local list = { pack(3, 3, 9), pack(3, 7, 9), pack(4, 5, 6) }
      -- Nothing wanted: everything in any recipe.
      lu.assertEquals(
        filter.ingredients({}, list, nil),
        { [3] = true, [9] = true, [7] = true, [4] = true, [5] = true, [6] = true }
      )
      -- Position 3 once: it is offered again only because one recipe holds it twice.
      lu.assertEquals(filter.ingredients({ 3 }, list), { [3] = true, [9] = true, [7] = true })
      -- Without a recipe that repeats it, it is not offered again.
      lu.assertEquals(filter.ingredients({ 3 }, { pack(3, 7, 9) }), { [7] = true, [9] = true })
    end,
  },
}
