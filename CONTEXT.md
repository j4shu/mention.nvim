# mention.nvim

A Neovim plugin that collects file/line-range mentions and free-text instructions into a single buffer, for pasting into Claude Code.

## Language

**Mention**:
A reference to a file (`@path`) or line range (`@path#L<n>` / `@path#L<n>-<m>`) in the syntax Claude Code understands.
_Avoid_: reference, link, attachment

**Collection**:
The single per-project buffer where mentions and free text accumulate. There is exactly one per project (keyed by cwd).
_Avoid_: list, scratchpad, sidebar

**Append**:
Adding a mention to the end of the collection. Always silent: the user stays where they are.
_Avoid_: add, capture, send

**Toggle**:
Opening the collection in a centered float, or closing it. The only way the collection is presented.
_Avoid_: open/show (as separate concepts)

**Free text**:
User-typed instructions interleaved between mentions. Opaque to the plugin: never parsed, validated, or touched.
_Avoid_: notes, comments, annotations

**Copy-all**:
Copying the entire collection verbatim to the system clipboard. The sole exit path for collected content.
_Avoid_: export, yank, send
