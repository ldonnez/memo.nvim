local utils = require("memo.utils")

local M = {}

--- Check if a specific key (or default) is unlocked in gpg-agent
--- @param id string?
--- @return boolean
local function is_key_unlocked(id)
	local cmd = { "gpg", "--batch", "--pinentry-mode=error", "--no-tty", "--sign" }
	if id then
		table.insert(cmd, 3, "--local-user")
		table.insert(cmd, 4, id)
	end
	return vim.system(cmd):wait().code == 0
end

--- Check if a specific key ID exists in the local secret keyring
--- @param id string
--- @return boolean
local function has_secret_key(id)
	if not id or id == "" then
		return false
	end
	-- We append a ! to the ID in GPG to force it to look for that exact ID
	local obj = vim.system({
		"gpg",
		"--batch",
		"--with-colons",
		"--list-secret-keys",
		id,
	}):wait()
	return obj.code == 0
end

--- Cache the passphrase for a specific key (or default)
--- Check if a specific key (or default) is unlocked in gpg-agent
--- @param pass string
--- @param id string?
--- @return boolean
local function cache_passphrase(pass, id)
	local cmd = {
		"gpg",
		"--batch",
		"--yes",
		"--pinentry-mode=loopback",
		"--passphrase",
		pass,
		"--sign",
	}
	if id then
		table.insert(cmd, 7, "--local-user")
		table.insert(cmd, 8, id)
	end

	local obj = vim.system(cmd):wait()

	if obj.code ~= 0 then
		vim.notify("GPG: Incorrect passphrase", vim.log.levels.ERROR)
		return false
	end
	return true
end

--- @param target_path string?
--- @return boolean
function M.get_gpg_passphrase(target_path)
	local keyids = {}

	if target_path and vim.fn.filereadable(target_path) == 1 then
		keyids = M.get_file_key_ids(target_path)
	end

	if #keyids > 0 then
		for _, id in ipairs(keyids) do
			if is_key_unlocked(id) then
				return true
			end
		end
	else
		-- Fallback: Check if the default local user is unlocked
		if is_key_unlocked() then
			return true
		end
	end

	local target_id = nil
	if #keyids > 0 then
		for _, id in ipairs(keyids) do
			if has_secret_key(id) then
				target_id = id
				break
			end
		end
	end

	local prompt_label = target_id and ("key: " .. target_id) or "default"
	local pass = utils.prompt_passphrase(prompt_label)
	if pass == "" then
		return false
	end

	return cache_passphrase(pass, target_id)
end

--- Get the Key IDs used for a specific file
--- @param path string
--- @return string[]
function M.get_file_key_ids(path)
	local cmd = { "gpg", "--batch", "--list-packets", "--no-tty", path }
	local obj = vim.system(cmd, { text = true }):wait()

	local ids = {}

	-- gpg output for this often goes to stderr
	for id in (obj.stderr or ""):gmatch("ID ([%w%d]+)") do
		table.insert(ids, id:upper())
	end

	return ids
end

--- Executes a GPG-related command after ensuring the session is authenticated.
--- We assume the last argument of a memo/gpg command is the file path.
--- @param cmd string[] The command to run (e.g., {'memo', 'decrypt', 'path/to/file'})
--- @param opts? vim.SystemOpts
--- @param on_exit? fun(obj: vim.SystemCompleted) Optional callback for async execution
--- @overload fun(cmd: string[], opts?: vim.SystemOpts, on_exit: fun(obj: vim.SystemCompleted)): vim.SystemObj?
--- @overload fun(cmd: string[], opts?: vim.SystemOpts): vim.SystemCompleted?
--- @return vim.SystemObj|vim.SystemCompleted|nil
function M.exec_with_gpg_auth(cmd, opts, on_exit)
	local target_path = cmd[#cmd] -- Assume last command param from cmd is file to be encrypted/decrypted

	if not M.get_gpg_passphrase(target_path) then
		return nil
	end

	if on_exit then
		return vim.system(cmd, opts, function(obj)
			if obj.code ~= 0 then
				local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or "Process exited with code " .. obj.code
				vim.schedule(function()
					vim.notify(err, vim.log.levels.ERROR)
				end)
			end
			on_exit(obj)
		end)
	end

	local obj = vim.system(cmd, opts):wait()

	if obj.code ~= 0 then
		local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or "Process exited with code " .. obj.code
		vim.notify(err, vim.log.levels.ERROR)
	end

	return obj
end

return M
