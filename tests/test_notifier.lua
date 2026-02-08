-- Tests for services/notifier.lua
local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.services.notifier'] = nil
  end,
}

local function get_notifier()
  return require('buddy.services.notifier')
end

T['Notifier'] = MiniTest.new_set()

T['Notifier']['new() requires send_fn'] = function()
  local Notifier = get_notifier()
  MiniTest.expect.error(function()
    Notifier.new({})
  end)
  MiniTest.expect.error(function()
    Notifier.new(nil)
  end)
end

T['Notifier']['new() creates instance with send_fn'] = function()
  local Notifier = get_notifier()
  local notifier = Notifier.new({
    send_fn = function() return true end,
  })
  MiniTest.expect.equality(type(notifier), 'table')
  MiniTest.expect.equality(type(notifier.notify), 'function')
  MiniTest.expect.equality(type(notifier.broadcast), 'function')
end

T['notify()'] = MiniTest.new_set()

T['notify()']['sends correct JSON-RPC notification'] = function()
  local Notifier = get_notifier()
  local sent = {}

  local notifier = Notifier.new({
    send_fn = function(session_id, msg)
      table.insert(sent, { session_id = session_id, msg = msg })
      return true
    end,
  })

  local ok = notifier:notify('session-1', 'notifications/tools/list_changed')

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(#sent, 1)
  MiniTest.expect.equality(sent[1].session_id, 'session-1')
  MiniTest.expect.equality(sent[1].msg.jsonrpc, '2.0')
  MiniTest.expect.equality(sent[1].msg.method, 'notifications/tools/list_changed')
  MiniTest.expect.equality(sent[1].msg.params, nil)
end

T['notify()']['includes params when provided'] = function()
  local Notifier = get_notifier()
  local sent = {}

  local notifier = Notifier.new({
    send_fn = function(session_id, msg)
      table.insert(sent, { session_id = session_id, msg = msg })
      return true
    end,
  })

  notifier:notify('session-1', 'notifications/resources/updated', { uri = 'file:///test' })

  MiniTest.expect.equality(#sent, 1)
  MiniTest.expect.equality(sent[1].msg.params.uri, 'file:///test')
end

T['notify()']['returns false when send fails'] = function()
  local Notifier = get_notifier()

  local notifier = Notifier.new({
    send_fn = function() return false end,
  })

  local ok = notifier:notify('session-1', 'test/method')
  MiniTest.expect.equality(ok, false)
end

T['notify()']['notification has no id field'] = function()
  local Notifier = get_notifier()
  local sent = {}

  local notifier = Notifier.new({
    send_fn = function(_session_id, msg)
      table.insert(sent, msg)
      return true
    end,
  })

  notifier:notify('s1', 'notifications/tools/list_changed')

  MiniTest.expect.equality(sent[1].id, nil)
end

T['broadcast()'] = MiniTest.new_set()

T['broadcast()']['sends to all specified sessions'] = function()
  local Notifier = get_notifier()
  local sent = {}

  local notifier = Notifier.new({
    send_fn = function(session_id, msg)
      table.insert(sent, { session_id = session_id, msg = msg })
      return true
    end,
  })

  notifier:broadcast('notifications/tools/list_changed', nil, { 's1', 's2', 's3' })

  MiniTest.expect.equality(#sent, 3)
  MiniTest.expect.equality(sent[1].session_id, 's1')
  MiniTest.expect.equality(sent[2].session_id, 's2')
  MiniTest.expect.equality(sent[3].session_id, 's3')
end

T['broadcast()']['includes params in broadcast'] = function()
  local Notifier = get_notifier()
  local sent = {}

  local notifier = Notifier.new({
    send_fn = function(session_id, msg)
      table.insert(sent, msg)
      return true
    end,
  })

  notifier:broadcast('notifications/progress', { progress = 50 }, { 's1' })

  MiniTest.expect.equality(#sent, 1)
  MiniTest.expect.equality(sent[1].params.progress, 50)
end

T['broadcast()']['broadcasts to all via broadcast_fn when session_ids is nil'] = function()
  local Notifier = get_notifier()
  local broadcasted = {}

  local notifier = Notifier.new({
    send_fn = function() return true end,
    broadcast_fn = function(msg)
      table.insert(broadcasted, msg)
    end,
  })

  notifier:broadcast('notifications/tools/list_changed', { test = true }, nil)

  MiniTest.expect.equality(#broadcasted, 1)
  MiniTest.expect.equality(broadcasted[1].jsonrpc, '2.0')
  MiniTest.expect.equality(broadcasted[1].method, 'notifications/tools/list_changed')
  MiniTest.expect.equality(broadcasted[1].params.test, true)
end

T['broadcast()']['does nothing when session_ids is nil and no broadcast_fn'] = function()
  local Notifier = get_notifier()
  local call_count = 0

  local notifier = Notifier.new({
    send_fn = function()
      call_count = call_count + 1
      return true
    end,
  })

  notifier:broadcast('test/method', nil, nil)

  MiniTest.expect.equality(call_count, 0)
end

T['broadcast()']['does nothing when session_ids is empty'] = function()
  local Notifier = get_notifier()
  local call_count = 0

  local notifier = Notifier.new({
    send_fn = function()
      call_count = call_count + 1
      return true
    end,
  })

  notifier:broadcast('test/method', nil, {})

  MiniTest.expect.equality(call_count, 0)
end

T['broadcast()']['continues even when some sends fail'] = function()
  local Notifier = get_notifier()
  local sent = {}

  local notifier = Notifier.new({
    send_fn = function(session_id, msg)
      table.insert(sent, session_id)
      -- s2 fails
      return session_id ~= 's2'
    end,
  })

  notifier:broadcast('test/method', nil, { 's1', 's2', 's3' })

  -- All 3 should have been attempted
  MiniTest.expect.equality(#sent, 3)
end

return T
