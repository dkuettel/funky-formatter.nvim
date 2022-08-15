local M = {}

function M.flash_signs_for_diff(diff, buffer)
    -- TODO indent blank lines plugin uses 10k :)
    local priority = 11000

    for i = 1, #diff do
        local target_at = diff[i][3]
        local target_length = diff[i][4]
        if target_length == 0 then
            vim.fn.sign_place(
                1,
                "FunkyFormatSigns",
                -- TODO use a minus sign to make it clear it was a removal
                "FunkyFormatSign",
                buffer,
                { lnum = math.min(math.max(1, target_at), vim.api.nvim_buf_line_count(buffer)), priority = priority }
            )
        else
            for j = target_at, target_at + target_length - 1 do
                -- TODO use a "change" sign to indicate just change
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

local function array_slice(array, from, count)
    -- return subarray starting at from with count elements
    local slice = {}
    for i = 1, count do
        slice[i] = array[from - 1 + i]
    end
    return slice
end

function M.apply_diff(buffer, diff, target)
    -- apply to buffer the diff to turn it into target

    -- the problem with vim.diff(source, target, ...)'s output:
    --   broken in the sense that it doesnt give a patch that fully converts from source to target
    --   insert-hunks have an uninuitive off-by-one index compared to change- and delete-hunks (easy to work around)
    --   source/target files with incomplete last lines dont diff correctly on that last line (patch is incomplete)
    --   none of the ignore_* options to vim.diff() change that behavior
    --   it takes a bit of tinkering to work around this

    -- we apply hunks backwards so that hunk indices dont change
    -- we check that indeed the hunk indices decrease strictly monotonically
    local no_changes_before = nil
    for i = #diff, 1, -1 do
        local source_at = diff[i][1]
        local source_length = diff[i][2]
        local target_at = diff[i][3]
        local target_length = diff[i][4]
        if source_length == 0 then
            -- insert hunk
            -- NOTE source_at is unintuitively off by one (vim.diff() quirk?)
            assert(no_changes_before == nil or source_at < no_changes_before)
            local target_lines = array_slice(target, target_at, target_length)
            vim.api.nvim_buf_set_lines(buffer, source_at, source_at, true, target_lines)
            no_changes_before = source_at
        elseif target_length == 0 then
            -- delete hunk
            assert(no_changes_before == nil or (source_at - 1) < no_changes_before)
            vim.api.nvim_buf_set_lines(buffer, source_at - 1, source_at - 1 + source_length, true, {})
            no_changes_before = source_at - 1
        else
            -- replacement hunk
            assert(no_changes_before == nil or (source_at - 1) < no_changes_before)
            local target_lines = array_slice(target, target_at, target_length)
            vim.api.nvim_buf_set_lines(buffer, source_at - 1, source_at - 1 + source_length, true, target_lines)
            no_changes_before = source_at - 1
        end
    end

    -- workaround for vim.diff()'s buggy handling of incomplete last lines
    if #target == 0 or vim.api.nvim_buf_line_count(buffer) == 0 then
        vim.api.nvim_buf_set_lines(buffer, 0, -1, true, target)
    else
        local actual_last_line = vim.api.nvim_buf_get_lines(buffer, -2, -1, true)[1]
        local target_last_line = target[#target]
        if actual_last_line == "" and target_last_line ~= "" then
            vim.api.nvim_buf_set_lines(buffer, -2, -1, true, {})
        elseif actual_last_line ~= "" and target_last_line == "" then
            vim.api.nvim_buf_set_lines(buffer, -1, -1, true, { "" })
        end
    end
end

return M
