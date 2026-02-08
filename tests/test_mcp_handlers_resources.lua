-- Tests for protocol/mcp/handlers/resources.lua
local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.mcp'] = nil
    package.loaded['buddy.mcp.methods'] = nil
    package.loaded['buddy.protocol.mcp.dispatcher'] = nil
    package.loaded['buddy.protocol.mcp.registry'] = nil
    package.loaded['buddy.protocol.jsonrpc'] = nil
    package.loaded['buddy.protocol.mcp.handlers.core'] = nil
    package.loaded['buddy.protocol.mcp.handlers.tools'] = nil
    package.loaded['buddy.protocol.mcp.handlers.resources'] = nil
    package.loaded['buddy.protocol.mcp.handlers.prompts'] = nil
    package.loaded['buddy.protocol.mcp.handlers.completion'] = nil
    package.loaded['buddy.protocol.mcp.handlers.notifications'] = nil
    package.loaded['buddy.tools'] = nil
    package.loaded['buddy.tools.executor'] = nil
    package.loaded['buddy.resources'] = nil
  end,
}

local function mcp_request(session_id, id, method, params)
  local dispatcher = require('buddy.protocol.mcp.dispatcher')
  return dispatcher.handle_request(session_id, {
    jsonrpc = '2.0',
    id = id,
    method = method,
    params = params or {},
  })
end

T['resources/list'] = MiniTest.new_set()

T['resources/list']['returns resource list'] = function()
  local response = mcp_request('s1', 1, 'resources/list')
  MiniTest.expect.equality(response.id, 1)
  MiniTest.expect.equality(type(response.result.resources), 'table')
end

T['resources/read'] = MiniTest.new_set()

T['resources/read']['errors on missing uri'] = function()
  local response = mcp_request('s1', 2, 'resources/read', {})
  MiniTest.expect.equality(response.error.code, -32603)
end

T['resources/subscribe'] = MiniTest.new_set()

T['resources/subscribe']['errors on missing uri'] = function()
  local response = mcp_request('s1', 3, 'resources/subscribe', {})
  MiniTest.expect.equality(response.error.code, -32603)
end

T['resources/subscribe']['succeeds with valid uri'] = function()
  local response = mcp_request('s1', 4, 'resources/subscribe', { uri = 'vim://buffer/1' })
  MiniTest.expect.equality(response.id, 4)
  -- Result is vim.empty_dict() — a table
  MiniTest.expect.equality(type(response.result), 'table')
end

T['resources/unsubscribe'] = MiniTest.new_set()

T['resources/unsubscribe']['errors on missing uri'] = function()
  local response = mcp_request('s1', 5, 'resources/unsubscribe', {})
  MiniTest.expect.equality(response.error.code, -32603)
end

T['resources/unsubscribe']['succeeds with valid uri'] = function()
  local response = mcp_request('s1', 6, 'resources/unsubscribe', { uri = 'vim://buffer/1' })
  MiniTest.expect.equality(response.id, 6)
  MiniTest.expect.equality(type(response.result), 'table')
end

T['resources/subscribe']['subscribe then unsubscribe roundtrip'] = function()
  local sub_response = mcp_request('s1', 7, 'resources/subscribe', { uri = 'vim://buffer/1' })
  MiniTest.expect.equality(sub_response.id, 7)

  local unsub_response = mcp_request('s1', 8, 'resources/unsubscribe', { uri = 'vim://buffer/1' })
  MiniTest.expect.equality(unsub_response.id, 8)
end

-- === Content helpers ===

T['content helpers'] = MiniTest.new_set()

T['content helpers']['image_content constructs correctly'] = function()
  local content = require('buddy.protocol.mcp.content')
  local result = content.image_content('abc123', 'image/jpeg')
  MiniTest.expect.equality(result.type, 'image')
  MiniTest.expect.equality(result.data, 'abc123')
  MiniTest.expect.equality(result.mimeType, 'image/jpeg')
end

T['content helpers']['image_content defaults to png'] = function()
  local content = require('buddy.protocol.mcp.content')
  local result = content.image_content('abc123')
  MiniTest.expect.equality(result.mimeType, 'image/png')
end

T['content helpers']['resource_content constructs correctly'] = function()
  local content = require('buddy.protocol.mcp.content')
  local result = content.resource_content('vim://buffer/1', 'text/lua', 'print("hi")')
  MiniTest.expect.equality(result.type, 'resource')
  MiniTest.expect.equality(result.resource.uri, 'vim://buffer/1')
  MiniTest.expect.equality(result.resource.mimeType, 'text/lua')
  MiniTest.expect.equality(result.resource.text, 'print("hi")')
end

T['content helpers']['embedded_resource constructs correctly'] = function()
  local content = require('buddy.protocol.mcp.content')
  local result = content.embedded_resource('vim://buffer/1', 'hello', 'text/plain')
  MiniTest.expect.equality(result.type, 'resource')
  MiniTest.expect.equality(result.resource.text, 'hello')
end

T['content helpers']['embedded_blob constructs correctly'] = function()
  local content = require('buddy.protocol.mcp.content')
  local result = content.embedded_blob('vim://file/x.png', 'base64data', 'image/png')
  MiniTest.expect.equality(result.resource.blob, 'base64data')
  MiniTest.expect.equality(result.resource.mimeType, 'image/png')
end

T['content helpers']['resource_link requires name'] = function()
  local content = require('buddy.protocol.mcp.content')
  MiniTest.expect.error(function()
    content.resource_link('vim://buffer/1', '')
  end)
end

T['content helpers']['resource_link constructs correctly'] = function()
  local content = require('buddy.protocol.mcp.content')
  local result = content.resource_link('vim://buffer/1', 'Buffer 1', 'A buffer', 'text/plain')
  MiniTest.expect.equality(result.type, 'resource_link')
  MiniTest.expect.equality(result.uri, 'vim://buffer/1')
  MiniTest.expect.equality(result.name, 'Buffer 1')
  MiniTest.expect.equality(result.description, 'A buffer')
  MiniTest.expect.equality(result.mimeType, 'text/plain')
end

T['content helpers']['audio_content constructs correctly'] = function()
  local content = require('buddy.protocol.mcp.content')
  local result = content.audio_content('audiodata', 'audio/wav')
  MiniTest.expect.equality(result.type, 'audio')
  MiniTest.expect.equality(result.data, 'audiodata')
  MiniTest.expect.equality(result.mimeType, 'audio/wav')
end

return T
