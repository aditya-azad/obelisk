local M = {}

local json = vim.json or {
    encode = function(t) return vim.fn.json_encode(t) end,
    decode = function(s) return vim.fn.json_decode(s) end,
}

local state = {
    notes_dir = "",
    url = "http://127.0.0.1:23119/better-bibtex/json-rpc",
    timeout = 5,
    keymaps = {
        insert = "<leader>wc",
        open_pdf = "<leader>wp",
        references = "<leader>wR",
    },
}

--- Return the path of `to_path` relative to the directory `from_dir`,
--- assuming `from_dir` is an ancestor of (or equal to) `to_path`'s directory.
--- Returns nil when `to_path` is not under `from_dir`.
---@param from_dir string
---@param to_path string
---@return string|nil
local function relpath_under(from_dir, to_path)
    from_dir = vim.fs.normalize(from_dir)
    to_path = vim.fs.normalize(to_path)
    if from_dir == "/" then
        return to_path:sub(2)
    end
    local prefix = from_dir .. "/"
    if to_path:sub(1, #prefix) == prefix then
        return to_path:sub(#prefix + 1)
    end
    return nil
end

--- Return true when `path` (absolute) lives inside the configured notes dir.
---@param path string
---@return boolean
local function in_notes_dir(path)
    if path == "" or state.notes_dir == "" then
        return false
    end
    return relpath_under(state.notes_dir, path) ~= nil
end

--- Find a loaded buffer whose file matches `path` (normalized comparison).
---@param path string
---@return integer|nil
local function find_buf_for_path(path)
    local norm = vim.fs.normalize(path)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) then
            local name = vim.api.nvim_buf_get_name(b)
            if name ~= "" and vim.fs.normalize(name) == norm then
                return b
            end
        end
    end
    return nil
end

--- Recursively collect files under `dir`, returning their paths relative to
--- `dir` (e.g. `papers/note.md`). Directories themselves are not included.
---@param dir string
---@return string[]
local function collect_files_recursive(dir)
    local result = {}
    local function walk(current_dir, prefix)
        local entries = vim.fn.readdir(current_dir)
        if not entries then
            return
        end
        table.sort(entries)
        for _, entry in ipairs(entries) do
            if entry ~= "." and entry ~= ".." then
                local full = current_dir .. "/" .. entry
                local rel = prefix == "" and entry or (prefix .. "/" .. entry)
                if vim.fn.isdirectory(full) == 0 then
                    result[#result + 1] = rel
                else
                    walk(full, rel)
                end
            end
        end
    end
    walk(dir, "")
    return result
end

--- Open `path` in the operating system's default application. Uses
--- `vim.ui.open` on Neovim 0.10+ and falls back to `open` (macOS),
--- `xdg-open` (Linux/BSD), or `cmd /c start` (Windows) on older versions.
---@param path string
local function open_in_system_viewer(path)
    if vim.ui and vim.ui.open then
        local ok, err = pcall(vim.ui.open, path)
        if ok then
            return
        end
        vim.notify("obelisk: could not open " .. path .. ": " .. tostring(err), vim.log.levels.WARN)
        return
    end
    if vim.fn.has("mac") == 1 then
        vim.fn.jobstart({ "open", path }, { detach = true })
        return
    elseif vim.fn.has("win32") == 1 then
        vim.fn.jobstart({ "cmd", "/c", "start", "", path }, { detach = true })
        return
    end
    if vim.fn.executable("xdg-open") == 1 then
        vim.fn.jobstart({ "xdg-open", path }, { detach = true })
        return
    end
    vim.notify("obelisk: no system file opener found (tried open, xdg-open)", vim.log.levels.ERROR)
end

--- Extract the Better BibTeX citation key from a CSL-JSON item. BBT emits
--- `citation-key` (and a duplicate `citekey`); fall back to a few alternates.
---@param item table
---@return string|nil
local function citekey_of(item)
    return item["citation-key"]
        or item.citekey
        or item.citationKey
        or item.key
end

--- Return the citation key under the cursor when it sits within a `[@…]`
--- pandoc citation. Handles locators (`[@smith2024, p. 12]`), suppress-author
--- prefixes (`[-@smith2024]`), and multiple citations (`[@a; @b]`); when the
--- cursor is inside the brackets but not directly on a key, the closest key is
--- returned. Returns nil when the cursor is not inside any `[@…]`.
---@return string|nil
local function citation_under_cursor()
    local line = vim.fn.getline(".")
    local col = vim.fn.col(".")
    local start = 1
    while true do
        local s, at_pos = line:find("%[%-?@", start)
        if not s then
            return nil
        end
        local e = line:find("%]", at_pos + 1)
        if not e then
            return nil
        end
        if col >= s and col <= e then
            local inner = line:sub(at_pos, e - 1)
            local cursor_inner = col - at_pos + 1
            local found = nil
            local best_dist = math.huge
            for pos, key in inner:gmatch("()@([^,;]+)") do
                local key_end = pos + #key
                if cursor_inner >= pos and cursor_inner <= key_end then
                    key = vim.trim(key)
                    return key ~= "" and key or nil
                end
                local dist = math.min(math.abs(cursor_inner - pos), math.abs(cursor_inner - key_end))
                if dist < best_dist then
                    best_dist = dist
                    found = key
                end
            end
            if found then
                found = vim.trim(found)
                return found ~= "" and found or nil
            end
            return nil
        end
        start = e + 1
    end
end

--- Find positions of `[@…]` citations in `line` that reference `citekey`.
--- Handles locators (`[@key, p. 12]`), suppress-author prefixes (`[-@key]`),
--- and multiple citations (`[@a; @b]`). Returns a list of matches where `col`
--- is the 1-based byte index of the `@` introducing the matching key.
---@param line string
---@param citekey string
---@return table[] matches { col = integer }
local function find_citation_matches(line, citekey)
    local matches = {}
    local start = 1
    while true do
        local s, at_pos = line:find("%[%-?@", start)
        if not s then
            break
        end
        local e = line:find("%]", at_pos + 1)
        if not e then
            break
        end
        local inner = line:sub(at_pos, e - 1)
        for pos, key in inner:gmatch("()@([^,;]+)") do
            key = vim.trim(key)
            if key == citekey then
                matches[#matches + 1] = { col = at_pos + pos - 1 }
            end
        end
        start = e + 1
    end
    return matches
end

--- Find every file under the notes directory that references `citekey` via a
--- `[@…]` pandoc citation. Loaded buffers are read in-memory so unsaved edits
--- are reflected. Returns a list of entries with the file path, line number,
--- column of the `@`, and the line text.
---@param citekey string
---@return table[] entries { path, lnum, col, text }
local function find_citation_references(citekey)
    local root = state.notes_dir
    if root == "" or citekey == "" then
        return {}
    end
    local results = {}
    for _, rel in ipairs(collect_files_recursive(root)) do
        local fpath = root .. "/" .. rel
        local lines = nil
        local buf = find_buf_for_path(fpath)
        if buf and vim.api.nvim_buf_is_loaded(buf) then
            lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        else
            local f = io.open(fpath, "r")
            if f then
                local content = f:read("*a")
                f:close()
                lines = vim.split(content, "\r?\n")
            end
        end
        if lines then
            for i, line in ipairs(lines) do
                for _, m in ipairs(find_citation_matches(line, citekey)) do
                    results[#results + 1] = {
                        path = fpath,
                        lnum = i,
                        col = m.col,
                        text = line,
                    }
                end
            end
        end
    end
    return results
end
--- ("Smith", "Smith & Jones", "Smith et al.", or "").
---@param item table
---@return string
local function format_authors(item)
    local authors = item.author or item.creators
    if type(authors) ~= "table" then
        return ""
    end
    local names = {}
    for _, a in ipairs(authors) do
        if type(a) == "table" then
            if a.name then
                names[#names + 1] = a.name
            elseif a.family then
                names[#names + 1] = a.family
            elseif a.literal then
                names[#names + 1] = a.literal
            end
        end
    end
    if #names == 0 then
        return ""
    elseif #names == 1 then
        return names[1]
    elseif #names == 2 then
        return names[1] .. " & " .. names[2]
    end
    return names[1] .. " et al."
end

--- Extract a 4-digit year from a CSL-JSON item's `issued` date-parts or the
--- Zotero `date` string.
---@param item table
---@return string
local function format_year(item)
    local issued = item.issued
    if type(issued) == "table" and type(issued["date-parts"]) == "table" then
        local first = issued["date-parts"][1]
        if type(first) == "table" and first[1] ~= nil then
            return tostring(first[1])
        end
    end
    if type(item.date) == "string" then
        local y = item.date:match("^(%d%d%d%d)")
        if y then
            return y
        end
    end
    return ""
end

--- Build a Telescope entry from a CSL-JSON item. The entry's `value` is the
--- citation key; `display` is a readable one-line summary; `ordinal` carries
--- every field a user might search by so the generic sorter keeps relevant
--- results. Returns nil for items without a citation key.
---@param item table
---@return table|nil
local function make_entry(item)
    local citekey = citekey_of(item)
    if not citekey or citekey == "" then
        return nil
    end
    local title = item.title or ""
    local authors = format_authors(item)
    local year = format_year(item)

    local display_parts = { citekey }
    local mid = ""
    if authors ~= "" and year ~= "" then
        mid = authors .. " (" .. year .. ")"
    elseif authors ~= "" then
        mid = authors
    elseif year ~= "" then
        mid = "(" .. year .. ")"
    end
    if mid ~= "" then
        display_parts[#display_parts + 1] = mid
    end
    if title ~= "" then
        display_parts[#display_parts + 1] = title
    end
    local display = table.concat(display_parts, "  |  ")
    local ordinal = citekey .. " " .. title .. " " .. authors .. " " .. year

    return {
        value = citekey,
        display = display,
        ordinal = ordinal,
    }
end

--- Synchronously check that the Better BibTeX JSON-RPC endpoint is reachable
--- and ready. Returns `(true, nil)` on success or `(false, err_msg)`.
---@return boolean, string|nil
local function bbt_ready()
    if vim.fn.executable("curl") ~= 1 then
        return false, "curl executable not found (required for Zotero integration)"
    end
    local body = json.encode({ jsonrpc = "2.0", method = "api.ready", params = {} })
    local out = vim.fn.system({
        "curl", "-sS", "-m", "1",
        state.url, "-X", "POST",
        "-H", "Content-Type: application/json",
        "-H", "Accept: application/json",
        "--data-binary", body,
    })
    if vim.v.shell_error ~= 0 then
        return false, "cannot reach Better BibTeX at " .. state.url
            .. " (is Zotero running with the Better BibTeX plugin?)"
    end
    if out == "" then
        return false, "empty response from Better BibTeX at " .. state.url
    end
    local ok, parsed = pcall(json.decode, out)
    if not ok or type(parsed) ~= "table" then
        return false, "could not parse Better BibTeX response"
    end
    if parsed.error then
        return false, parsed.error.message or "Better BibTeX error"
    end
    if not (parsed.result and parsed.result.betterbibtex) then
        return false, "Better BibTeX not ready at " .. state.url
    end
    return true
end

--- Asynchronously run a Better BibTeX `item.search` request for `query` and
--- invoke `callback(results, err)` when it completes. `results` is the CSL-JSON
--- item array (empty on success with no matches); `err` is a string on failure.
--- Returns the job id so the caller can cancel it.
---@param query string
---@param callback fun(results: table[]|nil, err: string|nil)
---@return integer|nil
local function bbt_search(query, callback)
    if vim.fn.executable("curl") ~= 1 then
        callback(nil, "curl executable not found")
        return nil
    end
    local body = json.encode({
        jsonrpc = "2.0",
        method = "item.search",
        params = { query },
    })
    local chunks = {}
    local job_id = vim.fn.jobstart({
        "curl", "-sS", "-m", tostring(state.timeout),
        state.url, "-X", "POST",
        "-H", "Content-Type: application/json",
        "-H", "Accept: application/json",
        "--data-binary", body,
    }, {
        on_stdout = function(_, data, _)
            if type(data) == "table" then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        chunks[#chunks + 1] = line
                    end
                end
            end
        end,
        on_exit = function(_, exit_code, _)
            if exit_code ~= 0 then
                callback(nil, string.format("curl exited %d (is Zotero running?)", exit_code))
                return
            end
            local raw = table.concat(chunks, "")
            if raw == "" then
                callback(nil, "empty response from Better BibTeX")
                return
            end
            local ok, parsed = pcall(json.decode, raw)
            if not ok then
                callback(nil, "could not parse Better BibTeX response")
                return
            end
            if type(parsed) == "table" and parsed.error then
                callback(nil, parsed.error.message or "json-rpc error")
                return
            end
            local result = parsed and parsed.result
            if type(result) ~= "table" then
                callback({}, nil)
                return
            end
            callback(result, nil)
        end,
    })
    return job_id
end

--- Synchronously run a Better BibTeX `item.attachments` request for `citekey`
--- and return the attachment array. Each attachment has a `path` field with the
--- absolute file path on disk (suitable for opening in a system viewer). Returns
--- `(attachments, nil)` on success or `(nil, err_msg)` on failure.
---@param citekey string
---@return table[]|nil, string|nil
local function bbt_attachments(citekey)
    if vim.fn.executable("curl") ~= 1 then
        return nil, "curl executable not found (required for Zotero integration)"
    end
    local body = json.encode({
        jsonrpc = "2.0",
        method = "item.attachments",
        params = { citekey },
    })
    local out = vim.fn.system({
        "curl", "-sS", "-m", tostring(state.timeout),
        state.url, "-X", "POST",
        "-H", "Content-Type: application/json",
        "-H", "Accept: application/json",
        "--data-binary", body,
    })
    if vim.v.shell_error ~= 0 then
        return nil, "cannot reach Better BibTeX at " .. state.url
            .. " (is Zotero running with the Better BibTeX plugin?)"
    end
    if out == "" then
        return nil, "empty response from Better BibTeX"
    end
    local ok, parsed = pcall(json.decode, out)
    if not ok or type(parsed) ~= "table" then
        return nil, "could not parse Better BibTeX response"
    end
    if parsed.error then
        return nil, parsed.error.message or "Better BibTeX error"
    end
    local result = parsed.result
    if type(result) ~= "table" then
        return nil, "no attachments found for @" .. citekey
    end
    return result, nil
end

--- Build a Telescope finder that queries Better BibTeX on every keystroke.
--- The finder implements the `__call(prompt, process_result, process_complete)`
--- contract used by telescope's picker loop, and uses a generation counter so
--- responses from cancelled (superseded) requests never feed the picker.
---@param entry_maker fun(item: table): table|nil
---@return table
local function new_bbt_finder(entry_maker)
    local obj = {}
    obj.__index = obj
    local current_job = nil
    local current_gen = 0
    local notified = false

    function obj:_find(prompt, process_result, process_complete)
        current_gen = current_gen + 1
        local gen = current_gen
        if current_job then
            vim.fn.jobstop(current_job)
            current_job = nil
        end

        local query = prompt or ""
        -- BBT's `item.search("")` returns nothing in current versions, so skip
        -- the request for an empty prompt and show an empty list instead.
        if query == "" then
            process_complete()
            return
        end

        current_job = bbt_search(query, function(results, err)
            if gen ~= current_gen then
                return
            end
            current_job = nil
            if err then
                if not notified then
                    notified = true
                    vim.schedule(function()
                        vim.notify("obelisk: Zotero search failed: " .. err, vim.log.levels.WARN)
                    end)
                end
                process_complete()
                return
            end
            if not results then
                process_complete()
                return
            end
            local n = 0
            for _, item in ipairs(results) do
                n = n + 1
                local entry = entry_maker(item)
                if entry then
                    entry.index = n
                end
                if process_result(entry) then
                    return
                end
            end
            process_complete()
        end)
    end

    function obj.close()
        current_gen = current_gen + 1
        if current_job then
            vim.fn.jobstop(current_job)
            current_job = nil
        end
    end

    return setmetatable(obj, {
        __call = function(t, ...) return t:_find(...) end,
    })
end

--- Insert `[@citekey]` at the current cursor position in `buffer`, then enter
--- insert mode with the cursor placed right after the closing `]`.
---@param buffer integer
---@param citekey string
local function insert_citation(buffer, citekey)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    local text = "[@" .. citekey .. "]"
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local lines = vim.api.nvim_buf_get_lines(buffer, row - 1, row, false)
    local line = lines[1] or ""
    local before = line:sub(1, col + 1)
    local after = line:sub(col + 2)
    vim.api.nvim_buf_set_lines(buffer, row - 1, row, false, { before .. text .. after })
    local new_col = col + #text
    vim.api.nvim_win_set_cursor(0, { row, new_col })
    vim.cmd("startinsert")
end

--- Check that Better BibTeX is reachable and open a Telescope picker that
--- searches the Zotero library by title/author/year. Selecting an entry
--- inserts `[@citekey]` at the cursor.
---@param buffer integer
function M._cite(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    local ready, err = bbt_ready()
    if not ready then
        vim.notify("obelisk: " .. err, vim.log.levels.ERROR)
        return
    end

    local ok, pickers = pcall(require, "telescope.pickers")
    if not ok then
        vim.notify("obelisk: telescope.nvim is required for citations", vim.log.levels.ERROR)
        return
    end
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers.new({}, {
        prompt_title = "Obelisk Citations (Zotero)",
        finder = new_bbt_finder(make_entry),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if selection then
                    insert_citation(buffer, selection.value)
                end
            end)
            return true
        end,
    }):find()
end

--- Open the PDF attachment of the `[@citekey]` under the cursor in the default
--- system viewer. Falls back to the key's default action when the cursor is not
--- inside a citation. Queries Better BibTeX for the item's attachments and
--- prefers the first PDF; if no PDF is found, opens the first attachment with a
--- file path.
---@param buffer integer
function M._open_citation_pdf(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    local citekey = citation_under_cursor()
    if not citekey then
        local key = state.keymaps.open_pdf
        if key ~= nil and key ~= "" then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), "n", false)
        end
        return
    end
    local attachments, err = bbt_attachments(citekey)
    if err then
        vim.notify("obelisk: " .. err, vim.log.levels.ERROR)
        return
    end
    local pdf_path = nil
    local any_path = nil
    for _, att in ipairs(attachments) do
        local p = att.path
        if type(p) == "string" and p ~= "" then
            any_path = p
            if p:lower():match("%.pdf$") then
                pdf_path = p
                break
            end
        end
    end
    local path = pdf_path or any_path
    if not path then
        vim.notify("obelisk: no file attachment found for @" .. citekey, vim.log.levels.WARN)
        return
    end
    open_in_system_viewer(path)
end

--- Open a Telescope picker listing every file under the notes directory that
--- references the `[@citekey]` under the cursor. Falls back to the key's
--- default action when the cursor is not inside a citation. Selecting an entry
--- opens the referencing file with the cursor on the `@citekey`.
---@param buffer integer
function M._citation_references(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    local citekey = citation_under_cursor()
    if not citekey then
        local key = state.keymaps.references
        if key ~= nil and key ~= "" then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), "n", false)
        end
        return
    end
    local entries = find_citation_references(citekey)
    if #entries == 0 then
        vim.notify("obelisk: no references to @" .. citekey, vim.log.levels.INFO)
        return
    end

    local ok, pickers = pcall(require, "telescope.pickers")
    if not ok then
        vim.notify("obelisk: telescope.nvim is required for citation references", vim.log.levels.ERROR)
        return
    end
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers.new({}, {
        prompt_title = "Obelisk References to @" .. citekey,
        finder = finders.new_table({
            results = entries,
            entry_maker = function(entry)
                local disp = string.format("%s:%d: %s",
                    vim.fn.fnamemodify(entry.path, ":."), entry.lnum,
                    (entry.text:gsub("^%s+", "")))
                return {
                    value = entry,
                    display = disp,
                    ordinal = disp,
                    filename = entry.path,
                    lnum = entry.lnum,
                    col = entry.col,
                }
            end,
        }),
        previewer = conf.grep_previewer({}),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if selection then
                    local e = selection.value
                    vim.cmd("edit " .. vim.fn.fnameescape(e.path))
                    vim.api.nvim_win_set_cursor(0, { e.lnum, math.max(0, e.col - 1) })
                end
            end)
            return true
        end,
    }):find()
end

---@param buffer integer
function M.attach(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    if vim.b[buffer].obelisk_cite_attached then
        return
    end
    local path = vim.api.nvim_buf_get_name(buffer)
    if not in_notes_dir(path) then
        return
    end
    vim.b[buffer].obelisk_cite_attached = true

    if state.keymaps.insert ~= nil and state.keymaps.insert ~= "" then
        vim.keymap.set("n", state.keymaps.insert, function()
            M._cite(buffer)
        end, {
            buffer = buffer,
            silent = true,
            desc = "insert a Zotero citation at the cursor",
        })
    end

    if state.keymaps.open_pdf ~= nil and state.keymaps.open_pdf ~= "" then
        vim.keymap.set("n", state.keymaps.open_pdf, function()
            M._open_citation_pdf(buffer)
        end, {
            buffer = buffer,
            silent = true,
            desc = "open the PDF of the citation under the cursor",
        })
    end

    if state.keymaps.references ~= nil and state.keymaps.references ~= "" then
        vim.keymap.set("n", state.keymaps.references, function()
            M._citation_references(buffer)
        end, {
            buffer = buffer,
            silent = true,
            desc = "find references to the citation under the cursor",
        })
    end
end

---@param opts? { notes_dir?: string, filetypes?: string[], url?: string, timeout?: integer, keymaps?: { insert?: string, open_pdf?: string, references?: string } }
function M.setup(opts)
    opts = opts or {}
    if opts.notes_dir and opts.notes_dir ~= "" then
        state.notes_dir = vim.fs.normalize(vim.fn.expand(opts.notes_dir))
    end
    if opts.url and opts.url ~= "" then
        state.url = opts.url
    end
    if opts.timeout and opts.timeout > 0 then
        state.timeout = opts.timeout
    end
    local filetypes = opts.filetypes or { "markdown" }
    if opts.keymaps ~= nil then
        if opts.keymaps.insert ~= nil then
            state.keymaps.insert = opts.keymaps.insert
        end
        if opts.keymaps.open_pdf ~= nil then
            state.keymaps.open_pdf = opts.keymaps.open_pdf
        end
        if opts.keymaps.references ~= nil then
            state.keymaps.references = opts.keymaps.references
        end
    end
    local ft_set = {}
    for _, ft in ipairs(filetypes) do
        ft_set[ft] = true
    end

    local group = vim.api.nvim_create_augroup("obelisk.cite", { clear = true })
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
