-- Open image from URL, file path, or clipboard
local helpers = require("buddy_viz.helpers")

local M = {}

function M.open(args)
  local source = args.source
  if not source then
    return { error = "source is required" }
  end

  local tmpdir = os.getenv("TMPDIR") or "/tmp"
  local ts = os.time()
  local path

  if source == "clipboard" then
    -- Get image from clipboard using xclip or wl-paste
    path = tmpdir .. "/clipboard-image-" .. ts .. ".png"
    local cmd
    if vim.fn.executable("wl-paste") == 1 then
      cmd = { "wl-paste", "--type", "image/png" }
    elseif vim.fn.executable("xclip") == 1 then
      cmd = { "xclip", "-selection", "clipboard", "-t", "image/png", "-o" }
    else
      return { error = "No clipboard tool found (need wl-paste or xclip)" }
    end

    local result = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      return { error = "Failed to get image from clipboard" }
    end

    local f = io.open(path, "wb")
    if not f then
      return { error = "Failed to write clipboard image" }
    end
    f:write(result)
    f:close()
  elseif source:match("^https?://") then
    -- Download from URL
    local ext = source:match("%.([^%.]+)$") or "png"
    if not ext:match("^(png|jpg|jpeg|gif|webp|svg)$") then
      ext = "png"
    end
    path = tmpdir .. "/downloaded-image-" .. ts .. "." .. ext

    local curl_result = vim.fn.system({ "curl", "-fsSL", "-o", path, source })
    if vim.v.shell_error ~= 0 then
      return { error = "Failed to download image: " .. curl_result }
    end

    -- Convert SVG to PNG if needed
    if ext == "svg" then
      local png_path = tmpdir .. "/downloaded-image-" .. ts .. ".png"
      local im_cmd = vim.fn.executable("magick") == 1 and "magick" or "convert"
      vim.fn.system({ im_cmd, "-density", "150", "-background", "white", path, png_path })
      os.remove(path)
      path = png_path
    end
  else
    -- Local file path
    path = vim.fn.expand(source)
    if vim.fn.filereadable(path) == 0 then
      return { error = "File not found: " .. path }
    end
  end

  -- Display using viewer
  vim.schedule(function()
    helpers.open_image(path)
  end)
  return {
    success = true,
    message = "Opening image: " .. path,
  }
end

return M
