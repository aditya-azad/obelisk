local config = require("obelisk.config")
local wikilink = require("obelisk.wikilink")

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
end

return M
