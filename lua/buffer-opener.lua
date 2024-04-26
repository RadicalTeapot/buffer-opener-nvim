local M = {}

---Generates a list of daily file paths within a specified week offset from the current date.
---@param root_folder string The base directory from which file paths will be constructed.
---@param week_offset? number The number of weeks before or after the current week to start searching for files (positive for future dates, negative for past dates). Defaults to 0 if not provided.
---@param only_existing? boolean Whether to include only existing files in the result set (true) or all possible paths (false). Defaults to true if not provided.
---@param date_format? string The format of date strings used when generating filenames. Acceptable formats are those supported by Lua `string.format`. Defaults to "%Y-%m-%d" if not provided.
---@return table file_paths A list of daily file paths (strings) for each day within the specified week offset.
M.get_week_daily_file_paths = function(root_folder, week_offset, only_existing, date_format)
    assert(root_folder ~= nil, "Root folder must be specified.")
    week_offset = week_offset or 0
    only_existing = only_existing == nil and true or only_existing
    date_format = date_format or "%Y-%m-%d"

    -- Strip away time hours info (i.e. only keep date info)
    local now_table = os.date("*t", os.time())
    local now = os.time({ year = now_table.year, month = now_table.month, day = now_table.day })

    -- [0-6] (Sunday to Saturday) to [0-6] (Monday to Sunday)
    local weekday = (tonumber(os.date("%w", now)) + 6) % 7

    -- Deltas (in seconds)
    local day_delta = 24 * 60 * 60
    local to_monday_delta = day_delta * weekday
    local week_delta = 7 * day_delta * week_offset

    -- Get paths to daily files
    local file_paths = {}
    for i = 1, 7 do
        local date = os.date(date_format, now + week_delta - to_monday_delta + (i - 1) * day_delta)
        local path = root_folder .. date .. ".md"
        -- Keep only existing files if flag is set
        local keep = (not only_existing) or vim.uv.fs_stat(path)
        if keep then
            file_paths[#file_paths + 1] = vim.fs.normalize(path)
        end
    end

    return file_paths
end

---Distributes a given count into vertical and horizontal splits.
---@param count number The number of elements to distribute. Must be greater than zero.
---@param max_vert_splits number The maximum number of vertical splits allowed. Must be greater than 0.
---@return table splits A table containing the horizontal splits indices for each vertical split configuration.
M.get_distributed_split_indices = function(count, max_vert_splits)
    vim.validate({ count = { count, "number" }, max_vert_splits = { max_vert_splits, "number" } })
    assert(count > 0, "Count must be a positive integer")
    assert(max_vert_splits > 0, "Max number of vertical splits must be a positive integer")

    -- Distribute to splits
    local upper_bound = math.min(max_vert_splits, count)
    local splits = {}
    for i = 1, upper_bound do
        local hsplits = { i }
        for j = i + max_vert_splits, count, max_vert_splits do
            hsplits[#hsplits + 1] = j
        end
        splits[#splits + 1] = hsplits
    end

    return splits
end

---Opens buffers in a new tab in vertical or horizontal splits, splitting them vertically based on the specified maximum number of splits.
---@param buffer_ids integer[] IDs of buffers to open.
---@param max_vert_splits? integer Maximum allowed vertical splits. Defaults to 3 if not provided.
M.open_buffers_in_new_tab_splits = function(buffer_ids, max_vert_splits)
    vim.validate({ buffer_ids = { buffer_ids, "table" } })
    max_vert_splits = max_vert_splits or 3

    if #buffer_ids == 0 then
        return
    end

    local splits = M.get_distributed_split_indices(#buffer_ids, max_vert_splits)

    vim.cmd([[tabnew]])
    for i, hsplits in ipairs(splits) do
        for j, split in ipairs(hsplits) do
            if j == 1 then
                if i == 1 then
                    vim.cmd("buffer " .. buffer_ids[split])
                else
                    vim.cmd("vert bo sb " .. buffer_ids[split])
                end
            else
                vim.cmd("sb " .. buffer_ids[split])
            end
        end
    end
end

---Opens files in a new tab in vertical and horizontal splits, splitting them vertically based on the specified maximum number of splits.
---@param file_paths string[] Paths to the files to be opened.
---@param max_vert_splits? integer Maximum allowed vertical splits. Defaults to 3 if not provided.
M.open_files_in_new_tab_splits = function(file_paths, max_vert_splits)
    vim.validate({ file_paths = { file_paths, "table" } })
    max_vert_splits = max_vert_splits or 3

    if #file_paths == 0 then
        return
    end

    local splits = M.get_distributed_split_indices(#file_paths, max_vert_splits)

    vim.cmd([[tabnew]])
    for i, hsplits in ipairs(splits) do
        for j, split in ipairs(hsplits) do
            local path = vim.fs.normalize(file_paths[split])
            path = string.gsub(path, " ", [[\ ]])
            if j == 1 then
                if i == 1 then
                    vim.cmd("edit " .. path)
                else
                    vim.cmd("vert bo sp " .. path)
                end
            else
                vim.cmd("sp " .. path)
            end
        end
    end
end

---Get list of loaded file buffers
---@return integer[] buffer_ids IDs of the loaded file buffers
M.get_file_buffers = function()
    local bufs = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local loaded = vim.api.nvim_buf_is_loaded(buf)
        local buftype = vim.fn.getbufvar(buf, "&buftype", "nofile")
        if loaded and buftype ~= "nofile" then
            bufs[#bufs + 1] = buf
        end
    end
    return bufs
end

M.default_opts = {
    only_existing = true,
    root_folder = [[01 Periodic notes\daily\]],
    date_format = "%Y-%m-%d",
}

M.setup = function(opts)
    opts = vim.tbl_deep_extend("force", M.default_opts, opts)

    vim.api.nvim_create_user_command("OpenWeekDailies", function(f_opts)
        local file_paths = M.get_week_daily_file_paths(opts.root_folder, f_opts.fargs[1], opts.only_existing, opts.date_format)
        M.open_files_in_new_tab_splits(file_paths)
    end, { nargs = '?', desc = "Open all daily files from given with given offset (0 for current)" })

    vim.api.nvim_create_user_command("OpenFileBuffers", function()
        local bufs = M.get_file_buffers()
        M.open_buffers_in_new_tab_splits(bufs)
    end, { desc = "Open all file buffers" })
end

return M
