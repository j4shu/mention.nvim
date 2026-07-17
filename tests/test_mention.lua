local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

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

return T
