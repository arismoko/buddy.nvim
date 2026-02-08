--- MCP Methods — Compatibility Facade
--- Re-exports handlers from protocol/mcp/handlers/* and content helpers from protocol/mcp/content.lua
--- This module exists for backward compatibility. New code should use:
---   require("buddy.protocol.mcp.registry") for handler lookup
---   require("buddy.protocol.mcp.content") for content constructors
local M = {}

-- Load all handler modules (they self-register into the registry)
require("buddy.protocol.mcp.handlers.core")
require("buddy.protocol.mcp.handlers.tools")
require("buddy.protocol.mcp.handlers.resources")
require("buddy.protocol.mcp.handlers.prompts")
require("buddy.protocol.mcp.handlers.completion")
require("buddy.protocol.mcp.handlers.notifications")

-- Re-export content helpers
local content = require("buddy.protocol.mcp.content")
M.image_content = content.image_content
M.audio_content = content.audio_content
M.resource_content = content.resource_content
M.embedded_resource = content.embedded_resource
M.embedded_blob = content.embedded_blob
M.resource_link = content.resource_link

-- Re-export log level accessor from core handler
local core = require("buddy.protocol.mcp.handlers.core")
M.get_log_level = core.get_log_level

-- Notification callback state — still owned here for backward compatibility
-- (router.lua sets this via methods.set_notify_callback)
M._notify_callback = nil

function M.set_notify_callback(callback)
  M._notify_callback = callback
end

function M.notify_tools_changed()
  if M._notify_callback then
    M._notify_callback({
      method = "notifications/tools/list_changed",
    })
  end
end

function M.notify_prompts_changed()
  if M._notify_callback then
    M._notify_callback({
      method = "notifications/prompts/list_changed",
    })
  end
end

function M.notify_resources_changed()
  if M._notify_callback then
    M._notify_callback({
      method = "notifications/resources/list_changed",
    })
  end
end

--- Notify subscribers that a resource was updated
---@param uri string The resource URI that changed
function M.notify_resource_updated(uri)
  if M._notify_callback then
    M._notify_callback({
      method = "notifications/resources/updated",
      params = { uri = uri },
    })
  end
end

--- Set up buffer change watching for resource notifications
---@param bufnr number Buffer number
---@param uri string Resource URI
function M.watch_buffer(bufnr, uri)
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      M.notify_resource_updated(uri)
      return false  -- keep watching
    end,
  })
end

--- Send cancellation notification to client
---@param request_id string|number The request ID to cancel
---@param reason? string Optional reason
function M.send_cancelled(request_id, reason)
  if M._notify_callback then
    M._notify_callback({
      method = "notifications/cancelled",
      params = {
        requestId = request_id,
        reason = reason,
      },
    })
  end
end

-- Proxy handler lookups through the registry for backward compatibility
-- Supports: methods["tools/list"], methods["initialize"], etc.
local registry = require("buddy.protocol.mcp.registry")
setmetatable(M, {
  __index = function(_self, key)
    return registry.get(key)
  end,
})

return M
