# Obelisk

A small Neovim plugin for wiki-style note linking in Markdown.

## Features

- **`[[ ]]` wikilink completion** — typing `[[` in insert mode opens a
  completion menu listing the files in the configured notes directory. The
  menu is shown without pre-selecting an item, so nothing is autofilled until
  you explicitly choose one. On confirmation the closing `]]` is added for you.
- **Follow links under the cursor** — in normal mode, press the `open`
  keybinding (default `<leader>wo`) while the cursor sits anywhere inside
  `[[some note]]` to open that file. If a matching file does not exist, a new
  `<name>.md` buffer is opened so the note can be created. When the cursor is
  not on a wikilink the key falls back to its normal behavior, so it never
  shadows your editor.
- **Anchor stripping** — link targets of the form `[[note#heading]]` resolve
  to the file `note`, ignoring the `#heading` portion when opening.
- **Rename notes** — press the `rename` keybinding (default `<leader>wr`) to
  rename the current file. Every `[[ ]]` reference to it across the note tree
  is rewritten to the new name (anchors and aliases are preserved).
- **Backlinks picker** — press the `backlinks` keybinding (default
  `<leader>wb`) to open a [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
  picker listing every file that references the current file via `[[ ]]`
  (including `[[name#anchor]]` and `[[name|alias]]` forms). Selecting an
  entry opens the referencing file with the cursor on the link.
- **Create notes** — press the `new` keybinding (default `<leader>wn`) to be
  prompted for a name, create a new `<name>.md` under the notes directory,
  and open it. Unlike the other keymaps this one is global, so it works from
  any buffer — not only files inside `notes_dir`. The name may be a relative
  path (e.g. `papers/idea`); nested directories are created as needed. If the
  file already exists it is simply opened.
- **Configurable filetypes** — wikilink completion and the keymaps are
  attached only to the filetypes you choose (defaults to `markdown`).
- **Notes-directory scoped** — all wikilink features only activate on files
  inside the configured `notes_dir`. Markdown files outside it are left
  untouched, and links resolve/open relative to that directory.
- **Named keymaps** — keybindings live under `wikilink.keymaps.<name>` so new
  ones can be added without crowding a single `keymap` option.
- **Typed configuration** — full [vimdoc][1] / `---@class` annotations so your
  Lua setup gets inline documentation and completion in your editor.

[1]: https://github.com/folke/neodev.nvim

## Requirements

- Neovim 0.9+ (uses `vim.keymap.set` and `vim.fn.complete`).
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) is required
  for the backlinks picker (`<leader>wb`). The other features work without it.

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "your-user/obelisk",
    dependencies = { "nvim-telescope/telescope.nvim" },
    config = function()
        require("obelisk").setup()
    end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "your-user/obelisk",
    config = function()
        require("obelisk").setup()
    end,
}
```

## Configuration

All options are optional; the values below are the defaults.

```lua
require("obelisk").setup({
    notes_dir = vim.fn.getcwd() .. "/notes",  -- directory where notes live
    wikilink = {
        enabled = true,                       -- enable [[ ]] completion + follow
        filetypes = { "markdown" },           -- where the feature is active
        keymaps = {
            open = "<leader>wo",              -- open the file under the cursor
            rename = "<leader>wr",            -- rename the current file (and fix links)
            backlinks = "<leader>wb",         -- Telescope picker of files referencing this one
            new = "<leader>wn",               -- create a new note and open it
        },
    },
})
```

### Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `notes_dir` | `string` | `vim.fn.getcwd() .. "/notes"` | Directory where notes live. Wikilink features (completion, follow, rename, backlinks) only activate on files inside this directory; `~` and relative paths are expanded/normalized. |
| `wikilink.enabled` | `boolean` | `true` | Enable `[[ ]]` completion and link-following. |
| `wikilink.filetypes` | `string[]` | `{ "markdown" }` | Filetypes where the wikilink features are attached. |
| `wikilink.keymaps` | `table` | `{ open = "<leader>wo", rename = "<leader>wr", backlinks = "<leader>wb", new = "<leader>wn" }` | Named wikilink keybindings (see below). |
| `wikilink.keymaps.open` | `string` | `"<leader>wo"` | Normal-mode keybinding used to open the file under the cursor. Set to `""` to disable it. |
| `wikilink.keymaps.rename` | `string` | `"<leader>wr"` | Normal-mode keybinding that renames the current file and rewrites `[[ ]]` references to it. Set to `""` to disable it. |
| `wikilink.keymaps.backlinks` | `string` | `"<leader>wb"` | Normal-mode keybinding that opens a Telescope picker of files referencing the current file via `[[ ]]`. Set to `""` to disable it. |
| `wikilink.keymaps.new` | `string` | `"<leader>wn"` | Normal-mode keybinding that prompts for a name, creates a new note under the notes directory, and opens it. This is a global keymap (works from any buffer, not only files in `notes_dir`). Set to `""` to disable it. |

## Usage

- Open a file inside your `notes_dir` (e.g. `~/notes/foo.md`) — the wikilink
  features attach automatically. Markdown files outside `notes_dir` are
  ignored.
- In insert mode, type `[[` — the completion menu appears; select an entry
  (or type your own text) and confirm. The `]]` is appended automatically.
- In normal mode, place the cursor anywhere on `[[some note]]` and press
  `<leader>wo` (the `open` keymap) to open `some note`. If the file doesn't
  exist yet, it is opened as a new buffer for you to fill in.
- In normal mode, press `<leader>wr` (the `rename` keymap) to rename the
  current file. You'll be prompted for the new name; all `[[ ]]` links pointing
  to it are updated (including `[[name#anchor]]` and `[[name|alias]]` forms).
- In normal mode, press `<leader>wb` (the `backlinks` keymap) to open a
  Telescope picker of files referencing the current file. Selecting an entry
  opens that file with the cursor placed on the referencing `[[ ]]` link.
- In normal mode, press `<leader>wn` (the `new` keymap) to create a new note.
  This works from any buffer. You'll be prompted for a name; the note is
  created under the notes directory (nested paths like `papers/idea` are
  supported) and opened for editing. If a file with that name already exists
  it is opened instead.
