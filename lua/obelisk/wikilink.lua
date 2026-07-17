local M = {}

local state = {
    notes_dir = "",
    keymaps = {
        open = "<leader>wg",
        rename = "<leader>wr",
        backlinks = "<leader>wb",
        new = "<leader>wn",
        find = "<leader>wo",
    },
}

local function strip_ext(name)
    return vim.fn.fnamemodify(name, ":r")
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

--- Open the file matching `name` from the notes directory.
--- `name` may be a relative path (e.g. `papers/note`) for nested files.
--- If no existing file matches, open a new note path so it can be created.
---@param name string
local function open_target(name)
    local dir = state.notes_dir
    for _, rel in ipairs(collect_files_recursive(dir)) do
        if strip_ext(rel) == name then
            vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/" .. rel))
            return
        end
    end
    local path = dir .. "/" .. name .. ".md"
    vim.cmd("edit " .. vim.fn.fnameescape(path))
end

--- Split a wikilink's inner text into its target and the trailing remainder
--- (e.g. `#anchor`, `|alias`, or `#anchor|alias`). The target ends at the
--- first `#` or `|`.
---@param inner string
---@return string target, string rest
local function split_link_target(inner)
    local h = inner:find("#", 1, true)
    local p = inner:find("|", 1, true)
    local cut
    if h and p then
        cut = math.min(h, p)
    elseif h then
        cut = h
    elseif p then
        cut = p
    end
    if cut then
        return inner:sub(1, cut - 1), inner:sub(cut)
    end
    return inner, ""
end

--- Replace every `[[expected]]`, `[[expected#anchor]]` and
--- `[[expected|alias]]` occurrence in `line` with `newexpected`, preserving
--- the anchor/alias portion. Returns the new text and the replacement count.
---@param line string
---@param expected string
---@param newexpected string
---@return string, integer
local function replace_wikilink_target(line, expected, newexpected)
    if expected == newexpected or expected == "" then
        return line, 0
    end
    local count = 0
    local result = line:gsub("%[%[([^%]]*)%]%]", function(inner)
        local target, rest = split_link_target(inner)
        if target == expected then
            count = count + 1
            return "[[" .. newexpected .. rest .. "]]"
        end
        return nil
    end)
    return result, count
end

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

--- Update every `[[ ]]` reference to `oldpath` within `fpath` so it points at
--- `newpath`. Loaded buffers are edited in memory (and saved); other files are
--- rewritten on disk. Returns `(files_changed, refs_changed)`.
---@param fpath string
---@param oldpath string
---@param newpath string
---@return integer, integer
local function update_references_in_file(fpath, oldpath, newpath)
    local d = vim.fn.fnamemodify(fpath, ":h")
    local rel = relpath_under(d, oldpath)
    if not rel then
        return 0, 0
    end
    local expected = strip_ext(rel)
    local newrel = relpath_under(d, newpath)
    if not newrel then
        return 0, 0
    end
    local newexpected = strip_ext(newrel)

    local buf = find_buf_for_path(fpath)
    if buf and vim.api.nvim_buf_is_loaded(buf) then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local changed = false
        local refs = 0
        for i, line in ipairs(lines) do
            local newline, n = replace_wikilink_target(line, expected, newexpected)
            if n > 0 then
                lines[i] = newline
                changed = true
                refs = refs + n
            end
        end
        if changed then
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.api.nvim_buf_call(buf, function()
                vim.cmd("silent! write")
            end)
            return 1, refs
        end
        return 0, 0
    end

    local f = io.open(fpath, "rb")
    if not f then
        return 0, 0
    end
    local content = f:read("*a")
    f:close()
    local newcontent, refs = replace_wikilink_target(content, expected, newexpected)
    if refs > 0 then
        local f2 = io.open(fpath, "wb")
        if f2 then
            f2:write(newcontent)
            f2:close()
        end
        return 1, refs
    end
    return 0, 0
end

---@param buffer integer
local function collect_items(buffer)
    local dir = state.notes_dir
    if dir == "" then
        return {}
    end
    local files = collect_files_recursive(dir)
    local items = {}
    for _, rel in ipairs(files) do
        items[#items + 1] = {
            word = strip_ext(rel),
            abbr = rel,
            dup = 1,
        }
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

--- Prompt for a name, create a new note under the notes directory, and open
--- it. The name may be a relative path (e.g. `papers/idea`); intermediate
--- directories are created as needed. A trailing `.md` is optional. If the
--- file already exists it is simply opened.
function M._new_note()
    local dir = state.notes_dir
    if dir == "" then
        vim.notify("obelisk: notes directory is not configured", vim.log.levels.WARN)
        return
    end
    vim.ui.input({
        prompt = "New note: ",
    }, function(input)
        if input == nil then
            return
        end
        local name = input
        if name:sub(-3) == ".md" then
            name = name:sub(1, -4)
        end
        vim.schedule(function()
            if name == "" then
                vim.notify("obelisk: empty name", vim.log.levels.ERROR)
                return
            end
            if name:find("[%[%]#|%\\%c]") then
                vim.notify("obelisk: name may not contain [, ], #, |, \\ or control characters",
                    vim.log.levels.ERROR)
                return
            end
            local path = dir .. "/" .. name .. ".md"
            local parent = vim.fn.fnamemodify(path, ":h")
            if parent ~= "" and vim.fn.isdirectory(parent) == 0 then
                vim.fn.mkdir(parent, "p")
            end
            vim.cmd("edit " .. vim.fn.fnameescape(path))
        end)
    end)
end

--- Open a Telescope picker listing every note under the notes directory.
--- Selecting an entry opens that note. This is a global action and works
--- from any buffer — not only files inside `notes_dir`.
function M._find_note()
    local dir = state.notes_dir
    if dir == "" then
        vim.notify("obelisk: notes directory is not configured", vim.log.levels.WARN)
        return
    end
    local files = collect_files_recursive(dir)
    if #files == 0 then
        vim.notify("obelisk: no notes found in " .. dir, vim.log.levels.INFO)
        return
    end

    local ok, pickers = pcall(require, "telescope.pickers")
    if not ok then
        vim.notify("obelisk: telescope.nvim is required to find notes", vim.log.levels.ERROR)
        return
    end
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers.new({}, {
        prompt_title = "Obelisk Notes",
        finder = finders.new_table({
            results = files,
            entry_maker = function(rel)
                local path = dir .. "/" .. rel
                return {
                    value = rel,
                    display = rel,
                    ordinal = rel,
                    filename = path,
                    path = path,
                }
            end,
        }),
        previewer = conf.file_previewer({}),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if selection then
                    vim.cmd("edit " .. vim.fn.fnameescape(selection.path))
                end
            end)
            return true
        end,
    }):find()
end

--- Collect files that may link to a file located in `target_dir`: the files
--- sitting directly in each directory from `target_dir` up to (and including)
--- `root`. With the plugin's relative-to-current-dir resolution, only files
--- in an ancestor-or-equal directory can link to the target file.
---@param target_dir string
---@param root string
---@return string[]
local function collect_ancestor_files(target_dir, root)
    local files = {}
    local d = target_dir
    while true do
        local entries = vim.fn.readdir(d)
        if entries then
            for _, entry in ipairs(entries) do
                if entry ~= "." and entry ~= ".." then
                    local full = d .. "/" .. entry
                    if vim.fn.isdirectory(full) == 0 then
                        files[#files + 1] = full
                    end
                end
            end
        end
        if d == root then
            break
        end
        local parent = vim.fn.fnamemodify(d, ":h")
        if parent == d then
            break
        end
        d = parent
    end
    return files
end

--- Perform the rename of `oldpath` to a new basename `newbase`, rewriting
--- `[[ ]]` references across the note tree.
---@param buffer integer
---@param oldpath string
---@param oldbase string
---@param ext string
---@param root string
---@param newbase string
local function do_rename(buffer, oldpath, oldbase, ext, root, newbase)
    if newbase == "" then
        vim.notify("obelisk: empty name", vim.log.levels.ERROR)
        return
    end
    if newbase:find("[%[/\\%]#|%c]") then
        vim.notify("obelisk: name may not contain /, \\, [, ], #, | or control characters",
            vim.log.levels.ERROR)
        return
    end
    if newbase == oldbase then
        vim.notify("obelisk: name unchanged", vim.log.levels.WARN)
        return
    end

    local olddir = vim.fn.fnamemodify(oldpath, ":h")
    local newpath = olddir .. "/" .. newbase .. (ext ~= "" and "." .. ext or "")
    if vim.fn.filereadable(newpath) == 1 or vim.fn.isdirectory(newpath) == 1 then
        vim.notify("obelisk: a file already exists at " .. newpath, vim.log.levels.ERROR)
        return
    end

    -- Collect candidate files: the files sitting directly in each directory
    -- on the path from the current file's directory up to the tree root. With
    -- the plugin's relative-to-current-dir resolution, only files in an
    -- ancestor-or-equal directory can link to the renamed file.
    local files = collect_ancestor_files(olddir, root)

    local files_changed = 0
    local refs_changed = 0
    for _, fpath in ipairs(files) do
        local fc, rc = update_references_in_file(fpath, oldpath, newpath)
        files_changed = files_changed + fc
        refs_changed = refs_changed + rc
    end

    -- Rename the file itself: persist the current buffer, move it on disk,
    -- then rebind the buffer to the new path.
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    vim.api.nvim_buf_call(buffer, function()
        vim.cmd("silent! write")
    end)
    local ok, err = os.rename(oldpath, newpath)
    if not ok then
        vim.notify("obelisk: rename failed: " .. tostring(err), vim.log.levels.ERROR)
        return
    end
    vim.api.nvim_buf_call(buffer, function()
        vim.cmd("silent! saveas! " .. vim.fn.fnameescape(newpath))
    end)

    vim.notify(string.format("obelisk: renamed %s -> %s (%d reference%s in %d file%s)",
        oldbase, newbase, refs_changed, refs_changed == 1 and "" or "s",
        files_changed, files_changed == 1 and "" or "s"), vim.log.levels.INFO)
end

--- Prompt for a new name and rename the current file, updating `[[ ]]`
--- references to it across the note tree.
---@param buffer integer
function M._rename_current(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    local oldpath = vim.fn.expand("%:p")
    if oldpath == "" then
        vim.notify("obelisk: current buffer has no file to rename", vim.log.levels.WARN)
        return
    end
    oldpath = vim.fs.normalize(oldpath)
    if not in_notes_dir(oldpath) then
        vim.notify("obelisk: current file is not inside the notes directory", vim.log.levels.WARN)
        return
    end
    local olddir = vim.fn.fnamemodify(oldpath, ":h")
    local oldbase = vim.fn.fnamemodify(oldpath, ":t:r")
    local ext = vim.fn.fnamemodify(oldpath, ":e")
    local root = state.notes_dir

    vim.ui.input({
        prompt = "Rename note to: ",
        default = oldbase,
    }, function(input)
        if input == nil then
            return
        end
        local newbase = input
        if ext ~= "" and newbase:sub(-(#ext + 1)) == "." .. ext then
            newbase = newbase:sub(1, -(#ext + 2))
        end
        vim.schedule(function()
            do_rename(buffer, oldpath, oldbase, ext, root, newbase)
        end)
    end)
end

--- Find positions of `[[ ]]` links in `line` whose target equals `expected`.
---@param line string
---@param expected string
---@return table[] matches { col = 1-based byte index of "[[" }
local function find_wikilink_matches(line, expected)
    local matches = {}
    local start = 1
    while true do
        local s, e = line:find("%[%[", start)
        if not s then
            break
        end
        local s2 = line:find("%]%]", e + 1)
        if not s2 then
            break
        end
        local inner = line:sub(e + 1, s2 - 1)
        local target = split_link_target(inner)
        if target == expected then
            matches[#matches + 1] = { col = s }
        end
        start = s2 + 2
    end
    return matches
end

--- Find every file that references `target_path` via a `[[ ]]` link. A file at
--- `fpath` references `target_path` when it contains a wikilink whose target
--- (the text before `#` or `|`) equals the extension-less path of
--- `target_path` relative to `fpath`'s directory. Loaded buffers are read
--- in-memory so unsaved edits are reflected.
---@param target_path string Absolute, normalized path.
---@return table[] entries { path, lnum, col, text }
local function find_backlinks(target_path)
    local target_dir = vim.fn.fnamemodify(target_path, ":h")
    local root = state.notes_dir

    local results = {}
    for _, fpath in ipairs(collect_ancestor_files(target_dir, root)) do
        if vim.fs.normalize(fpath) ~= target_path then
            local fdir = vim.fn.fnamemodify(fpath, ":h")
            local rel = relpath_under(fdir, target_path)
            if rel then
                local expected = strip_ext(rel)
                if expected ~= "" then
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
                            for _, m in ipairs(find_wikilink_matches(line, expected)) do
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
            end
        end
    end
    return results
end

--- Open a Telescope picker listing files that reference the current file via
--- `[[ ]]`. Selecting an entry opens the referencing file at the link.
---@param buffer integer
function M._backlinks(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    local target_path = vim.fn.expand("%:p")
    if target_path == "" then
        vim.notify("obelisk: current buffer has no file", vim.log.levels.WARN)
        return
    end
    target_path = vim.fs.normalize(target_path)
    if not in_notes_dir(target_path) then
        vim.notify("obelisk: current file is not inside the notes directory", vim.log.levels.WARN)
        return
    end
    local entries = find_backlinks(target_path)
    if #entries == 0 then
        vim.notify("obelisk: no backlinks to this file", vim.log.levels.INFO)
        return
    end

    local ok, pickers = pcall(require, "telescope.pickers")
    if not ok then
        vim.notify("obelisk: telescope.nvim is required for backlinks", vim.log.levels.ERROR)
        return
    end
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers.new({}, {
        prompt_title = "Obelisk Backlinks",
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
    if vim.b[buffer].obelisk_wikilink_attached then
        return
    end
    local path = vim.api.nvim_buf_get_name(buffer)
    if not in_notes_dir(path) then
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

    if state.keymaps.rename ~= nil and state.keymaps.rename ~= "" then
        vim.keymap.set("n", state.keymaps.rename, function()
            M._rename_current(buffer)
        end, {
            buffer = buffer,
            silent = true,
            desc = "Obelisk: rename current file and update wikilinks",
        })
    end

    if state.keymaps.backlinks ~= nil and state.keymaps.backlinks ~= "" then
        vim.keymap.set("n", state.keymaps.backlinks, function()
            M._backlinks(buffer)
        end, {
            buffer = buffer,
            silent = true,
            desc = "Obelisk: find backlinks to current file",
        })
    end
end

---@param opts? { notes_dir?: string, filetypes?: string[], keymaps?: { open?: string, rename?: string, backlinks?: string, new?: string, find?: string } }
function M.setup(opts)
    opts = opts or {}
    if opts.notes_dir and opts.notes_dir ~= "" then
        state.notes_dir = vim.fs.normalize(vim.fn.expand(opts.notes_dir))
    end
    local filetypes = opts.filetypes or { "markdown" }
    if opts.keymaps ~= nil then
        if opts.keymaps.open ~= nil then
            state.keymaps.open = opts.keymaps.open
        end
        if opts.keymaps.rename ~= nil then
            state.keymaps.rename = opts.keymaps.rename
        end
        if opts.keymaps.backlinks ~= nil then
            state.keymaps.backlinks = opts.keymaps.backlinks
        end
        if opts.keymaps.new ~= nil then
            state.keymaps.new = opts.keymaps.new
        end
        if opts.keymaps.find ~= nil then
            state.keymaps.find = opts.keymaps.find
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

    if state.keymaps.new ~= nil and state.keymaps.new ~= "" then
        vim.keymap.set("n", state.keymaps.new, function()
            M._new_note()
        end, {
            silent = true,
            desc = "Obelisk: create a new note and open it",
        })
    end

    if state.keymaps.find ~= nil and state.keymaps.find ~= "" then
        vim.keymap.set("n", state.keymaps.find, function()
            M._find_note()
        end, {
            silent = true,
            desc = "Obelisk: find and open a note with Telescope",
        })
    end
end

return M
