-- Contract of item matching for the console commands: which item a player means.
local lu = require("luaunit")
local names = require("names")

local LOCALIZED = {
  Wood = "Wood",
  Gentian = "Gentian",
  Clay = "Clay",
  GoldDust5 = "Gold Dust",
  GoldDust3 = "Gold Dust",
  GentianNectar = "Gentian Nectar",
  Salve = "Salve",
}
local PRODUCTS = { Clay = true, GoldDust5 = true, GoldDust3 = true, GentianNectar = true }
local source = {
  items = { "Wood", "Gentian", "Clay", "GoldDust5", "GoldDust3", "GentianNectar", "Salve" },
  display = function(name)
    return LOCALIZED[name]
  end,
  isProduct = function(name)
    return PRODUCTS[name] == true
  end,
}

return {
  TestNames = {
    testTheExactInternalNameWins = function()
      lu.assertEquals(names.resolve("Clay", source), "Clay")
      lu.assertEquals(names.resolve("clay", source), "Clay") -- case is ignored
      -- "Gentian" is also part of "GentianNectar", but the exact name wins (and it is not a product).
      lu.assertEquals({ names.resolve("Gentian", source) }, { nil, "not-product", "Gentian" })
    end,

    testTheExactLocalizedNameIsNext = function()
      lu.assertEquals(names.resolve("gentian nectar", source), "GentianNectar")
    end,

    testPartOfAName = function()
      lu.assertEquals(names.resolve("nectar", source), "GentianNectar")
      lu.assertEquals(names.resolve("lay", source), "Clay")
    end,

    testRepeatedLocalizedNamesAreAmbiguous = function()
      lu.assertEquals({ names.resolve("Gold Dust", source) }, { nil, "ambiguous", { "GoldDust5", "GoldDust3" } })
      lu.assertEquals(names.resolve("GoldDust5", source), "GoldDust5") -- the internal name settles it
    end,

    testAnItemNoCauldronMakes = function()
      lu.assertEquals({ names.resolve("Salve", source) }, { nil, "not-product", "Salve" })
    end,

    testUnknownAndEmpty = function()
      lu.assertEquals({ names.resolve("unicorn", source) }, { nil, "unknown" })
      lu.assertEquals({ names.resolve("", source) }, { nil, "empty" })
    end,

    testOnlyAsciiLettersAreFolded = function()
      lu.assertEquals(names.fold("Gold DUST"), "gold dust")
      lu.assertEquals(names.fold("\195\137"), "\195\137") -- a letter outside ASCII is left as it is
    end,
  },
}
