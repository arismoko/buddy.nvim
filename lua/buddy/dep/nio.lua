-- Single import point for nvim-nio with clear error message
-- All buddy code should require("buddy.dep.nio") instead of require("nio") directly

local ok, nio = pcall(require, "nio")
if not ok then
  error(
    "buddy.nvim requires nvim-nio for async operations.\n"
      .. "Install it with your plugin manager:\n"
      .. '  lazy.nvim: { "nvim-neotest/nvim-nio" }\n'
      .. '  rocks.nvim: :Rocks install nvim-nio\n'
      .. "Error: "
      .. tostring(nio),
    2
  )
end

return nio
