-- Shared helpers for viz tools
-- Uses Kitty graphics protocol for image display

local M = {}

local stdout = vim.loop.new_tty(1, false)
if not stdout then
  error("failed to open stdout")
end

local uv = vim.uv or vim.loop

--------------------------------------------------------------------------------
-- Base64 encoding (from PicVim)
--------------------------------------------------------------------------------

local ba = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function enc(data)
  return (
    (data:gsub(".", function(x)
      local r, b = "", x:byte()
      for i = 8, 1, -1 do
        r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0")
      end
      return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
      if #x < 6 then
        return ""
      end
      local c = 0
      for i = 1, 6 do
        c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0)
      end
      return ba:sub(c + 1, c + 1)
    end) .. ({ "", "==", "=" })[#data % 3 + 1]
  )
end

M.base64_encode = enc

--------------------------------------------------------------------------------
-- Image Viewer State
--------------------------------------------------------------------------------

local state = nil
local debounce_timer = nil
local DEBOUNCE_MS = 50
local keypress_state = { o_x = 0, o_y = 0, zoom = 0 }

local function delete_kitty_image()
  stdout:write("\27_Ga=d\27\\")
end

local function close_viewer()
  if state then
    if debounce_timer then
      debounce_timer:stop()
      debounce_timer:close()
      debounce_timer = nil
    end
    -- Reset keypress state
    keypress_state = { o_x = 0, o_y = 0, zoom = 0 }
    -- Delete the kitty image
    delete_kitty_image()
    -- Capture state before nilling
    local win = state.win
    local buf = state.buf
    local temp_scaled = state.temp_scaled
    local temp_png = state.temp_png
    -- Nil state FIRST to prevent autocmd re-entry
    state = nil
    -- Close window
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    -- Delete buffer
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    -- Cleanup temp files
    if temp_scaled and vim.fn.filereadable(temp_scaled) == 1 then
      vim.fn.delete(temp_scaled)
    end
    if temp_png and vim.fn.filereadable(temp_png) == 1 then
      vim.fn.delete(temp_png)
    end
  end
end

M.close_viewer = close_viewer

local function pngify(filepath)
  local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
  if ext == "png" then
    return filepath, nil
  end
  local temp_file = "/tmp/nvim_buddy_pngify.png"
  local cmd
  if ext == "gif" then
    cmd = "magick " .. vim.fn.shellescape(filepath) .. "[0] " .. temp_file
  else
    cmd = "magick " .. vim.fn.shellescape(filepath) .. " " .. temp_file
  end
  local result = vim.fn.system(cmd)
  if vim.v.shell_error == 0 then
    return temp_file, temp_file
  else
    return nil, nil
  end
end

local function rescale(filepath, w, h, zoom, o_x, o_y)
  local temp_file = "/tmp/nvim_buddy_scaled.png"
  if vim.fn.filereadable(temp_file) == 1 then
    vim.fn.delete(temp_file)
  end

  -- Pixel dimensions (terminal cells * approximate pixel multipliers)
  local r_w = math.floor(w * zoom * 10)
  local r_h = math.floor(h * zoom * 23)
  local extent_w = w * 10
  local extent_h = h * 23

  local o_x_str = o_x >= 0 and "+" .. o_x or tostring(o_x)
  local o_y_str = o_y >= 0 and "+" .. o_y or tostring(o_y)

  local cmd = string.format(
    "magick %s -resize %dx%d -background none -gravity center -extent %dx%d%s%s %s",
    vim.fn.shellescape(filepath),
    r_w, r_h,
    extent_w, extent_h, o_x_str, o_y_str,
    temp_file
  )

  local result = vim.fn.system(cmd)
  if vim.v.shell_error == 0 then
    return temp_file
  else
    return nil
  end
end

local function draw_image(x, y, w, h)
  if not state or not state.png_path then return end

  -- Rescale with current zoom/pan
  local scaled = rescale(state.png_path, w, h, state.zoom, state.offset_x, state.offset_y)
  if not scaled then
    vim.notify("Failed to rescale image", vim.log.levels.ERROR)
    return
  end
  state.temp_scaled = scaled

  -- Read the scaled image
  local file = io.open(scaled, "rb")
  if not file then
    vim.notify("Failed to open scaled image", vim.log.levels.ERROR)
    return
  end
  local data = file:read("*all")
  file:close()

  local encoded_data = enc(data)
  local pos = 1
  local chunk_size = 4096

  -- Position cursor before drawing
  stdout:write("\27[" .. (x + 2) .. ";" .. (y + 4) .. "H")

  while pos <= #encoded_data do
    local chunk = encoded_data:sub(pos, pos + chunk_size - 1)
    pos = pos + chunk_size
    local m = (pos <= #encoded_data) and "1" or "0"

    -- Use fixed image ID i=10 with a=T (transmit and display)
    local cmd = "\27_Ga=T,i=10,q=1,r=" .. h .. ",c=" .. w .. ",C=1,f=100,m=" .. m .. ";" .. chunk .. "\27\\"
    stdout:write(cmd)
    uv.sleep(1)
  end

  -- Reposition cursor
  stdout:write("\27[" .. (x + 1) .. ";" .. (y + 3) .. "H")
end

local function redraw()
  if not state or not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end

  local win_height = vim.api.nvim_win_get_height(state.win)
  local win_width = vim.api.nvim_win_get_width(state.win)
  local win_pos = vim.api.nvim_win_get_position(state.win)
  local x, y = win_pos[1], win_pos[2]

  -- Apply accumulated keypress deltas
  state.offset_x = state.offset_x + keypress_state.o_x
  state.offset_y = state.offset_y + keypress_state.o_y
  state.zoom = state.zoom + keypress_state.zoom
  keypress_state = { o_x = 0, o_y = 0, zoom = 0 }

  -- Clamp offsets
  local MAX_OFFSET_X = (win_width * 10) - 150
  local MIN_OFFSET_X = (-win_width * 10) + 150
  local MAX_OFFSET_Y = (win_height * 23) - 150
  local MIN_OFFSET_Y = (-win_height * 23) + 150

  state.offset_x = math.max(MIN_OFFSET_X, math.min(MAX_OFFSET_X, state.offset_x))
  state.offset_y = math.max(MIN_OFFSET_Y, math.min(MAX_OFFSET_Y, state.offset_y))
  state.zoom = math.max(0.1, math.min(5, state.zoom))

  draw_image(x, y, win_width - 6, win_height - 1)
end

local function schedule_redraw()
  -- Debounce: cancel pending, schedule new redraw after delay
  -- This batches multiple rapid keypresses into one render
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
  end
  debounce_timer = vim.defer_fn(function()
    redraw()
    debounce_timer = nil
  end, DEBOUNCE_MS)
end

local function setup_keymaps(buf)
  local opts = { buffer = buf, noremap = true, silent = true, nowait = true }

  -- Close
  vim.keymap.set("n", "q", close_viewer, opts)
  vim.keymap.set("n", "<Esc>", close_viewer, opts)

  -- Zoom in
  vim.keymap.set("n", "=", function()
    keypress_state.zoom = keypress_state.zoom + 0.2
    schedule_redraw()
  end, opts)
  vim.keymap.set("n", "+", function()
    keypress_state.zoom = keypress_state.zoom + 0.2
    schedule_redraw()
  end, opts)

  -- Zoom out
  vim.keymap.set("n", "-", function()
    keypress_state.zoom = keypress_state.zoom - 0.2
    schedule_redraw()
  end, opts)
  vim.keymap.set("n", "_", function()
    keypress_state.zoom = keypress_state.zoom - 0.2
    schedule_redraw()
  end, opts)

  -- Pan (hjkl)
  vim.keymap.set("n", "h", function()
    keypress_state.o_x = keypress_state.o_x - 30
    schedule_redraw()
  end, opts)
  vim.keymap.set("n", "l", function()
    keypress_state.o_x = keypress_state.o_x + 30
    schedule_redraw()
  end, opts)
  vim.keymap.set("n", "k", function()
    keypress_state.o_y = keypress_state.o_y - 30
    schedule_redraw()
  end, opts)
  vim.keymap.set("n", "j", function()
    keypress_state.o_y = keypress_state.o_y + 30
    schedule_redraw()
  end, opts)

  -- Arrow keys for pan
  vim.keymap.set("n", "<Left>", function()
    keypress_state.o_x = keypress_state.o_x - 30
    schedule_redraw()
  end, opts)
  vim.keymap.set("n", "<Right>", function()
    keypress_state.o_x = keypress_state.o_x + 30
    schedule_redraw()
  end, opts)
  vim.keymap.set("n", "<Up>", function()
    keypress_state.o_y = keypress_state.o_y - 30
    schedule_redraw()
  end, opts)
  vim.keymap.set("n", "<Down>", function()
    keypress_state.o_y = keypress_state.o_y + 30
    schedule_redraw()
  end, opts)

  -- Half-page scroll (Ctrl+d/u) - zoom
  vim.keymap.set("n", "<C-d>", function()
    keypress_state.zoom = keypress_state.zoom - 0.5
    schedule_redraw()
  end, opts)
  vim.keymap.set("n", "<C-u>", function()
    keypress_state.zoom = keypress_state.zoom + 0.5
    schedule_redraw()
  end, opts)

  -- Reset
  vim.keymap.set("n", "r", function()
    state.zoom = 0.9
    state.offset_x = 0
    state.offset_y = 0
    keypress_state = { o_x = 0, o_y = 0, zoom = 0 }
    redraw()
  end, opts)
end

function M.open_viewer(path)
  -- Close existing viewer
  close_viewer()

  -- Convert to PNG if needed
  local png_path, temp_png = pngify(path)
  if not png_path then
    vim.notify("Failed to convert image to PNG", vim.log.levels.ERROR)
    return nil
  end

  -- Calculate window size (95% of editor)
  local ui = vim.api.nvim_list_uis()[1]
  local width = math.floor(ui.width * 0.95)
  local height = math.floor(ui.height * 0.95)
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. vim.fn.fnamemodify(path, ":t") .. " ",
    title_pos = "center",
  })

  -- Set window options
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })
  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("list", false, { win = win })
  vim.api.nvim_set_option_value("cursorline", false, { win = win })

  state = {
    win = win,
    buf = buf,
    path = path,
    png_path = png_path,
    temp_png = temp_png,
    temp_scaled = nil,
    zoom = 0.9,
    offset_x = 0,
    offset_y = 0,
  }

  setup_keymaps(buf)

  -- Set up autocmd to clean up on window close
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if not state then return end
      delete_kitty_image()
      if state.temp_scaled and vim.fn.filereadable(state.temp_scaled) == 1 then
        vim.fn.delete(state.temp_scaled)
      end
      if state.temp_png and vim.fn.filereadable(state.temp_png) == 1 then
        vim.fn.delete(state.temp_png)
      end
      state = nil
    end,
  })

  -- Redraw on window resize
  vim.api.nvim_create_autocmd("WinResized", {
    callback = function()
      if state and state.win and vim.api.nvim_win_is_valid(state.win) then
        -- Check if our window was resized
        for _, w in ipairs(vim.v.event.windows) do
          if w == state.win then
            delete_kitty_image()
            redraw()
            break
          end
        end
      end
    end,
  })

  -- Redraw and recenter on terminal/nvim resize
  vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      if state and state.win and vim.api.nvim_win_is_valid(state.win) then
        -- Recenter the floating window
        local new_width = math.floor(vim.o.columns * 0.8)
        local new_height = math.floor(vim.o.lines * 0.8)
        local new_row = math.floor((vim.o.lines - new_height) / 2)
        local new_col = math.floor((vim.o.columns - new_width) / 2)

        vim.api.nvim_win_set_config(state.win, {
          relative = "editor",
          width = new_width,
          height = new_height,
          row = new_row,
          col = new_col,
        })

        delete_kitty_image()
        redraw()
      end
    end,
  })

  -- Initial render
  redraw()

  return true
end

--------------------------------------------------------------------------------
-- Pikchr Helper
--------------------------------------------------------------------------------

function M.find_pikchr_bin()
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    local bin = path .. "/bin/pikchr"
    if vim.fn.filereadable(bin) == 1 then
      return bin
    end
  end
  return nil
end

return M
