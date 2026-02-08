--- Multi-session registry for buddy.nvim
--- Stores session info at stdpath('state')..'/buddy/sessions.json'
---@tag buddy-sessions
local M = {}

local uv = vim.uv

local STALE_LOCK_SECONDS = 10

local function is_pid_alive(pid)
  if not pid or pid <= 0 then
    return false
  end

  local ok, res = pcall(uv.kill, pid, 0)
  if not ok then
    return false
  end

  if res == 0 or res == true or res == "EPERM" then
    return true
  end

  return false
end

local function try_cleanup_lock(lock_path)
  local stat = uv.fs_stat(lock_path)
  if not stat then
    return false
  end

  local pid
  local fd = uv.fs_open(lock_path, "r", 384)
  if fd then
    local data = uv.fs_read(fd, stat.size, 0) or ""
    uv.fs_close(fd)
    pid = tonumber(data:match("%d+"))
  end

  if pid and is_pid_alive(pid) then
    return false
  end

  local mtime = (stat.mtime and stat.mtime.sec) or os.time()
  local age = os.time() - mtime
  if pid or age > STALE_LOCK_SECONDS then
    pcall(uv.fs_unlink, lock_path)
    return true
  end

  return false
end

-- Seed RNG once for generate_id()
do
  local seed = (os.time() % 100000) + vim.fn.getpid()
  math.randomseed(seed)
end

--- Get the sessions file path
---@return string
local function get_sessions_path()
  local state_dir = vim.fn.stdpath("state") .. "/buddy"
  return state_dir .. "/sessions.json"
end

--- Get the lockfile path
---@return string
local function get_lock_path()
  return get_sessions_path() .. ".lock"
end

--- Ensure the sessions directory exists
local function ensure_dir()
  local state_dir = vim.fn.stdpath("state") .. "/buddy"
  if vim.fn.isdirectory(state_dir) == 0 then
    vim.fn.mkdir(state_dir, "p")
  end
end

--- Acquire a file lock (simple lockfile approach)
---@param timeout_ms? number Timeout in milliseconds (default: 1000)
---@return boolean success
---@return function|nil release Release function if acquired
local function acquire_lock(timeout_ms)
  timeout_ms = timeout_ms or 1000
  ensure_dir()
  local lock_path = get_lock_path()
  local start = uv.hrtime()
  local deadline = start + (timeout_ms * 1e6)

  while uv.hrtime() < deadline do
    -- Try to create lockfile exclusively
    local fd = uv.fs_open(lock_path, "wx", 384) -- 0600
    if fd then
      local pid = vim.fn.getpid()
      uv.fs_write(fd, tostring(pid), 0)
      uv.fs_close(fd)
      -- Return release function
      return true, function()
        pcall(uv.fs_unlink, lock_path)
      end
    end

    -- If lock exists, see if it's stale and can be cleared
    try_cleanup_lock(lock_path)
    -- Brief sleep and retry
    vim.wait(10)
  end
  return false, nil
end

--- Read sessions from disk
---@return table<string, table> sessions Map of session_id -> session data
local function read_sessions()
  local path = get_sessions_path()
  local fd = uv.fs_open(path, "r", 384)
  if not fd then
    return {}
  end

  local stat = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return {}
  end

  local data = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  if not data or data == "" then
    return {}
  end

  local ok, decoded = pcall(vim.json.decode, data)
  if not ok or type(decoded) ~= "table" then
    return {}
  end

  -- Preferred on-disk format: { version = 1, sessions = { ... } }
  if decoded.version and type(decoded.sessions) == "table" then
    return decoded
  end

  -- Back-compat: legacy format was just the sessions map
  return { version = 1, sessions = decoded }
end

--- Write sessions to disk atomically (temp + rename)
---@param sessions table<string, table>
---@return boolean success
local function write_sessions(sessions)
  ensure_dir()
  local path = get_sessions_path()
  local tmp_path = path .. ".tmp." .. vim.fn.getpid()

  -- Always write in versioned format
  if type(sessions) ~= "table" then
    return false
  end
  if not sessions.version then
    sessions = { version = 1, sessions = sessions }
  end

  local json = vim.json.encode(sessions)

  -- Write to temp file
  local fd = uv.fs_open(tmp_path, "w", 384) -- 0600
  if not fd then
    return false
  end

  local ok = uv.fs_write(fd, json, 0)
  uv.fs_close(fd)

  if not ok then
    uv.fs_unlink(tmp_path)
    return false
  end

  -- Atomic rename
  local rename_ok = uv.fs_rename(tmp_path, path)
  if not rename_ok then
    uv.fs_unlink(tmp_path)
    return false
  end

  return true
end

--- Generate a unique session ID
---@return string
local function generate_id()
  local servername = vim.v.servername
  if type(servername) == "string" and servername ~= "" then
    -- Make it key-safe (avoid slashes/spaces); keep mostly readable.
    local safe = servername:gsub("[^%w%._-]", "_")
    return safe
  end

  local pid = vim.fn.getpid()
  local time = os.time()
  local rand = math.random(1000, 9999)
  return string.format("%d_%d_%d", pid, time, rand)
end

-- Module state
local _session_id = nil
local _heartbeat_timer = nil

--- Get the current session ID
---@return string|nil session_id
function M.current_id()
  return _session_id
end

--- Register this instance in the sessions registry
---@param info table { host: string, port: number }
---@return string|nil session_id The assigned session ID, or nil on failure
function M.register(info)
  if _session_id then
    -- Already registered, just update
    M.update_heartbeat()
    return _session_id
  end

  local ok, release = acquire_lock()
  if not ok then
    vim.notify("[buddy] Failed to acquire sessions lock", vim.log.levels.WARN)
    return nil
  end

  local doc = read_sessions()
  local sessions = doc.sessions or {}
  _session_id = generate_id()

  sessions[_session_id] = {
    host = info.host or "127.0.0.1",
    port = info.port,
    pid = vim.fn.getpid(),
    cwd = vim.fn.getcwd(),
    label = nil,
    auth_token = info.auth_token,  -- Bearer token for HTTP auth (nil if auth disabled)
    started_at = os.time(),
    last_seen = os.time(),
  }

  doc.version = 1
  doc.sessions = sessions

  local write_ok = write_sessions(doc)
  release()

  if not write_ok then
    _session_id = nil
    return nil
  end

  -- Start heartbeat timer (every 15 seconds)
  M._start_heartbeat()

  return _session_id
end

--- Unregister this instance from the sessions registry
---@return boolean success
function M.unregister()
  if not _session_id then
    return true
  end

  -- Stop heartbeat
  M._stop_heartbeat()

  local ok, release = acquire_lock()
  if not ok then
    _session_id = nil
    return false
  end

  local doc = read_sessions()
  local sessions = doc.sessions or {}
  sessions[_session_id] = nil
  doc.version = 1
  doc.sessions = sessions

  local write_ok = write_sessions(doc)
  release()

  _session_id = nil
  return write_ok
end

--- Update the heartbeat timestamp for this session
---@return boolean success
function M.update_heartbeat()
  if not _session_id then
    return false
  end

  local ok, release = acquire_lock(500)
  if not ok then
    return false
  end

  local doc = read_sessions()
  local sessions = doc.sessions or {}
  if sessions[_session_id] then
    sessions[_session_id].last_seen = os.time()
    doc.version = 1
    doc.sessions = sessions
    write_sessions(doc)
  end

  release()
  return true
end

--- List all registered sessions
---@return table[] sessions Array of session info tables
function M.list()
  local ok, release = acquire_lock(500)
  if not ok then
    -- Read without lock if we can't acquire
    local doc = read_sessions()
    local sessions = doc.sessions or {}
    local result = {}
    for id, data in pairs(sessions) do
      data.id = id
      data.is_current = (id == _session_id)
      table.insert(result, data)
    end
    table.sort(result, function(a, b)
      return (a.started_at or 0) < (b.started_at or 0)
    end)
    return result
  end

  local doc = read_sessions()
  local sessions = doc.sessions or {}
  release()

  local result = {}
  for id, data in pairs(sessions) do
    data.id = id
    data.is_current = (id == _session_id)
    table.insert(result, data)
  end

  -- Sort by started_at
  table.sort(result, function(a, b)
    return (a.started_at or 0) < (b.started_at or 0)
  end)

  return result
end

--- Set a label for the current session
---@param label string The label to set
---@return boolean success
function M.set_label(label)
  if not _session_id then
    return false
  end

  local ok, release = acquire_lock()
  if not ok then
    return false
  end

  local doc = read_sessions()
  local sessions = doc.sessions or {}
  if sessions[_session_id] then
    sessions[_session_id].label = label
    doc.version = 1
    doc.sessions = sessions
    write_sessions(doc)
  end

  release()
  return true
end

--- Clean up stale sessions that haven't been seen recently
---@param max_age_seconds? number Maximum age in seconds (default: 60)
---@return number removed Number of sessions removed
function M.cleanup_stale(max_age_seconds)
  max_age_seconds = max_age_seconds or 60

  local ok, release = acquire_lock()
  if not ok then
    return 0
  end

  local doc = read_sessions()
  local sessions = doc.sessions or {}
  local now = os.time()
  local removed = 0
  local to_remove = {}

  for id, data in pairs(sessions) do
    local dominated_by_age = false
    local last_seen = data.last_seen or data.started_at or 0
    if (now - last_seen) > max_age_seconds then
      dominated_by_age = true
    end

    -- Also remove if PID is dead (regardless of age)
    local pid_dead = data.pid and not is_pid_alive(data.pid)

    if dominated_by_age or pid_dead then
      table.insert(to_remove, id)
    end
  end

  for _, id in ipairs(to_remove) do
    sessions[id] = nil
    removed = removed + 1
  end

  if removed > 0 then
    doc.version = 1
    doc.sessions = sessions
    write_sessions(doc)
  end

  release()
  return removed
end

--- Start the heartbeat timer (internal)
function M._start_heartbeat()
  if _heartbeat_timer then
    return
  end

  _heartbeat_timer = uv.new_timer()
  if _heartbeat_timer then
    _heartbeat_timer:start(15000, 15000, vim.schedule_wrap(function()
      M.update_heartbeat()
    end))
  end
end

--- Stop the heartbeat timer (internal)
function M._stop_heartbeat()
  if _heartbeat_timer then
    if not _heartbeat_timer:is_closing() then
      _heartbeat_timer:stop()
      _heartbeat_timer:close()
    end
    _heartbeat_timer = nil
  end
end

--- Get session info for the current session
---@return table|nil info Session info or nil if not registered
function M.current_info()
  if not _session_id then
    return nil
  end

  local doc = read_sessions()
  local sessions = doc.sessions or {}
  local data = sessions[_session_id]
  if data then
    data.id = _session_id
    data.is_current = true
  end
  return data
end

return M
