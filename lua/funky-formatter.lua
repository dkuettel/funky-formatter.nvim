local tools = require("funky-formatter-tools")

local M = { config = { formatters = {} } }

function M.setup(opts)
    M.config = opts or M.config
    M.config.formatters = M.config.formatters or {}
    vim.fn.sign_define("FunkyFormatSign", { linehl = "Search", text = "󰛂" })
end

function M.format(buffer)
    print("󰁫 Getting funky ...")

    if buffer == nil or buffer == 0 then
        buffer = vim.api.nvim_get_current_buf()
    end
    local filetype = vim.bo.filetype
    local formatter = vim.tbl_get(M, "config", "formatters", filetype)
    if not formatter then
        print(" No funky formatter for filetype '" .. filetype .. "'.")
        return
    end

    local formatted, stderr = tools.pipe_buffer(buffer, formatter.command)
    if stderr ~= nil then
        -- TODO what is the right way to show an error message? echoerr?
        print(" Formatter was not funky: " .. stderr)
        return
    end

    local original_str = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, true), "\n") .. "\n"
    local formatted_str = table.concat(formatted, "\n") .. "\n"
    local diff = assert(vim.diff(original_str, formatted_str, { result_type = "indices", algorithm = "minimal" }))
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
end

return M
