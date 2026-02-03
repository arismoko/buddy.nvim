return {
  name = "macro",
  title = "Macro Recorder",
  description = "Record and play macros",
  annotations = {
    destructiveHint = true,
  },
  input_schema = {
    type = "object",
    properties = {
      action = {
        type = "string",
        enum = { "record", "stop", "play" },
        description = "record: start recording macro, stop: stop recording, play: execute macro",
      },
      register = {
        type = "string",
        description = "Register to use (a-z). Defaults to 'q'.",
      },
      count = {
        type = "number",
        description = "Number of times to play macro. Defaults to 1.",
      },
    },
    required = { "action" },
  },

  run = function(args)
    local register = args.register or "q"
    local count = args.count or 1

    if args.action == "record" then
      vim.cmd("normal! q" .. register)
      return { success = true, register = register }

    elseif args.action == "stop" then
      vim.cmd("normal! q")
      return { success = true }

    elseif args.action == "play" then
      vim.cmd("normal! " .. count .. "@" .. register)
      return { success = true, register = register, count = count }

    else
      return { success = false, error = "Unknown action: " .. tostring(args.action) }
    end
  end,
}
