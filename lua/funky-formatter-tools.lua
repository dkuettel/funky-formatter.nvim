local M = {}

function M.run_command(command, stdin)
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

function M.flash_signs_for_diff(diff, buffer)
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

function M.get_diff_statistics(diff)
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

function M.remember_cursors(buffer)
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

return M
