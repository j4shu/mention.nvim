# mention.nvim

Collect file and line-range mentions (`@path`, `@path#L1-5`) into a single
per-project buffer, interleave free-text instructions, and copy the whole
collection to the system clipboard for pasting into Claude Code.

## Operations

Four argument-free Lua functions, all bound through config:

- `require('mention').append()`: append a mention for the current file to the
  collection. Mode-aware: in Visual mode it appends the selected line range
  (`@path#L3` or `@path#L3-7`), otherwise the whole file (`@path`). Paths are
  absolute with `~` for home, which Claude Code expands. Silent flow: you stay
  where you are; a `(mention)` notification shows what was appended.
- `require('mention').toggle()`: open the collection in a centered float, or
  close it if open. The float also closes on buffer-local `q` or when focus
  leaves it. The collection is a regular buffer: reorder mentions, delete
  lines, type instructions between them.
- `require('mention').copy()`: put the entire collection verbatim into the
  `+` register, ready to paste into Claude.
- `require('mention').clear()`: empty the collection after confirmation
  (defaults to No). Never deletes the buffer or its file.

There is exactly one collection per project, keyed by the working directory,
and it persists across sessions under `stdpath('state')/mention.nvim/`.

## Requirements

- Neovim >= 0.10

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'j4shu/mention.nvim',
  opts = {
    mappings = {
      append = '<leader>a',
      toggle = '<leader>A',
      copy = '<leader>y',
      clear = '<leader>X',
    },
  },
}
```

With any other plugin manager, install `j4shu/mention.nvim` and call
`require('mention').setup({ ... })`.

## Setup

No keymaps are created by default; the only built-in key is a buffer-local
`q` that closes the float. Set the four mappings via config (the block above
is a suggestion, not a default). Default config:

```lua
require('mention').setup({
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
})
```

## Documentation

See `:h mention.txt` for the full reference.
