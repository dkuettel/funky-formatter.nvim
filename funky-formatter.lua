local M = {}

function M.setup()
    vim.keymap.set("n", "--", M.test)
    vim.fn.sign_define("FunkyFormatSign", { linehl = "Search", text = "﯀" })
    print("reloaded --")
end

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

function M.test()
    -- local command = { "black", "--quiet", "--target-version=py39", "-" }
    local command = { "some-isort-and-black" }
    local text = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    local exit_code, stdout, stderr = run_command(command, text)

    if exit_code ~= 0 then
        print("Formatting was not funky.")
        return
    end

    vim.api.nvim_buf_set_lines(0, 0, -1, true, stdout)

    local text_str = table.concat(text, "\n")
    local stdout_str = table.concat(stdout, "\n")
    -- array of {left start, left size, right start, right size}
    local diff = vim.diff(text_str, stdout_str, { result_type = "indices" })

    local left_diff_count = 0
    local right_diff_count = 0
    for _, hunk in ipairs(diff) do
        left_diff_count = left_diff_count + hunk[2]
        right_diff_count = right_diff_count + hunk[4]
        for i = 0, hunk[4] - 1 do
            vim.fn.sign_place(1, "FunkyFormatSigns", "FunkyFormatSign", "%", { lnum = hunk[3] + i, priority = 500 })
        end
    end

    print("Funky formatting on " .. left_diff_count .. "->" .. right_diff_count .. " lines.")

    local buffer = vim.api.nvim_get_current_buf()
    vim.defer_fn(function()
        vim.fn.sign_unplace("FunkyFormatSigns", { buffer = buffer })
    end, 350)
end

return M
