-- The `recipes.*` console commands. They change the world's record (see record.lua) and nothing in the save.
-- Game-facing through the AF Mod Loader API's console: checked in game.
local names = require("names")
local record = require("record")

local commands = {}

local HOW_TO_GO_BACK = " To go back: recipes.unlock <item> shows all its recipes, then recipes.safe-lock <item> keeps "
  .. "only the discovered ones."

-- deps:
--   api: the AF Mod Loader API handle
--   session: the session (session.lua)
--   onChange(): the page must be built again
function commands.install(deps)
  local api, session = deps.api, deps.session

  -- The world and record to change, or nil after telling the player why not.
  local function target(out)
    local world, rec = session:current()
    if not world or not rec then
      out("Load a save first.")
      return nil
    end
    if rec.readOnly then
      out("Recipes cannot be changed for this world (" .. rec.readOnly .. "). See UE4SS.log.")
      return nil
    end
    return rec
  end

  local function universe()
    return session.catalog and session.catalog.products or {}
  end

  -- Runs `change(rec)`, saves, refreshes the page and says what happened.
  local function apply(rec, change, message, out)
    local before = rec:snapshot(universe())
    local signature = rec:signature()
    change(rec)
    local after = rec:snapshot(universe())
    if rec:signature() ~= signature then
      session:save()
      deps.onChange()
    end
    if session.catalog and not record.visibleChanged(before, after) then
      out(message .. " Nothing that was visible changed.")
    else
      out(message)
    end
  end

  -- `recipes.<name> confirm`: asks first.
  local function confirmed(name, question, args, out)
    if #args == 0 then
      out(question .. " To do it, type: recipes." .. name .. " confirm")
      return false
    end
    if #args ~= 1 or args[1] ~= "confirm" then
      out("Type recipes." .. name .. " to see what it does, or recipes." .. name .. " confirm to do it.")
      return false
    end
    return true
  end

  -- The product named by the arguments, or nil after telling the player why not.
  local function product(args, usage, out)
    local catalog = session.catalog
    if not catalog then
      out("The game's items are not read yet. Try again in a moment.")
      return nil
    end
    if #args == 0 then
      out("Usage: " .. usage)
      return nil
    end
    local text = table.concat(args, " ")
    local found, why, extra = names.resolve(text, {
      items = catalog.items,
      display = catalog.display,
      isProduct = catalog.isProduct,
    })
    if found then
      return found
    elseif why == "ambiguous" then
      out("More than one item matches '" .. text .. "': " .. table.concat(extra, ", ") .. ". Type the exact name.")
    elseif why == "not-product" then
      out("No cauldron makes " .. text .. ".")
    else
      out("No item called '" .. text .. "'.")
    end
    return nil
  end

  api.console.add({
    name = "recipes.unlockall",
    help = "Shows every cauldron recipe in the Recipes tab, discovered or not. Asks to confirm.",
    run = function(args, out)
      local rec = target(out)
      if not rec then
        return
      end
      if confirmed("unlockall", "This shows every recipe in the Recipes tab.", args, out) then
        apply(rec, rec.unlockAll, "Every recipe is shown now.", out)
      end
    end,
  })

  api.console.add({
    name = "recipes.lockall",
    help = "Hides every recipe in the Recipes tab, also the discovered ones. The record is kept: a recipe "
      .. "you set on a cauldron again comes back. Asks to confirm."
      .. HOW_TO_GO_BACK,
    run = function(args, out)
      local rec = target(out)
      if not rec then
        return
      end
      if confirmed("lockall", "This hides every recipe, also the discovered ones.", args, out) then
        apply(rec, rec.lockAll, "Every recipe is hidden now. The record of discovered recipes is kept.", out)
      end
    end,
  })

  api.console.add({
    name = "recipes.safe-lockall",
    help = "Hides every recipe except the discovered ones. Asks to confirm.",
    run = function(args, out)
      local rec = target(out)
      if not rec then
        return
      end
      if confirmed("safe-lockall", "This hides every recipe except the discovered ones.", args, out) then
        apply(rec, rec.safeLockAll, "Only the discovered recipes are shown now.", out)
      end
    end,
  })

  -- One item: all the same shape.
  local function perItem(name, help, change, message)
    api.console.add({
      name = "recipes." .. name,
      help = help,
      run = function(args, out)
        local rec = target(out)
        if not rec then
          return
        end
        local found = product(args, "recipes." .. name .. " <item>", out)
        if not found then
          return
        end
        apply(rec, function()
          change(rec, found)
        end, string.format(message, session.catalog.display(found)), out)
      end,
    })
  end

  perItem(
    "unlock",
    "recipes.unlock <item>: shows every recipe of the item (use quotes for names with spaces), discovered ones too.",
    function(rec, found)
      rec:unlock(found)
    end,
    "All the recipes of %s are shown now."
  )
  perItem(
    "lock",
    "recipes.lock <item>: hides every recipe of the item, discovered ones too." .. HOW_TO_GO_BACK,
    function(rec, found)
      rec:lock(found)
    end,
    "All the recipes of %s are hidden now."
  )
  perItem(
    "safe-lock",
    "recipes.safe-lock <item>: hides every recipe of the item except the discovered ones.",
    function(rec, found)
      rec:safeLock(found)
    end,
    "Only the discovered recipes of %s are shown now."
  )

  api.console.add({
    name = "recipes.status",
    help = "Shows the world and how many recipes are discovered, unlocked and locked.",
    run = function(_, out)
      local world, rec = session:current()
      if not world or not rec then
        out("Load a save first.")
        return
      end
      local counts = rec:counts()
      out("World: " .. world.title)
      out(string.format("Discovered recipes: %d (%d of them hidden)", counts.discovered, counts.discoveredHidden))
      out("Every recipe unlocked: " .. (counts.all and "yes" or "no"))
      out(string.format("Items unlocked: %d, items locked: %d", counts.unlocked, counts.locked))
      if rec.readOnly then
        out("Recipes cannot be saved for this world (" .. rec.readOnly .. "). See UE4SS.log.")
      end
      local index = session.index
      if index then
        if index:isFailed() then
          out("Recipe index: failed, see UE4SS.log. Only discovered recipes are listed.")
        else
          out(index:isDone() and "Recipe index: ready" or string.format("Recipe index: %d%%", index:progress()))
        end
      end
    end,
  })
end

return commands
