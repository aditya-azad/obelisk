local M = {}

---@class obelisk.WikilinkKeymaps
---@field open string Keybinding (normal mode) that opens the file under the cursor when it sits inside [[ ]]
---@field rename string Keybinding (normal mode) that renames the current file and updates [[ ]] references to it
---@field backlinks string Keybinding (normal mode) that opens a Telescope picker listing files referencing the current file via [[ ]]

---@class obelisk.WikilinkConfig
---@field enabled boolean Enable [[ ]] file-name completion
---@field filetypes string[] Filetypes where wikilink completion is active
---@field keymaps obelisk.WikilinkKeymaps Wikilink keybindings

---@class obelisk.Config
---@field greeting string Message shown by the :Obelisk command
---@field wikilink obelisk.WikilinkConfig Configuration for [[ ]] wikilink completion

M.defaults = {
    greeting = "hello",
    wikilink = {
        enabled = true,
        filetypes = { "markdown" },
        keymaps = {
            open = "<leader>wo",
            rename = "<leader>wr",
            backlinks = "<leader>wb",
        },
    },
}

return M
