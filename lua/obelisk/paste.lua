local M = {}

local state = {
    notes_dir = "",
    assets_dir = "assets",
    filetypes = { "markdown" },
    keymaps = {
        insert_paste = "<C-v>",
        normal_paste = "p",
        normal_paste_above = "P",
    },
}

local original_paste = nil
local paste_overridden = false
local image_handled_this_paste = false
local provider_warned = false

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

--- Absolute path of the assets directory under the notes directory.
---@return string
local function assets_root()
    return vim.fs.normalize(state.notes_dir .. "/" .. state.assets_dir)
end

--- Pick the clipboard provider available on this system.
--- Returns one of: "wayland", "xclip", "pngpaste", "macos", or nil.
---@return string|nil
local function clip_provider()
    if vim.fn.executable("wl-paste") == 1 then
        return "wayland"
    elseif vim.fn.executable("xclip") == 1 then
        return "xclip"
    elseif vim.fn.executable("pngpaste") == 1 then
        return "pngpaste"
    elseif vim.fn.executable("osascript") == 1 then
        return "macos"
    end
    return nil
end

--- Run `cmd` and return its stdout as a string (empty on failure).
---@param cmd string
---@return string
local function capture(cmd)
    local h = io.popen(cmd)
    if not h then
        return ""
    end
    local out = h:read("*a") or ""
    h:close()
    return out
end

--- Return true when the system clipboard currently holds an image.
---@param provider string
---@return boolean
local function clipboard_has_image(provider)
    if provider == "wayland" then
        return capture("wl-paste -l 2>/dev/null"):find("image/", 1, true) ~= nil
    elseif provider == "xclip" then
        return capture("xclip -selection clipboard -t TARGETS -o 2>/dev/null"):find("image/", 1, true) ~= nil
    elseif provider == "pngpaste" or provider == "macos" then
        local info = capture("osascript -e 'clipboard info' 2>/dev/null")
        return info:find("PNGf", 1, true) ~= nil or info:find("TIFF", 1, true) ~= nil
    end
    return false
end

--- Write the image currently in the clipboard to `dest`. Returns true on
--- success (the file exists and is non-empty afterwards).
---@param provider string
---@param dest string
---@return boolean
local function save_clipboard_image(provider, dest)
    local esc = vim.fn.shellescape(dest)
    local cmd
    if provider == "wayland" then
        cmd = "wl-paste -t image/png > " .. esc
    elseif provider == "xclip" then
        cmd = "xclip -selection clipboard -t image/png -o > " .. esc
    elseif provider == "pngpaste" then
        cmd = "pngpaste " .. esc
    elseif provider == "macos" then
        cmd = string.format(
            "osascript -e 'set theFile to (POSIX file %s)' "
                .. "-e 'set fp to open for access theFile with write permission' "
                .. "-e 'try' -e 'set eof of fp to 0' "
                .. "-e 'write (the clipboard as «class PNGf») to fp' "
                .. "-e 'end try' -e 'close access fp'",
            esc)
    end
    if not cmd then
        return false
    end
    os.execute(cmd .. " 2>/dev/null")
    return vim.fn.filereadable(dest) == 1 and vim.fn.getfsize(dest) > 0
end

--- Build a non-existing PNG path under the assets directory, using a
--- timestamp base name and a numeric suffix to avoid collisions.
---@return string
local function unique_image_path()
    local root = assets_root()
    local base = os.date("%Y-%m-%d-%H-%M-%S")
    local path = root .. "/" .. base .. ".png"
    local i = 1
    while vim.fn.filereadable(path) == 1 do
        path = root .. "/" .. base .. "-" .. tostring(i) .. ".png"
        i = i + 1
    end
    return path
end

--- Return `to_path` expressed relative to `from_dir` (e.g. `../assets/x.png`).
---@param from_dir string
---@param to_path string
---@return string
local function relative_to(from_dir, to_path)
    from_dir = vim.fs.normalize(from_dir)
    to_path = vim.fs.normalize(to_path)
    local function split(p)
        local t = {}
        for seg in p:gmatch("[^/]+") do
            t[#t + 1] = seg
        end
        return t
    end
    local a = split(from_dir)
    local b = split(to_path)
    local i = 1
    while i <= #a and i <= #b and a[i] == b[i] do
        i = i + 1
    end
    local parts = {}
    for _ = i, #a do
        parts[#parts + 1] = ".."
    end
    for j = i, #b do
        parts[#parts + 1] = b[j]
    end
    if #parts == 0 then
        return "."
    end
    return table.concat(parts, "/")
end

--- Insert `markdown` into `buffer` according to `mode`:
---   "i" — insert at the cursor (insert-mode paste)
---   "p" — insert as a new line below the cursor (normal-mode paste)
---   "P" — insert as a new line above the cursor (normal-mode paste above)
---@param buffer integer
---@param markdown string
---@param mode string
local function insert_markdown(buffer, markdown, mode)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    local line = vim.fn.line(".")
    if mode == "i" then
        local col = vim.fn.col(".")
        vim.api.nvim_buf_set_text(buffer, line - 1, col - 1, line - 1, col - 1, { markdown })
        vim.fn.cursor(line, col + #markdown)
    elseif mode == "P" then
        vim.api.nvim_buf_set_lines(buffer, line - 1, line - 1, false, { markdown })
        vim.fn.cursor(line, 1)
    else
        vim.api.nvim_buf_set_lines(buffer, line, line, false, { markdown })
        vim.fn.cursor(line + 1, 1)
    end
end

--- Attempt to paste an image from the clipboard into `buffer`. Returns true
--- when an image was found, saved under the assets directory, and a Markdown
--- image link was inserted. Returns false when the clipboard has no image (so
--- the caller can fall back to the original paste behavior).
---@param buffer integer
---@param mode string "i", "p", or "P"
---@return boolean
local function try_paste_image(buffer, mode)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return false
    end
    local path = vim.api.nvim_buf_get_name(buffer)
    if not in_notes_dir(path) then
        return false
    end
    local provider = clip_provider()
    if not provider then
        if not provider_warned then
            provider_warned = true
            vim.notify(
                "obelisk: no clipboard tool found (install wl-clipboard, xclip, or pngpaste)",
                vim.log.levels.WARN)
        end
        return false
    end
    if not clipboard_has_image(provider) then
        return false
    end

    local root = assets_root()
    if vim.fn.isdirectory(root) == 0 then
        vim.fn.mkdir(root, "p")
    end
    local dest = unique_image_path()
    if not save_clipboard_image(provider, dest) then
        vim.notify("obelisk: failed to save image from clipboard", vim.log.levels.ERROR)
        return false
    end

    local rel = relative_to(vim.fn.fnamemodify(path, ":h"), dest)
    insert_markdown(buffer, "![](" .. rel .. ")", mode)
    return true
end

--- Feed `key` to Neovim without re-triggering buffer-local mappings, so the
--- original paste/put behavior runs when the clipboard held no image.
---@param key string
local function feedkeys_original(key)
    vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes(key, true, true, true), "n", false)
end

--- Build the original normal-mode put command, preserving any count and
--- register the user supplied (e.g. `3p`, `"ap`).
---@param key string
---@return string
local function original_put_keys(key)
    local reg = vim.v.register
    local count = vim.v.count
    local keys = '"' .. reg
    if count > 0 then
        keys = keys .. tostring(count)
    end
    return keys .. key
end

---@param buffer integer
function M._insert_paste(buffer)
    if not try_paste_image(buffer, "i") then
        feedkeys_original(state.keymaps.insert_paste)
    end
end

---@param buffer integer
function M._normal_paste(buffer)
    if not try_paste_image(buffer, "p") then
        feedkeys_original(original_put_keys(state.keymaps.normal_paste))
    end
end

---@param buffer integer
function M._normal_paste_above(buffer)
    if not try_paste_image(buffer, "P") then
        feedkeys_original(original_put_keys(state.keymaps.normal_paste_above))
    end
end

--- Intercept `vim.paste` so bracketed-paste / GUI paste / middle-click also
--- get the image treatment when the current buffer is a note. Chains to the
--- previous implementation when the clipboard has no image.
local function override_vim_paste()
    if paste_overridden then
        return
    end
    paste_overridden = true
    original_paste = vim.paste
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.paste = function(lines, phase)
        if phase == 1 or phase == -1 then
            image_handled_this_paste = false
            local buf = vim.api.nvim_get_current_buf()
            if vim.api.nvim_buf_is_valid(buf) then
                local provider = clip_provider()
                if provider
                    and in_notes_dir(vim.api.nvim_buf_get_name(buf))
                    and clipboard_has_image(provider) then
                    if try_paste_image(buf, "i") then
                        image_handled_this_paste = true
                        return true
                    end
                end
            end
        elseif image_handled_this_paste then
            return true
        end
        return original_paste(lines, phase)
    end
end

---@param buffer integer
function M.attach(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    if vim.b[buffer].obelisk_paste_attached then
        return
    end
    local path = vim.api.nvim_buf_get_name(buffer)
    if not in_notes_dir(path) then
        return
    end
    vim.b[buffer].obelisk_paste_attached = true

    local km = state.keymaps
    if km.insert_paste ~= nil and km.insert_paste ~= "" then
        vim.keymap.set("i", km.insert_paste, function()
            M._insert_paste(buffer)
        end, {
            buffer = buffer,
            silent = true,
            desc = "paste image from clipboard (insert)",
        })
    end

    if km.normal_paste ~= nil and km.normal_paste ~= "" then
        vim.keymap.set("n", km.normal_paste, function()
            M._normal_paste(buffer)
        end, {
            buffer = buffer,
            silent = true,
            desc = "paste image from clipboard (normal)",
        })
    end

    if km.normal_paste_above ~= nil and km.normal_paste_above ~= "" then
        vim.keymap.set("n", km.normal_paste_above, function()
            M._normal_paste_above(buffer)
        end, {
            buffer = buffer,
            silent = true,
            desc = "paste image from clipboard above (normal)",
        })
    end
end

---@param opts? { notes_dir?: string, filetypes?: string[], assets_dir?: string, keymaps?: { insert_paste?: string, normal_paste?: string, normal_paste_above?: string } }
function M.setup(opts)
    opts = opts or {}
    if opts.notes_dir and opts.notes_dir ~= "" then
        state.notes_dir = vim.fs.normalize(vim.fn.expand(opts.notes_dir))
    end
    if opts.assets_dir and opts.assets_dir ~= "" then
        state.assets_dir = opts.assets_dir
    end
    local filetypes = opts.filetypes or { "markdown" }
    if opts.keymaps ~= nil then
        for _, k in ipairs({ "insert_paste", "normal_paste", "normal_paste_above" }) do
            if opts.keymaps[k] ~= nil then
                state.keymaps[k] = opts.keymaps[k]
            end
        end
    end

    local ft_set = {}
    for _, ft in ipairs(filetypes) do
        ft_set[ft] = true
    end

    local group = vim.api.nvim_create_augroup("obelisk.paste", { clear = true })
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

    override_vim_paste()
end

return M
