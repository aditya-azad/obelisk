local M = {}

---@class obelisk.WikilinkKeymaps
---@field open string Keybinding (normal mode) that opens the file under the cursor when it sits inside [[ ]]
---@field rename string Keybinding (normal mode) that renames the current file and updates [[ ]] references to it
---@field backlinks string Keybinding (normal mode) that opens a Telescope picker listing files referencing the current file via [[ ]]
---@field new string Keybinding (normal mode) that prompts for a name, creates a new note under the notes directory, and opens it

---@class obelisk.WikilinkConfig
---@field enabled boolean Enable [[ ]] file-name completion
---@field filetypes string[] Filetypes where wikilink completion is active
---@field keymaps obelisk.WikilinkKeymaps Wikilink keybindings

---@class obelisk.Config
---@field notes_dir string Directory where notes live; wikilink features only activate for files inside it
---@field wikilink obelisk.WikilinkConfig Configuration for [[ ]] wikilink completion

M.defaults = {
    notes_dir = vim.fn.getcwd() .. "/notes",
    wikilink = {
        enabled = true,
        filetypes = { "markdown" },
        keymaps = {
            open = "<leader>wo",
            rename = "<leader>wr",
            backlinks = "<leader>wb",
            new = "<leader>wn",
        },
    },
}

return M
