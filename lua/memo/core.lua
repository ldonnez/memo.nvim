local utils = require("memo.utils")

local M = {}

--- Check if GPG passphrase is cached, and prompt if not
--- @param keyid string?
--- @return boolean
function M.get_gpg_passphrase(keyid)
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
		return true
	end

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

	local cache = vim.system(cache_cmd):wait()
	return cache.code == 0
end

---@param path string
---@return vim.SystemCompleted?
function M.decrypt_to_stdout(path)
	if not M.get_gpg_passphrase() then
		return vim.notify("wrong gpg password", vim.log.levels.ERROR)
	end

	local cmd = { "memo", "decrypt", path }

	local obj = vim.system(cmd):wait()

	if obj.code ~= 0 then
		vim.notify("GPG Stdin Error: " .. (obj.stderr or "Unknown"), vim.log.levels.ERROR)
	end

	return obj
end

---@param lines string[]
---@param target string
---@return vim.SystemCompleted?
function M.encrypt_from_stdin(lines, target)
	if not M.get_gpg_passphrase() then
		vim.notify("wrong gpg password", vim.log.levels.ERROR)
		return
	end

	local input = table.concat(lines, "\n")
	local cmd = { "memo", "encrypt", target }
	local obj = vim.system(cmd, { stdin = input }):wait()

	if obj.code ~= 0 then
		vim.notify("GPG Stdin Error: " .. (obj.stderr or "Unknown"), vim.log.levels.ERROR)
	end

	return obj
end

---@return vim.SystemCompleted?
function M.memo_sync_git()
	local cmd = { "memo", "sync", "git" }

	return vim.system(cmd):wait()
end

return M
