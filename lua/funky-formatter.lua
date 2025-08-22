local M = {}

local tools = require("funky-formatter-tools")

---@type table<string,fun(string):string[]>
M.config = {}

-- opts maps filetypes to functions that take the path and return a command (string[]) to format that path in-place
---@param opts table<string,fun(string):string[]>
function M.setup(opts)
    M.config = opts or M.config
    vim.fn.sign_define("FunkyFormatSign", { linehl = "Search", text = "󰛂" })
end

---@type integer
local last_format_hrtime = 0

-- NOTE What is the approach, and why is this so complicated?
-- Approach:
-- - save the buffer to its file
-- - format the file (not the buffer) with the formatter
-- - read the file (in lua, not into the buffer)
-- - compute the diff unformatted -> formatted
-- - apply that diff to the in-memory buffer
-- - force-save that buffer again to the file
-- - add temporary highlights at the diff to flash to the user
-- Why is this so complicated?
-- - most formatters don't have good support to format from stdin
--   - the biggest problem is how they discover configuration files, they need a path for that
--   - this also means we only support formatting for buffers that are backed by a writeable file
-- - we cannot just read the formatted file into the buffer because
--   - it messes with the cursor position
--   - it messes with the lsp, clearing all diagnostics, because it is not an incremental change
--   - by applying a diff in-memory, the changes look incremental to the lsp again
-- - we have to force save in the end, otherwise vim thinks the file has been changed on disk and will complain
function M.format(buffer)
    print("󰁫 Getting funky ...")

    -- NOTE some code below cannot deal with a buffer 0, it has to be an actual id
    buffer = buffer or vim.api.nvim_get_current_buf()

    local filetype = vim.bo.filetype
    local formatter = vim.tbl_get(M, "config", filetype)
    if not formatter then
        print(" No funky formatter for filetype '" .. filetype .. "'.")
        return
    end

    local path = assert(vim.api.nvim_buf_get_name(buffer))
    vim.api.nvim_buf_call(buffer, function()
        vim.cmd([[silent update]]) -- saving to disk
    end)
    local unformatted = vim.api.nvim_buf_get_lines(buffer, 0, -1, true)

    local result = vim.system(formatter(path), { text = true }):wait()

    ---@type integer
    local now = vim.uv.hrtime() ---@diagnostic disable-line: undefined-field
    local since_seconds = (now - last_format_hrtime) / 1e9
    last_format_hrtime = now

    if result.code ~= 0 then
        if since_seconds > 1 then
            print(" Formatter was not funky, format again quickly to see details.")
        else
            print(" Formatter was not funky.")
            print(result.stdout .. result.stderr)
        end
        return
    end

    local formatted = vim.fn.readfile(path)

    local unformatted_str = table.concat(unformatted, "\n") .. "\n"
    local formatted_str = table.concat(formatted, "\n") .. "\n"
    local diff = assert(vim.diff(unformatted_str, formatted_str, { result_type = "indices", algorithm = "minimal" }))
    assert(type(diff) == "table")

    if #diff == 0 then
        -- NOTE vim.diff() is not always accurate (see tools.apply_diff() for more details)
        -- it should be true that `#diff==0 -> no changes are needed`
        -- but not always the reverse
        print(" Code was already funky.")
    else
        tools.apply_diff(buffer, diff, formatted)
        tools.flash_signs_for_diff(diff, buffer)
        local before_lines, after_lines = tools.get_diff_statistics(diff)
        print(" " .. before_lines .. " lines of crazy code turned into " .. after_lines .. " lines of funky code.")
    end

    -- double check that indeed the buffer is formatted
    if true then
        local actual = vim.api.nvim_buf_get_lines(buffer, 0, -1, true)
        assert(vim.deep_equal(actual, formatted))
    end

    -- force save to let vim know we are synced
    vim.api.nvim_buf_call(buffer, function()
        vim.cmd([[silent! write!]])
    end)
end

return M
