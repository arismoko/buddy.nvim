-- Tests for hot reload functionality
local T = MiniTest.new_set()

-- Fresh state for each test
T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.tools.hotreload'] = nil
  end,
  post_case = function()
    -- Clean up any test modules we created
    for k, _ in pairs(package.loaded) do
      if k:match('^test_plugin_') then
        package.loaded[k] = nil
      end
    end
  end
}

local function get_hotreload()
  return require('buddy.tools.hotreload')
end

T['clear_plugin_cache()'] = MiniTest.new_set()

T['clear_plugin_cache()']['clears exact prefix match'] = function()
  -- Set up test modules in package.loaded
  package.loaded['test_plugin_a'] = { loaded = true }
  package.loaded['test_plugin_a.submodule'] = { loaded = true }
  package.loaded['test_plugin_a.deep.nested'] = { loaded = true }

  local hotreload = get_hotreload()
  local count = hotreload.clear_plugin_cache('test_plugin_a')

  MiniTest.expect.equality(count, 3)
  MiniTest.expect.equality(package.loaded['test_plugin_a'], nil)
  MiniTest.expect.equality(package.loaded['test_plugin_a.submodule'], nil)
  MiniTest.expect.equality(package.loaded['test_plugin_a.deep.nested'], nil)
end

T['clear_plugin_cache()']['leaves other modules intact'] = function()
  -- Set up test modules
  package.loaded['test_plugin_b'] = { loaded = true }
  package.loaded['test_plugin_b.tools'] = { loaded = true }
  package.loaded['test_plugin_c'] = { loaded = true }
  package.loaded['test_plugin_c.tools'] = { loaded = true }
  package.loaded['other_module'] = { loaded = true }

  local hotreload = get_hotreload()
  hotreload.clear_plugin_cache('test_plugin_b')

  -- test_plugin_b should be cleared
  MiniTest.expect.equality(package.loaded['test_plugin_b'], nil)
  MiniTest.expect.equality(package.loaded['test_plugin_b.tools'], nil)

  -- Other modules should remain
  MiniTest.expect.equality(package.loaded['test_plugin_c'].loaded, true)
  MiniTest.expect.equality(package.loaded['test_plugin_c.tools'].loaded, true)
  MiniTest.expect.equality(package.loaded['other_module'].loaded, true)

  -- Clean up
  package.loaded['test_plugin_c'] = nil
  package.loaded['test_plugin_c.tools'] = nil
  package.loaded['other_module'] = nil
end

T['clear_plugin_cache()']['does not match partial prefix'] = function()
  -- test_plugin should NOT match test_plugin_partial
  package.loaded['test_plugin'] = { loaded = true }
  package.loaded['test_plugin_partial'] = { loaded = true }

  local hotreload = get_hotreload()
  hotreload.clear_plugin_cache('test_plugin')

  -- test_plugin should be cleared
  MiniTest.expect.equality(package.loaded['test_plugin'], nil)

  -- test_plugin_partial should NOT be cleared (different prefix)
  MiniTest.expect.equality(package.loaded['test_plugin_partial'].loaded, true)

  -- Clean up
  package.loaded['test_plugin_partial'] = nil
end

T['clear_plugin_cache()']['handles special regex characters in prefix'] = function()
  -- Prefix with special chars that could break regex
  package.loaded['test-plugin.special'] = { loaded = true }
  package.loaded['test-plugin.special.sub'] = { loaded = true }

  local hotreload = get_hotreload()
  local count = hotreload.clear_plugin_cache('test-plugin.special')

  MiniTest.expect.equality(count, 2)
  MiniTest.expect.equality(package.loaded['test-plugin.special'], nil)
  MiniTest.expect.equality(package.loaded['test-plugin.special.sub'], nil)
end

T['clear_plugin_cache()']['returns zero when no matches'] = function()
  local hotreload = get_hotreload()
  local count = hotreload.clear_plugin_cache('nonexistent_plugin_xyz')

  MiniTest.expect.equality(count, 0)
end

T['track_plugin()'] = MiniTest.new_set()

T['track_plugin()']['tracks plugin correctly'] = function()
  local hotreload = get_hotreload()

  -- Track a plugin
  hotreload.track_plugin('test_plugin_track', '/some/path/lua/test_plugin_track/buddy.lua')

  local tracked = hotreload.list_tracked()
  MiniTest.expect.equality(#tracked, 1)
  MiniTest.expect.equality(tracked[1].prefix, 'test_plugin_track')
  MiniTest.expect.equality(tracked[1].buddy_path, '/some/path/lua/test_plugin_track/buddy.lua')
  MiniTest.expect.equality(tracked[1].lua_dir, '/some/path/lua/test_plugin_track')

  -- Cleanup
  hotreload.untrack_plugin('test_plugin_track')
end

T['untrack_plugin()'] = MiniTest.new_set()

T['untrack_plugin()']['removes plugin from tracking'] = function()
  local hotreload = get_hotreload()

  hotreload.track_plugin('test_plugin_untrack', '/path/lua/test_plugin_untrack/buddy.lua')
  MiniTest.expect.equality(#hotreload.list_tracked(), 1)

  hotreload.untrack_plugin('test_plugin_untrack')
  MiniTest.expect.equality(#hotreload.list_tracked(), 0)
end

T['is_watching()'] = MiniTest.new_set()

T['is_watching()']['returns false by default'] = function()
  local hotreload = get_hotreload()
  MiniTest.expect.equality(hotreload.is_watching(), false)
end

T['is_watching()']['returns true after start_watching'] = function()
  local hotreload = get_hotreload()

  hotreload.start_watching()
  MiniTest.expect.equality(hotreload.is_watching(), true)

  -- Cleanup
  hotreload.stop_watching()
  MiniTest.expect.equality(hotreload.is_watching(), false)
end

return T
