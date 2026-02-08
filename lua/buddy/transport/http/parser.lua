--- Incremental HTTP/1.1 request parser
--- Processes chunked TCP data into parsed HTTP requests.
--- Supports single-request-per-connection (Connection: close) semantics.

---@class HTTPParserState
---@field buffer string Accumulated data
---@field headers_complete boolean Whether headers have been fully parsed
---@field content_length number Expected body length from Content-Length header
---@field request table|nil Parsed request (method, path, headers, version)
---@field error string|nil Parse error message

local M = {}

--- Create a new parser state
---@return HTTPParserState
function M.new()
  return {
    buffer = "",
    headers_complete = false,
    content_length = 0,
    request = nil,
    error = nil,
  }
end

--- Parse the HTTP request line into method, path, version
---@param line string The request line (e.g. "GET /path HTTP/1.1")
---@return string|nil method
---@return string|nil path
---@return string version
local function _parse_request_line(line)
  local parts = {}
  for part in line:gmatch("%S+") do
    parts[#parts + 1] = part
  end

  if #parts < 2 then
    return nil, nil, "1.1"
  end

  local method = parts[1]
  local path = parts[2]
  local version = "1.1"
  if parts[3] then
    version = parts[3]:match("(%d+%.%d+)") or "1.1"
  end

  return method, path, version
end

--- Parse raw header block into a table
---@param raw string Header lines (after request line)
---@return table<string, string> headers
---@return number content_length
local function _parse_headers(raw)
  local headers = {}
  local content_length = 0

  for line in raw:gmatch("[^\r\n]+") do
    local key, value = line:match("^([^:]+):%s*(.*)")
    if key and value then
      local lower_key = key:lower()
      headers[lower_key] = value
      if lower_key == "content-length" then
        content_length = tonumber(value) or 0
      end
    end
  end

  return headers, content_length
end

--- Parse query parameters from a path
---@param path string URL path possibly containing query string
---@return table<string, string> params
---@return string base_path Path without query string
function M.parse_query_params(path)
  local query_start = path:find("?")
  if not query_start then
    return {}, path
  end

  local query_string = path:sub(query_start + 1)
  local base_path = path:sub(1, query_start - 1)

  local params = {}
  for pair in query_string:gmatch("[^&]+") do
    local key, value = pair:match("^([^=]+)=([^=]*)")
    if key then
      -- URL decode the value
      value = value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
      end)
      params[key] = value
    end
  end

  return params, base_path
end

--- Feed a chunk of data to the parser
---
--- Returns nil while more data is needed.
--- Returns (request, body) when a complete request has been parsed.
--- Sets state.error on parse failures.
---
---@param state HTTPParserState
---@param chunk string New data from TCP read
---@return table|nil request Parsed request {method, path, headers, version, params}
---@return string|nil body Request body (empty string if no body)
function M.feed(state, chunk)
  state.buffer = state.buffer .. chunk

  -- Phase 1: Parse headers if not yet complete
  if not state.headers_complete then
    local header_end = state.buffer:find("\r\n\r\n")
    if not header_end then
      -- Need more data
      return nil, nil
    end

    local header_data = state.buffer:sub(1, header_end - 1)
    local body_start = header_end + 4

    -- Parse request line (may be the only line if no headers)
    local request_line_end = header_data:find("\r\n")
    local request_line, remaining_headers

    if request_line_end then
      request_line = header_data:sub(1, request_line_end - 1)
      remaining_headers = header_data:sub(request_line_end + 2)
    else
      -- No CRLF in header block — entire block is just the request line
      request_line = header_data
      remaining_headers = ""
    end

    local method, path, version = _parse_request_line(request_line)

    if not method then
      state.error = "Malformed request line"
      return nil, nil
    end

    -- Parse headers
    local headers, content_length = _parse_headers(remaining_headers)

    state.request = {
      method = method,
      path = path,
      headers = headers,
      version = version,
    }
    state.content_length = content_length
    state.headers_complete = true
    state.buffer = state.buffer:sub(body_start)
  end

  -- Phase 2: Check if we have the full body
  if #state.buffer >= state.content_length then
    local body = state.buffer:sub(1, state.content_length)
    return state.request, body
  end

  -- Need more body data
  return nil, nil
end

--- Reset parser state for reuse
---@param state HTTPParserState
function M.reset(state)
  state.buffer = ""
  state.headers_complete = false
  state.content_length = 0
  state.request = nil
  state.error = nil
end

return M
