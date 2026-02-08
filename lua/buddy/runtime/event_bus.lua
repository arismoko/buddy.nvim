--- Internal pub/sub event bus for buddy.nvim runtime
---
--- Provides decoupled communication between subsystems (transport, protocol,
--- services) without direct module dependencies. Subscribers receive events
--- asynchronously via vim.schedule to avoid reentrancy issues.

---@class BuddyEventBus
---@field _listeners table<string, table[]> event -> list of {cb, active}
local EventBus = {}
EventBus.__index = EventBus

--- Create a new EventBus instance
---@return BuddyEventBus
function EventBus.new()
  local self = setmetatable({}, EventBus)
  self._listeners = {}
  return self
end

--- Subscribe to an event
---
--- The callback receives the event payload table (or nil). Returns an
--- unsubscribe function that, when called, removes this specific listener.
---
---@param event string Event name (e.g. "session_connected")
---@param cb function Callback: fun(payload: table|nil)
---@return fun() unsubscribe Call to remove this listener
function EventBus:subscribe(event, cb)
  if not self._listeners[event] then
    self._listeners[event] = {}
  end

  local entry = { cb = cb, active = true }
  table.insert(self._listeners[event], entry)

  return function()
    entry.active = false
  end
end

--- Publish an event to all active subscribers
---
--- Inactive (unsubscribed) entries are pruned during iteration. Callbacks
--- are invoked synchronously in subscription order. Errors in individual
--- callbacks are caught with pcall and logged, but do not prevent other
--- subscribers from receiving the event.
---
---@param event string Event name
---@param payload table|nil Event data
function EventBus:publish(event, payload)
  local listeners = self._listeners[event]
  if not listeners then
    return
  end

  -- Iterate and prune dead entries in one pass
  local write = 0
  for i = 1, #listeners do
    local entry = listeners[i]
    if entry.active then
      write = write + 1
      listeners[write] = entry
      local ok, err = pcall(entry.cb, payload)
      if not ok then
        local log_ok, log = pcall(require, "buddy.log")
        if log_ok and log.error then
          log.error("EventBus: error in '%s' handler: %s", event, tostring(err))
        end
      end
    end
  end

  -- Trim removed entries
  for i = write + 1, #listeners do
    listeners[i] = nil
  end
end

return EventBus
