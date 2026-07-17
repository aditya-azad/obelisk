local M = {}

local state = {
    keymaps = {
        open = "<leader>wo",
    },
}

local function strip_ext(name)
    return vim.fn.fnamemodify(name, ":r")
end

--- Return the link target under the cursor when it sits within `[[ ]]`.
---@return string|nil
local function wikilink_under_cursor()
    local line = vim.fn.getline(".")
    local col = vim.fn.col(".")
    local start = 1
    while true do
        local s, e = line:find("%[%[", start)
        if not s then
            return nil
        end
        local s2 = line:find("%]%]", e + 1)
        if not s2 then
            return nil
        end
        if col >= s and col <= s2 + 1 then
            local text = line:sub(e + 1, s2 - 1)
            local anchor = text:find("#")
            if anchor then
                text = text:sub(1, anchor - 1)
            end
            return text
        end
        start = s2 + 2
    end
end

--- Open the file matching `name` from the current buffer's directory.
--- If no existing file matches, open a new note path so it can be created.
---@param name string
local function open_target(name)
    local dir = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":h")
    local entries = vim.fn.readdir(dir)
    if entries then
        table.sort(entries)
        for _, entry in ipairs(entries) do
            local full = dir .. "/" .. entry
            if vim.fn.isdirectory(full) == 0 and strip_ext(entry) == name then
                vim.cmd("edit " .. vim.fn.fnameescape(full))
                return
            end
        end
    end
    local path = dir .. "/" .. name .. ".md"
    vim.cmd("edit " .. vim.fn.fnameescape(path))
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
    local trigger_line = vim.fn.line(".")
    local trigger_col = vim.fn.col(".")
    vim.b[buffer].obelisk_trigger_line = trigger_line
    vim.b[buffer].obelisk_trigger_col = trigger_col
    vim.b[buffer].obelisk_trigger_text_before = vim.fn.getline(trigger_line):sub(trigger_col)
    local saved_copt = vim.o.completeopt
    local needs_noselect = not string.find(saved_copt, "noselect")
    if needs_noselect then
        vim.o.completeopt = saved_copt .. ",noselect"
    end
    vim.fn.complete(trigger_col, items)
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
    local trigger_line = vim.b[buffer].obelisk_trigger_line
    local trigger_col = vim.b[buffer].obelisk_trigger_col
    local text_before = vim.b[buffer].obelisk_trigger_text_before
    vim.b[buffer].obelisk_trigger_line = nil
    vim.b[buffer].obelisk_trigger_col = nil
    vim.b[buffer].obelisk_trigger_text_before = nil
    if trigger_line == nil or trigger_col == nil or text_before == nil then
        return
    end
    local current_line_text = vim.fn.getline(trigger_line)
    local text_after = current_line_text:sub(trigger_col)
    if text_after == text_before then
        return
    end
    if vim.fn.line(".") == trigger_line then
        local col = vim.fn.col(".")
        local line = vim.fn.getline(".")
        vim.fn.setline(".", line:sub(1, col - 1) .. "]]" .. line:sub(col))
        if vim.api.nvim_get_mode().mode == "i" then
            vim.fn.cursor(vim.fn.line("."), col + 2)
        end
    else
        vim.fn.setline(trigger_line, current_line_text .. "]]")
    end
end

--- Open the wikilink under the cursor; fall back to the key's default
--- action when the cursor is not inside `[[ ]]`.
---@param buffer integer
function M._open_under_cursor(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    local name = wikilink_under_cursor()
    if name and name ~= "" then
        open_target(name)
        return
    end
    local key = state.keymaps.open
    if key ~= nil and key ~= "" then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), "n", false)
    end
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

    if state.keymaps.open ~= nil and state.keymaps.open ~= "" then
        vim.keymap.set("n", state.keymaps.open, function()
            M._open_under_cursor(buffer)
        end, {
            buffer = buffer,
            silent = true,
            desc = "Obelisk: open wikilink under cursor",
        })
    end
end

---@param opts? { filetypes?: string[], keymaps?: { open?: string } }
function M.setup(opts)
    opts = opts or {}
    local filetypes = opts.filetypes or { "markdown" }
    if opts.keymaps ~= nil then
        if opts.keymaps.open ~= nil then
            state.keymaps.open = opts.keymaps.open
        end
    end
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
