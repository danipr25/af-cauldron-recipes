-- Contract of the recipe index: every combination is asked once, in small chunks, and the job survives a pause.
local lu = require("luaunit")
local index = require("index")

-- A fake game: the product depends on the positions, and every question costs one unit of fake time.
local function fixture(count)
  local f = { now = 0, calls = 0, queue = {}, progress = {}, done = nil, failed = nil, world = true }
  f.index = index.new({
    count = count,
    clock = function()
      return f.now
    end,
    schedule = function(fn)
      f.queue[#f.queue + 1] = fn
    end,
    prepare = function()
      if not f.world then
        return nil
      end
      return function(mode, i, j, k)
        f.calls = f.calls + 1
        f.now = f.now + 1
        if f.explodeAt and f.calls == f.explodeAt then
          error("game call failed")
        end
        return "P" .. ((i + j + (k or 0)) % 3) .. (mode == "advanced" and "a" or "n")
      end
    end,
    budget = 3, -- three questions per chunk
    checkEvery = 1,
    onProgress = function(percent)
      f.progress[#f.progress + 1] = percent
    end,
    onDone = function(seconds)
      f.done = seconds
    end,
    onFail = function(problem)
      f.failed = problem
    end,
  })
  -- Runs the scheduled chunks until nothing is left (or `limit` chunks ran).
  function f.drain(limit)
    local ran = 0
    while #f.queue > 0 and ran < (limit or math.huge) do
      table.remove(f.queue, 1)()
      ran = ran + 1
    end
    return ran
  end
  return f
end

return {
  TestIndex = {
    testPackAndUnpack = function()
      lu.assertEquals(index.pack(3, 1, 2), 1 * 65536 + 2 * 256 + 3)
      lu.assertEquals({ index.unpack(index.pack(170, 5, 90)) }, { 5, 90, 170 })
      lu.assertEquals({ index.unpack(index.pack(7, 2)) }, { 2, 7 })
    end,

    testEveryPairAndTripleIsAskedOnceAndGroupedByProduct = function()
      local f = fixture(4)
      f.index:start()
      f.drain()
      lu.assertTrue(f.index:isDone())
      -- 10 pairs (i <= j) and 20 triples (i <= j <= k).
      lu.assertEquals(f.calls, 10 + 20)
      local seen = {}
      local total = 0
      for _, mode in ipairs({ "advanced", "normal" }) do
        for _, product in ipairs({ "P0", "P1", "P2" }) do
          local name = product .. (mode == "advanced" and "a" or "n")
          for _, packed in ipairs(f.index:recipes(mode, name) or {}) do
            local i, j, k = index.unpack(packed)
            lu.assertTrue(i <= j and (k == nil or j <= k))
            lu.assertNil(seen[mode .. packed])
            seen[mode .. packed] = true
            total = total + 1
            local expected = "P" .. ((i + j + (k or 0)) % 3) .. (mode == "advanced" and "a" or "n")
            lu.assertEquals(name, expected)
          end
        end
      end
      lu.assertEquals(total, 30)
    end,

    testUsageCountsEachRecipeOncePerDistinctIngredient = function()
      -- { product, i, j, k, expected used table after adding it to an empty table }
      local cases = {
        { "A", 1, 2, 3, { [1] = { A = 1 }, [2] = { A = 1 }, [3] = { A = 1 } } },
        { "A", 2, 2, 5, { [2] = { A = 1 }, [5] = { A = 1 } } }, -- the same ingredient twice counts once
        { "A", 4, 4, 4, { [4] = { A = 1 } } },
        { "A", 1, 3, nil, { [1] = { A = 1 }, [3] = { A = 1 } } }, -- two ingredients (Advanced)
        { "A", 3, 3, nil, { [3] = { A = 1 } } },
      }
      for _, case in ipairs(cases) do
        local used = {}
        index.addUsage(used, case[1], case[2], case[3], case[4])
        lu.assertEquals(used, case[5])
      end
      -- Over several recipes and both modes the counts add up per product, and a finished index agrees with a
      -- count made from its own recipe lists.
      local f = fixture(4)
      f.index:start()
      f.drain()
      for position = 1, 4 do
        local expected = {}
        for _, mode in ipairs({ "advanced", "normal" }) do
          for _, product in ipairs({ "P0", "P1", "P2" }) do
            local name = product .. (mode == "advanced" and "a" or "n")
            for _, packed in ipairs(f.index:recipes(mode, name) or {}) do
              local i, j, k = index.unpack(packed)
              if i == position or j == position or k == position then
                expected[name] = (expected[name] or 0) + 1
              end
            end
          end
        end
        lu.assertEquals(f.index:usedIn(position), expected)
      end
      lu.assertEquals(f.index:usedIn(99), {})
    end,

    testWorkIsDoneInSmallChunksAndProgressReachesOneHundred = function()
      local f = fixture(6)
      f.index:start()
      local chunks = f.drain()
      lu.assertTrue(chunks > 1)
      lu.assertEquals(f.calls, 21 + 56)
      lu.assertEquals(f.progress[#f.progress], 100)
      lu.assertEquals(f.index:progress(), 100)
      for position = 2, #f.progress do
        lu.assertTrue(f.progress[position] > f.progress[position - 1]) -- only changes are reported
      end
      lu.assertNotNil(f.done)
    end,

    testEachChunkStaysNearTheBudget = function()
      local f = fixture(6)
      f.index:start()
      local longest = 0
      while #f.queue > 0 do
        local before = f.calls
        table.remove(f.queue, 1)()
        longest = math.max(longest, f.calls - before)
      end
      lu.assertTrue(longest <= 3, "a chunk asked " .. longest .. " questions in a budget of 3")
    end,

    testWithoutAWorldTheJobPausesAndResumes = function()
      local f = fixture(4)
      f.index:start()
      f.drain(2)
      local asked = f.calls
      f.world = false
      f.drain() -- the next chunk finds no world and stops without scheduling another
      lu.assertEquals(f.calls, asked)
      lu.assertEquals(#f.queue, 0)
      lu.assertFalse(f.index:isDone())
      f.index:resume() -- no world yet: it pauses again
      f.drain()
      lu.assertEquals(f.calls, asked)
      f.world = true
      f.index:resume()
      f.index:resume() -- twice does not schedule twice
      lu.assertEquals(#f.queue, 1)
      f.drain()
      lu.assertTrue(f.index:isDone())
      lu.assertEquals(f.calls, 30)
    end,

    testAnErrorStopsTheJobAndIsReported = function()
      local f = fixture(4)
      f.explodeAt = 5
      f.index:start()
      f.drain()
      lu.assertTrue(f.index:isFailed())
      lu.assertStrContains(f.failed, "game call failed")
      lu.assertEquals(#f.queue, 0)
    end,

    testCancelStopsScheduledWork = function()
      local f = fixture(4)
      f.index:start()
      f.index:cancel()
      f.drain()
      lu.assertEquals(f.calls, 0)
    end,

    testNoIngredientsIsDoneAtOnce = function()
      local f = fixture(0)
      f.index:start()
      lu.assertTrue(f.index:isDone())
      lu.assertEquals(f.progress, { 100 })
    end,
  },
}
