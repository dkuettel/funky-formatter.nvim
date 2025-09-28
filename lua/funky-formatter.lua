local M = {}

--a formatter takes a path and formats it in place
---@alias Formatter fun(path:string):vim.SystemCompleted

-- use M.path for arguments in a cmd string[] that are replaced with the file to format
M.path = 0

---@type table<string,Formatter>
M.config = {}

---@param cmd (string|0)[]
---@param path string
---@return vim.SystemCompleted
local function run_with_path(cmd, path)
    local call = vim.iter(cmd)
        :map(function(arg)
            if arg == M.path then
                return path
            end
            return arg
        end)
        :totable()
    return vim.system(call, { text = true }):wait()
end

---@param cmds (string|0)[][]
---@return Formatter
function M.from_cmds(cmds)
    return function(path)
        local result
        for _, cmd in ipairs(cmds) do
            result = run_with_path(cmd, path)
            if result.code ~= 0 then
                return result
            end
        end
        return result
    end
end

---@param cmd (string|0)[]
---@return Formatter
function M.from_cmd(cmd)
    return M.from_cmds({ cmd })
end

---@param cmd (string|0)[]
---@return Formatter
function M.from_stdout(cmd)
    return function(path)
        local result = run_with_path(cmd, path)
        if result.code ~= 0 then
            return result
        end
        local file = assert(io.open(path, "w+"))
        file:write(result.stdout)
        file:close()
        return result
    end
end

---@type table<string,table<string,Formatter>>
M.formatters = {
    python = {
        ruff = M.from_cmds({
            { "ruff", "check", "--fix-only", "--select", "I", "--silent", M.path },
            { "ruff", "format", "--quiet", M.path },
        }),
    },
    lua = {
        stylua = M.from_cmd({ "stylua", "--search-parent-directories", M.path }),
    },
    json = {
        jq = M.from_stdout({ "jq", ".", M.path }),
    },
    yaml = { prettier = M.from_cmd({ "prettier", "--parser", "yaml", M.path }) },
    html = { prettier = M.from_cmd({ "prettier", "--parser", "html", M.path }) },
    rust = { rustfmt = M.from_cmd({ "rustfmt", M.path }) },
    markdown = { pandoc = M.from_stdout({ "pandoc", "--from=markdown", "--to=markdown", M.path }) },
    gitignore = { sort = M.from_stdout({ "env", "-", "LC_ALL=C", "sort", "--unique", M.path }) },
    nix = { nixpkgsfmt = M.from_cmd({ "nixpkgs-fmt", M.path }) },
    toml = { taplo = M.from_cmd({ "taplo", "format", "--option", "indent_string=    ", M.path }) },
}

-- opts maps filetypes to functions that take the path and formatters
---@param opts table<string,Formatter>
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
    local formatter = M.config[filetype]
    if not formatter then
        print(" No funky formatter for filetype '" .. filetype .. "'.")
        return
    end

    local path = assert(vim.api.nvim_buf_get_name(buffer))
    vim.api.nvim_buf_call(buffer, function()
        vim.cmd([[silent update]]) -- saving to disk
    end)
    local unformatted = vim.api.nvim_buf_get_lines(buffer, 0, -1, true)

    local result = formatter(path)

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
        M.apply_diff(buffer, diff, formatted)
        M.flash_signs_for_diff(diff, buffer)
        local before_lines, after_lines = tools.get_diff_statistics(diff)
        print(" " .. before_lines .. " lines of crazy code turned into " .. after_lines .. " lines of funky code.")
    end

    -- double check that indeed the buffer is formatted
    if true then
        local actual = vim.api.nvim_buf_get_lines(buffer, 0, -1, true)
        -- NOTE seems like vim buffers cannot be empty like a file (as in {}), but are always at least {""}
        if #actual == 1 and actual[1] == "" then
            actual = {}
        end
        assert(vim.deep_equal(actual, formatted), "Buffer is not the same as the file after applying the diff. ")
    end

    -- force save to let vim know we are synced
    vim.api.nvim_buf_call(buffer, function()
        vim.cmd([[silent! write!]])
    end)
end

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

---@param buffer integer
---@param diff integer[][]
---@param target string[]
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
