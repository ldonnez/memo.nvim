local M = {}

local message = require("memo.message")

--- Name of the environment variable the passphrase of a passphrase note is
--- handed to `memo` in, which keeps it out of the process list and off disk.
local PASSPHRASE_ENV = "MEMO_NOTE_PASSPHRASE"

local NO_PASSPHRASE = "the passphrase was not given"

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

--- The passphrase a buffer already holds for a note.
--- @param bufnr? integer
--- @return string?
local function cached_passphrase(bufnr)
	if not bufnr then
		return nil
	end

	return vim.b[bufnr].memo_symmetric_passphrase
end

--- The passphrase of a symmetrically encrypted file: the one the buffer already
--- holds, or a prompt for it. A new passphrase is kept in the buffer, so writing the
--- note back wil keep it cached and wil not ask for it again.
--- @param path string
--- @param bufnr? integer buffer to keep the passphrase in
--- @return string? nil when the prompt was dismissed
local function get_symmetric_passphrase(path, bufnr)
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

--- Whether a note is encrypted with a passphrase instead of a key. The agent
--- only caches key passphrases, so `memo` is told where the passphrase is
--- instead. A buffer that holds one counts as symmetric.
--- @param path string
--- @return boolean
local function is_symmetric(path)
	return read_packets(path).symmetric
end

--- Runs a command for a passphrase note, handing the passphrase to it in the
--- environment.
--- @param cmd string[]
--- @param passphrase string
--- @param opts? vim.SystemOpts
--- @param on_exit? fun(obj: vim.SystemCompleted)
--- @return vim.SystemObj
local function run_with_passphrase(cmd, passphrase, opts, on_exit)
	local all = vim.tbl_extend("force", opts or {}, { env = { [PASSPHRASE_ENV] = passphrase } })

	return vim.system(cmd, all, on_exit)
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
--- Important to be importable for overriding in tests!
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

--- Get the Key IDs used for a specific file
--- Important to be importable for overriding in tests!
--- @param path string
--- @return string[]
function M.get_file_key_ids(path)
	return read_packets(path).key_ids
end

--- Encrypts content into a note, keeping a passphrase note encrypted with a
--- passphrase.
--- @param path string the note to write to
--- @param input string[] the content to encrypt
--- @param bufnr? integer buffer the note was decrypted into, so a passphrase
--- note is written back the way it was encrypted
--- @return vim.SystemCompleted
function M.encrypt(path, input, bufnr)
	if is_symmetric(path) then
		local passphrase = get_symmetric_passphrase(path, bufnr)

		if not passphrase then
			-- A result the caller can still read .code from, for a command that
			-- never ran.
			return { code = 1, signal = 0, stdout = "", stderr = ("Not writing %s: %s"):format(path, NO_PASSPHRASE) }
		end

		-- `memo` owns the encryption, so a passphrase note is byte for byte what
		-- the CLI writes.
		return run_with_passphrase(
			{ "memo", "encrypt", "--symmetric", path, "--passphrase-env", PASSPHRASE_ENV },
			passphrase,
			{ stdin = input }
		):wait()
	end

	return vim.system({ "memo", "encrypt", path }, {
		stdin = input,
	}):wait()
end

--- Decrypts a note with whatever gpg needs to read it: the passphrase of a
--- passphrase note, which `memo` reads from the environment, or an unlocked key
--- for a key note.
--- @param path string the note to decrypt
--- @param bufnr? integer buffer that keeps the passphrase of a passphrase note
--- @param opts? vim.SystemOpts
--- @param on_exit? fun(obj: vim.SystemCompleted)
--- @return vim.SystemObj? nil when a passphrase prompt was dismissed
function M.decrypt(path, bufnr, opts, on_exit)
	if is_symmetric(path) then
		local passphrase = get_symmetric_passphrase(path, bufnr)

		if not passphrase then
			return nil
		end

		return run_with_passphrase(
			{ "memo", "decrypt", path, "--passphrase-env", PASSPHRASE_ENV },
			passphrase,
			opts,
			on_exit
		)
	end

	if not M.unlock_key(path) then
		return nil
	end

	return vim.system({ "memo", "decrypt", path }, opts, on_exit)
end

return M
