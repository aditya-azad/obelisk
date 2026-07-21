local config = require("obelisk.config")
local wikilink = require("obelisk.wikilink")
local paste = require("obelisk.paste")
local cite = require("obelisk.cite")

local M = {}

---@type obelisk.Config
M.config = {}

---@param opts? obelisk.Config
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", config.defaults, opts or {})

    if M.config.wikilink.enabled then
        wikilink.setup({
            notes_dir = M.config.notes_dir,
            filetypes = M.config.wikilink.filetypes,
            keymaps = M.config.wikilink.keymaps,
        })
    end

    if M.config.paste.enabled then
        paste.setup({
            notes_dir = M.config.notes_dir,
            filetypes = M.config.paste.filetypes,
            assets_dir = M.config.paste.assets_dir,
            keymaps = M.config.paste.keymaps,
        })
    end

    if M.config.cite.enabled then
        cite.setup({
            notes_dir = M.config.notes_dir,
            filetypes = M.config.cite.filetypes,
            url = M.config.cite.url,
            timeout = M.config.cite.timeout,
            keymaps = M.config.cite.keymaps,
        })
    end
end

return M
