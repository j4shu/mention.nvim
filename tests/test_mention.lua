local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Isolate collection storage and cwd per case. The sandbox lives in the test
-- runner's tempdir so it survives child restarts and exits.
local sandbox_root

local enter_sandbox = function()
  child.lua('vim.env.XDG_STATE_HOME = ' .. vim.inspect(sandbox_root .. '/state'))
  child.fn.chdir(sandbox_root .. '/proj')
end

local setup_sandbox = function()
  sandbox_root = vim.fn.tempname()
  vim.fn.mkdir(sandbox_root .. '/proj', 'p')
  enter_sandbox()
end

local edit_test_file = function(lines)
  local path = child.fn.getcwd() .. '/file.txt'
  child.fn.writefile(lines or { 'line 1', 'line 2', 'line 3', 'line 4', 'line 5' }, path)
  child.cmd('edit ' .. child.fn.fnameescape(path))
  return path
end

local mock_notify = function()
  child.lua([[
    _G.notify_log = {}
    vim.notify = function(msg, level) table.insert(_G.notify_log, { msg, level }) end
  ]])
end

-- Path of the persisted collection: single file under the state subdirectory
local state_files = function()
  local dir = child.lua_get([[vim.fn.stdpath('state')]]) .. '/mention.nvim'
  return vim.fn.glob(dir .. '/*', true, true)
end

local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      child.lua([[require('mention').setup()]])
    end,
    post_once = child.stop,
  },
})

T['setup()'] = new_set()

T['setup()']['creates global table'] = function()
  eq(child.lua_get([[type(_G.Mention)]]), 'table')
  eq(child.lua_get([[type(Mention.setup)]]), 'function')
end

T['setup()']['creates config with defaults'] = function()
  eq(child.lua_get('type(Mention.config)'), 'table')
  eq(child.lua_get('Mention.config.mappings'), { append = '', toggle = '', copy = '', clear = '' })
  eq(child.lua_get('Mention.config.window'), { width = 0.5, height = 0.6, border = 'rounded' })
  eq(child.lua_get('Mention.config.silent'), false)
end

T['setup()']['respects user config'] = function()
  child.lua([[Mention.setup({ silent = true, window = { width = 0.8 } })]])
  eq(child.lua_get('Mention.config.silent'), true)
  eq(child.lua_get('Mention.config.window.width'), 0.8)
  -- Unspecified fields keep defaults
  eq(child.lua_get('Mention.config.window.height'), 0.6)
end

T['setup()']['validates config'] = function()
  expect.error(function() child.lua([[Mention.setup({ silent = 'yes' })]]) end, '`silent`.*boolean')
  expect.error(function() child.lua([[Mention.setup({ mappings = { append = 1 } })]]) end, '`mappings%.append`.*string')
end

T['setup()']['creates configured mappings'] = function()
  child.lua([[Mention.setup({ mappings = { append = 'ga', toggle = 'gA' } })]])
  local has_map = function(mode, lhs)
    return child.lua_get([[vim.fn.maparg(...) ~= '']], { lhs, mode })
  end
  eq(has_map('n', 'ga'), true)
  eq(has_map('x', 'ga'), true)
  eq(has_map('n', 'gA'), true)
  -- Empty string means no mapping
  eq(has_map('n', 'gz'), false)
end

T['append()'] = new_set({ hooks = { pre_case = setup_sandbox } })

T['append()']['persists a whole-file mention'] = function()
  local path = edit_test_file()
  child.lua('Mention.append()')

  local files = state_files()
  eq(#files, 1)
  eq(vim.fn.readfile(files[1]), { '@' .. child.fn.fnamemodify(path, ':p:~'), '' })
end

T['append()']['persists a line-range mention from Visual selection'] = function()
  local path = edit_test_file()
  child.type_keys('2G', 'V', '2j')
  child.lua('Mention.append()')

  eq(vim.fn.readfile(state_files()[1]), { '@' .. child.fn.fnamemodify(path, ':p:~') .. '#L2-4', '' })
end

T['append()']['collapses a single-line Visual selection to `#L<n>`'] = function()
  local path = edit_test_file()
  child.type_keys('3G', 'v')
  child.lua('Mention.append()')

  eq(vim.fn.readfile(state_files()[1]), { '@' .. child.fn.fnamemodify(path, ':p:~') .. '#L3', '' })
end

T['append()']['normalizes a reversed Visual selection'] = function()
  local path = edit_test_file()
  child.type_keys('4G', 'V', '2k')
  child.lua('Mention.append()')

  eq(vim.fn.readfile(state_files()[1]), { '@' .. child.fn.fnamemodify(path, ':p:~') .. '#L2-4', '' })
end

T['append()']['separates successive entries with one blank line'] = function()
  local path = edit_test_file()
  child.lua('Mention.append()')
  child.type_keys('2G', 'V')
  child.lua('Mention.append()')

  local mention = '@' .. child.fn.fnamemodify(path, ':p:~')
  eq(vim.fn.readfile(state_files()[1]), { mention, '', mention .. '#L2', '' })
end

T['append()']['notifies with the appended mention'] = function()
  local path = edit_test_file()
  mock_notify()
  child.lua('Mention.append()')

  local info = child.lua_get('vim.log.levels.INFO')
  eq(child.lua_get('_G.notify_log'), { { '(mention) @' .. child.fn.fnamemodify(path, ':p:~'), info } })
end

T['append()']['respects `config.silent`'] = function()
  edit_test_file()
  mock_notify()
  child.lua([[Mention.setup({ silent = true })]])
  child.lua('Mention.append()')

  eq(child.lua_get('_G.notify_log'), {})
  eq(#state_files(), 1)
end

T['append()']['errors on a buffer without a name'] = function()
  mock_notify()
  -- Errors are never silenced
  child.lua([[Mention.setup({ silent = true })]])
  child.lua('Mention.append()')

  local err = child.lua_get('vim.log.levels.ERROR')
  eq(child.lua_get('_G.notify_log'), { { '(mention) cannot append: buffer has no name', err } })
  eq(#state_files(), 0)
end

T['append()']['keys the collection by cwd at first use, unaffected by later `:cd`'] = function()
  local path = edit_test_file()
  child.lua('Mention.append()')
  child.fn.mkdir(sandbox_root .. '/other', 'p')
  child.fn.chdir(sandbox_root .. '/other')
  child.lua('Mention.append()')

  local files = state_files()
  eq(#files, 1)
  -- Filename is the keying cwd, undofile-style encoded
  eq(vim.fn.fnamemodify(files[1], ':t'):find('%%proj$') ~= nil, true)
  local mention = '@' .. child.fn.fnamemodify(path, ':p:~')
  eq(vim.fn.readfile(files[1]), { mention, '', mention, '' })
end

T['append()']['persists the collection across sessions'] = function()
  local path = edit_test_file()
  child.lua('Mention.append()')

  child.restart({ '-u', 'scripts/minimal_init.lua' })
  child.lua([[require('mention').setup()]])
  enter_sandbox()
  child.cmd('edit ' .. child.fn.fnameescape(path))
  child.lua('Mention.append()')

  local mention = '@' .. child.fn.fnamemodify(path, ':p:~')
  eq(vim.fn.readfile(state_files()[1]), { mention, '', mention, '' })
end

T['append()']['autosaves edits made in the collection buffer'] = function()
  edit_test_file()
  child.lua('Mention.append()')
  local state_file = state_files()[1]

  child.cmd('edit ' .. child.fn.fnameescape(state_file))
  eq(child.api.nvim_get_option_value('swapfile', { buf = 0 }), false)
  -- Interleave free text; InsertLeave triggers the autosave
  child.type_keys('Go', 'do the thing', '<Esc>')
  eq(vim.fn.readfile(state_file)[3], 'do the thing')

  -- Normal-mode edit; TextChanged triggers the autosave
  child.type_keys('dd')
  eq(vim.fn.readfile(state_file)[3], nil)
end

T['append()']['persists unsaved collection changes on quit'] = function()
  edit_test_file()
  child.lua('Mention.append()')
  local state_file = state_files()[1]

  -- Modify the collection without visiting it, so no autosave event fires
  child.lua(
    ('vim.api.nvim_buf_set_lines(vim.fn.bufnr(%s), -1, -1, true, { "trailing note" })'):format(
      vim.inspect(state_file)
    )
  )
  pcall(child.cmd, 'qall!')
  vim.wait(1000, function() return vim.fn.readfile(state_file)[3] ~= nil end, 10)

  eq(vim.fn.readfile(state_file)[3], 'trailing note')
end

return T
