-- Contract of the recipe pages: discovered recipes first, no recipe twice, pages of a fixed size.
local lu = require("luaunit")
local listing = require("listing")

local function packedOf(page)
  local list = {}
  for _, item in ipairs(page.items) do
    list[#list + 1] = item.packed
  end
  return list
end

return {
  TestListing = {
    testDiscoveredFirstThenTheIndexWithoutRepeats = function()
      local page = listing.page({ 30, 10 }, { 10, 20, 30, 40 }, 1, 20)
      lu.assertEquals(packedOf(page), { 30, 10, 20, 40 })
      lu.assertEquals(page.total, 4)
      lu.assertEquals(page.items[1].discovered, true)
      lu.assertEquals(page.items[3].discovered, false)
    end,

    testPagesCutAcrossTheTwoLists = function()
      local indexed = {}
      for number = 1, 10 do
        indexed[number] = number * 10
      end
      local first = listing.page({ 20 }, indexed, 1, 4)
      lu.assertEquals(packedOf(first), { 20, 10, 30, 40 })
      lu.assertEquals({ first.total, first.pages }, { 10, 3 })
      lu.assertEquals(packedOf(listing.page({ 20 }, indexed, 2, 4)), { 50, 60, 70, 80 })
      lu.assertEquals(packedOf(listing.page({ 20 }, indexed, 3, 4)), { 90, 100 })
    end,

    testTheRequestedPageIsKeptInRange = function()
      local indexed = { 1, 2, 3 }
      lu.assertEquals(listing.page({}, indexed, 9, 2).page, 2)
      lu.assertEquals(listing.page({}, indexed, 0, 2).page, 1)
    end,

    testNothingToShowIsOneEmptyPage = function()
      local page = listing.page({}, nil, 1, 20)
      lu.assertEquals({ page.total, page.pages, page.page, #page.items }, { 0, 1, 1, 0 })
    end,

    testDiscoveredOnlyWhileTheIndexIsNotReady = function()
      local page = listing.page({ 5, 6 }, nil, 1, 20)
      lu.assertEquals(packedOf(page), { 5, 6 })
    end,
  },
}
