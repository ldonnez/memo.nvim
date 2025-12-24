local utils = require("memo.utils")

local M = {}

--- Check if GPG passphrase is cached, and prompt if not
--- @param keyid string?
--- @return boolean
function M.get_gpg_passphrase(keyid)
	-- 1. Check if cached
	local check_cmd = {
		"gpg",
		"--batch",
		"--pinentry-mode=error",
		"--no-tty",
		"--sign",
	}
	if keyid then
		table.insert(check_cmd, 3, "--local-user")
		table.insert(check_cmd, 4, keyid)
	end

	local check = vim.system(check_cmd, { stdin = "test", text = true }):wait()
	if check.code == 0 then
		return true -- already cached
	end

	-- 2. Ask for passphrase
	local pass = utils.prompt_passphrase()

	if pass == "" then
		vim.notify("GPG operation cancelled", vim.log.levels.WARN)
		return false
	end

	local cache_cmd = {
		"gpg",
		"--batch",
		"--yes",
		"--no-tty",
		"--pinentry-mode=loopback",
		"--passphrase",
		pass,
		"--sign",
	}
	if keyid then
		table.insert(cache_cmd, 7, "--local-user")
		table.insert(cache_cmd, 8, keyid)
	end

	local cache = vim.system(cache_cmd, { stdin = "test", text = true }):wait()
	return cache.code == 0
end

---@param tmpfile string
---@param target string
---@return vim.SystemCompleted?
function M.encrypt_file(tmpfile, target)
	if not M.get_gpg_passphrase() then
		return vim.notify("wrong gpg password", vim.log.levels.ERROR)
	end

	local cmd = { "memo", "encrypt", tmpfile, target }

	return vim.system(cmd):wait()
end

---@param path string
---@return vim.SystemCompleted?
function M.decrypt_file(path)
	if not M.get_gpg_passphrase() then
		return vim.notify("wrong gpg password", vim.log.levels.ERROR)
	end

	local cmd = { "memo", "decrypt", path }

	local opts = { text = true, stdin = "test" }
	return vim.system(cmd, opts):wait()
end

---@return vim.SystemCompleted?
function M.memo_sync_git()
	local cmd = { "memo", "sync", "git" }

	return vim.system(cmd):wait()
end

---@param bufnr integer
---@param original_file string
---@param lines string[]
---@param meta_key string
function M.load_decrypted(bufnr, original_file, lines, meta_key)
	local base = utils.base_name(original_file)

	vim.b[bufnr][meta_key] = original_file

	vim.bo[bufnr].buftype = "acwrite" -- prevents default write
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].undofile = false
	vim.bo[bufnr].bin = false

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_buf_set_name(bufnr, base)
	vim.cmd("keepalt file " .. vim.fn.fnameescape(base))

	-- filetype detection
	local ft = vim.filetype.match({ filename = base })
	if ft then
		vim.bo.filetype = ft
	end

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = bufnr,
		callback = function()
			M.encrypt_from_buffer(original_file)
		end,
	})

	vim.cmd("doautocmd BufReadPost")
	vim.api.nvim_set_option_value("modified", false, { buf = bufnr })

	vim.notify("Decrypted and loaded: " .. base, vim.log.levels.INFO)
end

---@param original_gpg string
function M.encrypt_from_buffer(original_gpg)
	local tmp = vim.fn.tempname() .. ".txt"
	vim.cmd("silent! write! " .. tmp)

	local ok = M.encrypt_file(tmp, original_gpg)

	vim.fn.delete(tmp)

	if ok then
		vim.bo.modified = false
		vim.notify("Encrypted -> " .. original_gpg, vim.log.levels.INFO)
	else
		vim.notify("GPG encryption failed", vim.log.levels.ERROR)
	end
end

return M
