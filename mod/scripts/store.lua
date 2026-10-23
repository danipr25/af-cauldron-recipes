-- Reads and writes the mod's record file for a world, without ever losing the player's data. Pure Lua: the file
-- functions and the JSON functions are handed in, so it is tested without the game (tests/test_store.lua).
--   <dir>\af-cauldron-recipes-<world key>.json          the record
--   <dir>\af-cauldron-recipes-<world key>.json.tmp      a copy being written (finished by a rename)
--   <dir>\af-cauldron-recipes-<world key>.broken-<time>.json   a file that could not be read, kept for the player
local record = require("record")

local store = {}

local Store = {}
Store.__index = Store

-- options:
--   dir: the data folder (no trailing backslash)
--   files: { read(path) -> text or nil, write(path, text) -> true (or nil and why), remove(path),
--     rename(from, to) -> true (or nil and why) }
--   json: { encode(value) -> text, decode(text) -> value (raises on invalid text) }
--   log(text)
--   now() -> seconds (default os.time)
function store.new(options)
  local self = setmetatable({}, Store)
  self.dir = options.dir
  self.files = options.files
  self.json = options.json
  self.log = options.log
  self.now = options.now or os.time
  return self
end

function Store:path(key)
  return self.dir .. "\\af-cauldron-recipes-" .. key .. ".json"
end

-- Reads one file. Returns the decoded data, or nil and "missing" or "broken".
function Store:readData(path)
  local text = self.files.read(path)
  if text == nil then
    return nil, "missing"
  end
  local ok, data = pcall(self.json.decode, text)
  if not ok or type(data) ~= "table" then
    return nil, "broken"
  end
  return data
end

-- Renames a file out of the way so the player keeps it. Returns the new path, or nil and why.
function Store:setAside(key, path)
  local broken = self.dir .. "\\af-cauldron-recipes-" .. key .. ".broken-" .. tostring(self.now()) .. ".json"
  local renamed, problem = self.files.rename(path, broken)
  if not renamed then
    return nil, problem
  end
  return broken
end

-- Sets a file that cannot be used aside and starts a new record. Returns the record and "quarantined", or a
-- read-only record and "unreadable" when the file could not be moved away.
function Store:quarantine(key, path, title, reason)
  local fresh = record.new(title)
  local broken, problem = self:setAside(key, path)
  if not broken then
    self.log(
      "the recipe record of this world cannot be used ("
        .. reason
        .. ") and could not be renamed ("
        .. tostring(problem)
        .. "). Recipes will not be saved for this world until that is fixed"
    )
    fresh.readOnly = "unreadable"
    return fresh, "unreadable"
  end
  self.log(
    "the recipe record of this world cannot be used ("
      .. reason
      .. "). It was kept as "
      .. broken
      .. " and a new record was started"
  )
  self:save(key, fresh)
  return fresh, "quarantined"
end

-- Loads the record of the world. Always returns a record, and what happened: "new" (no file yet), "loaded",
-- "recovered" (the finished copy `<file>.tmp` was used because the file was missing or unreadable), "quarantined"
-- (the file was unreadable: it was renamed and a new record written), "unreadable" (it could not even be renamed:
-- read only), "newer" (written by a newer mod: read only) or "other-world" (the file belongs to a world with another
-- name: read only). A record that is read only is never written. The copy follows the same rules as the file.
function Store:load(key, title)
  local path = self:path(key)
  local copyPath = path .. ".tmp"
  local data, why = self:readData(path)
  local source, recovered = path, false
  if not data then
    local copy, copyWhy = self:readData(copyPath)
    if why == "missing" then
      if copyWhy == "missing" then
        return record.new(title), "new"
      end
      data, source, recovered = copy, copyPath, true
    elseif copy and record.decode(copy, title) then
      -- The file is unreadable but its finished copy is fine: keep the file for the player and use the copy.
      local kept = self:setAside(key, path)
      if kept then
        self.log("the recipe record of this world could not be read. It was kept as " .. kept)
        data, source, recovered = copy, copyPath, true
      end
    end
  end
  if not data then
    return self:quarantine(key, source, title, "it is not valid JSON")
  end

  if type(data.version) == "number" and data.version > record.VERSION then
    self.log(
      "the recipe record of this world was written by a newer version of Cauldron Recipes. Update the mod: recipes "
        .. "will not be saved for this world until then"
    )
    local newer = record.new(title)
    newer.readOnly = "newer"
    return newer, "newer"
  end

  local loaded, problem = record.decode(data, title)
  if not loaded then
    return self:quarantine(key, source, title, tostring(problem))
  end

  if data.world ~= title then
    self.log(
      "the file for this world holds the recipes of another world ('"
        .. tostring(data.world)
        .. "' and not '"
        .. tostring(title)
        .. "'), so recipes will not be saved for this world"
    )
    local other = record.new(title)
    other.readOnly = "other-world"
    return other, "other-world"
  end

  if recovered then
    self.log("the recipe record of this world was restored from its unfinished copy")
    self:save(key, loaded)
    return loaded, "recovered"
  end
  return loaded, "loaded"
end

-- Writes the record: to a new file first, then renamed over the old one (os.rename cannot replace a file, so the
-- old one is removed just before). If the game stops in between, the finished copy is used at the next load.
-- Returns true when the file is written. When it returns false, a second value "pending" says the finished copy
-- `<file>.tmp` holds the new record (the last rename failed), so the next load uses it; without it nothing changed.
function Store:save(key, rec)
  if rec.readOnly then
    return false
  end
  local ok, text = pcall(self.json.encode, rec:toTable())
  if not ok then
    self.log("could not save the recipes (" .. tostring(text) .. ")")
    return false
  end
  local path = self:path(key)
  local temporary = path .. ".tmp"
  local written, problem = self.files.write(temporary, text)
  if not written then
    self.log("could not save the recipes to " .. temporary .. " (" .. tostring(problem) .. ")")
    return false
  end
  -- Read the copy back before the old file goes away: a copy that does not parse must never replace it.
  local copy = self.files.read(temporary)
  if copy == nil or not pcall(self.json.decode, copy) then
    self.log(
      "the new recipe file "
        .. temporary
        .. " could not be read back, so the old file was left as it is and the recipes were not saved"
    )
    self.files.remove(temporary)
    return false
  end
  local removed, removeProblem = self.files.remove(path)
  -- A file that was not there is fine; one that is still there means the old record cannot be replaced.
  if not removed and self.files.read(path) ~= nil then
    self.log(
      "could not replace the recipe file ("
        .. tostring(removeProblem)
        .. "). The new copy "
        .. temporary
        .. " was kept and the old file was not changed"
    )
    return false
  end
  local renamed, renameProblem = self.files.rename(temporary, path)
  if not renamed then
    self.log(
      "could not finish saving the recipes ("
        .. tostring(renameProblem)
        .. "). The copy "
        .. temporary
        .. " will be used the next time the world is loaded"
    )
    return false, "pending"
  end
  return true
end

return store
