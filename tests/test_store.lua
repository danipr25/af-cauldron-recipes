-- Contract of the store: the record file is never lost, whatever happens while it is written or read.
local lu = require("luaunit")
local record = require("record")
local store = require("store")

local DIR = "C:\\game\\mods\\.data"
local FILE = DIR .. "\\af-cauldron-recipes-W_1.json"
local BROKEN = DIR .. "\\af-cauldron-recipes-W_1.broken-1000.json"

-- A fake disk and fake JSON: encode keeps the table and returns a token, decode gives it back (and raises on
-- anything else).
local function fixture()
  local disk, saved, ops, logs = {}, {}, {}, {}
  local counter = 0
  local json = {
    encode = function(value)
      counter = counter + 1
      saved[counter] = value
      return "JSON#" .. counter
    end,
    decode = function(text)
      local id = tostring(text):match("^JSON#(%d+)$")
      if not id then
        error("invalid JSON")
      end
      return saved[tonumber(id)]
    end,
  }
  local files = {
    read = function(path)
      return disk[path]
    end,
    write = function(path, text)
      ops[#ops + 1] = "write " .. path
      disk[path] = text
      return true
    end,
    remove = function(path)
      ops[#ops + 1] = "remove " .. path
      disk[path] = nil
      return true
    end,
    rename = function(from, to)
      ops[#ops + 1] = "rename " .. from .. " " .. to
      if disk[to] ~= nil then
        return nil, "File exists" -- like os.rename
      end
      disk[to] = disk[from]
      disk[from] = nil
      return true
    end,
  }
  local s = store.new({
    dir = DIR,
    files = files,
    json = json,
    log = function(text)
      logs[#logs + 1] = text
    end,
    now = function()
      return 1000
    end,
  })
  return { disk = disk, ops = ops, logs = logs, store = s, json = json }
end

local function sample()
  local rec = record.new("W 1")
  rec:addDiscovered("advanced", { "Gentian", "GentianNectar" }, "Clay", "filter")
  return rec
end

return {
  TestStore = {
    testSavesToATemporaryFileThenRenamesIt = function()
      local f = fixture()
      lu.assertTrue(f.store:save("W_1", sample()))
      lu.assertEquals(f.ops, { "write " .. FILE .. ".tmp", "remove " .. FILE, "rename " .. FILE .. ".tmp " .. FILE })
      lu.assertNil(f.disk[FILE .. ".tmp"])
      -- Saving again replaces the file (a rename alone could not).
      lu.assertTrue(f.store:save("W_1", sample()))
      lu.assertNotNil(f.disk[FILE])
    end,

    testRoundTrip = function()
      local f = fixture()
      f.store:save("W_1", sample())
      local rec, status = f.store:load("W_1", "W 1")
      lu.assertEquals(status, "loaded")
      lu.assertEquals(rec:toTable(), sample():toTable())
    end,

    testNoFileIsANewRecord = function()
      local f = fixture()
      local rec, status = f.store:load("W_1", "W 1")
      lu.assertEquals(status, "new")
      lu.assertEquals(#rec.discovered, 0)
      lu.assertEquals(f.ops, {}) -- nothing is written until something changes
    end,

    testAFinishedCopyIsRecoveredWhenTheFileIsMissing = function()
      local f = fixture()
      f.disk[FILE .. ".tmp"] = f.json.encode(sample():toTable())
      local rec, status = f.store:load("W_1", "W 1")
      lu.assertEquals(status, "recovered")
      lu.assertEquals(#rec.discovered, 1)
      lu.assertNotNil(f.disk[FILE])
      lu.assertNil(f.disk[FILE .. ".tmp"])
    end,

    testAnUnreadableFileIsKeptAndANewRecordIsWritten = function()
      local f = fixture()
      f.disk[FILE] = "not json at all"
      local rec, status = f.store:load("W_1", "W 1")
      lu.assertEquals(status, "quarantined")
      lu.assertEquals(#rec.discovered, 0)
      lu.assertEquals(f.disk[BROKEN], "not json at all")
      lu.assertNotNil(f.disk[FILE]) -- a fresh record
      lu.assertEquals(select(2, f.store:load("W_1", "W 1")), "loaded")
      lu.assertStrContains(f.logs[1], "broken-1000")
    end,

    testARecordFromANewerModIsNeverWritten = function()
      local f = fixture()
      f.disk[FILE] = f.json.encode({ version = 2, world = "W 1", things = {} })
      local before = f.disk[FILE]
      local rec, status = f.store:load("W_1", "W 1")
      lu.assertEquals(status, "newer")
      lu.assertEquals(rec.readOnly, "newer")
      lu.assertFalse(f.store:save("W_1", rec))
      lu.assertEquals(f.disk[FILE], before)
      lu.assertEquals(f.ops, {})
    end,

    testTheFileOfAnotherWorldIsNotUsedNorWritten = function()
      local f = fixture()
      local other = record.new("w 1") -- same file on a case-insensitive disk, different title
      other:addDiscovered("advanced", { "A", "B" }, "C", "filter")
      f.disk[FILE] = f.json.encode(other:toTable())
      local before = f.disk[FILE]
      local rec, status = f.store:load("W_1", "W 1")
      lu.assertEquals(status, "other-world")
      lu.assertEquals(#rec.discovered, 0)
      lu.assertFalse(f.store:save("W_1", rec))
      lu.assertEquals(f.disk[FILE], before)
    end,

    testAnUnreadableFileWithAFinishedCopyUsesTheCopyAndKeepsTheFile = function()
      local f = fixture()
      f.disk[FILE] = "garbage"
      f.disk[FILE .. ".tmp"] = f.json.encode(sample():toTable())
      local rec, status = f.store:load("W_1", "W 1")
      lu.assertEquals(status, "recovered")
      lu.assertEquals(#rec.discovered, 1)
      lu.assertEquals(f.disk[BROKEN], "garbage")
      lu.assertEquals(select(2, f.store:load("W_1", "W 1")), "loaded")
    end,

    testTheCopyFollowsTheSameRulesAsTheFile = function()
      local newer = fixture()
      newer.disk[FILE .. ".tmp"] = newer.json.encode({ version = 2, world = "W 1" })
      local rec, status = newer.store:load("W_1", "W 1")
      lu.assertEquals({ status, rec.readOnly }, { "newer", "newer" })
      lu.assertNil(newer.disk[FILE])

      local broken = fixture()
      broken.disk[FILE .. ".tmp"] = "garbage"
      local _, brokenStatus = broken.store:load("W_1", "W 1")
      lu.assertEquals(brokenStatus, "quarantined")
      lu.assertEquals(broken.disk[BROKEN], "garbage")
    end,

    testAFileThatCannotBeRemovedIsReportedAndKept = function()
      local f = fixture()
      f.store:save("W_1", sample())
      local before = f.disk[FILE]
      f.store.files.remove = function()
        return nil, "denied"
      end
      lu.assertFalse(f.store:save("W_1", sample()))
      lu.assertEquals(f.disk[FILE], before)
      lu.assertStrContains(f.logs[#f.logs], "could not replace")
    end,

    testACopyThatDoesNotReadBackNeverReplacesTheFile = function()
      local f = fixture()
      f.store:save("W_1", sample())
      local before = f.disk[FILE]
      f.store.files.write = function(path, _)
        f.disk[path] = "cut short" -- the disk lost part of the data
        return true
      end
      lu.assertFalse(f.store:save("W_1", sample()))
      lu.assertEquals(f.disk[FILE], before)
      lu.assertNil(f.disk[FILE .. ".tmp"])
      lu.assertStrContains(f.logs[#f.logs], "could not be read back")
    end,

    testAMissingOldFileIsNotAnError = function()
      local f = fixture()
      f.store.files.remove = function()
        return nil, "No such file"
      end
      lu.assertTrue(f.store:save("W_1", sample()))
    end,

    testAFailedRenameKeepsTheFinishedCopy = function()
      local f = fixture()
      f.store.files.rename = function()
        return nil, "denied"
      end
      lu.assertFalse(f.store:save("W_1", sample()))
      lu.assertNotNil(f.disk[FILE .. ".tmp"])
      lu.assertStrContains(f.logs[1], "could not finish saving")
    end,
  },
}
