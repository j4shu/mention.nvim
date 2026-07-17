# mention.nvim

Collect file and line-range mentions (`@path`, `@path#L1-5`) into a single
mention buffer and interleave free-text instructions for pasting into Claude
Code. One mention buffer per project (keyed by cwd), persisted across sessions
as a plain file: open it and take its content from there.

## Requirements

- Neovim >= 0.12

## Installation

```lua
vim.pack.add({ 'https://github.com/j4shu/mention.nvim' })
```

## Setup

No global keymaps are created by default; the only built-in key is a
buffer-local close mapping in the float (default `q`, configurable). Set the
mappings via config. Default config:

```lua
require('mention').setup({
  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Append a mention for the current file (Normal) or the selected line
    -- range (Visual) to the end of the mention buffer. Paths are `~`-absolute,
    -- which Claude Code expands. You stay where you are.
    append = '',

    -- Open the mention buffer in a centered float, or close it if open. It
    -- also closes on the close key or when focus leaves it; edit it like any
    -- buffer.
    toggle = '',

    -- Close the float (buffer-local in the mention buffer;
    -- the default `q` sacrifices macro recording there)
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
})
```

For example:

```lua
require('mention').setup({
  mappings = {
    append = '<leader>a',
    toggle = '<leader>A',
  },
})
```

## Documentation

See `:h mention.txt` for the full reference.
