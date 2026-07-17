--- *mention.nvim* Collect file mentions for pasting into Claude
---
--- Append file/line-range mentions (`@path`, `@path#L1-5`) to a single
--- mention buffer and interleave free-text instructions. The mention buffer
--- persists as a plain file, ready to open and use directly.
---
--- Setup with `require('mention').setup({})` (replace `{}` with your config).

local Mention = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |Mention.config|.
Mention.setup = function(config)
  _G.Mention = Mention

  config = H.setup_config(config)
  H.apply_config(config)
end

--- Append a mention to the mention buffer
---
--- Mode-aware: in Visual mode appends the current file with the selected line
--- range (`@path#L<n>` / `@path#L<n>-<m>`) and returns to Normal mode,
--- otherwise the whole file (`@path`). Paths are absolute with `~` for home.
--- The mention is followed by one blank line, at the end of the mention
--- buffer, and persisted.
Mention.append = function()
  local path = vim.fn.expand('%:p:~')
  if path == '' then return H.notify('cannot append: buffer has no name', 'ERROR') end
  local mention = '@' .. path .. H.range_suffix()
  -- The `x` mapping is `<Cmd>`-based, which stays in Visual mode; leave it
  -- now that the range is captured
  if vim.fn.mode():match('[vV\22]') then vim.cmd('normal! \27') end

  local buf_id = H.ensure_mention_buf()
  local last = vim.api.nvim_buf_line_count(buf_id)
  local is_empty = last == 1 and vim.api.nvim_buf_get_lines(buf_id, 0, 1, true)[1] == ''
  vim.api.nvim_buf_set_lines(buf_id, is_empty and 0 or last, last, true, { mention, '' })
  H.mention_buf_save(buf_id)

  H.notify(mention, 'INFO')
end

--- Toggle the mention buffer
---
--- Opens the mention buffer in a centered float (geometry per `config.window`,
--- minimum 40x10) with the cursor on the last line, or closes it if open.
Mention.toggle = function()
  if H.float_is_open() then return H.float_close(true) end
  H.float_open()
end

--- Module config
---
--- Default values:
Mention.config = {
  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Append mention for current file (Normal) or line range (Visual)
    append = '',

    -- Toggle the mention buffer
    toggle = '',

    -- Close the float (buffer-local in the mention buffer)
    close = 'q',
  },

  -- Float geometry (fractions of the editor size)
  window = {
    width = 0.5,
    height = 0.6,
    border = 'rounded',
  },

  -- Whether to suppress non-error feedback
  silent = false,
}

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(Mention.config)

-- Runtime state: mention buffer and window ids, resolved state path
H.cache = { buf_id = nil, win_id = nil, state_path = nil }

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.append', config.mappings.append, 'string')
  H.check_type('mappings.toggle', config.mappings.toggle, 'string')
  H.check_type('mappings.close', config.mappings.close, 'string')

  H.check_type('window', config.window, 'table')
  H.check_type('window.width', config.window.width, 'number')
  H.check_type('window.height', config.window.height, 'number')
  H.check_type('window.border', config.window.border, 'string')

  H.check_type('silent', config.silent, 'boolean')

  return config
end

H.apply_config = function(config)
  Mention.config = config

  local m = config.mappings
  H.map('n', m.append, '<Cmd>lua Mention.append()<CR>', { desc = 'Append mention for current file' })
  H.map('x', m.append, '<Cmd>lua Mention.append()<CR>', { desc = 'Append mention for selected lines' })
  H.map('n', m.toggle, '<Cmd>lua Mention.toggle()<CR>', { desc = 'Toggle mention buffer' })
end

-- Mentions -------------------------------------------------------------------
-- `#L<n>` / `#L<n>-<m>` for the Visual selection; '' outside Visual mode
H.range_suffix = function()
  if not vim.fn.mode():match('[vV\22]') then return '' end
  local from, to = vim.fn.line('v'), vim.fn.line('.')
  if from > to then from, to = to, from end
  return from == to and ('#L' .. from) or ('#L' .. from .. '-' .. to)
end

-- Mention buffer -------------------------------------------------------------
-- Path of the persisted mention buffer: keyed by cwd at first use
-- (undofile-style encoding), unaffected by later `:cd`
H.state_path = function()
  if H.cache.state_path == nil then
    local dir = vim.fs.joinpath(vim.fn.stdpath('state'), 'mention.nvim')
    vim.fn.mkdir(dir, 'p')
    H.cache.state_path = vim.fs.joinpath(dir, (vim.fn.getcwd():gsub('[\\/:]', '%%')))
  end
  return H.cache.state_path
end

H.ensure_mention_buf = function()
  if H.cache.buf_id ~= nil and vim.api.nvim_buf_is_valid(H.cache.buf_id) then return H.cache.buf_id end

  local buf_id = vim.fn.bufadd(H.state_path())
  vim.fn.bufload(buf_id)

  local group = vim.api.nvim_create_augroup('Mention', {})
  -- Autosave makes swap files redundant (and their recovery prompts ugly).
  -- Re-apply on enter/read: entering a `bufadd()`ed buffer for the first
  -- time re-initializes its buffer-local options (Neovim 0.13).
  local swapoff = function() vim.bo[buf_id].swapfile = false end
  swapoff()
  vim.api.nvim_create_autocmd(
    { 'BufEnter', 'BufReadPost' },
    { group = group, buffer = buf_id, callback = swapoff, desc = 'Keep mention buffer swapless' }
  )

  -- Buffer-local close key (the default `q` sacrifices macro recording in
  -- this buffer); `nowait` beats non-buffer mappings sharing the prefix
  H.map('n', Mention.config.mappings.close, function()
    if H.float_is_open() then H.float_close(true) end
  end, { buffer = buf_id, nowait = true, desc = 'Close mention buffer' })

  -- Boundary saves suffice: edits happen only in the float and every way out
  -- of it fires BufLeave; VimLeavePre covers quitting from inside it.
  local save = function() H.mention_buf_save(buf_id) end
  vim.api.nvim_create_autocmd(
    'BufLeave',
    { group = group, buffer = buf_id, callback = save, desc = 'Autosave mention buffer' }
  )
  vim.api.nvim_create_autocmd(
    'VimLeavePre',
    { group = group, callback = save, desc = 'Autosave mention buffer' }
  )

  H.cache.buf_id = buf_id
  return buf_id
end

-- Float window ---------------------------------------------------------------
H.float_is_open = function()
  return H.cache.win_id ~= nil and vim.api.nvim_win_is_valid(H.cache.win_id)
end

H.float_close = function(refocus)
  local win_id, prev_win = H.cache.win_id, H.cache.prev_win
  H.cache.win_id = nil
  if win_id == nil or not vim.api.nvim_win_is_valid(win_id) then return end
  vim.api.nvim_win_close(win_id, false)
  if refocus and prev_win ~= nil and vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end
end

H.float_open = function()
  local buf_id = H.ensure_mention_buf()
  H.cache.prev_win = vim.api.nvim_get_current_win()

  local width = math.max(40, math.floor(vim.o.columns * Mention.config.window.width))
  local height = math.max(10, math.floor(vim.o.lines * Mention.config.window.height))
  H.cache.win_id = vim.api.nvim_open_win(buf_id, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2) - 1,
    border = Mention.config.window.border,
    title = ' \u{f1fa} mention.nvim ', -- nf-fa-at + plugin name
    title_pos = 'center',
  })
  vim.api.nvim_win_set_cursor(H.cache.win_id, { vim.api.nvim_buf_line_count(buf_id), 0 })

  -- Focus-leave auto-close. Scheduled: closing a window during WinLeave is
  -- forbidden. No refocus - the user already went somewhere.
  vim.api.nvim_create_autocmd('WinLeave', {
    group = vim.api.nvim_create_augroup('Mention', { clear = false }),
    buffer = buf_id,
    once = true,
    callback = function() vim.schedule(function() H.float_close(false) end) end,
    desc = 'Auto-close mention buffer float',
  })
end

H.mention_buf_save = function(buf_id)
  if not vim.api.nvim_buf_is_valid(buf_id) then return end
  vim.api.nvim_buf_call(buf_id, function() vim.cmd('silent update') end)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mention.nvim) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.notify = function(msg, level_name)
  if Mention.config.silent and level_name ~= 'ERROR' then return end
  vim.notify('(mention.nvim) ' .. msg, vim.log.levels[level_name])
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

return Mention
