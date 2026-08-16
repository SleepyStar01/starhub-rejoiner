-- StarhubRejoiner: Terminal UI components
-- Beautiful TUI rendering for Termux — colors, tables, menus, banners

local ui = {}

-- ============================================================
-- ANSI Color Codes
-- ============================================================

ui.color = {
    -- Reset
    reset     = "\27[0m",
    bold      = "\27[1m",
    dim       = "\27[2m",
    underline = "\27[4m",

    -- Foreground
    black     = "\27[30m",
    red       = "\27[91m",
    green     = "\27[92m",
    yellow    = "\27[93m",
    blue      = "\27[94m",
    magenta   = "\27[95m",
    cyan      = "\27[96m",
    white     = "\27[97m",
    gray      = "\27[90m",

    -- Background
    bg_black  = "\27[40m",
    bg_red    = "\27[41m",
    bg_green  = "\27[42m",
    bg_yellow = "\27[43m",
    bg_blue   = "\27[44m",
    bg_cyan   = "\27[46m",
    bg_white  = "\27[47m",
}

local C = ui.color

--- Apply color to text
---@param text string
---@param color string ANSI color code
---@return string
function ui.c(text, color)
    return color .. tostring(text) .. C.reset
end

--- Bold text
function ui.bold(text)
    return C.bold .. tostring(text) .. C.reset
end

--- Dim text
function ui.dim(text)
    return C.dim .. tostring(text) .. C.reset
end

-- ============================================================
-- BRAND BANNER
-- ============================================================

local BANNER = {
    C.cyan .. "╔══════════════════════════════════════════════╗" .. C.reset,
    C.cyan .. "║" .. C.reset .. C.bold .. C.cyan .. "          ★ StarhubRejoiner v1.0 ★           " .. C.reset .. C.cyan .. "║" .. C.reset,
    C.cyan .. "╚══════════════════════════════════════════════╝" .. C.reset,
}

--- Print the application banner
function ui.banner()
    for _, line in ipairs(BANNER) do
        print(line)
    end
end

--- Print a section header
---@param title string
function ui.header(title)
    local bar = C.cyan .. string.rep("─", 46) .. C.reset
    print("")
    print(bar)
    print(C.bold .. C.white .. "  " .. title .. C.reset)
    print(bar)
end

--- Print a sub-header
---@param title string
function ui.subheader(title)
    print("")
    print(C.yellow .. C.bold .. "  " .. title .. C.reset)
    print(C.gray .. "  " .. string.rep("·", 40) .. C.reset)
end

-- ============================================================
-- STATUS INDICATORS
-- ============================================================

ui.status = {
    ok      = C.green  .. "●" .. C.reset,
    error   = C.red    .. "●" .. C.reset,
    warning = C.yellow .. "●" .. C.reset,
    info    = C.cyan   .. "●" .. C.reset,
    off     = C.gray   .. "●" .. C.reset,
}

--- Get colored status text
---@param state string "ingame"|"stopped"|"crashed"|"disconnected"|"launching"|"unknown"
---@return string
function ui.state_badge(state)
    local badges = {
        running      = C.green  .. "● running"      .. C.reset,
        background   = C.yellow .. "● background"   .. C.reset,
        stopped      = C.red    .. "● stopped"      .. C.reset,
        crashed      = C.red    .. "● crashed"      .. C.reset,
        disconnected = C.yellow .. "● disconnected" .. C.reset,
        launching    = C.cyan   .. "● launching"    .. C.reset,
        rejoining    = C.cyan   .. "● rejoining"    .. C.reset,
        unknown      = C.gray   .. "● unknown"      .. C.reset,
    }
    return badges[state] or badges.unknown
end

-- ============================================================
-- TABLE RENDERER
-- ============================================================

--- Calculate visible string length (ignoring ANSI escape codes)
---@param s string
---@return number
function ui.visible_len(s)
    -- strip ANSI escape sequences
    local stripped = tostring(s):gsub("\27%[[%d;]*[A-Za-z]", "")
    return #stripped
end

--- Pad string to target width (accounting for ANSI codes)
---@param s string
---@param width number
---@param align string "left"|"right"|"center"
---@return string
function ui.pad(s, width, align)
    s = tostring(s)
    local visible = ui.visible_len(s)
    local needed = width - visible
    if needed <= 0 then return s end

    align = align or "left"
    if align == "right" then
        return string.rep(" ", needed) .. s
    elseif align == "center" then
        local left = math.floor(needed / 2)
        local right = needed - left
        return string.rep(" ", left) .. s .. string.rep(" ", right)
    else
        return s .. string.rep(" ", needed)
    end
end

--- Truncate text to max visible width
---@param text string
---@param max_width number
---@return string
function ui.truncate(text, max_width)
    text = tostring(text)
    if ui.visible_len(text) <= max_width then
        return text
    end
    if max_width <= 3 then
        return text:sub(1, max_width)
    end
    -- For colored strings, just truncate the raw text part
    local stripped = text:gsub("\27%[[%d;]*[A-Za-z]", "")
    return stripped:sub(1, max_width - 2) .. ".."
end

--- Render a bordered table
---@param headers table Array of column header strings
---@param rows table Array of row arrays
---@param options table|nil { col_widths: table, border_color: string }
function ui.table(headers, rows, options)
    options = options or {}
    local border_color = options.border_color or C.cyan
    local bc = border_color

    -- Calculate column widths
    local col_widths = options.col_widths or {}
    for i, h in ipairs(headers) do
        col_widths[i] = col_widths[i] or ui.visible_len(h)
    end
    for _, row in ipairs(rows) do
        for i, cell in ipairs(row) do
            local len = ui.visible_len(cell)
            if len > (col_widths[i] or 0) then
                col_widths[i] = len
            end
        end
    end

    -- Add padding
    for i = 1, #col_widths do
        col_widths[i] = col_widths[i] + 2 -- 1 space padding each side
    end

    -- Build border lines
    local function make_line(left, mid, right, fill)
        local parts = { bc .. left }
        for i, w in ipairs(col_widths) do
            parts[#parts + 1] = string.rep(fill, w)
            if i < #col_widths then
                parts[#parts + 1] = mid
            end
        end
        parts[#parts + 1] = right .. C.reset
        return table.concat(parts)
    end

    local top_line = make_line("┌", "┬", "┐", "─")
    local mid_line = make_line("├", "┼", "┤", "─")
    local bot_line = make_line("└", "┴", "┘", "─")

    local function make_row(cells, is_header)
        local parts = { bc .. "│" .. C.reset }
        for i, cell in ipairs(cells) do
            local text = ui.pad(" " .. ui.truncate(tostring(cell), col_widths[i] - 2) .. " ", col_widths[i])
            if is_header then
                text = C.bold .. C.white .. text .. C.reset
            end
            parts[#parts + 1] = text
            parts[#parts + 1] = bc .. "│" .. C.reset
        end
        return table.concat(parts)
    end

    -- Print table
    print(top_line)
    print(make_row(headers, true))
    print(mid_line)
    if #rows == 0 then
        local empty_width = 0
        for _, w in ipairs(col_widths) do empty_width = empty_width + w end
        empty_width = empty_width + #col_widths - 1 -- separators
        local msg = C.gray .. " (empty)" .. C.reset
        print(bc .. "│" .. C.reset .. ui.pad(msg, empty_width) .. bc .. "│" .. C.reset)
    else
        for _, row in ipairs(rows) do
            print(make_row(row))
        end
    end
    print(bot_line)
end

-- ============================================================
-- MENU SYSTEM
-- ============================================================

--- Print a menu and get user selection
---@param items table Array of { key: string, label: string, color: string|nil }
---@param prompt string|nil Custom prompt text
---@return string|nil Selected key
function ui.menu(items, prompt)
    print("")
    local max_key_len = 0
    for _, item in ipairs(items) do
        if #tostring(item.key) > max_key_len then
            max_key_len = #tostring(item.key)
        end
    end

    for _, item in ipairs(items) do
        local key_str = ui.pad(tostring(item.key), max_key_len, "right")
        local color = item.color or C.white
        local label = item.label or ""
        local prefix = "  "
        if item.separator then
            print("")
        else
            print(prefix .. C.cyan .. "[" .. C.yellow .. key_str .. C.cyan .. "]" .. C.reset .. " " .. color .. label .. C.reset)
        end
    end

    print("")
    local separator = C.cyan .. string.rep("═", 46) .. C.reset
    print(separator)
    io.write(C.cyan .. "? " .. C.white .. (prompt or "Select an option") .. " : " .. C.reset)
    io.flush()
    local input = io.read("*l")
    return input and input:match("^%s*(.-)%s*$") or nil
end

--- Simple yes/no prompt
---@param question string
---@param default boolean|nil Default value (true=yes, false=no)
---@return boolean
function ui.confirm(question, default)
    local hint = default == true and "(Y/n)" or
                 default == false and "(y/N)" or "(y/n)"
    io.write(C.cyan .. "? " .. C.white .. question .. " " .. C.gray .. hint .. " " .. C.reset)
    io.flush()
    local input = (io.read("*l") or ""):lower():match("^%s*(.-)%s*$")
    if input == "" and default ~= nil then
        return default
    end
    return input == "y" or input == "yes"
end

--- Text input prompt
---@param label string
---@param default string|nil Default value
---@return string
function ui.input(label, default)
    local hint = default and (" [" .. tostring(default) .. "]") or ""
    io.write(C.cyan .. "? " .. C.white .. label .. C.gray .. hint .. " : " .. C.reset)
    io.flush()
    local input = (io.read("*l") or ""):match("^%s*(.-)%s*$")
    if input == "" and default then
        return default
    end
    return input
end

--- Number input prompt
---@param label string
---@param default number|nil
---@param min_val number|nil
---@param max_val number|nil
---@return number|nil
function ui.input_number(label, default, min_val, max_val)
    local hint = default and (" [" .. tostring(default) .. "]") or ""
    io.write(C.cyan .. "? " .. C.white .. label .. C.gray .. hint .. " : " .. C.reset)
    io.flush()
    local input = (io.read("*l") or ""):match("^%s*(.-)%s*$")
    if input == "" and default then
        return default
    end
    local num = tonumber(input)
    if not num then return default end
    if min_val and num < min_val then num = min_val end
    if max_val and num > max_val then num = max_val end
    return num
end

-- ============================================================
-- LOG / MESSAGE OUTPUT
-- ============================================================

--- Print an info message
function ui.info(msg)
    print(C.cyan .. "[*]" .. C.reset .. " " .. tostring(msg))
end

--- Print a success message
function ui.success(msg)
    print(C.green .. "[✓]" .. C.reset .. " " .. tostring(msg))
end

--- Print a warning message
function ui.warn(msg)
    print(C.yellow .. "[!]" .. C.reset .. " " .. tostring(msg))
end

--- Print an error message
function ui.error(msg)
    print(C.red .. "[✗]" .. C.reset .. " " .. tostring(msg))
end

--- Print a timestamped log message
---@param msg string
---@param color string|nil
function ui.log(msg, color)
    local time = os.date("%H:%M:%S")
    color = color or C.white
    print(C.gray .. "[" .. time .. "]" .. C.reset .. " " .. color .. tostring(msg) .. C.reset)
end

--- Print a divider line
---@param char string|nil Character to repeat
---@param width number|nil Line width
function ui.divider(char, width)
    char = char or "─"
    width = width or 46
    print(C.cyan .. string.rep(char, width) .. C.reset)
end

--- Print key=value info line
---@param key string
---@param value any
function ui.kv(key, value)
    print("  " .. C.gray .. tostring(key) .. ": " .. C.reset .. C.white .. tostring(value) .. C.reset)
end

--- Spinner/progress animation (call in a loop)
---@param frame number Current frame number
---@return string Spinner character
function ui.spinner(frame)
    local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    return C.cyan .. frames[(frame % #frames) + 1] .. C.reset
end

--- Print a box around text
---@param text string
---@param color string|nil Border color
function ui.box(text, color)
    color = color or C.cyan
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    local max_len = 0
    for _, line in ipairs(lines) do
        local len = ui.visible_len(line)
        if len > max_len then max_len = len end
    end
    max_len = max_len + 2 -- padding

    print(color .. "┌" .. string.rep("─", max_len) .. "┐" .. C.reset)
    for _, line in ipairs(lines) do
        print(color .. "│" .. C.reset .. " " .. ui.pad(line, max_len - 2) .. " " .. color .. "│" .. C.reset)
    end
    print(color .. "└" .. string.rep("─", max_len) .. "┘" .. C.reset)
end

--- Clear current line (for live updates)
function ui.clear_line()
    io.write("\r\27[2K")
    io.flush()
end

--- Write text without newline (for live updates)
function ui.write(text)
    io.write(text)
    io.flush()
end

return ui
