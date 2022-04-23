local M = {}

function M.setup()
    vim.keymap.set("n", "--", M.test, { desc = "funky formatting" })
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
    print(" Getting funky ...")
    vim.cmd("redraw")

    -- local command = { "black", "--quiet", "--target-version=py39", "-" }
    local command = { "some-isort-and-black" }
    local text = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    local exit_code, stdout, stderr = run_command(command, text)

    if exit_code ~= 0 then
        print(" Formatting was not funky.")
        return
    end

    -- using the diff we could probable place the cursor even more reliably?
    -- TODO anyway I think more is needed, all the windows that show this buffer need to be restored
    -- local view = vim.fn.winsaveview()
    -- vim.api.nvim_buf_set_lines(0, 0, -1, true, stdout)
    -- vim.fn.winrestview(view)

    local text_str = table.concat(text, "\n")
    local stdout_str = table.concat(stdout, "\n")
    -- array of {left start, left size, right start, right size}
    local diff = vim.diff(text_str, stdout_str, { result_type = "indices" })

    -- TODO assuming hunks are forward in source file? we go backwards so indices dont change
    -- but even then :/ hunks could cross over maybe? looks like not, we could at least check, and check in the end the same content?
    for i = #diff, 1, -1 do
        local old_start, old_size, new_start, new_size = unpack(diff[i])
        local new_lines = {}
        for j = new_start, new_start + new_size - 1 do
            table.insert(new_lines, stdout[j])
        end
        -- TODO is that registered as an edit? how does it interact with undo, and with signs and stuff
        -- does it batch changes before other things are recomputed?
        vim.api.nvim_buf_set_lines(0, old_start - 1, old_start - 1 + old_size, true, new_lines)
        -- if #new_lines == 0 then
        --     vim.fn.sign_place(1, "FunkyFormatSigns", "FunkyFormatSign", "%", { lnum = old_start, priority = 11000 })
        -- else
        --     for j = old_start, old_start + #new_lines - 1 do
        --         vim.fn.sign_place(1, "FunkyFormatSigns", "FunkyFormatSign", "%", { lnum = j, priority = 11000 })
        --     end
        -- end
    end
    -- TODO alternative is to get all window cursor positions and adapt based on hunk sizes, then easy full lines set

    -- diff doesnt indicate well when lines have only been removed, because then the hunk on the right side is empty
    -- could show empty hunks still as if it was size 1?
    local left_diff_count = 0
    local right_diff_count = 0
    for i = 1, #diff do
        local old_start, old_size, new_start, new_size = unpack(diff[i])
        left_diff_count = left_diff_count + old_size
        right_diff_count = right_diff_count + new_size
        -- TODO indent blank lines plugin uses 10k :)
        if new_size == 0 then
            vim.fn.sign_place(1, "FunkyFormatSigns", "FunkyFormatSign", "%", { lnum = new_start, priority = 11000 })
        else
            for j = new_start, new_start + new_size - 1 do
                vim.fn.sign_place(1, "FunkyFormatSigns", "FunkyFormatSign", "%", { lnum = j, priority = 11000 })
            end
        end
    end

    if #diff == 0 then
        print(" Code was already funky.")
    else
        print(" " .. left_diff_count .. " lines turned into " .. right_diff_count .. " lines of funky code.")
    end

    local buffer = vim.api.nvim_get_current_buf()
    vim.defer_fn(function()
        vim.fn.sign_unplace("FunkyFormatSigns", { buffer = buffer })
    end, 500)
end

return M
