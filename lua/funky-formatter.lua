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

local function apply_diff_to_buffer(diff, after, buffer)
    -- the only reason we need to apply the diff instead of just set the new buffer contents
    -- is because vim dislocates the view and cursors in views on the buffer
    -- (also other signs might be recomputed, not sure if that is a big problem though)
    -- vim.diff is a bit weird with it's output especially around size==0
    -- TODO assuming hunks are forward in source file? we go backwards so indices dont change
    -- but even then :/ hunks could cross over maybe? looks like not, we could at least check, and check in the end the same content?
    -- TODO something is wrong here, simple python file applies wrong, is it that the diff is not as I thought?
    -- test on
    -- [[
    -- import time
    -- time.sleep()
    -- print()
    -- ]] or alternatively also same but with print() way down
    -- oh am I supposed to read that diff forward? is it actually a sequence of mutations?
    -- no I dont think so, or does vim.diff mess it up when there is an early empty line?
    -- TODO ok at this point I'm not sure what is the format
    -- the simple example before seems to insert the space before import if I go backwards
    -- vim.diff is broken or just inconsistent? when the source has size 0, it seems to insert after that, but before makes more sense if you want continuity of the size argument
    for i = #diff, 1, -1 do
        local before_start, before_size, after_start, after_size = unpack(diff[i])
        local after_lines = {}
        for j = after_start, after_start + after_size - 1 do
            table.insert(after_lines, after[j])
        end
        -- TODO is that registered as an edit? how does it interact with undo, and with signs and stuff
        -- does it batch changes before other things are recomputed?
        if before_size == 0 then
            -- weird vim.diff behavior with size==0 in before? or is it nvim_buf_set_lines that is strange?
            -- with size==0 it means insert after, not before, which would make more sense
            vim.api.nvim_buf_set_lines(buffer, before_start - 1 + 1, before_start - 1 + 1, true, after_lines)
        else
            vim.api.nvim_buf_set_lines(buffer, before_start - 1, before_start - 1 + before_size, true, after_lines)
        end
    end
    -- TODO alternative is to get all window cursor positions and adapt based on hunk sizes, then easy full lines set
    -- TODO of course the other sanity check is to see that buffer is not ==after ...
    -- sanity check, speed impact?
    local actual = vim.api.nvim_buf_get_lines(buffer, 0, -1, true)
    if not vim.deep_equal(actual, after) then
        -- TODO that message should be visible to the user, add it to the normal message so it's never missed?
        print("OMFG not the same, forcing it")
        vim.api.nvim_buf_set_lines(buffer, 0, -1, true, after)
    end
    -- TODO ah well it's still happening, either vim.diff is broken, or I dont interpret it right
    -- TODO maybe lets try to go for that lsp diff edit thing instead?
    -- https://github.com/neovim/neovim/issues/14645#issuecomment-893816076 should work
    -- also see if view can be adjusted? together with diff I can probably make a smart positioning?
    -- that should all be way easier then, plus if the diff was per column and not just line, could show even more flashy
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

M.config = { formatters = {} }

function M.setup(opts)
    M.config = opts or M.config
    M.config.formatters = M.config.formatters or {}
    vim.fn.sign_define("FunkyFormatSign", { linehl = "Search", text = "﯀" })
end

function M.format()
    print(" Getting funky ...")
    vim.cmd("redraw")

    local buffer = vim.api.nvim_get_current_buf()
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

    -- print("before:")
    -- print(vim.inspect(before_str))
    -- print("after:")
    -- print(vim.inspect(after_str))
    -- print(vim.inspect(diff))
    -- print(vim.inspect(vim.diff(before_str, after_str)))

    apply_diff_to_buffer(diff, after, buffer)

    flash_signs_for_diff(diff, buffer)

    local before_lines, after_lines = get_diff_statistics(diff)
    print(" " .. before_lines .. " lines of crazy code turned into " .. after_lines .. " lines of funky code.")
end

return M
