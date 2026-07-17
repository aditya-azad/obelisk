# Obelisk

A small Neovim plugin for wiki-style note linking in Markdown.

## Features

- **`[[ ]]` wikilink completion** — typing `[[` in insert mode opens a
  completion menu listing the files in the current note's directory. The menu
  is shown without pre-selecting an item, so nothing is autofilled until you
  explicitly choose one. On confirmation the closing `]]` is added for you.
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
- **Configurable filetypes** — wikilink completion and the keymaps are
  attached only to the filetypes you choose (defaults to `markdown`).
- **Named keymaps** — keybindings live under `wikilink.keymaps.<name>` so new
  ones can be added without crowding a single `keymap` option.
- **Typed configuration** — full [vimdoc][1] / `---@class` annotations so your
  Lua setup gets inline documentation and completion in your editor.

[1]: https://github.com/folke/neodev.nvim

## Requirements

- Neovim 0.9+ (uses `vim.keymap.set` and `vim.fn.complete`).

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "your-user/obelisk",
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
    greeting = "hello",                       -- message shown by :Obelisk
    wikilink = {
        enabled = true,                       -- enable [[ ]] completion + follow
        filetypes = { "markdown" },           -- where the feature is active
        keymaps = {
            open = "<leader>wo",              -- open the file under the cursor
            rename = "<leader>wr",            -- rename the current file (and fix links)
        },
    },
})
```

### Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `greeting` | `string` | `"hello"` | Text shown by the `:Obelisk` command. |
| `wikilink.enabled` | `boolean` | `true` | Enable `[[ ]]` completion and link-following. |
| `wikilink.filetypes` | `string[]` | `{ "markdown" }` | Filetypes where the wikilink features are attached. |
| `wikilink.keymaps` | `table` | `{ open = "<leader>wo", rename = "<leader>wr" }` | Named wikilink keybindings (see below). |
| `wikilink.keymaps.open` | `string` | `"<leader>wo"` | Normal-mode keybinding used to open the file under the cursor. Set to `""` to disable it. |
| `wikilink.keymaps.rename` | `string` | `"<leader>wr"` | Normal-mode keybinding that renames the current file and rewrites `[[ ]]` references to it. Set to `""` to disable it. |

## Usage

- In insert mode, type `[[` — the completion menu appears; select an entry
  (or type your own text) and confirm. The `]]` is appended automatically.
- In normal mode, place the cursor anywhere on `[[some note]]` and press
  `<leader>wo` (the `open` keymap) to open `some note`. If the file doesn't
  exist yet, it is opened as a new buffer for you to fill in.
- In normal mode, press `<leader>wr` (the `rename` keymap) to rename the
  current file. You'll be prompted for the new name; all `[[ ]]` links pointing
  to it are updated (including `[[name#anchor]]` and `[[name|alias]]` forms).
- Run `:Obelisk` to print the configured `greeting` (handy for verifying that
  setup ran).
