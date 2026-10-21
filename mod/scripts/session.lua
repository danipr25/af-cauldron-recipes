-- Holds what the mod knows while the game runs: the loaded world, its record, the item catalog and the recipe index,
-- and wires them together when a world is entered. Game-facing glue: checked in game.
local catalogModule = require("catalog")
local indexModule = require("index")

local session = {}

local Session = {}
Session.__index = Session

local CATALOG_TRIES = 6

-- Runs `fn` on the game thread after `ms` milliseconds.
function session.later(ms, fn)
  ExecuteWithDelay(ms, function()
    ExecuteInGameThread(fn)
  end)
end

-- deps:
--   api: the AF Mod Loader API handle
--   log(text)
--   store: a store (store.lua)
--   onReady(world): the catalog and the record are ready for this world (look for the cauldrons now)
--   onRefresh(): something shown on the page changed
--   onProgress(percent): the index advanced
function session.new(deps)
  local self = setmetatable({}, Session)
  self.deps = deps
  self.world = nil
  self.record = nil
  self.catalog = nil
  self.index = nil
  self.recordStatus = nil
  return self
end

-- The current world and its record, or nil when no world is loaded (or its record is not loaded yet).
function Session:current()
  local now = self.deps.api.world.current()
  if not now or not self.world or now.generation ~= self.world.generation or not self.record then
    return nil
  end
  return now, self.record
end

-- Writes the record of the current world when it changed. Returns true when it was written.
function Session:save()
  if not self.world or not self.record then
    return false
  end
  return self.deps.store:save(self.world.key, self.record)
end

-- A world was entered (api.world.onEnter).
function Session:enter(world)
  local log = self.deps.log
  self.world = world
  self.record, self.recordStatus = self.deps.store:load(world.key, world.title)
  log(string.format("world '%s': record %s", world.title, self.recordStatus))
  if self.index then
    self.index:resume()
  end
  self:prepare(world.generation, 1)
end

function Session:isCurrent(generation)
  local now = self.deps.api.world.current()
  return now ~= nil and now.generation == generation
end

-- Reads the item table (the game may need a moment after a load), keeps the catalog and the index, checks the
-- record against the game's data, and tells the rest of the mod.
function Session:prepare(generation, attempt)
  if not self:isCurrent(generation) then
    return
  end
  local log = self.deps.log
  local fresh, why = catalogModule.load(log)
  if not fresh then
    if attempt >= CATALOG_TRIES then
      log("could not read the game's items (" .. tostring(why) .. "). Load the save again to retry")
      return
    end
    session.later(attempt * 1000, function()
      self:prepare(generation, attempt + 1)
    end)
    return
  end
  self:adopt(fresh)
  self:validateRecord()
  if self.index then
    self.index:start()
  end
  self.deps.onReady(self.world)
  self.deps.onRefresh()
end

-- Keeps the catalog we have when the item table is the same, otherwise starts again with the new one.
function Session:adopt(fresh)
  local log = self.deps.log
  if self.catalog and self.catalog.key == fresh.key then
    return
  end
  if self.index then
    self.index:cancel()
  end
  self.catalog = fresh
  log(
    string.format(
      "items: %d rows, %d cauldron ingredients, %d cauldron products",
      #fresh.items,
      #fresh.ingredients,
      #fresh.products
    )
  )
  log(
    string.format(
      "bHideInGame: %d item(s) have it set (%s), %d could not be read",
      #fresh.hiddenInGame,
      table.concat(fresh.hiddenInGame, ", "),
      fresh.hiddenUnreadable
    )
  )
  local api = self.deps.api
  self.index = indexModule.new({
    count = #fresh.ingredients,
    prepare = function()
      if not api.world.current() then
        return nil
      end
      return fresh.newOracle()
    end,
    schedule = function(fn)
      session.later(1, fn)
    end,
    onProgress = function(percent)
      self.deps.onProgress(percent)
    end,
    onDone = function(seconds)
      log(string.format("recipe index ready: %d combinations in %.1f s of game time", self.index.total, seconds))
      self.deps.onRefresh()
    end,
    onFail = function(problem)
      log("could not build the recipe index (" .. problem .. "). Recipes that were not discovered will not be listed")
    end,
  })
end

-- Marks the record's entries that use items the game no longer has, and refreshes their products.
function Session:validateRecord()
  local record, catalog = self.record, self.catalog
  if not record or not catalog then
    return
  end
  local oracle = catalog.newOracle()
  local changed, unknown = record:revalidate(function(name)
    return catalog.ingredientIndex[name] ~= nil
  end, function(name)
    return catalog.productSet[name] == true
  end, function(mode, inputs)
    if not oracle then
      return nil
    end
    local indexes = {}
    for position, name in ipairs(inputs) do
      indexes[position] = catalog.ingredientIndex[name]
    end
    local ok, product = pcall(oracle, mode, indexes[1], indexes[2], indexes[3])
    return ok and product or nil
  end)
  if unknown > 0 then
    self.deps.log(
      string.format("%d saved recipe(s) use items this version of the game does not have: kept, but not shown", unknown)
    )
  end
  if changed then
    self.deps.log("some saved recipes now give a different product in the game: the record was updated")
    self:save()
  end
end

return session
