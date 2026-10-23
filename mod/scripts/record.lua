-- The mod's own record for one world: which recipes the player has seen on their cauldrons ("discovered"), which
-- recipes are shown or hidden, and which recipes the player starred ("favorites").
-- Pure Lua with no game access, so it is tested without the game (tests/test_record.lua).
-- The rules are listed in the README (what the commands do).
local record = {}

-- Version 2 added the favorites. A mod that only knows version 1 would drop the field when it writes, so it treats a
-- version 2 file as written by a newer mod and leaves it alone (read only).
record.VERSION = 2
record.SLOTS = { normal = 3, advanced = 2 } -- ingredients per cauldron: Normal 3, Advanced 2

local Record = {}
Record.__index = Record

local function sortedCopy(list)
  local copy = {}
  for index, value in ipairs(list) do
    copy[index] = value
  end
  table.sort(copy)
  return copy
end

local function keysOf(set)
  local list = {}
  for name in pairs(set) do
    list[#list + 1] = name
  end
  table.sort(list)
  return list
end

local function keyOf(mode, sortedInputs)
  return mode .. "|" .. table.concat(sortedInputs, ",")
end

local function count(set)
  local total = 0
  for _ in pairs(set) do
    total = total + 1
  end
  return total
end

-- An empty record for the world with this title.
function record.new(title)
  return setmetatable({
    world = title,
    discovered = {}, -- entries { mode, inputs (sorted), product, seen }, in the order they were found
    byKey = {},
    favorites = {}, -- entries { mode, inputs (sorted), product }, in the order starred (product: display only)
    favByKey = {},
    all = false,
    unlocked = {}, -- sets of product names
    locked = {},
    hidden = {},
    readOnly = nil, -- nil, or why this record must not be written: "newer" or "other-world"
  }, Record)
end

local function readList(value)
  if value == nil then
    return {}
  end
  if type(value) ~= "table" then
    return nil
  end
  local set = {}
  for _, name in ipairs(value) do
    if type(name) ~= "string" then
      return nil
    end
    set[name] = true
  end
  return set
end

-- Is this decoded recipe entry well formed? Returns nil, or why not.
local function checkEntry(entry)
  if type(entry) ~= "table" or record.SLOTS[entry.mode] == nil or type(entry.product) ~= "string" then
    return "bad recipe entry"
  end
  if type(entry.inputs) ~= "table" or #entry.inputs ~= record.SLOTS[entry.mode] then
    return "bad recipe inputs"
  end
  for _, name in ipairs(entry.inputs) do
    if type(name) ~= "string" then
      return "bad recipe inputs"
    end
  end
  return nil
end

-- Builds a record from decoded file data. Returns the record, or nil and why the data is not usable.
function record.decode(data, title)
  if type(data) ~= "table" then
    return nil, "not a table"
  end
  if data.version ~= 1 and data.version ~= record.VERSION then
    return nil, "unknown version"
  end
  if type(data.world) ~= "string" then
    return nil, "no world name"
  end
  if data.all ~= nil and type(data.all) ~= "boolean" then
    return nil, "bad 'all'"
  end
  local self = record.new(title or data.world)
  self.all = data.all == true
  for field, target in pairs({ unlocked = "unlocked", locked = "locked", hiddenProducts = "hidden" }) do
    local set = readList(data[field])
    if not set then
      return nil, "bad list '" .. field .. "'"
    end
    self[target] = set
  end
  for _, field in ipairs({ "discovered", "favorites" }) do
    if data[field] ~= nil and type(data[field]) ~= "table" then
      return nil, "bad list '" .. field .. "'"
    end
  end
  for _, entry in ipairs(data.discovered or {}) do
    local problem = checkEntry(entry)
    if problem then
      return nil, problem
    end
    self:addEntry(entry.mode, entry.inputs, entry.product, type(entry.seen) == "string" and entry.seen or "load")
  end
  -- Version 1 had no favorites.
  for _, entry in ipairs(data.version >= 2 and data.favorites or {}) do
    local problem = checkEntry(entry)
    if problem then
      return nil, problem
    end
    self:addFavorite(entry.mode, entry.inputs, entry.product)
  end
  return self
end

-- The plain table that is written to the file (dense lists only, no transient fields).
function Record:toTable()
  local discovered = {}
  for index, entry in ipairs(self.discovered) do
    discovered[index] =
      { mode = entry.mode, inputs = sortedCopy(entry.inputs), product = entry.product, seen = entry.seen }
  end
  local favorites = {}
  for index, entry in ipairs(self.favorites) do
    favorites[index] = { mode = entry.mode, inputs = sortedCopy(entry.inputs), product = entry.product }
  end
  return {
    version = record.VERSION,
    world = self.world,
    discovered = discovered,
    favorites = favorites,
    all = self.all,
    unlocked = keysOf(self.unlocked),
    locked = keysOf(self.locked),
    hiddenProducts = keysOf(self.hidden),
  }
end

-- Adds an entry without looking at visibility. Returns the entry and whether it is new.
function Record:addEntry(mode, inputs, product, seen)
  local sorted = sortedCopy(inputs)
  local key = keyOf(mode, sorted)
  local entry = self.byKey[key]
  if entry then
    return entry, false
  end
  entry = { mode = mode, inputs = sorted, product = product, seen = seen }
  self.discovered[#self.discovered + 1] = entry
  self.byKey[key] = entry
  return entry, true
end

-- Adds a favorite without looking at visibility. Returns the entry and whether it is new.
function Record:addFavorite(mode, inputs, product, at)
  local sorted = sortedCopy(inputs)
  local key = keyOf(mode, sorted)
  local entry = self.favByKey[key]
  if entry then
    return entry, false
  end
  entry = { mode = mode, inputs = sorted, product = product }
  table.insert(self.favorites, math.min(at or #self.favorites + 1, #self.favorites + 1), entry)
  self.favByKey[key] = entry
  return entry, true
end

function Record:isFavorite(mode, inputs)
  return self.favByKey[keyOf(mode, sortedCopy(inputs))] ~= nil
end

-- Stars the recipe, or takes the star away. `product` is only kept for display. Returns whether it is a favorite now,
-- and, when the star was taken away, the position the favorite had (pass it to addFavorite to put it back).
function Record:toggleFavorite(mode, inputs, product)
  local key = keyOf(mode, sortedCopy(inputs))
  local entry = self.favByKey[key]
  if not entry then
    self:addFavorite(mode, inputs, product)
    return true
  end
  self.favByKey[key] = nil
  local position
  for index, candidate in ipairs(self.favorites) do
    if candidate == entry then
      position = index
      table.remove(self.favorites, index)
      break
    end
  end
  return false, position
end

-- Is this favorite shown? Only when its recipe would be shown anyway: discovered with its product's discovered
-- recipes shown, or its product's other recipes shown. A locked recipe keeps its star, hidden until it is shown again.
function Record:favoriteVisible(entry)
  if entry.unknown then
    return false
  end
  local seen = self.byKey[keyOf(entry.mode, entry.inputs)]
  if seen and not seen.unknown and self:discoveredVisible(entry.product) then
    return true
  end
  return self:otherVisible(entry.product)
end

-- The visible favorites of this mode (and of this product, when given), in the order they were starred.
function Record:favoritesFor(mode, product)
  local list = {}
  for _, entry in ipairs(self.favorites) do
    if entry.mode == mode and (product == nil or entry.product == product) and self:favoriteVisible(entry) then
      list[#list + 1] = entry
    end
  end
  return list
end

-- The entry of this recipe, or nil.
function Record:find(mode, inputs)
  return self.byKey[keyOf(mode, sortedCopy(inputs))]
end

-- Records that the player set this recipe on a cauldron. `seen` is "filter" (the player changed a filter),
-- "crafting" or "load" (found when the world was loaded). Only the first two bring a hidden product back, so a
-- load never undoes a lock. Returns true when anything changed (and so the file must be written).
function Record:addDiscovered(mode, inputs, product, seen)
  local entry, added = self:addEntry(mode, inputs, product, seen)
  local changed = added
  if entry.product ~= product then
    entry.product = product
    changed = true
  end
  if seen ~= "load" and self.hidden[product] then
    self.hidden[product] = nil
    changed = true
  end
  return changed
end

-- Entries of this mode and product that are in the current game data (see revalidate), in the order found.
function Record:discoveredFor(mode, product)
  local list = {}
  for _, entry in ipairs(self.discovered) do
    if entry.mode == mode and entry.product == product and not entry.unknown then
      list[#list + 1] = entry
    end
  end
  return list
end

function Record:hasDiscovered(mode, product)
  for _, entry in ipairs(self.discovered) do
    if entry.mode == mode and entry.product == product and not entry.unknown then
      return true
    end
  end
  return false
end

-- Are the discovered recipes of this product shown?
function Record:discoveredVisible(product)
  return not self.hidden[product]
end

-- Are the recipes of this product that were not discovered shown?
function Record:otherVisible(product)
  return self.unlocked[product] == true or (self.all and not self.locked[product])
end

-- Can recipes that were not discovered be shown for some product?
function Record:anyUnlocked()
  return self.all or next(self.unlocked) ~= nil
end

-- Marks which entries (discovered and favorites) use names that the current game data no longer has (they stay in
-- the file, and are not shown), and refreshes the stored product of the others. `known(name)` says whether an item
-- is a cauldron ingredient now, `knownProduct(name)` whether it can be a product, and `oracle(mode, inputs)` is the
-- game's own answer (or nil). Returns whether any stored product changed, how many discovered entries are not shown,
-- and how many favorites are not shown.
function Record:revalidate(known, knownProduct, oracle)
  local changed = false
  local function check(list)
    local unknown = 0
    for _, entry in ipairs(list) do
      local usable = knownProduct(entry.product)
      for _, name in ipairs(entry.inputs) do
        usable = usable and known(name)
      end
      if usable then
        entry.unknown = nil
        local product = oracle(entry.mode, entry.inputs)
        if product and product ~= entry.product and knownProduct(product) then
          entry.product = product
          changed = true
        end
      else
        entry.unknown = true
        unknown = unknown + 1
      end
    end
    return unknown
  end
  local unknown = check(self.discovered)
  local unknownFavorites = check(self.favorites)
  return changed, unknown, unknownFavorites
end

-- Console commands. Each one changes the record and says nothing; the caller compares snapshots to tell the player
-- whether anything visible changed.

function Record:unlockAll()
  self.all = true
  self.locked = {}
  self.hidden = {}
end

function Record:lockAll()
  self.all = false
  self.unlocked = {}
  self.locked = {}
  self.hidden = {}
  for _, entry in ipairs(self.discovered) do
    self.hidden[entry.product] = true
  end
end

function Record:safeLockAll()
  self.all = false
  self.unlocked = {}
  self.locked = {}
  self.hidden = {}
end

function Record:unlock(product)
  self.locked[product] = nil
  self.hidden[product] = nil
  self.unlocked[product] = true
end

function Record:lock(product)
  self.locked[product] = true
  self.hidden[product] = true
  self.unlocked[product] = nil
end

function Record:safeLock(product)
  self.locked[product] = true
  self.unlocked[product] = nil
  self.hidden[product] = nil
end

-- What is shown for each product, as a number: 1 when its discovered recipes are shown, 2 when its other recipes
-- are shown. `products` lists the products to look at; discovered ones are always included.
function Record:snapshot(products)
  local snapshot = {}
  local withDiscovered = {}
  for _, entry in ipairs(self.discovered) do
    if not entry.unknown then
      withDiscovered[entry.product] = true
    end
  end
  local function look(product)
    local value = 0
    if withDiscovered[product] and self:discoveredVisible(product) then
      value = value + 1
    end
    if self:otherVisible(product) then
      value = value + 2
    end
    snapshot[product] = value
  end
  for _, product in ipairs(products) do
    look(product)
  end
  for product in pairs(withDiscovered) do
    look(product)
  end
  return snapshot
end

-- True when the two snapshots differ in what a player would see.
function record.visibleChanged(before, after)
  for product, value in pairs(before) do
    if after[product] ~= value then
      return true
    end
  end
  for product, value in pairs(after) do
    if before[product] ~= value then
      return true
    end
  end
  return false
end

-- A text that is the same for two records with the same stored settings (not the discovered list): tells whether a
-- command changed anything.
function Record:signature()
  local t = self:toTable()
  return table.concat({
    tostring(t.all),
    table.concat(t.unlocked, ","),
    table.concat(t.locked, ","),
    table.concat(t.hiddenProducts, ","),
  }, "|")
end

-- Numbers for recipes.status.
function Record:counts()
  local total, hiddenCount = 0, 0
  for _, entry in ipairs(self.discovered) do
    if not entry.unknown then
      total = total + 1
      if self.hidden[entry.product] then
        hiddenCount = hiddenCount + 1
      end
    end
  end
  return {
    discovered = total,
    discoveredHidden = hiddenCount,
    unlocked = count(self.unlocked),
    locked = count(self.locked),
    all = self.all,
  }
end

return record
