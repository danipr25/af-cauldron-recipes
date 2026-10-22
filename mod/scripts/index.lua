-- The index of every cauldron recipe: for each product, every combination of ingredients that makes it. It is built
-- in the background, a few milliseconds per game tick, by asking the game's own answer for each combination.
-- Pure Lua: the game's answer, the clock and the scheduler are handed in, so it is tested without the game
-- (tests/test_index.lua).
--
-- A combination is stored as one whole number, `i * 65536 + j * 256 + k`, where i, j and k are positions in the
-- ingredient list (1 or more; k is 0 for Advanced), with i <= j <= k. The order of the ingredients does not change
-- the product (verified in game), so each combination is asked once.
local index = {}

local Index = {}
Index.__index = Index

-- Packs positions, given in any order, into the stored number (k may be nil for two ingredients).
function index.pack(i, j, k)
  local list = { i, j, k }
  table.sort(list)
  return (list[1] or 0) * 65536 + (list[2] or 0) * 256 + (list[3] or 0)
end

-- Counts one recipe for each distinct ingredient position it uses: used[position][product] = number of recipes of
-- that product that use the position. A recipe that uses an ingredient twice counts once for it. Positions may come
-- in any order and k may be nil.
function index.addUsage(used, product, i, j, k)
  local seen = {}
  for _, position in ipairs({ i, j, k or i }) do
    if not seen[position] then
      seen[position] = true
      local byProduct = used[position]
      if not byProduct then
        byProduct = {}
        used[position] = byProduct
      end
      byProduct[product] = (byProduct[product] or 0) + 1
    end
  end
end

-- The positions of a stored number: i, j and k (k is nil for two ingredients).
function index.unpack(packed)
  local k = packed % 256
  return packed // 65536, (packed // 256) % 256, k > 0 and k or nil
end

-- options:
--   count: how many ingredients there are (at most 255)
--   prepare(): called at the start of each chunk. Returns the oracle `oracle(mode, i, j, k)` -> product name or nil
--     (k is nil for "advanced"), or nil when the game cannot answer now (no world): the job then pauses until resume().
--   clock(): seconds (default os.clock)
--   schedule(fn): runs fn later, on the game thread
--   budget: seconds of work per chunk (default 0.003)
--   checkEvery: combinations between clock readings (default 32)
--   onProgress(percent): whenever the whole percent changes
--   onDone(seconds): when every combination was asked. `seconds` is the time spent in chunks.
--   onFail(problem): when the oracle raised an error. The job stops.
function index.new(options)
  local self = setmetatable({}, Index)
  self.count = options.count
  self.prepare = options.prepare
  self.clock = options.clock or os.clock
  self.schedule = options.schedule
  self.budget = options.budget or 0.003
  self.checkEvery = options.checkEvery or 32
  self.onProgress = options.onProgress or function() end
  self.onDone = options.onDone or function() end
  self.onFail = options.onFail or function() end
  self.byMode = { normal = {}, advanced = {} }
  self.used = {} -- see index.addUsage
  self.cursor = { mode = "advanced", i = 1, j = 1, k = 1 }
  local n = self.count
  self.total = n * (n + 1) // 2 + n * (n + 1) * (n + 2) // 6
  self.asked = 0
  self.percent = 0
  self.spent = 0
  self.started = false
  self.pending = false -- a chunk is scheduled
  self.paused = false
  self.done = false
  self.failed = false
  self.cancelled = false
  if self.count > 255 then
    -- Positions are packed into one byte each: a bigger game cannot be indexed, but nothing else depends on it.
    self.failed = true
    self.refused = true -- unlike other failures, a new job would fail the same way
    self.failure = "the game has more than 255 cauldron ingredients, which this version of the mod cannot index"
  end
  return self
end

function Index:queue()
  if self.pending or self.done or self.failed or self.cancelled then
    return
  end
  self.pending = true
  self.schedule(function()
    self.pending = false
    self:chunk()
  end)
end

-- Starts the job (once).
function Index:start()
  if self.started then
    return
  end
  self.started = true
  if self.failed then
    self.onFail(self.failure)
    return
  end
  if self.total == 0 then
    self.done = true
    self.onProgress(100)
    self.onDone(0)
    return
  end
  self:queue()
end

-- Carries on after a pause (a new world is loaded).
function Index:resume()
  if self.paused then
    self.paused = false
    self:queue()
  end
end

-- Stops the job for good: chunks already scheduled do nothing.
function Index:cancel()
  self.cancelled = true
end

function Index:isDone()
  return self.done
end

-- True when the game has too many ingredients for the index: a new job would not help.
function Index:isRefused()
  return self.refused == true
end

function Index:isFailed()
  return self.failed
end

-- 0 to 100.
function Index:progress()
  return self.percent
end

-- The stored numbers of the recipes that make `product` in this mode ("normal" or "advanced"), or nil.
-- Complete only when isDone(); before that it holds what was found so far.
function Index:recipes(mode, product)
  return self.byMode[mode][product]
end

-- For an ingredient position: { [product] = how many recipes of that product use it }, from both modes. Complete only
-- when isDone(). The table belongs to the index: do not change it.
function Index:usedIn(position)
  return self.used[position] or {}
end

-- Moves to the next combination. Returns false when there is none left.
function Index:step(oracle)
  local c = self.cursor
  local n = self.count
  local product
  if c.mode == "advanced" then
    product = oracle("advanced", c.i, c.j, nil)
    if product ~= nil then
      local list = self.byMode.advanced[product]
      if not list then
        list = {}
        self.byMode.advanced[product] = list
      end
      list[#list + 1] = c.i * 65536 + c.j * 256
      index.addUsage(self.used, product, c.i, c.j, nil)
    end
    c.j = c.j + 1
    if c.j > n then
      c.i = c.i + 1
      c.j = c.i
      if c.i > n then
        c.mode, c.i, c.j, c.k = "normal", 1, 1, 1
      end
    end
  else
    product = oracle("normal", c.i, c.j, c.k)
    if product ~= nil then
      local list = self.byMode.normal[product]
      if not list then
        list = {}
        self.byMode.normal[product] = list
      end
      list[#list + 1] = c.i * 65536 + c.j * 256 + c.k
      index.addUsage(self.used, product, c.i, c.j, c.k)
    end
    c.k = c.k + 1
    if c.k > n then
      c.j = c.j + 1
      c.k = c.j
      if c.j > n then
        c.i = c.i + 1
        c.j = c.i
        c.k = c.i
        if c.i > n then
          return false
        end
      end
    end
  end
  self.asked = self.asked + 1
  return true
end

-- One chunk of work: asks combinations until the budget is used, then schedules the next chunk.
function Index:chunk()
  if self.done or self.failed or self.cancelled then
    return
  end
  local oracle = self.prepare()
  if not oracle then
    self.paused = true
    return
  end
  local startedAt = self.clock()
  local ok, problem = pcall(function()
    local sinceClock = 0
    repeat
      if not self:step(oracle) then
        self.asked = self.total
        self.done = true
        return
      end
      sinceClock = sinceClock + 1
      if sinceClock >= self.checkEvery then
        sinceClock = 0
        if self.clock() - startedAt >= self.budget then
          return
        end
      end
    until false
  end)
  self.spent = self.spent + (self.clock() - startedAt)
  if not ok then
    self.failed = true
    self.onFail(tostring(problem))
    return
  end
  local percent = self.asked * 100 // self.total
  if percent ~= self.percent then
    self.percent = percent
    self.onProgress(percent)
  end
  if self.done then
    if self.percent ~= 100 then
      self.percent = 100
      self.onProgress(100)
    end
    self.onDone(self.spent)
  else
    self:queue()
  end
end

return index
