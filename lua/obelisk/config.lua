local M = {}

---@class obelisk.WikilinkKeymaps
---@field open string Keybinding (normal mode) that opens the file under the cursor when it sits inside [[ ]]
---@field rename string Keybinding (normal mode) that renames the current file and updates [[ ]] references to it
---@field backlinks string Keybinding (normal mode) that opens a Telescope picker listing files referencing the current file via [[ ]]
---@field new string Keybinding (normal mode) that prompts for a name, creates a new note under the notes directory, and opens it
---@field find string Keybinding (normal mode) that opens a Telescope picker listing every note under the notes directory for quick opening

---@class obelisk.WikilinkConfig
---@field enabled boolean Enable [[ ]] file-name completion
---@field filetypes string[] Filetypes where wikilink completion is active
---@field keymaps obelisk.WikilinkKeymaps Wikilink keybindings

---@class obelisk.PasteKeymaps
---@field insert_paste string Keybinding (insert mode) intercepted to paste images; falls back to its normal behavior when the clipboard has no image
---@field normal_paste string Keybinding (normal mode) intercepted to paste images below the cursor; falls back to normal put when the clipboard has no image
---@field normal_paste_above string Keybinding (normal mode) intercepted to paste images above the cursor; falls back to normal put when the clipboard has no image

---@class obelisk.PasteConfig
---@field enabled boolean Enable pasting images from the clipboard as Markdown links
---@field filetypes string[] Filetypes where image-paste is active
---@field assets_dir string Directory (relative to notes_dir) where pasted images are saved
---@field keymaps obelisk.PasteKeymaps Named paste keybindings

---@class obelisk.Config
---@field notes_dir string Directory where notes live; wikilink features only activate for files inside it
---@field wikilink obelisk.WikilinkConfig Configuration for [[ ]] wikilink completion
---@field paste obelisk.PasteConfig Configuration for pasting images from the clipboard as Markdown

M.defaults = {
    notes_dir = vim.fn.getcwd() .. "/notes",
    wikilink = {
        enabled = true,
        filetypes = { "markdown" },
        keymaps = {
            open = "<leader>wg",
            rename = "<leader>wr",
            backlinks = "<leader>wb",
            new = "<leader>wn",
            find = "<leader>wo",
        },
    },
    paste = {
        enabled = true,
        filetypes = { "markdown" },
        assets_dir = "assets",
        keymaps = {
            insert_paste = "<C-v>",
            normal_paste = "p",
            normal_paste_above = "P",
        },
    },
}

return M
