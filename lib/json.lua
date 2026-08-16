-- StarhubRejoiner: Pure Lua JSON encoder/decoder
-- No external dependencies required

local json = {}

-- ============================================================
-- DECODE
-- ============================================================

local function decode_error(str, idx, msg)
    local line = 1
    local col = 1
    for i = 1, idx do
        if str:sub(i, i) == "\n" then
            line = line + 1
            col = 1
        else
            col = col + 1
        end
    end
    error(string.format("[json] decode error at line %d col %d: %s", line, col, msg))
end

local function skip_whitespace(str, idx)
    local _, next_idx = str:find("^[ \n\r\t]*", idx)
    return (next_idx or idx - 1) + 1
end

local function decode_string(str, idx)
    if str:sub(idx, idx) ~= '"' then
        decode_error(str, idx, "expected '\"'")
    end
    idx = idx + 1
    local parts = {}
    local start = idx
    while idx <= #str do
        local c = str:sub(idx, idx)
        if c == '"' then
            parts[#parts + 1] = str:sub(start, idx - 1)
            return table.concat(parts), idx + 1
        elseif c == "\\" then
            parts[#parts + 1] = str:sub(start, idx - 1)
            idx = idx + 1
            local esc = str:sub(idx, idx)
            local escape_map = {
                ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
                ['b'] = '\b', ['f'] = '\f', ['n'] = '\n',
                ['r'] = '\r', ['t'] = '\t',
            }
            if esc == 'u' then
                local hex = str:sub(idx + 1, idx + 4)
                if not hex:match("^%x%x%x%x$") then
                    decode_error(str, idx, "invalid unicode escape")
                end
                local codepoint = tonumber(hex, 16)
                if codepoint < 128 then
                    parts[#parts + 1] = string.char(codepoint)
                elseif codepoint < 2048 then
                    parts[#parts + 1] = string.char(
                        192 + math.floor(codepoint / 64),
                        128 + (codepoint % 64)
                    )
                else
                    parts[#parts + 1] = string.char(
                        224 + math.floor(codepoint / 4096),
                        128 + math.floor((codepoint % 4096) / 64),
                        128 + (codepoint % 64)
                    )
                end
                idx = idx + 5
            elseif escape_map[esc] then
                parts[#parts + 1] = escape_map[esc]
                idx = idx + 1
            else
                decode_error(str, idx, "invalid escape '\\" .. esc .. "'")
            end
            start = idx
        else
            idx = idx + 1
        end
    end
    decode_error(str, start, "unterminated string")
end

local decode_value -- forward declaration

local function decode_array(str, idx)
    idx = idx + 1 -- skip '['
    local result = {}
    idx = skip_whitespace(str, idx)
    if str:sub(idx, idx) == ']' then
        return result, idx + 1
    end
    while true do
        local value
        value, idx = decode_value(str, idx)
        result[#result + 1] = value
        idx = skip_whitespace(str, idx)
        local c = str:sub(idx, idx)
        if c == ']' then
            return result, idx + 1
        elseif c == ',' then
            idx = skip_whitespace(str, idx + 1)
        else
            decode_error(str, idx, "expected ']' or ','")
        end
    end
end

local function decode_object(str, idx)
    idx = idx + 1 -- skip '{'
    local result = {}
    idx = skip_whitespace(str, idx)
    if str:sub(idx, idx) == '}' then
        return result, idx + 1
    end
    while true do
        if str:sub(idx, idx) ~= '"' then
            decode_error(str, idx, "expected string key")
        end
        local key
        key, idx = decode_string(str, idx)
        idx = skip_whitespace(str, idx)
        if str:sub(idx, idx) ~= ':' then
            decode_error(str, idx, "expected ':'")
        end
        idx = skip_whitespace(str, idx + 1)
        local value
        value, idx = decode_value(str, idx)
        result[key] = value
        idx = skip_whitespace(str, idx)
        local c = str:sub(idx, idx)
        if c == '}' then
            return result, idx + 1
        elseif c == ',' then
            idx = skip_whitespace(str, idx + 1)
        else
            decode_error(str, idx, "expected '}' or ','")
        end
    end
end

decode_value = function(str, idx)
    idx = skip_whitespace(str, idx)
    local c = str:sub(idx, idx)
    if c == '"' then
        return decode_string(str, idx)
    elseif c == '{' then
        return decode_object(str, idx)
    elseif c == '[' then
        return decode_array(str, idx)
    elseif c == 't' then
        if str:sub(idx, idx + 3) == "true" then
            return true, idx + 4
        end
        decode_error(str, idx, "invalid value")
    elseif c == 'f' then
        if str:sub(idx, idx + 4) == "false" then
            return false, idx + 5
        end
        decode_error(str, idx, "invalid value")
    elseif c == 'n' then
        if str:sub(idx, idx + 3) == "null" then
            return nil, idx + 4
        end
        decode_error(str, idx, "invalid value")
    elseif c == '-' or (c >= '0' and c <= '9') then
        local num_str = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", idx)
        if not num_str then
            decode_error(str, idx, "invalid number")
        end
        local num = tonumber(num_str)
        if not num then
            decode_error(str, idx, "invalid number: " .. num_str)
        end
        return num, idx + #num_str
    else
        decode_error(str, idx, "unexpected character '" .. c .. "'")
    end
end

--- Decode a JSON string into a Lua value
---@param str string JSON string
---@return any Decoded Lua value
function json.decode(str)
    if type(str) ~= "string" then
        error("[json] decode expects a string, got " .. type(str))
    end
    str = str:gsub("^\239\187\191", "") -- strip BOM
    local value, idx = decode_value(str, 1)
    idx = skip_whitespace(str, idx)
    if idx <= #str then
        decode_error(str, idx, "trailing content after value")
    end
    return value
end

-- ============================================================
-- ENCODE
-- ============================================================

local encode_value -- forward declaration

local function encode_string(val)
    val = tostring(val)
    local escape_map = {
        ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b',
        ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
    }
    val = val:gsub('["\\\b\f\n\r\t]', escape_map)
    -- escape control characters
    val = val:gsub("[\x00-\x1f]", function(c)
        return string.format("\\u%04x", string.byte(c))
    end)
    return '"' .. val .. '"'
end

local function is_array(t)
    if type(t) ~= "table" then return false end
    local max_idx = 0
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
            return false
        end
        if k > max_idx then max_idx = k end
        count = count + 1
    end
    return max_idx == count
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

encode_value = function(val, indent, current_indent)
    local val_type = type(val)
    if val == nil then
        return "null"
    elseif val_type == "boolean" then
        return val and "true" or "false"
    elseif val_type == "number" then
        if val ~= val then return "null" end -- NaN
        if val == math.huge or val == -math.huge then return "null" end
        if val == math.floor(val) and math.abs(val) < 1e15 then
            return string.format("%d", val)
        end
        return tostring(val)
    elseif val_type == "string" then
        return encode_string(val)
    elseif val_type == "table" then
        local next_indent = indent and (current_indent .. indent) or nil
        local separator = indent and ",\n" or ","
        local open_newline = indent and "\n" or ""
        local close_indent = indent and current_indent or ""

        if is_array(val) then
            if #val == 0 then return "[]" end
            local parts = {}
            for i = 1, #val do
                local prefix = next_indent and next_indent or ""
                parts[#parts + 1] = prefix .. encode_value(val[i], indent, next_indent or "")
            end
            return "[" .. open_newline .. table.concat(parts, separator) .. open_newline .. close_indent .. "]"
        else
            local keys = sorted_keys(val)
            if #keys == 0 then return "{}" end
            local parts = {}
            for _, k in ipairs(keys) do
                local prefix = next_indent and next_indent or ""
                local key_str = encode_string(tostring(k))
                local val_str = encode_value(val[k], indent, next_indent or "")
                local kv_sep = indent and ": " or ":"
                parts[#parts + 1] = prefix .. key_str .. kv_sep .. val_str
            end
            return "{" .. open_newline .. table.concat(parts, separator) .. open_newline .. close_indent .. "}"
        end
    else
        error("[json] cannot encode type: " .. val_type)
    end
end

--- Encode a Lua value into a JSON string
---@param val any Lua value to encode
---@param pretty boolean|nil If true, output is pretty-printed with 2-space indent
---@return string JSON string
function json.encode(val, pretty)
    local indent = pretty and "  " or nil
    return encode_value(val, indent, "")
end

--- Read and decode a JSON file
---@param path string File path
---@return any|nil Decoded value, or nil on error
---@return string|nil Error message
function json.read_file(path)
    local f, err = io.open(path, "r")
    if not f then
        return nil, "cannot open file: " .. tostring(err)
    end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then
        return nil, "file is empty"
    end
    local ok, result = pcall(json.decode, content)
    if not ok then
        return nil, tostring(result)
    end
    return result, nil
end

--- Encode and write a value to a JSON file
---@param path string File path
---@param val any Value to encode
---@param pretty boolean|nil Pretty-print
---@return boolean Success
---@return string|nil Error message
function json.write_file(path, val, pretty)
    local ok, encoded = pcall(json.encode, val, pretty)
    if not ok then
        return false, tostring(encoded)
    end
    local f, err = io.open(path, "w")
    if not f then
        return false, "cannot write file: " .. tostring(err)
    end
    f:write(encoded)
    f:write("\n")
    f:close()
    return true, nil
end

return json
