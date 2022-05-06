local M = {}

local function run_command(command, stdin)
    local stdout, stderr
    local opts = {
        stdout_buffered = true,
        on_stdout = function(_, data, _)
            data[#data] = nil
            stdout = data
        end,
        stderr_buffered = true,
        on_stderr = function(_, data, _)
            data[#data] = nil
            stderr = data
        end,
    }
    local job = vim.fn.jobstart(command, opts)
    vim.fn.chansend(job, stdin)
    vim.fn.chanclose(job, "stdin")
    -- TODO could use timeout (2nd argument) to show a ... to the user to have more feedback?
    local exit_code = vim.fn.jobwait({ job })[1]
    return exit_code, stdout, stderr
end

local function flash_signs_for_diff(diff, buffer)
    -- TODO indent blank lines plugin uses 10k :)
    local priority = 11000

    for i = 1, #diff do
        local _, _, after_start, after_size = unpack(diff[i])
        if after_size == 0 then
            vim.fn.sign_place(
                1,
                "FunkyFormatSigns",
                "FunkyFormatSign",
                buffer,
                { lnum = math.max(1, after_start), priority = priority }
            )
        else
            for j = after_start, after_start + after_size - 1 do
                vim.fn.sign_place(1, "FunkyFormatSigns", "FunkyFormatSign", buffer, { lnum = j, priority = priority })
            end
        end
    end

    vim.defer_fn(function()
        vim.fn.sign_unplace("FunkyFormatSigns", { buffer = buffer })
    end, 500)
end

local function get_diff_statistics(diff)
    local before = 0
    local after = 0
    for i = 1, #diff do
        before = before + diff[i][2]
        after = after + diff[i][4]
    end
    return before, after
end

local function adjust_cursor(cursor, buffer, diff)
    local row, col = unpack(cursor)
    for _, hunk in ipairs(diff) do
        local before_start, before_size, _, after_size = unpack(hunk)
        if before_start + before_size - 1 < row then
            row = row - before_size + after_size
        end
    end
    local line_count = vim.api.nvim_buf_line_count(buffer)
    row = math.min(math.max(1, row), line_count)
    local col_count = #vim.api.nvim_buf_get_lines(buffer, row - 1, row, true)
    col = math.min(math.max(0, col), col_count - 1)
    return { row, col }
end

local function remember_cursors(buffer)
    local windows = vim.fn.win_findbuf(buffer)
    local locations = {}
    for _, window in ipairs(windows) do
        locations[window] = vim.api.nvim_win_get_cursor(window)
    end
    local function restore(diff)
        for window, cursor in pairs(locations) do
            cursor = adjust_cursor(cursor, buffer, diff)
            vim.api.nvim_win_set_cursor(window, cursor)
        end
    end
    return restore
end

M.config = { formatters = {} }

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
    local exit_code, after, error = run_command(formatter.command, before)

    if exit_code ~= 0 then
        print(" Formatting was not funky: '" .. error .. "'")
        return
    end

    local before_str = table.concat(before, "\n")
    local after_str = table.concat(after, "\n")
    local diff = vim.diff(before_str, after_str, { result_type = "indices" })
    -- diff is array of hunk arrays {start_old, size_old, start_new, size_new}
    -- indices are 1-based

    if #diff == 0 then
        print(" Code was already funky.")
        return
    end

    local restore = remember_cursors(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, true, after)
    restore(diff)
    -- an alternative to restoring cursor locations is to apply the diff in hunks
    -- I tried it but either the vim.diff result is not fully consistent or I misinterpret it

    flash_signs_for_diff(diff, buffer)

    local before_lines, after_lines = get_diff_statistics(diff)
    print(" " .. before_lines .. " lines of crazy code turned into " .. after_lines .. " lines of funky code.")
end

return M
