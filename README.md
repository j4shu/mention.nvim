# mention.nvim

Collect file and line-range mentions (`@path`, `@path#L1-5`) into a single
buffer, interleave free-text instructions, and copy the whole collection to
the system clipboard for pasting into Claude Code. One collection per project
(keyed by cwd), persisted across sessions.

## Requirements

- Neovim >= 0.12

## Installation

```lua
vim.pack.add({ 'https://github.com/j4shu/mention.nvim' })
```

## Setup

No keymaps are created by default; the only built-in key is a buffer-local
`q` that closes the float. Set the four mappings via config. Default config:

```lua
require('mention').setup({
  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Append a mention for the current file (Normal) or the selected line
    -- range (Visual) to the end of the collection. Paths are `~`-absolute,
    -- which Claude Code expands. You stay where you are.
    append = '',

    -- Open the collection in a centered float, or close it if open. It also
    -- closes on `q` or when focus leaves it; edit it like any buffer.
    toggle = '',

    -- Copy the entire collection verbatim to the system clipboard.
    copy = '',

    -- Empty the collection after confirmation; never deletes it.
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
})
```

For example:

```lua
require('mention').setup({
  mappings = {
    append = '<leader>a',
    toggle = '<leader>A',
    copy = '<leader>y',
    clear = '<leader>X',
  },
})
```

## Documentation

See `:h mention.txt` for the full reference.
