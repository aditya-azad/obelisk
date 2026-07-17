local M = {}

---@class obelisk.WikilinkConfig
---@field enabled boolean Enable [[ ]] file-name completion
---@field filetypes string[] Filetypes where wikilink completion is active

---@class obelisk.Config
---@field greeting string Message shown by the :Obelisk command
---@field wikilink obelisk.WikilinkConfig Configuration for [[ ]] wikilink completion

M.defaults = {
    greeting = "hello",
    wikilink = {
        enabled = true,
        filetypes = { "markdown" },
    },
}

return M
