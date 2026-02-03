-- Chart generation tool
local helpers = require("buddy_viz.helpers")

local M = {}

function M.render(args)
  local chart_type = args.chart_type or args.type
  local title = args.title or ""
  local data_json = args.data
  local series_json = args.series

  if not chart_type then
    return { error = "type is required" }
  end

  if not data_json then
    return { error = "data is required" }
  end

  -- Load the SVG charts library from the internal module
  local svg_charts = require("buddy_viz.svg_charts")

  -- Parse data (handle both table and JSON string)
  local data
  if type(data_json) == "table" then
    data = data_json
  else
    local ok, decoded = pcall(vim.json.decode, data_json)
    if not ok then
      return { error = "Invalid JSON data: " .. tostring(decoded) }
    end
    data = decoded
  end

  -- Parse series (handle both table and JSON string)
  local series = {}
  if series_json then
    if type(series_json) == "table" then
      series = series_json
    else
      local sok, s = pcall(vim.json.decode, series_json)
      if sok then series = s end
    end
  end

  -- Generate SVG
  local svg
  if chart_type == "bar" then
    -- Validate bar chart data format
    if not data[1] or not data[1].values then
      return { error = 'Bar chart requires format: [{"label":"Q1","values":[10,20]},...]' }
    end
    svg = svg_charts.bar_chart({ data = data, series = series, title = title })
  elseif chart_type == "line" then
    -- Validate line chart data format
    if not data[1] or not data[1].values then
      return { error = 'Line chart requires format: [{"label":"Q1","values":[10,20]},...]' }
    end
    svg = svg_charts.line_chart({ data = data, series = series, title = title })
  elseif chart_type == "pie" then
    -- Validate pie chart data format
    if not data[1] or data[1].value == nil then
      return { error = 'Pie chart requires format: [{"label":"A","value":30},...]' }
    end
    svg = svg_charts.pie_chart({ data = data, title = title })
  else
    return { error = "Unknown chart type: " .. chart_type }
  end

  -- Write SVG and convert to PNG
  local tmpdir = os.getenv("TMPDIR") or "/tmp"
  local ts = os.time()
  local svg_file = tmpdir .. "/lua-chart-" .. ts .. ".svg"
  local png_file = tmpdir .. "/lua-chart-" .. ts .. ".png"

  local f = io.open(svg_file, "w")
  if not f then
    return { error = "Failed to write SVG file" }
  end
  f:write(svg)
  f:close()

  -- Convert to PNG
  local im_cmd = vim.fn.executable("magick") == 1 and "magick" or "convert"
  local result = vim.fn.system({
    im_cmd,
    "-density", "150",
    "-background", "white",
    svg_file,
    png_file,
  })
  local exit_code = vim.v.shell_error

  os.remove(svg_file)

  if exit_code ~= 0 then
    return { error = "ImageMagick convert failed: " .. result }
  end

  -- Open in viewer
  vim.schedule(function()
    helpers.open_viewer(png_file)
  end)
  return { success = true, message = "Rendered chart: " .. png_file }
end

return M
