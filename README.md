# Obelisk

A small Neovim plugin for wiki-style note linking in Markdown.

> DISCLAIMER: Check out the zotero release for zotero version of the software

## Features

- **`[[ ]]` wikilink completion** — typing `[[` in insert mode opens a
  completion menu listing the files in the configured notes directory. The
  menu is shown without pre-selecting an item, so nothing is autofilled until
  you explicitly choose one. On confirmation the closing `]]` is added for you.
- **Follow links under the cursor** — in normal mode, press the `open`
  keybinding (default `<leader>wg`) while the cursor sits anywhere inside
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
- **Find notes** — press the `find` keybinding (default `<leader>wo`) to open a
  [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) picker
  listing every note under the notes directory (including nested files).
  Selecting an entry opens that note. Like `new`, this is a global keymap, so
  it works from any buffer.
- **Paste images as Markdown** — copying an image to the system clipboard and
  pasting (via `<C-v>` in insert mode, `p`/`P` in normal mode, or any bracketed
  / GUI / middle-click paste) into a note saves the image under
  `notes_dir/assets` and inserts a `![](assets/…)` link at the cursor. Text
  pastes pass through unchanged when the clipboard has no image.
- **Insert citations** — press the `insert` keybinding (default
  `<leader>wc`) to open a [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
  picker that searches your refree library live (by title, author, or year)
  via the refree REST API. Selecting an entry inserts a citation at the
  cursor in the style of the current buffer: a pandoc-style `[@citekey]`
  (e.g. `[@smith2024example]`) in Markdown, or a `\cite{citekey}` (e.g.
  `\cite{smith2024example}`) in LaTeX. You're left in insert mode right
  after the inserted text.
- **Open citation PDFs** — place the cursor on a citation (`[@citekey]` in
  Markdown, `\cite{citekey}` in LaTeX; locators like `\cite[p. 12]{key}` and
  multiple keys `\cite{a, b}` are handled) and press the `open_pdf`
  keybinding (default `<leader>wp`) to open the item's PDF in your operating
  system's default viewer. The citekey is resolved via refree's citekey
  lookup; the reference's stored PDF is opened.
- **Citation references picker** *(Markdown only)* — place the cursor on a
  `[@citekey]` citation and press the `references` keybinding (default
  `<leader>wR`) to open a [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
  picker listing every file under the notes directory that cites that same
  key (via `[@citekey]`, `[@citekey, p. 12]`, `[-@citekey]`, or
  `[@a; @citekey]`). Selecting an entry opens the referencing file with the
  cursor on the `@citekey`.
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
  for the backlinks picker (`<leader>wb`), the find picker (`<leader>wo`), the
  citation picker (`<leader>wc`), and the citation references picker
  (`<leader>wR`). The other features work without it.
- A clipboard tool is required for pasting images: `wl-clipboard` (Wayland),
  `xclip` (X11), or `pngpaste` (macOS). The feature is skipped silently (text
  paste still works) if none is found.
- refree running locally is required for the citation picker (`<leader>wc`).
  `curl` is used to talk to the refree REST API. The other features work
  without it.
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
            open = "<leader>wg",              -- open the file under the cursor
            rename = "<leader>wr",            -- rename the current file (and fix links)
            backlinks = "<leader>wb",         -- Telescope picker of files referencing this one
            new = "<leader>wn",               -- create a new note and open it
            find = "<leader>wo",              -- Telescope picker to open any note
        },
    },
    paste = {
        enabled = true,                       -- enable pasting images as Markdown
        filetypes = { "markdown" },           -- where the feature is active
        assets_dir = "assets",                -- saved images go under notes_dir/assets_dir
        keymaps = {
            insert_paste = "<C-v>",           -- insert-mode paste key
            normal_paste = "p",               -- normal-mode paste (below cursor)
            normal_paste_above = "P",         -- normal-mode paste (above cursor)
        },
    },
    cite = {
        enabled = true,                       -- enable refree citation insertion
        filetypes = { "markdown", "tex" },    -- where the feature is active
        base_url = "http://127.0.0.1:23119",  -- refree REST base URL
        timeout = 5,                          -- seconds to wait per search request
        keymaps = {
            insert = "<leader>wc",            -- Telescope picker to insert a citation ([@key] / \cite{key})
            open_pdf = "<leader>wp",          -- open the PDF of the citation under the cursor
            references = "<leader>wR",        -- Telescope picker of files citing the [@citekey] under the cursor (Markdown only)
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
| `wikilink.keymaps` | `table` | `{ open = "<leader>wg", rename = "<leader>wr", backlinks = "<leader>wb", new = "<leader>wn", find = "<leader>wo" }` | Named wikilink keybindings (see below). |
| `wikilink.keymaps.open` | `string` | `"<leader>wg"` | Normal-mode keybinding used to open the file under the cursor. Set to `""` to disable it. |
| `wikilink.keymaps.rename` | `string` | `"<leader>wr"` | Normal-mode keybinding that renames the current file and rewrites `[[ ]]` references to it. Set to `""` to disable it. |
| `wikilink.keymaps.backlinks` | `string` | `"<leader>wb"` | Normal-mode keybinding that opens a Telescope picker of files referencing the current file via `[[ ]]`. Set to `""` to disable it. |
| `wikilink.keymaps.new` | `string` | `"<leader>wn"` | Normal-mode keybinding that prompts for a name, creates a new note under the notes directory, and opens it. This is a global keymap (works from any buffer, not only files in `notes_dir`). Set to `""` to disable it. |
| `wikilink.keymaps.find` | `string` | `"<leader>wo"` | Normal-mode keybinding that opens a Telescope picker listing every note under the notes directory for quick opening. This is a global keymap (works from any buffer, not only files in `notes_dir`). Set to `""` to disable it. |
| `paste.enabled` | `boolean` | `true` | Enable pasting images from the clipboard as Markdown links. |
| `paste.filetypes` | `string[]` | `{ "markdown" }` | Filetypes where image-paste is active. |
| `paste.assets_dir` | `string` | `"assets"` | Directory (relative to `notes_dir`) where pasted images are saved. It is created on first paste if it does not exist. |
| `paste.keymaps` | `table` | `{ insert_paste = "<C-v>", normal_paste = "p", normal_paste_above = "P" }` | Named paste keybindings (see below). |
| `paste.keymaps.insert_paste` | `string` | `"<C-v>"` | Insert-mode key intercepted to paste images. When the clipboard has no image it falls back to the key's normal behavior (insert-next-char-literally in a terminal, or paste in a GUI). Set to `""` to disable it. |
| `paste.keymaps.normal_paste` | `string` | `"p"` | Normal-mode key intercepted to paste images below the cursor. When the clipboard has no image it falls back to the normal put (preserving any count and register, e.g. `3p`, `"ap`). Set to `""` to disable it. |
| `paste.keymaps.normal_paste_above` | `string` | `"P"` | Normal-mode key intercepted to paste images above the cursor, with the same fallback as `normal_paste`. Set to `""` to disable it. |
| `cite.enabled` | `boolean` | `true` | Enable the refree citation picker. |
| `cite.filetypes` | `string[]` | `{ "markdown", "tex" }` | Filetypes where the citation picker is active. In `markdown` (and `pandoc`) buffers citations use the pandoc `[@citekey]` style and all three keymaps are attached. In `tex`/`latex`/`plaintex` buffers citations use the LaTeX `\cite{citekey}` style and only `insert` and `open_pdf` are attached (`references` is not, since LaTeX citation-scoping across a project differs from the notes-tree search). |
| `cite.base_url` | `string` | `"http://127.0.0.1:23119"` | refree REST base URL (no trailing slash). Change only if refree runs on a different port. |
| `cite.timeout` | `integer` | `5` | Seconds to wait for a single refree search request before giving up. |
| `cite.keymaps` | `table` | `{ insert = "<leader>wc", open_pdf = "<leader>wp", references = "<leader>wR" }` | Named citation keybindings (see below). |
| `cite.keymaps.insert` | `string` | `"<leader>wc"` | Normal-mode keybinding that opens a Telescope picker to search refree references by title/author/year and insert a citation at the cursor — `[@citekey]` in Markdown, `\cite{citekey}` in LaTeX. In Markdown it is attached only to buffers inside `notes_dir`; in LaTeX it is attached to any buffer of the configured filetypes (LaTeX projects are not notes-tree scoped). Set to `""` to disable it. |
| `cite.keymaps.open_pdf` | `string` | `"<leader>wp"` | Normal-mode keybinding that opens the PDF of the citation under the cursor in the default system viewer. The citation form is detected per filetype (`[@citekey]` in Markdown, `\cite{citekey}` in LaTeX; locators like `\cite[p. 12]{key}`, suppress-author prefixes (`[-@key]`), and multiple keys (`[@a; @b]` / `\cite{a, b}`) are handled — the key closest to the cursor is used). The citekey is looked up via refree's citekey endpoint and the reference's stored PDF is opened. Set to `""` to disable it. |
| `cite.keymaps.references` | `string` | `"<leader>wR"` | Normal-mode keybinding that opens a Telescope picker listing every file under the notes directory that references the `[@citekey]` under the cursor (including `[@key, p. 12]`, `[-@key]`, and `[@a; @key]` forms). Selecting an entry opens the referencing file with the cursor on the `@citekey`. Falls back to the key's normal behavior when the cursor is not inside a citation. Attached only in Markdown (pandoc) buffers; not attached for LaTeX. Set to `""` to disable it. |

## Usage

- Open a file inside your `notes_dir` (e.g. `~/notes/foo.md`) — the wikilink
  features attach automatically. Markdown files outside `notes_dir` are
  ignored.
- In insert mode, type `[[` — the completion menu appears; select an entry
  (or type your own text) and confirm. The `]]` is appended automatically.
- In normal mode, place the cursor anywhere on `[[some note]]` and press
  `<leader>wg` (the `open` keymap) to open `some note`. If the file doesn't
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
- In normal mode, press `<leader>wo` (the `find` keymap) to open a Telescope
  picker listing every note under the notes directory. This works from any
  buffer. Selecting an entry opens that note.
- Copy an image to your system clipboard (e.g. a screenshot), then paste inside
  a note with `<C-v>` (insert mode) or `p`/`P` (normal mode) — or via any
  bracketed / GUI / middle-click paste. The image is saved under
  `notes_dir/assets` as `<timestamp>.png` and a `![](assets/…)` link is
  inserted at the cursor (or on a new line below/above for `p`/`P`). Links use
  a path relative to the note, so nested notes get `../assets/…`. Pasting text
  (no image in the clipboard) works exactly as normal. Files outside
  `notes_dir` are never affected.
- In normal mode, press `<leader>wc` (the `insert` keymap) to open the
  citation picker. Type part of a paper's title or an author's name; results
  stream in live from refree as you type. Selecting an entry inserts a
  citation at the cursor in the buffer's style: `[@citekey]`
  (e.g. `[@smith2024example]`) in Markdown, or `\cite{citekey}`
  (e.g. `\cite{smith2024example}`) in LaTeX, leaving you in insert mode right
  after the inserted text. In Markdown the keymap attaches only to buffers
  inside `notes_dir`; in LaTeX it attaches to any `.tex` buffer. refree must
  be running for this to work.
- In normal mode, place the cursor anywhere inside a citation —
  `[@smith2024]` or `[@smith2024, p. 12]` in Markdown, `\cite{smith2024}` or
  `\cite[p. 12]{smith2024}` in LaTeX — and press `<leader>wp` (the `open_pdf`
  keymap) to open the item's PDF in your system's default viewer. Locators
  (`\cite[p. 12]{key}`), suppress-author prefixes (`[-@key]`), and multiple
  citations (`[@a; @b]` or `\cite{a, b}`) are handled — the key closest to
  the cursor is used. refree must be running.
- In normal mode, place the cursor anywhere inside a `[@citekey]` citation
  (e.g. `[@smith2024]` or `[@smith2024, p. 12]`) and press `<leader>wR` (the
  `references` keymap) to open a Telescope picker of every file under the notes
  directory that cites that same key. Locators, suppress-author prefixes
  (`[-@key]`), and multiple citations (`[@a; @b]`) are all matched. Selecting an
  entry opens the referencing file with the cursor placed on the `@citekey`.
  When the cursor is not on a citation the key falls back to its normal
  behavior. This keymap is attached only in Markdown (pandoc) buffers.
