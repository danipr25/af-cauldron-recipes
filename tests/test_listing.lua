-- Contract of the recipe pages: favorites first, then discovered, then the rest; no recipe twice; pages of a fixed
-- size; the Favorites view's grouping.
local lu = require("luaunit")
local indexModule = require("index")
local listing = require("listing")
local record = require("record")

local function packedOf(page)
  local list = {}
  for _, item in ipairs(page.items) do
    list[#list + 1] = item.packed
  end
  return list
end

local function item(packed, kind)
  return { packed = packed, kind = kind }
end

-- A catalog with four ingredients, A to D (positions 1 to 4), and a display name that is the lower case name.
local catalog = { ingredientIndex = { A = 1, B = 2, C = 3, D = 4 } }

local function display(name)
  return name:lower()
end

return {
  TestListingCounts = {
    testTotalsUnderEachHeading = function()
      local cases = {
        { f = {}, d = {}, i = nil, want = { favorite = 0, discovered = 0, other = 0, allDiscovered = 0 } },
        { f = {}, d = { 5, 6 }, i = nil, want = { favorite = 0, discovered = 2, other = 0, allDiscovered = 2 } },
        { f = {}, d = {}, i = { 1, 2, 3 }, want = { favorite = 0, discovered = 0, other = 3, allDiscovered = 0 } },
        {
          f = {},
          d = { 2, 9 },
          i = { 1, 2, 3 },
          want = { favorite = 0, discovered = 2, other = 2, allDiscovered = 2 },
        },
        -- A favorite that was also discovered, and also in the index, counts once, as a favorite.
        {
          f = { 2 },
          d = { 2, 9 },
          i = { 1, 2, 3 },
          want = { favorite = 1, discovered = 1, other = 2, allDiscovered = 2 },
        },
      }
      for _, case in ipairs(cases) do
        lu.assertEquals(listing.counts(case.f, case.d, case.i), case.want)
      end
    end,
  },

  TestListingRows = {
    testRecipesGoTwoToARowUnderTheirHeadingAndKindsNeverMix = function()
      local rows = listing.rows({
        item(1, "favorite"),
        item(2, "discovered"),
        item(3, "discovered"),
        item(4, "discovered"),
        item(5, "other"),
        item(6, "other"),
      }, 2)
      lu.assertEquals(rows, {
        { heading = true, kind = "favorite" },
        { recipes = { 1 }, kind = "favorite" },
        { heading = true, kind = "discovered" },
        { recipes = { 2, 3 }, kind = "discovered" },
        { recipes = { 4 }, kind = "discovered" },
        { heading = true, kind = "other" },
        { recipes = { 5, 6 }, kind = "other" },
      })
    end,

    testAPageWithoutRecipesHasNoRows = function()
      lu.assertEquals(listing.rows({}, 2), {})
    end,

    testThreeToARowLeavesAShortLastRow = function()
      local items = {}
      for number = 1, 4 do
        items[number] = item(number, "other")
      end
      lu.assertEquals(listing.rows(items, 3), {
        { heading = true, kind = "other" },
        { recipes = { 1, 2, 3 }, kind = "other" },
        { recipes = { 4 }, kind = "other" },
      })
    end,

    testEveryModesPageIsWholeRows = function()
      for mode, perRow in pairs(listing.PER_ROW) do
        local size = listing.PAGE_SIZE[mode]
        lu.assertEquals(size % perRow, 0)
        local indexed = {}
        for number = 1, size * 2 do
          indexed[number] = number
        end
        local rows = listing.rows(listing.page({}, {}, indexed, 1, size).items, perRow)
        lu.assertEquals(#rows, 1 + size // perRow) -- the heading, then only full rows
        lu.assertEquals(#rows[#rows].recipes, perRow)
      end
      lu.assertEquals({ listing.PER_ROW.advanced, listing.PAGE_SIZE.advanced }, { 3, 42 })
      lu.assertEquals({ listing.PER_ROW.normal, listing.PAGE_SIZE.normal }, { 2, 40 })
    end,
  },

  TestListing = {
    testFavoritesThenDiscoveredThenTheIndexWithoutRepeats = function()
      -- 30 is a favorite and discovered, 10 is discovered and in the index.
      local page = listing.page({ 40, 30 }, { 30, 10 }, { 10, 20, 30, 50 }, 1, 20)
      lu.assertEquals(packedOf(page), { 40, 30, 10, 20, 50 })
      lu.assertEquals(page.total, 5)
      local kinds = {}
      for _, entry in ipairs(page.items) do
        kinds[#kinds + 1] = entry.kind
      end
      lu.assertEquals(kinds, { "favorite", "favorite", "discovered", "other", "other" })
    end,

    testPagesCutAcrossTheThreeLists = function()
      local indexed = {}
      for number = 1, 8 do
        indexed[number] = number * 10
      end
      local first = listing.page({ 200 }, { 300, 20 }, indexed, 1, 4)
      lu.assertEquals(packedOf(first), { 200, 300, 20, 10 })
      lu.assertEquals({ first.total, first.pages }, { 10, 3 })
      lu.assertEquals(packedOf(listing.page({ 200 }, { 300, 20 }, indexed, 2, 4)), { 30, 40, 50, 60 })
      lu.assertEquals(packedOf(listing.page({ 200 }, { 300, 20 }, indexed, 3, 4)), { 70, 80 })
    end,

    testTheRequestedPageIsKeptInRange = function()
      local indexed = { 1, 2, 3 }
      lu.assertEquals(listing.page({}, {}, indexed, 9, 2).page, 2)
      lu.assertEquals(listing.page({}, {}, indexed, 0, 2).page, 1)
    end,

    testNothingToShowIsOneEmptyPage = function()
      local page = listing.page({}, {}, nil, 1, 20)
      lu.assertEquals({ page.total, page.pages, page.page, #page.items }, { 0, 1, 1, 0 })
    end,

    testDiscoveredOnlyWhileTheIndexIsNotReady = function()
      local page = listing.page({}, { 5, 6 }, nil, 1, 20)
      lu.assertEquals(packedOf(page), { 5, 6 })
    end,
  },

  TestRecipeLists = {
    testFavoritesAreFilteredByVisibilityAndSkipUnknownInputs = function()
      local rec = record.new("W")
      local index = {
        recipes = function()
          return { 99 }
        end,
      }
      rec:addDiscovered("advanced", { "A", "B" }, "P", "filter")
      rec:toggleFavorite("advanced", { "B", "A" }, "P") -- discovered
      rec:toggleFavorite("advanced", { "C", "D" }, "P") -- not discovered
      rec:toggleFavorite("advanced", { "A", "Gone" }, "P") -- an input the catalog no longer has
      rec:toggleFavorite("normal", { "A", "B", "C" }, "P") -- another mode
      local favorites, discovered, indexed = listing.recipeLists(rec, catalog, index, "advanced", "P")
      lu.assertEquals(favorites, { indexModule.pack(1, 2) })
      lu.assertEquals(discovered, { indexModule.pack(1, 2) })
      lu.assertNil(indexed)
      rec:unlock("P") -- everything of P is shown: the second favorite too
      favorites, discovered, indexed = listing.recipeLists(rec, catalog, index, "advanced", "P")
      lu.assertEquals(favorites, { indexModule.pack(1, 2), indexModule.pack(3, 4) })
      lu.assertEquals({ #discovered, indexed[1] }, { 1, 99 })
      rec:lock("P") -- locked: nothing of P is shown, favorites included
      favorites, discovered = listing.recipeLists(rec, catalog, index, "advanced", "P")
      lu.assertEquals({ #favorites, #discovered }, { 0, 0 })
    end,
  },

  TestFavoriteGroups = {
    testGroupedByProductNameThenIngredientsAndUnknownLeftOut = function()
      local rec = record.new("W")
      rec:unlockAll()
      rec:toggleFavorite("advanced", { "C", "D" }, "Zinc")
      rec:toggleFavorite("advanced", { "A", "C" }, "Zinc")
      rec:toggleFavorite("advanced", { "B", "D" }, "Brass")
      rec:toggleFavorite("advanced", { "A", "Gone" }, "Brass") -- not an ingredient now
      rec:toggleFavorite("normal", { "A", "B", "C" }, "Brass") -- another mode
      local groups = listing.favoriteGroups(rec, catalog, "advanced", display)
      lu.assertEquals(#groups, 2)
      lu.assertEquals(groups[1].product, "Brass")
      lu.assertEquals(groups[1].recipes, { indexModule.pack(2, 4) })
      lu.assertEquals(groups[2].product, "Zinc")
      lu.assertEquals(groups[2].recipes, { indexModule.pack(1, 3), indexModule.pack(3, 4) })
    end,

    testPagesCountRecipesAndRepeatATitleAcrossAPageBreak = function()
      local groups = {
        { product = "Brass", recipes = { 1, 2, 3 } },
        { product = "Zinc", recipes = { 4, 5 } },
      }
      local first = listing.favoritePage(groups, 1, 4, 2)
      lu.assertEquals({ first.total, first.pages }, { 5, 2 })
      lu.assertEquals(first.rows, {
        { title = "Brass" },
        { recipes = { 1, 2 }, product = "Brass" },
        { recipes = { 3 }, product = "Brass" },
        { title = "Zinc" },
        { recipes = { 4 }, product = "Zinc" },
      })
      lu.assertEquals(listing.favoritePage(groups, 2, 4, 2).rows, {
        { title = "Zinc" },
        { recipes = { 5 }, product = "Zinc" },
      })
      lu.assertEquals(listing.favoritePage(groups, 9, 4, 2).page, 2)
      lu.assertEquals(listing.favoritePage({}, 1, 4, 2), { total = 0, pages = 1, page = 1, rows = {} })
    end,
  },
}
