local M = {}

---@class obelisk.WikilinkKeymaps
---@field open string Keybinding (normal mode) that opens the file under the cursor when it sits inside [[ ]]

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
        },
    },
}

return M
