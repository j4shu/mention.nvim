--- *mention.nvim* Collect file mentions for pasting into Claude
---
--- Append file/line-range mentions (`@path`, `@path#L1-5`) to a single
--- collection buffer, interleave free-text instructions, and copy the whole
--- collection to the system clipboard.
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

--- Append a mention to the collection
---
--- Mode-aware: in Visual mode appends the current file with the selected line
--- range (`@path#L<n>` / `@path#L<n>-<m>`), otherwise the whole file
--- (`@path`). Paths are absolute with `~` for home. The mention is followed
--- by one blank line, at the end of the collection, and persisted.
Mention.append = function()
  local path = vim.fn.expand('%:p:~')
  if path == '' then return H.notify('cannot append: buffer has no name', 'ERROR') end
  local mention = '@' .. path .. H.range_suffix()

  local buf_id = H.ensure_collection_buf()
  local last = vim.api.nvim_buf_line_count(buf_id)
  local is_empty = last == 1 and vim.api.nvim_buf_get_lines(buf_id, 0, 1, true)[1] == ''
  vim.api.nvim_buf_set_lines(buf_id, is_empty and 0 or last, last, true, { mention, '' })
  H.collection_save(buf_id)

  H.notify(mention, 'INFO')
end

--- Module config
---
--- Default values:
Mention.config = {
  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Append mention for current file (Normal) or line range (Visual)
    append = '',

    -- Toggle the collection window
    toggle = '',

    -- Copy entire collection to system clipboard
    copy = '',

    -- Clear the collection (asks for confirmation)
    clear = '',
  },

  -- Collection window geometry (fractions of the editor size)
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

-- Runtime state: collection buffer and window ids, resolved collection path
H.cache = { buf_id = nil, win_id = nil, state_path = nil }

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.append', config.mappings.append, 'string')
  H.check_type('mappings.toggle', config.mappings.toggle, 'string')
  H.check_type('mappings.copy', config.mappings.copy, 'string')
  H.check_type('mappings.clear', config.mappings.clear, 'string')

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
  H.map('n', m.toggle, '<Cmd>lua Mention.toggle()<CR>', { desc = 'Toggle mention collection' })
  H.map('n', m.copy, '<Cmd>lua Mention.copy()<CR>', { desc = 'Copy mention collection' })
  H.map('n', m.clear, '<Cmd>lua Mention.clear()<CR>', { desc = 'Clear mention collection' })
end

-- Mentions -------------------------------------------------------------------
-- `#L<n>` / `#L<n>-<m>` for the Visual selection; '' outside Visual mode
H.range_suffix = function()
  if not vim.fn.mode():match('[vV\22]') then return '' end
  local from, to = vim.fn.line('v'), vim.fn.line('.')
  if from > to then from, to = to, from end
  return from == to and ('#L' .. from) or ('#L' .. from .. '-' .. to)
end

-- Collection -----------------------------------------------------------------
-- Path of the persisted collection: keyed by cwd at first use (undofile-style
-- encoding), unaffected by later `:cd`
H.state_path = function()
  if H.cache.state_path == nil then
    local dir = vim.fs.joinpath(vim.fn.stdpath('state'), 'mention.nvim')
    vim.fn.mkdir(dir, 'p')
    H.cache.state_path = vim.fs.joinpath(dir, (vim.fn.getcwd():gsub('[\\/:]', '%%')))
  end
  return H.cache.state_path
end

H.ensure_collection_buf = function()
  if H.cache.buf_id ~= nil and vim.api.nvim_buf_is_valid(H.cache.buf_id) then return H.cache.buf_id end

  local buf_id = vim.fn.bufadd(H.state_path())
  vim.fn.bufload(buf_id)
  -- Autosave makes swap files redundant (and their recovery prompts ugly)
  vim.bo[buf_id].swapfile = false

  local group = vim.api.nvim_create_augroup('Mention', {})
  local save = function() H.collection_save(buf_id) end
  vim.api.nvim_create_autocmd(
    { 'TextChanged', 'InsertLeave', 'BufLeave' },
    { group = group, buffer = buf_id, callback = save, desc = 'Autosave mention collection' }
  )
  vim.api.nvim_create_autocmd(
    'VimLeavePre',
    { group = group, callback = save, desc = 'Autosave mention collection' }
  )

  H.cache.buf_id = buf_id
  return buf_id
end

H.collection_save = function(buf_id)
  if not vim.api.nvim_buf_is_valid(buf_id) then return end
  vim.api.nvim_buf_call(buf_id, function() vim.cmd('silent update') end)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mention) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.notify = function(msg, level_name)
  if Mention.config.silent and level_name ~= 'ERROR' then return end
  vim.notify('(mention) ' .. msg, vim.log.levels[level_name])
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

return Mention
