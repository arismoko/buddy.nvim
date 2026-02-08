local T = MiniTest.new_set()

local parser = require("buddy.transport.http.parser")

T["parser"] = MiniTest.new_set()

T["parser"]["new() creates fresh state"] = function()
  local state = parser.new()
  MiniTest.expect.equality(state.buffer, "")
  MiniTest.expect.equality(state.headers_complete, false)
  MiniTest.expect.equality(state.content_length, 0)
  MiniTest.expect.equality(state.request, nil)
  MiniTest.expect.equality(state.error, nil)
end

T["parser"]["parses complete GET request in one chunk"] = function()
  local state = parser.new()
  local request, body = parser.feed(state, "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n")

  MiniTest.expect.equality(request.method, "GET")
  MiniTest.expect.equality(request.path, "/health")
  MiniTest.expect.equality(request.version, "1.1")
  MiniTest.expect.equality(request.headers["host"], "localhost")
  MiniTest.expect.equality(body, "")
end

T["parser"]["parses complete POST request with body"] = function()
  local state = parser.new()
  local json_body = '{"jsonrpc":"2.0","method":"ping","id":1}'
  local raw = "POST /message?sessionId=123 HTTP/1.1\r\n"
    .. "Content-Type: application/json\r\n"
    .. "Content-Length: " .. #json_body .. "\r\n"
    .. "\r\n"
    .. json_body

  local request, body = parser.feed(state, raw)

  MiniTest.expect.equality(request.method, "POST")
  MiniTest.expect.equality(request.path, "/message?sessionId=123")
  MiniTest.expect.equality(request.headers["content-type"], "application/json")
  MiniTest.expect.equality(body, json_body)
end

T["parser"]["handles headers split across two chunks"] = function()
  local state = parser.new()

  -- First chunk: partial headers
  local request, body = parser.feed(state, "GET /sse HTTP/1.1\r\nHost: local")
  MiniTest.expect.equality(request, nil)
  MiniTest.expect.equality(body, nil)

  -- Second chunk: rest of headers
  request, body = parser.feed(state, "host\r\nAccept: text/event-stream\r\n\r\n")
  MiniTest.expect.equality(request.method, "GET")
  MiniTest.expect.equality(request.path, "/sse")
  MiniTest.expect.equality(request.headers["host"], "localhost")
  MiniTest.expect.equality(request.headers["accept"], "text/event-stream")
  MiniTest.expect.equality(body, "")
end

T["parser"]["handles body split across two chunks"] = function()
  local state = parser.new()
  local json_body = '{"method":"tools/list"}'

  -- First chunk: headers + partial body
  local raw_headers = "POST /message HTTP/1.1\r\n"
    .. "Content-Length: " .. #json_body .. "\r\n"
    .. "\r\n"
    .. '{"method":'

  local request, body = parser.feed(state, raw_headers)
  MiniTest.expect.equality(request, nil) -- body not complete yet
  MiniTest.expect.equality(body, nil)

  -- Second chunk: rest of body
  request, body = parser.feed(state, '"tools/list"}')
  MiniTest.expect.equality(request.method, "POST")
  MiniTest.expect.equality(body, json_body)
end

T["parser"]["handles request split across many small chunks"] = function()
  local state = parser.new()
  local full = "GET / HTTP/1.1\r\nHost: x\r\n\r\n"

  -- Feed one byte at a time
  local request, body
  for i = 1, #full do
    request, body = parser.feed(state, full:sub(i, i))
    if request then break end
  end

  MiniTest.expect.equality(request.method, "GET")
  MiniTest.expect.equality(request.path, "/")
  MiniTest.expect.equality(body, "")
end

T["parser"]["parses request with no HTTP version"] = function()
  local state = parser.new()
  local request, body = parser.feed(state, "GET /path\r\n\r\n")

  -- Method with only 2 parts (no version) should still parse
  MiniTest.expect.equality(request.method, "GET")
  MiniTest.expect.equality(request.path, "/path")
  MiniTest.expect.equality(request.version, "1.1") -- default
  MiniTest.expect.equality(body, "")
end

T["parser"]["sets error on malformed request line"] = function()
  local state = parser.new()
  -- Only one word in request line
  local request, _body = parser.feed(state, "BADREQUEST\r\n\r\n")
  MiniTest.expect.equality(request, nil)
  MiniTest.expect.equality(state.error, "Malformed request line")
end

T["parser"]["returns nil while waiting for headers"] = function()
  local state = parser.new()
  local request, body = parser.feed(state, "GET /test HTTP/1.1\r\nHost: localhost\r\n")
  -- No \r\n\r\n yet — headers not complete
  MiniTest.expect.equality(request, nil)
  MiniTest.expect.equality(body, nil)
  MiniTest.expect.equality(state.headers_complete, false)
end

T["parser"]["handles zero content-length"] = function()
  local state = parser.new()
  local request, body = parser.feed(state, "POST /test HTTP/1.1\r\nContent-Length: 0\r\n\r\n")

  MiniTest.expect.equality(request.method, "POST")
  MiniTest.expect.equality(body, "")
end

T["parser"]["reset() clears state for reuse"] = function()
  local state = parser.new()
  parser.feed(state, "GET / HTTP/1.1\r\nHost: x\r\n\r\n")

  parser.reset(state)

  MiniTest.expect.equality(state.buffer, "")
  MiniTest.expect.equality(state.headers_complete, false)
  MiniTest.expect.equality(state.content_length, 0)
  MiniTest.expect.equality(state.request, nil)
  MiniTest.expect.equality(state.error, nil)
end

T["parse_query_params"] = MiniTest.new_set()

T["parse_query_params"]["parses query string from path"] = function()
  local params, base = parser.parse_query_params("/message?sessionId=abc123&foo=bar")
  MiniTest.expect.equality(base, "/message")
  MiniTest.expect.equality(params.sessionId, "abc123")
  MiniTest.expect.equality(params.foo, "bar")
end

T["parse_query_params"]["returns empty params for path without query"] = function()
  local params, base = parser.parse_query_params("/health")
  MiniTest.expect.equality(base, "/health")
  MiniTest.expect.equality(next(params), nil)
end

T["parse_query_params"]["URL decodes values"] = function()
  local params, _ = parser.parse_query_params("/test?name=hello%20world&path=%2Ffoo%2Fbar")
  MiniTest.expect.equality(params.name, "hello world")
  MiniTest.expect.equality(params.path, "/foo/bar")
end

T["parse_query_params"]["handles single parameter"] = function()
  local params, base = parser.parse_query_params("/sse?token=abc")
  MiniTest.expect.equality(base, "/sse")
  MiniTest.expect.equality(params.token, "abc")
end

return T
