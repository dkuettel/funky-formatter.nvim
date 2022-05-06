local tools = require("funky-formatter-tools")

local M = { config = { formatters = {} } }

function M.setup(opts)
    M.config = opts or M.config
    M.config.formatters = M.config.formatters or {}
    vim.fn.sign_define("FunkyFormatSign", { linehl = "Search", text = "﯀" })
end

function M.format(buffer)
    print(" Getting funky ...")
    vim.cmd("redraw")

    if buffer == nil or buffer == 0 then
        buffer = vim.api.nvim_get_current_buf()
    end
    local filetype = vim.api.nvim_buf_get_option(buffer, "filetype")
    local formatter = vim.tbl_get(M, "config", "formatters", filetype)
    if not formatter then
        print(" No funky formatter for filetype '" .. filetype .. "'.")
        return
    end

    local before = vim.api.nvim_buf_get_lines(buffer, 0, -1, true)
    local exit_code, after, error = tools.run_command(formatter.command, before)

    if exit_code ~= 0 then
        print(" Formatting was not funky: '" .. error .. "'")
        return
    end

    local before_str = table.concat(before, "\n")
    local after_str = table.concat(after, "\n")
    local diff = vim.diff(before_str, after_str, { result_type = "indices" })

    if #diff == 0 then
        print(" Code was already funky.")
        return
    end

    local restore = tools.remember_cursors(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, true, after)
    restore(diff)
    -- an alternative to restoring cursor locations is to apply the diff in hunks
    -- I tried it but either the vim.diff result is not fully consistent or I misinterpret it

    tools.flash_signs_for_diff(diff, buffer)

    local before_lines, after_lines = tools.get_diff_statistics(diff)
    print(" " .. before_lines .. " lines of crazy code turned into " .. after_lines .. " lines of funky code.")
end

return M
