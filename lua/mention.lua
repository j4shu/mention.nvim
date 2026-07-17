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

-- Runtime state: collection buffer and window ids
H.cache = { buf_id = nil, win_id = nil }

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

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mention) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.notify = function(msg, level_name)
  if Mention.config.silent then return end
  vim.notify('(mention) ' .. msg, vim.log.levels[level_name])
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

return Mention
