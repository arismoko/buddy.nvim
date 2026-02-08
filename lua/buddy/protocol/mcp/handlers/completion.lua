--- MCP completion handler: completion/complete
local registry = require("buddy.protocol.mcp.registry")

registry.register("completion/complete", function(_session_id, params)
  if not params or not params.ref then
    error("Missing required parameter: ref")
  end

  local ref = params.ref
  local argument = params.argument or {}
  local values = {}

  -- Handle prompt argument completion
  if ref.type == "ref/prompt" then
    local prompt_name = ref.name
    local arg_name = argument.name

    -- Provide suggestions based on prompt and argument
    if prompt_name == "refactor_selection" and arg_name == "goal" then
      values = {
        { value = "simplify", description = "Simplify complex code" },
        { value = "extract", description = "Extract to function/variable" },
        { value = "rename", description = "Improve naming" },
        { value = "dry", description = "Remove duplication" },
      }
    elseif prompt_name == "write_tests" and arg_name == "framework" then
      values = {
        { value = "mini.test", description = "mini.nvim test framework" },
        { value = "plenary", description = "Plenary test framework" },
        { value = "busted", description = "Busted test framework" },
      }
    elseif prompt_name == "explain_buffer" and arg_name == "focus" then
      values = {
        { value = "overall structure", description = "High-level overview" },
        { value = "error handling", description = "How errors are handled" },
        { value = "performance", description = "Performance considerations" },
        { value = "dependencies", description = "External dependencies" },
      }
    end
    -- Handle resource URI completion
  elseif ref.type == "ref/resource" then
    -- Suggest buffer URIs
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name and name ~= "" then
          table.insert(values, {
            value = "vim://buffer/" .. bufnr,
            description = vim.fn.fnamemodify(name, ":t"),
          })
        end
      end
    end
  end

  return {
    completion = {
      values = values,
      total = #values,
      hasMore = false,
    },
  }
end)
