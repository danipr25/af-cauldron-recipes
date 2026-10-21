-- What the game says about cauldron items, read at runtime: the ingredients and products from the item table, the
-- localized names, and the game's own answer for any combination. Game-facing: checked in game, see docs/game-data.md
-- for the calls and how they were verified. No recipe rule is written here.
local catalog = {}

-- Unverified in game: the table row has a `bHideInGame` flag (header dump). When true, items the game hides are left
-- out. It ships off until the in-game test shows what the flag means (the log lists the items that have it).
local EXCLUDE_HIDDEN = false

local GAME_STATE = "BP_BeltTDGameState_C"
local LIBRARY = "/Game/Blueprints/Core/BP_BeltTDFunctionLib.Default__BP_BeltTDFunctionLib_C"

local function isValid(object)
  if object == nil then
    return false
  end
  local ok, valid = pcall(function()
    return object:IsValid()
  end)
  return ok and valid == true
end

-- The text of an FName, FString or string, or nil when there is none (never the string "nil").
local function text(value)
  if value == nil then
    return nil
  end
  local ok, result = pcall(function()
    return value:ToString()
  end)
  if ok and type(result) == "string" then
    return result
  end
  if type(value) == "string" then
    return value
  end
  return nil
end
catalog.text = text

local function number(value)
  return tonumber(value) or tonumber(tostring(value))
end

-- The game state is kept for the session and looked up again only when it is no longer valid.
local cachedState = nil
local function gameState()
  if isValid(cachedState) then
    return cachedState
  end
  local state = FindFirstOf(GAME_STATE)
  if isValid(state) then
    cachedState = state
    return state
  end
  cachedState = nil
  return nil
end

-- The game's own product for these item names, or nil. Raises if the game call fails.
local function productOf(state, names)
  local list = {}
  for index, name in ipairs(names) do
    list[index] = FName(name)
  end
  local product = text(state:GetCauldronProduct(list, {}, {}))
  if product == nil or product == "None" or product == "" then
    return nil
  end
  return product
end

-- The product of a recipe given as item names, or nil when the game cannot say (no game state, or no product).
function catalog.productOfNames(names)
  local state = gameState()
  if not state then
    return nil
  end
  local ok, product = pcall(productOf, state, names)
  if ok then
    return product
  end
  return nil
end

-- Reads the item table. Returns the catalog, or nil and why (the game state is not there yet, the table is empty).
-- log(text) is used for what a player or the developer should know.
local loadTimed = false
function catalog.load(log)
  local startedAt = os.clock()
  local state = gameState()
  if not state then
    return nil, "the game is not ready"
  end
  local ok, table_ = pcall(function()
    return state.EnemyConfig
  end)
  if not ok or not isValid(table_) then
    return nil, "the game's item table is not there"
  end

  local self = { items = {}, ingredients = {}, ingredientIndex = {}, products = {}, productSet = {} }
  local hiddenSeen, unreadable = {}, 0
  local first, last
  local read, problem = pcall(function()
    table_:ForEachRow(function(name, row)
      name = text(name)
      if name == nil then
        return
      end
      first = first or name
      last = name
      self.items[#self.items + 1] = name
      local hiddenFlag = nil
      local flagOk, flag = pcall(function()
        return row.bHideInGame
      end)
      if flagOk and type(flag) == "boolean" then
        hiddenFlag = flag
      else
        unreadable = unreadable + 1
      end
      if hiddenFlag then
        hiddenSeen[#hiddenSeen + 1] = name
      end
      if EXCLUDE_HIDDEN and hiddenFlag then
        return
      end
      if (number(row.CauldronCost) or 0) > 0 then
        self.ingredients[#self.ingredients + 1] = name
        self.ingredientIndex[name] = #self.ingredients
      end
      if (number(row.CauldronMulti) or 0) > 0 then
        self.products[#self.products + 1] = name
        self.productSet[name] = true
      end
    end)
  end)
  if not read then
    return nil, "the item table could not be read (" .. tostring(problem) .. ")"
  end
  if #self.items == 0 then
    return nil, "the item table is empty"
  end
  self.key = #self.items .. ":" .. tostring(first) .. ":" .. tostring(last)
  self.hiddenInGame = hiddenSeen
  self.hiddenUnreadable = unreadable
  if not loadTimed then
    loadTimed = true
    log(string.format("read the item table in %.0f ms", (os.clock() - startedAt) * 1000))
  end
  self.fnames = {}
  for index, name in ipairs(self.ingredients) do
    self.fnames[index] = FName(name)
  end

  -- Localized names, read when first needed and kept for the session.
  local displayCache, displayCount, displayTime = {}, 0, 0
  local library = nil
  function self.display(name)
    local cached = displayCache[name]
    if cached then
      return cached
    end
    local started = os.clock()
    local shown = name
    local shownOk, shownValue = pcall(function()
      library = library or StaticFindObject(LIBRARY)
      local out = {}
      library:GetItemDisplayName(FName(name), gameState(), out)
      return text(out.DisplayName)
    end)
    if shownOk and shownValue ~= nil and shownValue ~= "" then
      shown = shownValue
    end
    displayCache[name] = shown
    displayCount = displayCount + 1
    displayTime = displayTime + (os.clock() - started)
    if displayCount == #self.items then
      log(string.format("read the localized names of %d items in %.0f ms", displayCount, displayTime * 1000))
    end
    return shown
  end

  function self.isProduct(name)
    return self.productSet[name] == true
  end

  -- The oracle the index uses: `oracle(mode, i, j, k)` with positions in the ingredient list. Nil when the game
  -- state is not there.
  function self.newOracle()
    local game = gameState()
    if not game then
      return nil
    end
    local fnames = self.fnames
    return function(mode, i, j, k)
      local list
      if mode == "advanced" then
        list = { fnames[i], fnames[j] }
      else
        list = { fnames[i], fnames[j], fnames[k] }
      end
      local product = text(game:GetCauldronProduct(list, {}, {}))
      if product == nil or product == "None" or product == "" then
        return nil
      end
      return product
    end
  end

  return self
end

return catalog
