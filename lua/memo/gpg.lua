local M = {}

local message = require("memo.message")

--- Variable the passphrase of a passphrase note is handed to `memo` in.
local PASSPHRASE_ENV = "MEMO_NOTE_PASSPHRASE"

local NO_PASSPHRASE = "the passphrase was not given"

local NO_MATCH = "the passphrases do not match"

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

--- Get the user info for a key ID.
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

--- The passphrase a buffer holds for a note.
--- @param bufnr? integer
--- @return string?
local function cached_passphrase(bufnr)
	if not bufnr then
		return nil
	end

	return vim.b[bufnr].memo_symmetric_passphrase
end

--- The passphrase of a passphrase note: the one the buffer holds, or a prompt
--- for it.
--- @param path string
--- @param bufnr? integer buffer to keep the passphrase in
--- @param confirm boolean prompt for the passphrase twice
--- @return string? pass nil when there is none
--- @return string? fail why there is none
local function get_symmetric_passphrase(path, bufnr, confirm)
	local cached = cached_passphrase(bufnr)

	if cached then
		return cached
	end

	local name = vim.fn.fnamemodify(path, ":t")
	local pass = M.prompt_passphrase(("note %s (symmetric)"):format(name))

	if pass == "" then
		return nil, NO_PASSPHRASE
	end

	if confirm then
		local again = M.prompt_passphrase(("note %s (symmetric, confirmation)"):format(name))

		if again ~= pass then
			return nil, NO_MATCH
		end
	end

	if bufnr then
		vim.b[bufnr].memo_symmetric_passphrase = pass

		-- Dropped together with the buffer.
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

--- Reads the packets of an encrypted note: whether it is symmetric and which
--- keys it is encrypted to.
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

--- Whether a note is encrypted with a passphrase instead of a key.
--- @param path string
--- @return boolean
local function is_symmetric(path)
	return read_packets(path).symmetric
end

--- Runs a command with the passphrase in the environment.
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

--- Makes sure gpg-agent holds a key the note can be read with.
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

--- Encrypts content into a note.
---@class GpgEncryptOpts
---@field mode? "passphrase"|"key" how to encrypt a new note, "key" when
---omitted; an existing note always keeps the way it was encrypted

---@class GpgEncryptRequest: GpgEncryptOpts
---@field bufnr? integer buffer holding the passphrase of a passphrase note

--- @param path string the note to write to
--- @param input string[] the content to encrypt
--- @param opts? GpgEncryptRequest
--- @return vim.SystemCompleted
function M.encrypt(path, input, opts)
	opts = opts or {}

	local exists = require("memo.utils").file_exists(path)

	-- A note that does not exist's encryption is determined bymode; an existing one keeps
	-- the way its file is encrypted.
	local new_passphrase = opts.mode == "passphrase" and not exists
	local passphrase_mode = new_passphrase or is_symmetric(path)

	if not passphrase_mode then
		return vim.system({ "memo", "encrypt", path }, { stdin = input }):wait()
	end

	local passphrase, fail = get_symmetric_passphrase(path, opts.bufnr, new_passphrase)

	if not passphrase then
		-- A result for a command that never ran.
		return { code = 1, signal = 0, stdout = "", stderr = ("Not writing %s: %s"):format(path, fail) }
	end

	return run_with_passphrase(
		{ "memo", "encrypt", "--symmetric", path, "--passphrase-env", PASSPHRASE_ENV },
		passphrase,
		{ stdin = input }
	):wait()
end

--- Decrypts a note with its passphrase or an unlocked key.
--- @param path string the note to decrypt
--- @param bufnr? integer buffer that keeps the passphrase of a passphrase note
--- @param opts? vim.SystemOpts
--- @param on_exit? fun(obj: vim.SystemCompleted)
--- @return vim.SystemObj? nil when a passphrase prompt was dismissed
function M.decrypt(path, bufnr, opts, on_exit)
	if is_symmetric(path) then
		local passphrase = get_symmetric_passphrase(path, bufnr, false)

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
