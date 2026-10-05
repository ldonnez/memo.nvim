local M = {}

--- Name of the environment variable exec_with_passphrase hands the passphrase over
--- in, for a command that knows to read it from there.
M.PASSPHRASE_ENV = "MEMO_NOTE_PASSPHRASE"
local message = require("memo.message")

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

--- Get the user info for a key ID, so we know the local secret keyring holds it
--- and how to call it.
--- @param id string
--- @return { uid: string, name?: string, email?: string }?
local function get_key_info(id)
	if not id or id == "" then
		return nil
	end

	local obj = vim.system({
		"gpg",
		"--batch",
		"--with-colons",
		"--list-secret-keys",
		id .. "!",
	}, { text = true }):wait()

	if obj.code ~= 0 then
		return nil
	end

	for line in (obj.stdout or ""):gmatch("[^\r\n]+") do
		if vim.startswith(line, "uid:") then
			local fields = vim.split(line, ":", { plain = true })

			-- Field 10 = UID string
			local uid = fields[10]

			if uid and uid ~= "" then
				local name, email = uid:match("^(.-)%s*<([^>]+)>$")

				return {
					uid = uid,
					name = name,
					email = email,
				}
			end
		end
	end

	return nil
end

---Cache the passphrase for a specific key (or default)
---@param pass string
---@param id string?
---@return boolean
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
		message.defer_error("GPG: incorrect passphrase")
		return false
	end
	return true
end

--- Prompt user for passphrase
--- Important to be importable for overriding in tests!
---@param label string
---@return string
function M.prompt_passphrase(label)
	return vim.fn.inputsecret("GPG Passphrase for " .. label .. ": ")
end

--- Makes sure gpg-agent holds a key the note can be read with, asking for a
--- passphrase and caching it in gpg-agent when it does not.
--- @param target_path string?
--- @return boolean
function M.unlock_key(target_path)
	local keyids = {}

	if target_path and require("memo.utils").file_exists(target_path) then
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
	local prompt_label = "default"

	for _, id in ipairs(keyids) do
		local info = get_key_info(id)

		if info then
			target_id = id

			if info.name and info.email then
				prompt_label = string.format("%s <%s> (%s)", info.name, info.email, id)
			else
				prompt_label = string.format("%s (%s)", info.uid, id)
			end

			break
		end
	end

	local pass = M.prompt_passphrase(prompt_label)

	if pass == "" then
		return false
	end

	return cache_passphrase(pass, target_id)
end

--- The passphrase a buffer already holds for a note.
--- @param bufnr? integer
--- @return string?
local function cached_passphrase(bufnr)
	if not bufnr then
		return nil
	end

	return vim.b[bufnr].memo_symmetric_passphrase
end

--- Reads the packets of an encrypted note, from one `gpg --list-packets` run:
--- whether it is encrypted with a passphrase instead of a key, and the keys it is
--- encrypted to.
--- @param path string
--- @return { symmetric: boolean, key_ids: string[] }
local function read_packets(path)
	local obj = vim.system(
		{ "gpg", "--batch", "--list-packets", "--pinentry-mode=loopback", "--no-tty", path },
		{ text = true }
	)
		:wait()

	-- The packets go to stdout, the recipient key IDs to stderr.
	local stderr = obj.stderr or ""
	local file = {
		symmetric = ((obj.stdout or "") .. stderr):find("symkey enc packet", 1, true) ~= nil,
		key_ids = {},
	}

	for id in stderr:gmatch("ID ([%w%d]+)") do
		table.insert(file.key_ids, id:upper())
	end

	return file
end

--- Whether a file is encrypted with a passphrase instead of a key. The agent
--- only caches key passphrases, so `memo decrypt` is told where the passphrase
--- is. A buffer that holds one counts as symmetric.
--- @param path string
--- @return boolean
function M.is_symmetric(path)
	return read_packets(path).symmetric
end

--- The passphrase of a symmetrically encrypted file: the one the buffer already
--- holds, or a prompt for it. A new passphrase is kept in the buffer, so writing the
--- note back wil keep it cached and wil not ask for it again.
--- @param path string
--- @param bufnr? integer buffer to keep the passphrase in
--- @return string? nil when the prompt was dismissed
function M.get_symmetric_passphrase(path, bufnr)
	local cached = cached_passphrase(bufnr)

	if cached then
		return cached
	end

	local pass = M.prompt_passphrase(("note %s (symmetric)"):format(vim.fn.fnamemodify(path, ":t")))

	if pass == "" then
		return nil
	end

	if bufnr then
		vim.b[bufnr].memo_symmetric_passphrase = pass

		-- The buffer holds the passphrase for as long as it is open, so drop it as
		-- soon as the buffer goes away instead of leaving it behind.
		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = bufnr,
			once = true,
			callback = function()
				pcall(vim.api.nvim_buf_del_var, bufnr, "memo_symmetric_passphrase")
			end,
		})
	end

	return pass
end

--- Get the Key IDs used for a specific file
--- @param path string
--- @return string[]
function M.get_file_key_ids(path)
	return read_packets(path).key_ids
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

	if not M.unlock_key(target_path) then
		return nil
	end

	if on_exit then
		return vim.system(cmd, opts, on_exit)
	end

	return vim.system(cmd, opts):wait()
end

--- Runs a command with the passphrase.
--- It passes it with PASSPHRASE_ENV, which keeps it out of the process list and off disk.
--- This works for memo and for a plain gpg call.
--- @param cmd string[] The command to run.
--- @param passphrase string
--- @param opts? vim.SystemOpts
--- @param on_exit? fun(obj: vim.SystemCompleted) Optional callback for async execution
--- @return vim.SystemObj
function M.exec_with_passphrase(cmd, passphrase, opts, on_exit)
	local all = vim.tbl_extend("force", opts or {}, { env = { [M.PASSPHRASE_ENV] = passphrase } })

	return vim.system(cmd, all, on_exit)
end

return M
