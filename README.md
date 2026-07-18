<img width="1920" height="1051" alt="SCR-20260717-rvkn" src="https://github.com/user-attachments/assets/1c779b02-8a29-415f-905c-b631b7d6c935" />

# mention.nvim

Collect file and line-range mentions (`@path`, `@path#L1-5`) into a single
mention buffer and interleave free-text instructions for pasting into a
coding agent such as Claude Code. One mention buffer per project (keyed by
cwd), persisted across sessions as a plain file: open it and yank.

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
    -- range (Visual) to the end of the mention buffer.
    append = '',

    -- Open the mention buffer in a centered float, or close it if open.
    toggle = '',

    -- Close the float (buffer-local)
    close = 'q',
  },

  -- Float geometry (fractions of the editor size)
  window = {
    width = 0.5,
    height = 0.6,
    border = nil, -- Defaults to `vim.o.winborder`
  },

  -- Mention format: `function(path, from, to) -> string`, or `nil` for the
  -- default `@path#L<from>-<to>`. See `:h Mention.config`.
  format = nil,

  -- Whether to suppress non-error feedback
  silent = false,

  -- Whether to open the mention buffer float (focused) after each append
  auto_open = false,
})
```

For example:

```lua
require('mention').setup({
  mappings = {
    append = '<leader>y',
    toggle = '<leader>m',
    close = '<Esc>'
  }
})
```

## Mention format

You can customize the mention format by providing a `format` function. It
receives the absolute file path and the selected line range (`from`/`to`,
both `nil` outside Visual mode) and returns the mention string. For
example, GitHub Copilot CLI (cwd-relative path, `:N-M` range):

```lua
require('mention').setup({
  format = function(path, from, to)
    path = vim.fn.fnamemodify(path, ':.')
    return '@' .. path .. (from and (':' .. from .. '-' .. to) or '')
  end,
})
```

## Documentation

See `:h mention.txt` for the full reference.
