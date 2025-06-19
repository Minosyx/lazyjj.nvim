-- File: lua/lazyjj/init.lua

local M = {}

---Finds the root of a jujutsu repository by searching upwards from a given path.
---@param start_path string|nil The path to start searching from.
---@return string The path to the repository root, or nil if not found.
local function find_jj_root(start_path)
	-- Use vim.loop (libuv) for filesystem operations
	local uv = vim.loop

	-- If no start_path is provided, default to the directory of the current buffer
	local path = start_path or vim.api.nvim_buf_get_name(0)
	if not path or path == "" then
		return vim.fn.getcwd() -- Fallback for empty/unnamed buffers
	end

	-- Use the directory containing the file
	path = vim.fn.fnamemodify(path, ":h")

	while path and path ~= "/" and path ~= "" do
		-- Check if the .jj directory exists in the current path
		local jj_dir = path .. "/.jj"
		-- Use uv.fs_stat to check for directory existence without blocking
		local stat = uv.fs_stat(jj_dir)
		if stat and stat.type == "directory" then
			return path -- Found the root
		end

		-- Move to the parent directory
		local parent = vim.fn.fnamemodify(path, ":h")
		if parent == path then -- Reached the top (e.g., '/')
			break
		end
		path = parent
	end

	-- If no .jj directory was found, return the fallback cwd
	return vim.fn.getcwd()
end

local function open_floating_window()
	-- Get plenary's float window module which handles window creation
	local plenary = require("plenary.window.float")

	-- Create centered floating window
	local win = plenary.percentage_range_window(M.config.col_range, M.config.row_range, {
		border = {
			"╭",
			"─",
			"╮",
			"│",
			"│",
			"╰",
			"─",
			"╯",
		},
	})

	-- Set buffer filetype for syntax highlighting
	vim.bo[win.bufnr].filetype = "lazyjj"

	-- Ensure window is completely opaque
	vim.wo[win.win_id].winblend = 0

	-- Hide buffer when window closes rather than delete it
	vim.cmd("setlocal bufhidden=hide")

	-- Automatically hide window when focus is lost
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = win.bufnr,
		callback = function()
			vim.cmd("hide")
		end,
		once = true,
	})

	-- Return window and buffer handles for further manipulation if needed
	return win.win_id, win.bufnr
end

function M.setup(opts)
	-- Store user config for later use
	M.config = vim.tbl_deep_extend("force", {
		-- Default configuration options can go here
		mapping = "<leader>jj", -- Default keymapping
		-- Default size for plenary
		col_range = 0.9,
		row_range = 0.8,
	}, opts or {})

	-- Create user command
	vim.api.nvim_create_user_command("LazyJJ", M.open, {})

	-- Set up keymapping if provided
	if M.config.mapping then
		vim.keymap.set("n", M.config.mapping, M.open, {
			noremap = true,
			silent = true,
			desc = "LazyJJ", -- This will work with WhichKey and similar plugins
		})
	end
end

function M.open()
	-- Check if lazyjj is available
	local cmd = "lazyjj"
	if vim.fn.executable(cmd) ~= 1 then
		vim.notify(
			"lazyjj executable not found. Please install lazyjj and ensure it's in your PATH.",
			vim.log.levels.ERROR
		)
		return
	end

	local prev_win = vim.api.nvim_get_current_win()

	-- Get jj project dir
	local cwd = find_jj_root()

	-- Create floating window
	open_floating_window()

	-- Execute lazyjj in the floating window
	vim.fn.jobstart(cmd, {
		term = true,
		cwd = cwd,
		-- Return to previous window on exit
		on_exit = function()
			if vim.api.nvim_win_is_valid(prev_win) then
				vim.api.nvim_set_current_win(prev_win)
			end
		end,
		-- Handle potential errors
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line:match("^Error:.*") then
					vim.notify("lazyjj error: " .. line, vim.log.levels.ERROR)
				end
			end
		end,
	})

	-- Enter insert mode to allow immediate interaction
	vim.cmd("startinsert")
end

return M
