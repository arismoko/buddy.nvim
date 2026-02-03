-- buddy_viz: MCP Tool Definition
-- MCP layer - formats responses, calls plugin's plain Lua API

local viz = require("buddy_viz")

local function ok(text)
  return { content = { { type = "text", text = text or "Success" } } }
end

local function err(message)
  return { isError = true, content = { { type = "text", text = message } } }
end

return {
  name = "viz",
  description = "Visualization tool for images, charts, and diagrams",
  input_schema = {
    type = "object",
    properties = {
      action = {
        type = "string",
        enum = { "chart", "image", "open", "pikchr" },
        description = "The visualization action to perform",
      },
      -- Chart action args
      type = { type = "string", enum = { "bar", "line", "pie" }, description = "Chart type (for action=chart)" },
      data = {
        type = "array",
        description = "Data points for chart",
        items = {
          type = "object",
          properties = {
            label = { type = "string", description = "Data point label" },
            values = { type = "array", items = { type = "number" }, description = "Values for each series" },
          },
          required = { "label", "values" },
        },
      },
      title = { type = "string", description = "Chart title (for action=chart)" },
      series = {
        type = "array",
        items = { type = "string" },
        description = "Series names matching values array",
      },
      -- Image action args
      path = { type = "string", description = "Absolute path to image file (for action=image)" },
      -- Open action args
      source = { type = "string", description = "Image source: URL, file path, or 'clipboard' (for action=open)" },
      -- Pikchr action args
      diagram = { type = "string", description = 'Pikchr diagram code (for action=pikchr). Example: "box \"Hello\"; arrow; circle \"World\""' },
    },
    required = { "action" },
  },
  run = function(args)
    local action = args.action

    -- Handle data and series being passed as JSON strings or tables
    if type(args.data) == "string" then
      args.data = vim.json.decode(args.data)
    end
    if type(args.series) == "string" then
      args.series = vim.json.decode(args.series)
    end

    if action == "chart" then
      local result = viz.chart.render(args)
      if result.error then
        return err(result.error)
      end
      return ok(result.message or "Chart rendered")
    elseif action == "image" then
      local result = viz.image.display(args)
      if result.error then
        return err(result.error)
      end
      return ok(result.message or "Image displayed")
    elseif action == "open" then
      local result = viz.open.open(args)
      if result.error then
        return err(result.error)
      end
      return ok(result.message or "Image opened")
    elseif action == "pikchr" then
      local result = viz.pikchr.render(args)
      if result.error then
        return err(result.error)
      end
      return ok(result.message or "Diagram rendered")
    else
      return err("Unknown action: " .. tostring(action))
    end
  end,
}
