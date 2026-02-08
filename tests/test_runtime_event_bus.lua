local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.runtime.event_bus'] = nil
  end,
}

local function new_bus()
  return require('buddy.runtime.event_bus').new()
end

T['EventBus'] = MiniTest.new_set()

T['EventBus']['new() creates independent instances'] = function()
  local bus1 = new_bus()
  local bus2 = new_bus()
  local count = 0
  bus1:subscribe('evt', function() count = count + 1 end)
  bus2:publish('evt', {})
  MiniTest.expect.equality(count, 0)
  bus1:publish('evt', {})
  MiniTest.expect.equality(count, 1)
end

T['EventBus']['subscribe and publish'] = function()
  local bus = new_bus()
  local received = nil
  bus:subscribe('test_event', function(payload)
    received = payload
  end)
  bus:publish('test_event', { key = 'value' })
  MiniTest.expect.equality(received.key, 'value')
end

T['EventBus']['publish with no subscribers does not error'] = function()
  local bus = new_bus()
  -- Should not throw
  bus:publish('nonexistent_event', { data = 1 })
  bus:publish('another_event')
end

T['EventBus']['unsubscribe removes listener'] = function()
  local bus = new_bus()
  local count = 0
  local unsub = bus:subscribe('evt', function()
    count = count + 1
  end)
  bus:publish('evt')
  MiniTest.expect.equality(count, 1)
  unsub()
  bus:publish('evt')
  MiniTest.expect.equality(count, 1)
end

T['EventBus']['multiple subscribers all receive events'] = function()
  local bus = new_bus()
  local results = {}
  bus:subscribe('multi', function(p) results[#results + 1] = 'a:' .. p.v end)
  bus:subscribe('multi', function(p) results[#results + 1] = 'b:' .. p.v end)
  bus:subscribe('multi', function(p) results[#results + 1] = 'c:' .. p.v end)
  bus:publish('multi', { v = '1' })
  MiniTest.expect.equality(#results, 3)
  MiniTest.expect.equality(results[1], 'a:1')
  MiniTest.expect.equality(results[2], 'b:1')
  MiniTest.expect.equality(results[3], 'c:1')
end

T['EventBus']['unsubscribe one does not affect others'] = function()
  local bus = new_bus()
  local a_count, b_count = 0, 0
  local unsub_a = bus:subscribe('evt', function() a_count = a_count + 1 end)
  bus:subscribe('evt', function() b_count = b_count + 1 end)

  bus:publish('evt')
  MiniTest.expect.equality(a_count, 1)
  MiniTest.expect.equality(b_count, 1)

  unsub_a()
  bus:publish('evt')
  MiniTest.expect.equality(a_count, 1)
  MiniTest.expect.equality(b_count, 2)
end

T['EventBus']['subscriber error does not prevent other subscribers'] = function()
  local bus = new_bus()
  local received = false
  bus:subscribe('err_event', function()
    error('boom')
  end)
  bus:subscribe('err_event', function()
    received = true
  end)
  bus:publish('err_event')
  MiniTest.expect.equality(received, true)
end

T['EventBus']['publish with nil payload'] = function()
  local bus = new_bus()
  local called = false
  local received_payload = 'sentinel'
  bus:subscribe('nil_evt', function(payload)
    called = true
    received_payload = payload
  end)
  bus:publish('nil_evt')
  MiniTest.expect.equality(called, true)
  MiniTest.expect.equality(received_payload, nil)
end

T['EventBus']['different events are independent'] = function()
  local bus = new_bus()
  local a_count, b_count = 0, 0
  bus:subscribe('event_a', function() a_count = a_count + 1 end)
  bus:subscribe('event_b', function() b_count = b_count + 1 end)
  bus:publish('event_a')
  MiniTest.expect.equality(a_count, 1)
  MiniTest.expect.equality(b_count, 0)
  bus:publish('event_b')
  MiniTest.expect.equality(a_count, 1)
  MiniTest.expect.equality(b_count, 1)
end

T['EventBus']['double unsubscribe is safe'] = function()
  local bus = new_bus()
  local count = 0
  local unsub = bus:subscribe('evt', function() count = count + 1 end)
  unsub()
  unsub() -- should not error
  bus:publish('evt')
  MiniTest.expect.equality(count, 0)
end

return T
