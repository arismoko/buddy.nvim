--- MCP content type constructors
--- Helpers for building image, audio, resource, and link content blocks
local M = {}

--- Create an ImageContent block
---@param base64_data string Base64-encoded image data
---@param mime_type? string MIME type (default: image/png)
---@return table
function M.image_content(base64_data, mime_type)
  return {
    type = "image",
    data = base64_data,
    mimeType = mime_type or "image/png",
  }
end

--- Create an AudioContent block
---@param base64_data string Base64-encoded audio data
---@param mime_type string MIME type (e.g., "audio/wav", "audio/mp3", "audio/ogg")
---@return table
function M.audio_content(base64_data, mime_type)
  return {
    type = "audio",
    data = base64_data,
    mimeType = mime_type,
  }
end

--- Create a ResourceContent block (text-based)
---@param uri string Resource URI
---@param mime_type? string MIME type (default: text/plain)
---@param text string Text content
---@return table
function M.resource_content(uri, mime_type, text)
  return {
    type = "resource",
    resource = {
      uri = uri,
      mimeType = mime_type or "text/plain",
      text = text,
    },
  }
end

--- Create an EmbeddedResource content block
--- Use when returning actual resource content in a tool response
---@param uri string Resource URI
---@param text string Text content
---@param mime_type? string MIME type (default: text/plain)
---@return table
function M.embedded_resource(uri, text, mime_type)
  return {
    type = "resource",
    resource = {
      uri = uri,
      mimeType = mime_type or "text/plain",
      text = text,
    },
  }
end

--- Create an EmbeddedResource with binary blob
---@param uri string Resource URI
---@param blob string Base64-encoded binary data
---@param mime_type string MIME type
---@return table
function M.embedded_blob(uri, blob, mime_type)
  return {
    type = "resource",
    resource = {
      uri = uri,
      mimeType = mime_type,
      blob = blob,
    },
  }
end

--- Create a ResourceLink content block (reference without content)
---@param uri string Resource URI
---@param name string Human-readable name (required)
---@param description? string Description
---@param mime_type? string MIME type
---@return table
function M.resource_link(uri, name, description, mime_type)
  if not name or name == "" then
    error("ResourceLink requires a name")
  end
  local link = {
    type = "resource_link",
    uri = uri,
    name = name,
  }
  if description then link.description = description end
  if mime_type then link.mimeType = mime_type end
  return link
end

return M
