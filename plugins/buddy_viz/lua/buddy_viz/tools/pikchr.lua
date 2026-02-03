-- Pikchr diagram rendering tool
local helpers = require("buddy_viz.helpers")

local M = {}

function M.render(args)
  local diagram = args.diagram
  if not diagram then
    return { error = "diagram is required" }
  end

  local bin_path = helpers.find_pikchr_bin()
  if not bin_path then
    return { error = "Pikchr binary not found in runtimepath" }
  end

  local tmpdir = os.getenv("TMPDIR") or "/tmp"
  local ts = os.time()
  local input_file = tmpdir .. "/pikchr-input-" .. ts .. ".pikchr"
  local svg_file = tmpdir .. "/pikchr-output-" .. ts .. ".svg"
  local png_file = tmpdir .. "/pikchr-output-" .. ts .. ".png"

  -- Write diagram to temp file
  local f = io.open(input_file, "w")
  if not f then
    return { error = "Failed to write temp file" }
  end
  f:write(diagram)
  f:close()

  -- Run pikchr (outputs SVG to stdout)
  local svg_content = vim.fn.system({ bin_path, "--svg-only", input_file })
  local exit_code = vim.v.shell_error

  os.remove(input_file)

  if exit_code ~= 0 then
    return { error = "Pikchr failed: " .. svg_content }
  end

  -- Write SVG
  local svg_f = io.open(svg_file, "w")
  if not svg_f then
    return { error = "Failed to write SVG file" }
  end
  svg_f:write(svg_content)
  svg_f:close()

  -- Convert to PNG
  local im_cmd = vim.fn.executable("magick") == 1 and "magick" or "convert"
  local convert_result = vim.fn.system({ im_cmd, "-density", "150", "-background", "white", svg_file, png_file })
  local convert_exit = vim.v.shell_error

  os.remove(svg_file)

  if convert_exit ~= 0 then
    return { error = "ImageMagick failed: " .. convert_result }
  end

  -- Open in viewer
  vim.schedule(function()
    helpers.open_viewer(png_file)
  end)
  return { success = true, message = "Rendered: " .. png_file }
end

return M
