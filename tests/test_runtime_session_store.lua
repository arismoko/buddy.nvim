local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.runtime.state.session_store'] = nil
  end,
}

local function new_store()
  return require('buddy.runtime.state.session_store').new()
end

T['SessionStore'] = MiniTest.new_set()

T['SessionStore']['new() creates independent instances'] = function()
  local s1 = new_store()
  local s2 = new_store()
  s1:init_session('sess1', { capabilities = { sampling = {} } })
  MiniTest.expect.equality(s2:get('sess1'), nil)
end

T['SessionStore']['init_session and get'] = function()
  local store = new_store()
  store:init_session('s1', {
    capabilities = { sampling = {} },
    clientInfo = { name = 'test-client', version = '1.0' },
  })
  local session = store:get('s1')
  MiniTest.expect.no_equality(session, nil)
  MiniTest.expect.equality(session.session_id, 's1')
  MiniTest.expect.equality(session.capabilities.sampling ~= nil, true)
  MiniTest.expect.equality(session.client_info.name, 'test-client')
end

T['SessionStore']['get returns nil for unknown session'] = function()
  local store = new_store()
  MiniTest.expect.equality(store:get('nonexistent'), nil)
end

T['SessionStore']['init_session with empty params'] = function()
  local store = new_store()
  store:init_session('s1', {})
  local session = store:get('s1')
  MiniTest.expect.no_equality(session, nil)
  MiniTest.expect.equality(vim.tbl_count(session.capabilities), 0)
  MiniTest.expect.equality(vim.tbl_count(session.client_info), 0)
end

T['SessionStore']['update merges patch'] = function()
  local store = new_store()
  store:init_session('s1', { capabilities = { roots = {} } })
  store:update('s1', { cached_roots = { '/home/user' } })
  local session = store:get('s1')
  MiniTest.expect.equality(session.cached_roots[1], '/home/user')
  -- Original fields preserved
  MiniTest.expect.equality(session.capabilities.roots ~= nil, true)
end

T['SessionStore']['update on nonexistent session is no-op'] = function()
  local store = new_store()
  -- Should not throw
  store:update('nonexistent', { key = 'value' })
  MiniTest.expect.equality(store:get('nonexistent'), nil)
end

T['SessionStore']['cleanup removes session'] = function()
  local store = new_store()
  store:init_session('s1', { capabilities = {} })
  MiniTest.expect.no_equality(store:get('s1'), nil)
  store:cleanup('s1')
  MiniTest.expect.equality(store:get('s1'), nil)
end

T['SessionStore']['cleanup on nonexistent session is safe'] = function()
  local store = new_store()
  -- Should not throw
  store:cleanup('nonexistent')
end

T['SessionStore']['full lifecycle'] = function()
  local store = new_store()
  -- Init
  store:init_session('lifecycle', { capabilities = { sampling = {} }, clientInfo = { name = 'c' } })
  MiniTest.expect.no_equality(store:get('lifecycle'), nil)

  -- Update
  store:update('lifecycle', { cached_roots = { '/tmp' } })
  MiniTest.expect.equality(store:get('lifecycle').cached_roots[1], '/tmp')

  -- Add subscriptions
  store:add_subscription('lifecycle', 'file:///a.txt')
  store:add_subscription('lifecycle', 'file:///b.txt')

  -- Cleanup
  store:cleanup('lifecycle')
  MiniTest.expect.equality(store:get('lifecycle'), nil)
end

-- ── Subscriptions ──────────────────────────────────────────────────────

T['SessionStore']['add_subscription and remove_subscription'] = function()
  local store = new_store()
  store:init_session('s1', {})
  store:add_subscription('s1', 'file:///test.txt')
  local session = store:get('s1')
  MiniTest.expect.equality(session.subscriptions['file:///test.txt'], true)

  store:remove_subscription('s1', 'file:///test.txt')
  session = store:get('s1')
  MiniTest.expect.equality(session.subscriptions['file:///test.txt'], nil)
end

T['SessionStore']['add_subscription on nonexistent session is no-op'] = function()
  local store = new_store()
  store:add_subscription('ghost', 'file:///x')
  MiniTest.expect.equality(store:get('ghost'), nil)
end

T['SessionStore']['remove_subscription on nonexistent session is no-op'] = function()
  local store = new_store()
  store:remove_subscription('ghost', 'file:///x')
end

T['SessionStore']['subscribers_for_uri'] = function()
  local store = new_store()
  store:init_session('s1', {})
  store:init_session('s2', {})
  store:init_session('s3', {})

  store:add_subscription('s1', 'file:///shared.txt')
  store:add_subscription('s2', 'file:///shared.txt')
  store:add_subscription('s3', 'file:///other.txt')

  local subs = store:subscribers_for_uri('file:///shared.txt')
  table.sort(subs)
  MiniTest.expect.equality(#subs, 2)
  MiniTest.expect.equality(subs[1], 's1')
  MiniTest.expect.equality(subs[2], 's2')
end

T['SessionStore']['subscribers_for_uri with no subscribers'] = function()
  local store = new_store()
  local subs = store:subscribers_for_uri('file:///nothing')
  MiniTest.expect.equality(#subs, 0)
end

T['SessionStore']['subscribers_for_uri updates after cleanup'] = function()
  local store = new_store()
  store:init_session('s1', {})
  store:init_session('s2', {})
  store:add_subscription('s1', 'file:///doc.txt')
  store:add_subscription('s2', 'file:///doc.txt')

  store:cleanup('s1')
  local subs = store:subscribers_for_uri('file:///doc.txt')
  MiniTest.expect.equality(#subs, 1)
  MiniTest.expect.equality(subs[1], 's2')
end

return T
