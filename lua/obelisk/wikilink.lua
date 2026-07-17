local M = {}

local function strip_ext(name)
    return vim.fn.fnamemodify(name, ":r")
end

---@param buffer integer
local function collect_items(buffer)
    local filepath = vim.fn.expand("%:p")
    if filepath == "" then
        return {}
    end
    local dir = vim.fn.fnamemodify(filepath, ":h")
    local entries = vim.fn.readdir(dir)
    if not entries then
        return {}
    end
    table.sort(entries)
    local items = {}
    for _, entry in ipairs(entries) do
        if entry ~= "." and entry ~= ".." then
            local full = dir .. "/" .. entry
            if vim.fn.isdirectory(full) == 0 then
                items[#items + 1] = {
                    word = strip_ext(entry),
                    abbr = entry,
                    dup = 1,
                }
            end
        end
    end
    return items
end

---@param buffer integer
function M._check(buffer)
    if vim.v.char ~= "[" then
        return
    end
    local line = vim.fn.getline(".")
    local col = vim.fn.col(".")
    if line:sub(col - 1, col - 1) ~= "[" then
        return
    end
    vim.schedule(function()
        M._trigger(buffer)
    end)
end

---@param buffer integer
function M._trigger(buffer)
    if vim.api.nvim_get_mode().mode ~= "i" then
        return
    end
    local items = collect_items(buffer)
    if #items == 0 then
        return
    end
    vim.b[buffer].obelisk_wikilink_active = true
    local saved_copt = vim.o.completeopt
    local needs_noselect = not string.find(saved_copt, "noselect")
    if needs_noselect then
        vim.o.completeopt = saved_copt .. ",noselect"
    end
    vim.fn.complete(vim.fn.col("."), items)
    if needs_noselect then
        vim.o.completeopt = saved_copt
    end
end

---@param buffer integer
function M._complete_done(buffer)
    if not vim.b[buffer].obelisk_wikilink_active then
        return
    end
    vim.b[buffer].obelisk_wikilink_active = false
    local item = vim.v.event.completed_item
    if type(item) ~= "table" or item.word == nil or item.word == "" then
        return
    end
    vim.fn.feedkeys("]]", "n")
end

---@param buffer integer
function M.attach(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    if vim.b[buffer].obelisk_wikilink_attached then
        return
    end
    vim.b[buffer].obelisk_wikilink_attached = true

    vim.api.nvim_create_autocmd("InsertCharPre", {
        buffer = buffer,
        callback = function()
            M._check(buffer)
        end,
    })

    vim.api.nvim_create_autocmd("CompleteDone", {
        buffer = buffer,
        callback = function()
            M._complete_done(buffer)
        end,
    })
end

---@param opts? { filetypes?: string[] }
function M.setup(opts)
    opts = opts or {}
    local filetypes = opts.filetypes or { "markdown" }
    local ft_set = {}
    for _, ft in ipairs(filetypes) do
        ft_set[ft] = true
    end

    local group = vim.api.nvim_create_augroup("obelisk.wikilink", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = filetypes,
        callback = function(args)
            M.attach(args.buf)
        end,
    })

    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buffer) and ft_set[vim.bo[buffer].filetype] then
            M.attach(buffer)
        end
    end
end

return M
