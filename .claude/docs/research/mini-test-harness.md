# Research: mini.test harness for a standalone plugin (#3)

Sources: local checkout `~/git/mini.nvim` (primary). Key files: `TESTING.md`, `lua/mini/test.lua`, `doc/mini-test.txt`, `Makefile`, `scripts/`, `tests/`, `.github/workflows/quality-control.yml`.

## 1. Canonical standalone layout

`~/git/mini.nvim/TESTING.md:131-146` prescribes exactly this for a standalone plugin repo:

```
.
├── deps/mini.nvim          # mini.nvim clone (dev dependency, gitignored)
├── lua/mention/init.lua    # plugin under test
├── Makefile
├── scripts/minimal_init.lua
└── tests/test_mention.lua
```

- Test files: Lua files in `tests/`, named `test_*.lua`, each returning one test set (`TESTING.md:154`).
- Optional: `tests/helpers.lua` for shared child-setup wrappers and custom expectations (`TESTING.md:966-984`, real example `~/git/mini.nvim/tests/helpers.lua`).
- Optional: `scripts/minitest.lua` runner script (`~/git/mini.nvim/scripts/minitest.lua` is 4 lines: `require('mini.test')`, `setup()` if needed, `run()`). Only needed to customize collection; skip for a small plugin.

## 2. Bootstrapping mini.nvim as dev dependency

`TESTING.md:171-176`: clone into `deps/`:

```bash
mkdir -p deps
git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim deps/mini.nvim
```

Make it a Makefile order-only prerequisite so local runs and CI self-bootstrap (`TESTING.md:205-218`):

```make
test: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

test_file: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim $@
```

Add `deps/` to `.gitignore`.

## 3. minimal_init.lua

Proposed content for standalone repos (`TESTING.md:180-197`):

```lua
-- Add plugin repo root to runtimepath
vim.cmd([[let &rtp.=','.getcwd()]])

-- Set up mini.test only in headless runs
if #vim.api.nvim_list_uis() == 0 then
  vim.cmd('set rtp+=deps/mini.nvim')
  require('mini.test').setup()
end
```

The same file doubles as the child-process init (`child.restart({'-u', 'scripts/minimal_init.lua'})`), so the plugin is on `rtp` in both parent and child. mini.nvim's own `scripts/minimal_init.lua` adds colorscheme/statusline pinning only to stabilize screenshots; not needed here.

Note: all commands assume cwd = repo root (`TESTING.md:16`).

## 4. Running tests

- Headless (shell/CI): `nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"` (mini.nvim's own `Makefile:12-19` does exactly this, plus `MiniTest.run_file('tests/$@.lua')` for per-module targets at `Makefile:22-31`).
- Interactive (debugging): inside a Neovim session with mini.test set up, `:lua MiniTest.run()` / `MiniTest.run_file()` / `MiniTest.run_at_location()`; results in a floating window, `q` closes (`TESTING.md:228`).
- API line refs in `lua/mini/test.lua`: `setup()` :158, `new_set()` :299, `run()` :400, `run_file()` :419, `expect.equality` :700, `expect.reference_screenshot` :818, `new_child_neovim()` :1139.

CI (`~/git/mini.nvim/.github/workflows/quality-control.yml:34-60`): matrix over Neovim versions (`v0.10.4`..`nightly`) + windows, install via `rhysd/action-setup-vim@v1` with `neovim: true`, then `run: make test`. The `deps/mini.nvim` Make rule handles the clone; no separate CI checkout step needed.

## 5. Child-process pattern (the core idea)

`TESTING.md:703-734`: every case runs against a fresh headless child Neovim, talked to over RPC. This isolates state (registers, buffers, options, autocmds) from the test runner's own session, which is exactly what mention.nvim needs for register/clipboard and buffer-state assertions.

Standard skeleton (used by every `tests/test_*.lua` in mini.nvim):

```lua
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      child.lua([[M = require('mention')]])
    end,
    post_once = child.stop,
  },
})
```

Key child methods (`lua/mini/test.lua:1139+`):
- `child.lua(str, args)` / `child.lua_get(str, args)` (:1380) — execute / execute-and-return Lua in child.
- `child.type_keys(...)` (:1316) — emulate typed keys (strings or nested tables; optional leading ms delay).
- Redirection tables: `child.api.*`, `child.fn.*`, `child.cmd()/cmd_capture()`, `child.o/bo/wo`, `child.b/g/...` (`TESTING.md:777-842`).
- Limits: no functions/userdata across RPC ("Cannot convert given lua type"); blocked child (hit-enter prompt, operator-pending) hangs — helpers error preemptively (`TESTING.md:709-711`).

Common first-line fix: `child.bo.readonly = false` (initial buffer is readonly; slows tests — `TESTING.md:800-801`, `tests/helpers.lua` `child.setup`).

## 6. new_set: hooks and parametrize

- Hooks: `pre_once`, `pre_case`, `post_case`, `post_once` (`TESTING.md:393-399`). Canonical use: `pre_case` restarts child; `post_once = child.stop`.
- `parametrize = { {args1...}, {args2...} }` multiplies cases; nested sets multiply combinations; args are passed to the test function (`TESTING.md:436-474`). Useful for mention.nvim: same append test across `{path}`, `{path, {1,5}}` (range) inputs.
- `n_retry = N` for flaky/timing tests (`TESTING.md:478-500`); unlikely needed here.
- Expectations: `expect.equality`, `no_equality`, `expect.error(f, pattern?)`, `no_error`; custom via `MiniTest.new_expectation()` (`TESTING.md:316-379`). `Helpers.expect.match/no_match` in `tests/helpers.lua:6-16` is a handy copy-paste.

## 7. Screenshot testing: skip it

`expect.reference_screenshot(child.get_screenshot())` auto-creates/compares references in `tests/screenshots/` (`TESTING.md:894-962`; `lua/mini/test.lua:818`). It is designed for visual features (highlights, floats, statusline). mention.nvim's behavior (buffer line content, register content) is fully assertable via `child.api.nvim_buf_get_lines()` and `child.fn.getreg()`; screenshots would only add brittleness (case-insensitive-FS name clashes, path-length caveats, `TESTING.md:993-995`). Recommendation: do not use, unless a UI (floating collection window) is added later.

## 8. Clipboard (`+` register) in headless child

Headless CI has no clipboard provider, so `setreg('+', ...)`/`getreg('+')` against the real system clipboard is unreliable. mini.nvim's own tests mock it with `g:clipboard` inside the child. Two variants:

No-op clipboard (`tests/test_clue.lua:1249-1259`):

```lua
child.lua([[
  local empty = function() return '' end
  vim.g.clipboard = {
    name  = 'myClipboard',
    copy  = { ['+'] = empty, ['*'] = empty },
    paste = { ['+'] = empty, ['*'] = empty },
  }
]])
```

Round-trip clipboard (`tests/test_snippets.lua:3106-3118`) returns fixed content from `paste`. For mention.nvim's copy-to-clipboard action, the most useful mock captures what was copied:

```lua
child.lua([[
  _G.clip = {}
  vim.g.clipboard = {
    name  = 'test',
    copy  = { ['+'] = function(lines, regtype) _G.clip = { lines, regtype } end,
              ['*'] = function() end },
    paste = { ['+'] = function() return _G.clip end,
              ['*'] = function() return { {}, 'v' } end },
  }
]])
-- then: eq(child.lua_get('_G.clip[1]'), { '@lua/mention/init.lua#L1-5' })
```

Set the mock in `pre_case` (after `child.restart`) so `getreg('+')`/`setreg('+')` route through it. Alternative without any mock: assert on `child.fn.getreg('+')` still works if the copy action uses `setreg` only, but comments in `tests/test_clue.lua:1250-1251` warn `setreg('+', ...)` is "not guaranteed to be working for system clipboard" without `g:clipboard` — mock it.

## 9. Minimal harness for mention.nvim (concrete file list)

1. `scripts/minimal_init.lua` — the 3-part init from section 3.
2. `Makefile` — `test`, `test_file` (FILE env var), `deps/mini.nvim` targets from section 2.
3. `tests/test_mention.lua` — skeleton from section 5; groups per action: `T['append()']`, `T['toggle()']`, `T['clear()']`, `T['copy()']`; use `child.api.nvim_buf_get_lines` to assert collection-buffer content, `child.fn.getreg('+')` + `g:clipboard` mock for copy.
4. `.gitignore` entry: `deps/`.
5. CI workflow (optional but cheap): checkout, `rhysd/action-setup-vim@v1` (neovim), `make test`, matrix over supported Neovim versions.

Optional later: `tests/helpers.lua` (only when a second test file appears), `scripts/minitest.lua` (only if custom collection/reporting is needed).
