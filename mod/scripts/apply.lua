-- Sets a recipe on the cauldron whose panel is open, when the player clicks "Use". The only thing the mod changes in
-- the game world, and only through the game's own CauldronFacilityComponent:NetCommandSetFilterName, the call the
-- game makes when the player picks a filter (see the README and docs/game-data.md). The plan is pure Lua
-- (tests/test_apply.lua); the flow around it takes the game objects from its caller.
local apply = {}

local Applier = {}
Applier.__index = Applier

local NONE = "None"

-- The slots of a cauldron component as a plain Lua list of { filter = name or nil, items = number }. The game's array
-- is indexed from 1 to its length: iterating it with ipairs crashed the game. `text(value)` turns an FName into text.
function apply.readSlots(component, text)
  local slots = component.FacilityContainer.Slots
  local list = {}
  for number = 1, #slots do
    local slot = slots[number]
    local filter = text(slot.SlotFilterName)
    if filter == "" or filter == NONE then
      filter = nil
    end
    list[number] = { filter = filter, items = tonumber(slot.ItemStack) or 0 }
  end
  return list
end

-- What to do to make the slots hold the recipe `inputs` (item names, in any order).
-- Slots whose filter already is one of the inputs stay as they are (the order of the filters does not matter, each
-- input is used once). The others change: first the ones that have a filter are cleared, then every one is set, so
-- only the last call can complete the recipe and the game never sees a half-changed one as a recipe.
-- Returns { ok = false, reason = "slots" } when the slot count is not the recipe's size, { ok = true, same = true }
-- when nothing needs to change, or
-- { ok = true, clear = { slot, ... }, set = { { slot, name }, ... }, items = n, held = m } with
-- slots counted from 0 (as the game's call takes them), `items` the number of items in the changing slots and `held`
-- the number in all slots (only written to the log).
function apply.plan(slots, inputs)
  if #slots ~= #inputs then
    return { ok = false, reason = "slots" }
  end
  local wanted = {}
  for _, name in ipairs(inputs) do
    wanted[name] = (wanted[name] or 0) + 1
  end
  local changing = {}
  for number, slot in ipairs(slots) do
    if slot.filter and (wanted[slot.filter] or 0) > 0 then
      wanted[slot.filter] = wanted[slot.filter] - 1
    else
      changing[#changing + 1] = number
    end
  end
  if #changing == 0 then
    return { ok = true, same = true }
  end
  local missing = {}
  for _, name in ipairs(inputs) do
    if wanted[name] > 0 then
      wanted[name] = wanted[name] - 1
      missing[#missing + 1] = name
    end
  end
  local plan = { ok = true, clear = {}, set = {}, items = 0, held = 0 }
  for _, slot in ipairs(slots) do
    plan.held = plan.held + slot.items
  end
  for place, number in ipairs(changing) do
    if slots[number].filter then
      plan.clear[#plan.clear + 1] = number - 1
    end
    plan.set[#plan.set + 1] = { number - 1, missing[place] }
    plan.items = plan.items + slots[number].items
  end
  return plan
end

local function joined(inputs)
  return table.concat(inputs, ", ")
end

-- deps:
--   api: the AF Mod Loader API handle (api.defer)
--   log(text)
--   text(value): the text of an FName
--   fname(text): makes an FName
function apply.new(deps)
  return setmetatable({ deps = deps }, Applier)
end

-- Runs `fn` deferred, unless work for this panel open (`info`) is already waiting or running: a burst of clicks
-- applies once. A new open has a new `info`.
function Applier:queue(info, fn)
  if self.busy == info then
    return
  end
  self.busy = info
  self.deps.api.defer(function()
    local ok, problem = pcall(fn)
    if self.busy == info then
      self.busy = nil
    end
    if not ok then
      error(problem, 0)
    end
  end)
end

-- The player clicked Use on `entry` ({ product, inputs }). `info` is the panel's info (API panels.tab); `ui` has
-- message(text) (tell the player).
-- Nothing touches the game inside the click: the work is deferred and starts by checking the panel is still open.
function Applier:request(info, mode, entry, ui)
  self:queue(info, function()
    self:run(info, mode, entry, ui)
  end)
end

function Applier:fail(ui, why, detail, shown)
  self.deps.log("could not set the recipe on the cauldron: " .. why .. (detail and (" (" .. detail .. ")") or ""))
  ui.message(shown or "The recipe could not be set. See UE4SS.log.")
end

function Applier:run(info, mode, entry, ui)
  if not info.isCurrent() then
    return
  end
  local deps = self.deps
  local component = info.component
  if component == nil then
    return self:fail(ui, "the cauldron could not be read")
  end
  -- Read now: the slots may have changed since the page was built.
  local read, slots = pcall(apply.readSlots, component, deps.text)
  if not read then
    return self:fail(ui, "the cauldron could not be read", tostring(slots))
  end
  local plan = apply.plan(slots, entry.inputs)
  if not plan.ok then
    local message = string.format("This cauldron has %d slots, not %d. Nothing was changed.", #slots, #entry.inputs)
    deps.log("did not set the recipe: " .. message)
    ui.message(message)
    return
  end
  if plan.same then
    ui.message("That recipe is already set on this cauldron.")
    return
  end
  local calls = {}
  for _, slot in ipairs(plan.clear) do
    calls[#calls + 1] = { slot, NONE }
  end
  for _, call in ipairs(plan.set) do
    calls[#calls + 1] = call
  end
  for _, call in ipairs(calls) do
    local ok, problem = pcall(function()
      component:NetCommandSetFilterName(call[1], deps.fname(call[2]))
    end)
    if not ok then
      self:fail(
        ui,
        "the cauldron may be partly changed, check its filters",
        tostring(problem),
        "Cauldron may be partly set. Check it."
      )
      return
    end
  end
  deps.log(
    string.format(
      "set the recipe %s on a %s cauldron by the player's click (%s)",
      joined(entry.inputs),
      mode,
      plan.held > 0 and (plan.held .. " items were in the cauldron") or "it held no items"
    )
  )
  info.showGame()
end

return apply
