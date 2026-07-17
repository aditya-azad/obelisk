local config = require("obelisk.config")
local wikilink = require("obelisk.wikilink")

local M = {}

---@type obelisk.Config
M.config = {}

---@param opts? obelisk.Config
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", config.defaults, opts or {})

    vim.api.nvim_create_user_command("Obelisk", function()
        vim.notify("obelisk: " .. M.config.greeting, vim.log.levels.INFO)
    end, { desc = "Obelisk demo command" })

    if M.config.wikilink.enabled then
        wikilink.setup({
            notes_dir = M.config.notes_dir,
            filetypes = M.config.wikilink.filetypes,
            keymaps = M.config.wikilink.keymaps,
        })
    end
end

return M
