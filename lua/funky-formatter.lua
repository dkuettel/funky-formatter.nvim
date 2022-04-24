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
    local exit_code = vim.fn.jobwait({ job })[1]
    return exit_code, stdout, stderr
end

local function apply_diff_to_buffer(diff, after, buffer)
    -- TODO assuming hunks are forward in source file? we go backwards so indices dont change
    -- but even then :/ hunks could cross over maybe? looks like not, we could at least check, and check in the end the same content?
    for i = #diff, 1, -1 do
        local before_start, before_size, after_start, after_size = unpack(diff[i])
        local after_lines = {}
        for j = after_start, after_start + after_size - 1 do
            table.insert(after_lines, after[j])
        end
        -- TODO is that registered as an edit? how does it interact with undo, and with signs and stuff
        -- does it batch changes before other things are recomputed?
        vim.api.nvim_buf_set_lines(buffer, before_start - 1, before_start - 1 + before_size, true, after_lines)
    end
    -- TODO alternative is to get all window cursor positions and adapt based on hunk sizes, then easy full lines set
end

local function place_signs_for_diff(diff, buffer)
    -- TODO indent blank lines plugin uses 10k :)
    local priority = 11000
    for i = 1, #diff do
        local _, _, after_start, after_size = unpack(diff[i])
        if after_size == 0 then
            vim.fn.sign_place(
                1,
                "FunkyFormatSigns",
                "FunkyFormatSign",
                "%",
                { lnum = after_start, priority = priority }
            )
        else
            for j = after_start, after_start + after_size - 1 do
                vim.fn.sign_place(1, "FunkyFormatSigns", "FunkyFormatSign", buffer, { lnum = j, priority = priority })
            end
        end
    end
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

M.config = {
    formatters = {
        python = { command = { "some-isort-and-black" } },
    },
}

function M.setup()
    vim.fn.sign_define("FunkyFormatSign", { linehl = "Search", text = "﯀" })
end

function M.format()
    print(" Getting funky ...")
    vim.cmd("redraw")

    local buffer = vim.api.nvim_get_current_buffer()
    local filetype = vim.api.nvim_buf_get_option(buffer, "filetype")
    local formatter = M.config.formatters[filetype]
    if not formatter then
        print(" No funky formatter for filetype '" .. filetype .. "'.")
        return
    end

    local before = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    -- TODO can we use :%!command even easier? does it handle jumping cursors? still make diff before and after for funkiness
    -- seems like that one does lose the cursor position according to people, maybe old, try to be sure
    local exit_code, after, error = run_command(formatter.command, before)

    if exit_code ~= 0 then
        print(" Formatting was not funky: '" .. error .. "'")
        return
    end

    -- TODO still not sure if this easier code could be made to work
    -- local view = vim.fn.winsaveview()
    -- vim.api.nvim_buf_set_lines(0, 0, -1, true, stdout)
    -- vim.fn.winrestview(view)

    local before_str = table.concat(before, "\n")
    local after_str = table.concat(after, "\n")
    local diff = vim.diff(before_str, after_str, { result_type = "indices" })

    if #diff == 0 then
        print(" Code was already funky.")
        return
    end

    apply_diff_to_buffer(diff, after, buffer)

    place_signs_for_diff(diff, buffer)
    vim.defer_fn(function()
        vim.fn.sign_unplace("FunkyFormatSigns", { buffer = buffer })
    end, 500)

    local before_lines, after_lines = get_diff_statistics(diff)
    print(" " .. before_lines .. " lines of crazy code turned into " .. after_lines .. " lines of funky code.")
end

return M
