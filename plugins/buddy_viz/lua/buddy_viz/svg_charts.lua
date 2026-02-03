-- Pure Lua SVG Chart Generator
-- Generates bar charts, line graphs, etc. without external dependencies

local M = {}

-- SVG helper functions
local function escape_xml(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function rgb_to_hex(r, g, b)
  return string.format("#%02x%02x%02x", r, g, b)
end

-- Default color palette (material design inspired)
M.colors = {
  "#4285f4", -- blue
  "#ea4335", -- red
  "#fbbc04", -- yellow
  "#34a853", -- green
  "#ff6d01", -- orange
  "#46bdc6", -- cyan
  "#7baaf7", -- light blue
  "#f07b72", -- light red
}

-- Generate SVG bar chart
function M.bar_chart(opts)
  local data = opts.data          -- { {label="Q1", values={10,20}}, ... }
  local series = opts.series or {} -- {"Series A", "Series B"}
  local title = opts.title or ""
  local width = opts.width or 800
  local height = opts.height or 500
  local colors = opts.colors or M.colors

  local margin = { top = 60, right = 120, bottom = 60, left = 60 }
  local chart_w = width - margin.left - margin.right
  local chart_h = height - margin.top - margin.bottom

  -- Find max value
  local max_val = 0
  for _, d in ipairs(data) do
    for _, v in ipairs(d.values) do
      max_val = math.max(max_val, v)
    end
  end
  max_val = max_val * 1.1 -- 10% headroom

  local num_groups = #data
  local num_series = #data[1].values
  local group_width = chart_w / num_groups
  local bar_width = (group_width * 0.8) / num_series
  local bar_gap = group_width * 0.1

  local svg = {}
  table.insert(svg, string.format([[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d">]], width, height))
  
  -- Background
  table.insert(svg, [[<rect width="100%" height="100%" fill="white"/>]])

  -- Title
  if title ~= "" then
    table.insert(svg, string.format(
      [[<text x="%d" y="30" text-anchor="middle" font-size="18" font-weight="bold" font-family="Helvetica, Arial, sans-serif">%s</text>]],
      width / 2, escape_xml(title)
    ))
  end

  -- Chart area group
  table.insert(svg, string.format([[<g transform="translate(%d,%d)">]], margin.left, margin.top))

  -- Y-axis gridlines and labels
  local num_ticks = 5
  for i = 0, num_ticks do
    local y = chart_h - (i / num_ticks) * chart_h
    local val = (i / num_ticks) * max_val
    table.insert(svg, string.format(
      [[<line x1="0" y1="%d" x2="%d" y2="%d" stroke="#e0e0e0"/>]],
      y, chart_w, y
    ))
    table.insert(svg, string.format(
      [[<text x="-10" y="%d" text-anchor="end" font-size="12" font-family="Helvetica, Arial, sans-serif" dominant-baseline="middle">%.0f</text>]],
      y, val
    ))
  end

  -- Bars
  for i, d in ipairs(data) do
    local group_x = (i - 1) * group_width + bar_gap
    for j, v in ipairs(d.values) do
      local bar_h = (v / max_val) * chart_h
      local bar_x = group_x + (j - 1) * bar_width
      local bar_y = chart_h - bar_h
      local color = colors[((j - 1) % #colors) + 1]
      table.insert(svg, string.format(
        [[<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" rx="2"/>]],
        bar_x, bar_y, bar_width * 0.9, bar_h, color
      ))
      -- Value label on top of bar
      table.insert(svg, string.format(
        [[<text x="%.1f" y="%.1f" text-anchor="middle" font-size="10" font-family="Helvetica, Arial, sans-serif">%.0f</text>]],
        bar_x + bar_width * 0.45, bar_y - 5, v
      ))
    end
    -- X-axis label
    table.insert(svg, string.format(
      [[<text x="%.1f" y="%d" text-anchor="middle" font-size="12" font-family="Helvetica, Arial, sans-serif">%s</text>]],
      group_x + (num_series * bar_width) / 2, chart_h + 20, escape_xml(d.label)
    ))
  end

  -- Axes
  table.insert(svg, string.format([[<line x1="0" y1="%d" x2="%d" y2="%d" stroke="black"/>]], chart_h, chart_w, chart_h))
  table.insert(svg, string.format([[<line x1="0" y1="0" x2="0" y2="%d" stroke="black"/>]], chart_h))

  table.insert(svg, [[</g>]])

  -- Legend
  if #series > 0 then
    local legend_x = width - margin.right + 10
    local legend_y = margin.top
    for i, s in ipairs(series) do
      local color = colors[((i - 1) % #colors) + 1]
      local y = legend_y + (i - 1) * 20
      table.insert(svg, string.format(
        [[<rect x="%d" y="%d" width="12" height="12" fill="%s"/>]],
        legend_x, y, color
      ))
      table.insert(svg, string.format(
        [[<text x="%d" y="%d" font-size="11" font-family="Helvetica, Arial, sans-serif">%s</text>]],
        legend_x + 18, y + 10, escape_xml(s)
      ))
    end
  end

  table.insert(svg, [[</svg>]])
  return table.concat(svg, "\n")
end

-- Generate SVG line chart
function M.line_chart(opts)
  local data = opts.data          -- { {label="Jan", values={10,20}}, ... }
  local series = opts.series or {}
  local title = opts.title or ""
  local width = opts.width or 800
  local height = opts.height or 500
  local colors = opts.colors or M.colors

  local margin = { top = 60, right = 120, bottom = 60, left = 60 }
  local chart_w = width - margin.left - margin.right
  local chart_h = height - margin.top - margin.bottom

  -- Find max value
  local max_val = 0
  for _, d in ipairs(data) do
    for _, v in ipairs(d.values) do
      max_val = math.max(max_val, v)
    end
  end
  max_val = max_val * 1.1
  local num_points = #data
  local num_series = #data[1].values
  local x_step = chart_w / (num_points - 1)

  local svg = {}
  table.insert(svg, string.format([[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d">]], width, height))
  table.insert(svg, [[<rect width="100%" height="100%" fill="white"/>]])

  -- Title
  if title ~= "" then
    table.insert(svg, string.format(
      [[<text x="%d" y="30" text-anchor="middle" font-size="18" font-weight="bold" font-family="Helvetica, Arial, sans-serif">%s</text>]],
      width / 2, escape_xml(title)
    ))
  end

  table.insert(svg, string.format([[<g transform="translate(%d,%d)">]], margin.left, margin.top))

  -- Y-axis gridlines
  local num_ticks = 5
  for i = 0, num_ticks do
    local y = chart_h - (i / num_ticks) * chart_h
    local val = (i / num_ticks) * max_val
    table.insert(svg, string.format([[<line x1="0" y1="%d" x2="%d" y2="%d" stroke="#e0e0e0"/>]], y, chart_w, y))
    table.insert(svg, string.format(
      [[<text x="-10" y="%d" text-anchor="end" font-size="12" font-family="Helvetica, Arial, sans-serif" dominant-baseline="middle">%.0f</text>]],
      y, val
    ))
  end

  -- Lines and points for each series
  for s = 1, num_series do
    local color = colors[((s - 1) % #colors) + 1]
    local points = {}
    for i, d in ipairs(data) do
      local x = (i - 1) * x_step
      local y = chart_h - (d.values[s] / max_val) * chart_h
      table.insert(points, string.format("%.1f,%.1f", x, y))
    end
    -- Line
    table.insert(svg, string.format(
      [[<polyline points="%s" fill="none" stroke="%s" stroke-width="2"/>]],
      table.concat(points, " "), color
    ))
    -- Points
    for i, d in ipairs(data) do
      local x = (i - 1) * x_step
      local y = chart_h - (d.values[s] / max_val) * chart_h
      table.insert(svg, string.format(
        [[<circle cx="%.1f" cy="%.1f" r="4" fill="%s"/>]],
        x, y, color
      ))
    end
  end

  -- X-axis labels
  for i, d in ipairs(data) do
    local x = (i - 1) * x_step
    table.insert(svg, string.format(
      [[<text x="%.1f" y="%d" text-anchor="middle" font-size="12" font-family="Helvetica, Arial, sans-serif">%s</text>]],
      x, chart_h + 20, escape_xml(d.label)
    ))
  end

  -- Axes
  table.insert(svg, string.format([[<line x1="0" y1="%d" x2="%d" y2="%d" stroke="black"/>]], chart_h, chart_w, chart_h))
  table.insert(svg, string.format([[<line x1="0" y1="0" x2="0" y2="%d" stroke="black"/>]], chart_h))

  table.insert(svg, [[</g>]])

  -- Legend
  if #series > 0 then
    local legend_x = width - margin.right + 10
    local legend_y = margin.top
    for i, s in ipairs(series) do
      local color = colors[((i - 1) % #colors) + 1]
      local y = legend_y + (i - 1) * 20
      table.insert(svg, string.format([[<rect x="%d" y="%d" width="12" height="12" fill="%s"/>]], legend_x, y, color))
      table.insert(svg, string.format(
        [[<text x="%d" y="%d" font-size="11" font-family="Helvetica, Arial, sans-serif">%s</text>]],
        legend_x + 18, y + 10, escape_xml(s)
      ))
    end
  end

  table.insert(svg, [[</svg>]])
  return table.concat(svg, "\n")
end

-- Generate SVG pie chart
function M.pie_chart(opts)
  local data = opts.data    -- { {label="A", value=30}, {label="B", value=70} }
  local title = opts.title or ""
  local width = opts.width or 500
  local height = opts.height or 500
  local colors = opts.colors or M.colors

  local cx, cy = width / 2, height / 2
  local radius = math.min(width, height) / 2 - 60

  -- Calculate total
  local total = 0
  for _, d in ipairs(data) do
    total = total + d.value
  end

  local svg = {}
  table.insert(svg, string.format([[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d">]], width, height))
  table.insert(svg, [[<rect width="100%" height="100%" fill="white"/>]])

  -- Title
  if title ~= "" then
    table.insert(svg, string.format(
      [[<text x="%d" y="30" text-anchor="middle" font-size="18" font-weight="bold" font-family="Helvetica, Arial, sans-serif">%s</text>]],
      width / 2, escape_xml(title)
    ))
  end

  -- Draw slices
  local start_angle = -90 -- Start from top
  for i, d in ipairs(data) do
    local slice_angle = (d.value / total) * 360
    local end_angle = start_angle + slice_angle
    local color = colors[((i - 1) % #colors) + 1]

    -- Handle full circle (100%) case - draw a circle instead of arc
    if slice_angle >= 359.99 then
      table.insert(svg, string.format(
        [[<circle cx="%d" cy="%d" r="%d" fill="%s" stroke="white" stroke-width="2"/>]],
        cx, cy, radius, color
      ))
    else
      -- Convert to radians
      local start_rad = math.rad(start_angle)
      local end_rad = math.rad(end_angle)

      -- Calculate arc points
      local x1 = cx + radius * math.cos(start_rad)
      local y1 = cy + radius * math.sin(start_rad)
      local x2 = cx + radius * math.cos(end_rad)
      local y2 = cy + radius * math.sin(end_rad)

      local large_arc = slice_angle > 180 and 1 or 0

      -- SVG arc path
      local path = string.format(
        "M %d %d L %.1f %.1f A %d %d 0 %d 1 %.1f %.1f Z",
        cx, cy, x1, y1, radius, radius, large_arc, x2, y2
      )
      table.insert(svg, string.format([[<path d="%s" fill="%s" stroke="white" stroke-width="2"/>]], path, color))
    end

    -- Label
    local mid_angle = math.rad(start_angle + slice_angle / 2)
    local label_r = radius * 0.7
    local label_x = cx + label_r * math.cos(mid_angle)
    local label_y = cy + label_r * math.sin(mid_angle)
    local pct = (d.value / total) * 100
    table.insert(svg, string.format(
      [[<text x="%.1f" y="%.1f" text-anchor="middle" font-size="12" font-weight="bold" font-family="Helvetica, Arial, sans-serif" fill="white">%.0f%%</text>]],
      label_x, label_y, pct
    ))

    start_angle = end_angle
  end

  -- Legend
  local legend_y = height - 40
  local legend_x = 20
  for i, d in ipairs(data) do
    local color = colors[((i - 1) % #colors) + 1]
    local x = legend_x + (i - 1) * 100
    table.insert(svg, string.format([[<rect x="%d" y="%d" width="12" height="12" fill="%s"/>]], x, legend_y, color))
    table.insert(svg, string.format(
      [[<text x="%d" y="%d" font-size="11" font-family="Helvetica, Arial, sans-serif">%s</text>]],
      x + 16, legend_y + 10, escape_xml(d.label)
    ))
  end

  table.insert(svg, [[</svg>]])
  return table.concat(svg, "\n")
end

return M
