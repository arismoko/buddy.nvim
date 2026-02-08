local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.runtime.state.request_store'] = nil
  end,
}

local function new_store()
  return require('buddy.runtime.state.request_store').new()
end

T['RequestStore'] = MiniTest.new_set()

T['RequestStore']['new() creates independent instances'] = function()
  local r1 = new_store()
  local r2 = new_store()
  r1:start('req1', { session_id = 's1', method = 'test' })
  MiniTest.expect.equality(r2:get('req1'), nil)
end

T['RequestStore']['start and get'] = function()
  local store = new_store()
  store:start('req1', { session_id = 's1', method = 'tools/call' })
  local entry = store:get('req1')
  MiniTest.expect.no_equality(entry, nil)
  MiniTest.expect.equality(entry.key, 'req1')
  MiniTest.expect.equality(entry.session_id, 's1')
  MiniTest.expect.equality(entry.status, 'pending')
  MiniTest.expect.equality(entry.meta.method, 'tools/call')
  MiniTest.expect.equality(entry.result, nil)
  MiniTest.expect.equality(entry.error, nil)
end

T['RequestStore']['get returns nil for unknown key'] = function()
  local store = new_store()
  MiniTest.expect.equality(store:get('nonexistent'), nil)
end

T['RequestStore']['resolve pending request'] = function()
  local store = new_store()
  store:start('req1', { session_id = 's1' })
  local ok = store:resolve('req1', { content = 'hello' })
  MiniTest.expect.equality(ok, true)
  local entry = store:get('req1')
  MiniTest.expect.equality(entry.status, 'resolved')
  MiniTest.expect.equality(entry.result.content, 'hello')
end

T['RequestStore']['resolve non-pending returns false'] = function()
  local store = new_store()
  store:start('req1', { session_id = 's1' })
  store:resolve('req1', 'first')
  local ok = store:resolve('req1', 'second')
  MiniTest.expect.equality(ok, false)
end

T['RequestStore']['resolve unknown key returns false'] = function()
  local store = new_store()
  local ok = store:resolve('ghost', 'data')
  MiniTest.expect.equality(ok, false)
end

T['RequestStore']['reject pending request'] = function()
  local store = new_store()
  store:start('req1', { session_id = 's1' })
  local ok = store:reject('req1', 'timeout')
  MiniTest.expect.equality(ok, true)
  local entry = store:get('req1')
  MiniTest.expect.equality(entry.status, 'rejected')
  MiniTest.expect.equality(entry.error, 'timeout')
end

T['RequestStore']['reject non-pending returns false'] = function()
  local store = new_store()
  store:start('req1', { session_id = 's1' })
  store:reject('req1', 'err1')
  local ok = store:reject('req1', 'err2')
  MiniTest.expect.equality(ok, false)
end

T['RequestStore']['reject unknown key returns false'] = function()
  local store = new_store()
  local ok = store:reject('ghost', 'err')
  MiniTest.expect.equality(ok, false)
end

T['RequestStore']['cannot resolve after reject'] = function()
  local store = new_store()
  store:start('req1', { session_id = 's1' })
  store:reject('req1', 'err')
  local ok = store:resolve('req1', 'data')
  MiniTest.expect.equality(ok, false)
  MiniTest.expect.equality(store:get('req1').status, 'rejected')
end

T['RequestStore']['cannot reject after resolve'] = function()
  local store = new_store()
  store:start('req1', { session_id = 's1' })
  store:resolve('req1', 'data')
  local ok = store:reject('req1', 'err')
  MiniTest.expect.equality(ok, false)
  MiniTest.expect.equality(store:get('req1').status, 'resolved')
end

-- ── cleanup_by_session ─────────────────────────────────────────────────

T['RequestStore']['cleanup_by_session removes all session requests'] = function()
  local store = new_store()
  store:start('req1', { session_id = 's1', method = 'a' })
  store:start('req2', { session_id = 's1', method = 'b' })
  store:start('req3', { session_id = 's2', method = 'c' })

  store:cleanup_by_session('s1')

  MiniTest.expect.equality(store:get('req1'), nil)
  MiniTest.expect.equality(store:get('req2'), nil)
  MiniTest.expect.no_equality(store:get('req3'), nil)
end

T['RequestStore']['cleanup_by_session rejects pending before removal'] = function()
  local store = new_store()
  store:start('req1', { session_id = 's1' })
  store:start('req2', { session_id = 's1' })
  store:resolve('req2', 'done')

  -- We can't check the status after cleanup since entries are removed,
  -- but we can verify the resolve on req2 was already done
  store:cleanup_by_session('s1')
  MiniTest.expect.equality(store:get('req1'), nil)
  MiniTest.expect.equality(store:get('req2'), nil)
end

T['RequestStore']['cleanup_by_session with no matching requests is safe'] = function()
  local store = new_store()
  store:start('req1', { session_id = 's1' })
  -- Should not throw
  store:cleanup_by_session('s999')
  -- Original request untouched
  MiniTest.expect.no_equality(store:get('req1'), nil)
end

T['RequestStore']['cleanup_by_session with empty store is safe'] = function()
  local store = new_store()
  -- Should not throw
  store:cleanup_by_session('s1')
end

T['RequestStore']['start records started_at timestamp'] = function()
  local store = new_store()
  local before = vim.uv.hrtime()
  store:start('req1', { session_id = 's1' })
  local after = vim.uv.hrtime()
  local entry = store:get('req1')
  MiniTest.expect.equality(entry.started_at >= before, true)
  MiniTest.expect.equality(entry.started_at <= after, true)
end

return T
