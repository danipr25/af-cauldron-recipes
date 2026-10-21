-- Finds the recipes the player sets on their cauldrons and adds them to the world's record. Game-facing: checked in
-- game. The calls used are listed in docs/game-data.md ("Detecting the recipes on the player's cauldrons").
local catalog = require("catalog")

local discover = {}

local Discover = {}
Discover.__index = Discover

-- The two cauldron kinds. `class` is the Blueprint class, `slots` how many ingredients it takes.
local KINDS = {
  { class = "BP_PewterCauldron_C", mode = "normal", slots = 3 },
  { class = "BP_SilverCauldron_C", mode = "advanced", slots = 2 },
}
local FILTER_HOOK = "/Script/BeltTD.CauldronFacilityComponent:NetCommandSetFilterName"
local INVENTORY_HOOK = "/Script/BeltTD.CauldronFacilityComponent:OnInventoryUpdate"

-- Unverified in game: for a cauldron whose slots have no filter, take the recipe from the items it holds when its
-- inventory changes. It ships off until the in-game test shows how often the hook fires and that it records right.
local DETECT_FROM_ITEMS = false

-- Scans of the placed cauldrons after a world is entered: they may not exist for a few seconds.
local SCAN_DELAYS_MS = { 1000, 3000, 6000, 10000 }

local text = catalog.text

local function isValid(object)
  if object == nil then
    return false
  end
  local ok, valid = pcall(function()
    return object:IsValid()
  end)
  return ok and valid == true
end

local function isUnset(name)
  return name == nil or name == "" or name == "None"
end

-- deps:
--   api: the AF Mod Loader API handle
--   log(text)
--   session: the session (session.lua)
--   later(ms, fn): runs fn on the game thread later
--   onChange(): the record changed and was saved: refresh the page
function discover.new(deps)
  local self = setmetatable({}, Discover)
  self.deps = deps
  self.warned = {}
  self.tabScanGeneration = nil
  self.hooked = false
  return self
end

function Discover:warnOnce(key, message)
  if not self.warned[key] then
    self.warned[key] = true
    self.deps.log(message)
  end
end

-- Records one recipe. `source` is "load", "filter" or "crafting". Returns true when the record changed.
function Discover:record(rec, mode, inputs, source)
  local product = catalog.productOfNames(inputs)
  if not product then
    self:warnOnce("noproduct", "the game gave no product for a cauldron recipe, so it was not recorded")
    return false
  end
  return rec:addDiscovered(mode, inputs, product, source)
end

-- Saves and refreshes the page after something was added.
function Discover:finish(changed)
  if changed then
    self.deps.session:save()
    self.deps.onChange()
  end
end

-- The filters of one cauldron's slots as item names, from the component, or nil when a slot has none. `overrideSlot`
-- (counted from 1) and `overrideName` replace what the component says for one slot: the hook gives the slot that
-- just changed.
local function readSlots(component, wanted, overrideSlot, overrideName)
  local slots = component.FacilityContainer.Slots
  if #slots ~= wanted then
    return nil
  end
  local names = {}
  for slot = 1, wanted do
    local name
    if slot == overrideSlot then
      name = overrideName
    else
      name = text(slots[slot].SlotFilterName)
      if isUnset(name) and DETECT_FROM_ITEMS then
        local itemName = text(slots[slot].ItemName)
        if not isUnset(itemName) and (tonumber(slots[slot].ItemStack) or 0) > 0 then
          name = itemName
        end
      end
    end
    if isUnset(name) then
      return nil
    end
    names[slot] = name
  end
  return names
end

-- Looks at every placed cauldron. Returns true when the record changed.
function Discover:scan(source)
  local world, rec = self.deps.session:current()
  if not world or not rec or rec.readOnly then
    return false
  end
  local changed = false
  local stateWorld = nil
  local state = FindFirstOf("BP_BeltTDGameState_C")
  if isValid(state) then
    local ok, value = pcall(function()
      return state:GetWorld():GetAddress()
    end)
    stateWorld = ok and value or nil
  end
  if stateWorld == nil then
    self:warnOnce("world", "cannot tell which world a cauldron belongs to, so every cauldron found is used")
  end
  for _, kind in ipairs(KINDS) do
    for _, actor in ipairs(FindAllOf(kind.class) or {}) do
      local ok, problem = pcall(function()
        if not isValid(actor) or actor:GetFName():ToString():find("Default__", 1, true) then
          return
        end
        if stateWorld ~= nil then
          local same, address = pcall(function()
            return actor:GetWorld():GetAddress()
          end)
          if same and address ~= stateWorld then
            return
          end
        end
        local inputs = readSlots(actor.CauldronFacility, kind.slots)
        if inputs and self:record(rec, kind.mode, inputs, source) then
          changed = true
        end
      end)
      if not ok then
        self:warnOnce("scan", "could not read a cauldron (" .. tostring(problem) .. ")")
      end
    end
  end
  return changed
end

-- A world was entered and its record is ready: scan a few times in the next seconds, because the cauldrons may not
-- exist yet. Each scan checks that the same world is still loaded.
function Discover:scanSoon(world)
  local generation = world.generation
  for _, delay in ipairs(SCAN_DELAYS_MS) do
    self.deps.later(delay, function()
      local now = self.deps.api.world.current()
      if now and now.generation == generation then
        self:finish(self:scan("load"))
      end
    end)
  end
end

-- The tab page is being built: scan once per world entry, so the page is right even if the delayed scans have not
-- run yet. The page is being built right now and will show what was found, so only the file is written.
function Discover:onTabBuild(world)
  if self.tabScanGeneration == world.generation then
    return
  end
  self.tabScanGeneration = world.generation
  if self:scan("load") then
    self.deps.session:save()
  end
end

-- Finds which cauldron kind a component belongs to, by its owner's name. Returns the kind, or nil.
function Discover:kindOf(component)
  local owner = component:GetOwner():GetFName():ToString()
  for _, kind in ipairs(KINDS) do
    if owner:sub(1, #kind.class) == kind.class then
      return kind
    end
  end
  self:warnOnce("owner", "a cauldron has an unexpected name (" .. owner .. "), so its recipe was not recorded")
  return nil
end

function Discover:onFilterChanged(component, slotNumber, filter)
  local world, rec = self.deps.session:current()
  if not world or not rec or rec.readOnly then
    return
  end
  local kind = self:kindOf(component)
  if not kind then
    return
  end
  -- The hook gives the slot counted from 0; the other slots come from the component.
  local names = readSlots(component, kind.slots, slotNumber + 1, text(filter))
  if names then
    self:finish(self:record(rec, kind.mode, names, "filter"))
  end
end

function Discover:onInventoryUpdate(component)
  local world, rec = self.deps.session:current()
  if not world or not rec or rec.readOnly then
    return
  end
  local kind = self:kindOf(component)
  if not kind then
    return
  end
  local names = readSlots(component, kind.slots)
  if names then
    self:finish(self:record(rec, kind.mode, names, "crafting"))
  end
end

-- Registers the game hooks. The filter hook is the mod's only own hook; the inventory one is registered only when
-- DETECT_FROM_ITEMS is on. Safe to call again: it registers once. Returns true when registered.
function Discover:install()
  if self.hooked then
    return true
  end
  local function guard(name, fn)
    return function(...)
      local ok, problem = pcall(fn, ...)
      if not ok then
        self:warnOnce("hook-" .. name, "the " .. name .. " hook failed (" .. tostring(problem) .. ")")
      end
    end
  end
  local function nothing() end
  local ok, problem = pcall(
    RegisterHook,
    FILTER_HOOK,
    nothing,
    guard("filter", function(context, slot, filter)
      self:onFilterChanged(context:get(), slot:get(), filter:get())
    end)
  )
  if not ok then
    self:warnOnce(
      "register",
      "could not watch cauldron filters yet (" .. tostring(problem) .. "). New recipes are found again at the next load"
    )
    return false
  end
  if DETECT_FROM_ITEMS then
    local inventoryOk, inventoryProblem = pcall(
      RegisterHook,
      INVENTORY_HOOK,
      nothing,
      guard("inventory", function(context)
        self:onInventoryUpdate(context:get())
      end)
    )
    if not inventoryOk then
      self:warnOnce("register-inventory", "could not watch cauldron inventories (" .. tostring(inventoryProblem) .. ")")
    end
  end
  self.hooked = true
  return true
end

return discover
