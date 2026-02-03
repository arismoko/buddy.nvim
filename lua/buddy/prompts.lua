local M = {}

-- Built-in prompts for common Neovim tasks
local prompts = {
  {
    name = "explain_buffer",
    title = "Explain Buffer",
    description = "Explain the current buffer's code",
    arguments = {
      { name = "focus", description = "What aspect to focus on (optional)", required = false },
    },
  },
  {
    name = "refactor_selection",
    title = "Refactor Selection",
    description = "Suggest refactoring for selected code",
    arguments = {
      { name = "goal", description = "Refactoring goal (e.g., simplify, extract, rename)", required = true },
    },
  },
  {
    name = "fix_diagnostics",
    title = "Fix Diagnostics",
    description = "Fix LSP diagnostics in current buffer",
    arguments = {},
  },
  {
    name = "write_tests",
    title = "Write Tests",
    description = "Generate tests for the current buffer",
    arguments = {
      { name = "framework", description = "Test framework to use", required = false },
    },
  },
}

function M.list()
  return prompts
end

function M.get(name, arguments)
  for _, prompt in ipairs(prompts) do
    if prompt.name == name then
      local messages = {}
      
      if name == "explain_buffer" then
        local focus = arguments.focus or "overall structure and purpose"
        table.insert(messages, {
          role = "user",
          content = {
            { type = "text", text = "Explain this code, focusing on: " .. focus },
            { type = "resource", resource = { uri = "vim://buffer/0" } },
          },
        })
      elseif name == "refactor_selection" then
        table.insert(messages, {
          role = "user",
          content = {
            { type = "text", text = "Refactor the selected code with goal: " .. (arguments.goal or "improve") },
          },
        })
      elseif name == "fix_diagnostics" then
        table.insert(messages, {
          role = "user",
          content = {
            { type = "text", text = "Fix all LSP diagnostics in the current buffer" },
          },
        })
      elseif name == "write_tests" then
        local framework = arguments.framework or "the appropriate test framework"
        table.insert(messages, {
          role = "user",
          content = {
            { type = "text", text = "Write tests using " .. framework .. " for this code:" },
            { type = "resource", resource = { uri = "vim://buffer/0" } },
          },
        })
      end
      
      return {
        description = prompt.description,
        messages = messages,
      }
    end
  end
  return nil
end

return M
