local M = {}

--- What gpg-agent knows, shared by every caller: the recipients of a note and
--- which keys its cache holds. See `memo.gpg_cache`.
local cache = require("memo.gpg_cache").new()

--- File descriptor a passphrase is handed to gpg or `memo` on. 0 is stdin:
--- `memo` reads the first line off it as the passphrase and leaves the rest for
--- gpg, so the passphrase never reaches the environment, the argument list or
--- the disk.
local PASSPHRASE_FD = "0"

local NO_PASSPHRASE = "the passphrase was not given"

local NO_MATCH = "the passphrases do not match"

--- Milliseconds a decrypt may run before gpg is killed.
local DECRYPT_TIMEOUT_MS = 30000

--- Runs a command with the passphrase on the first line of its stdin, followed
--- by optional content (a note being encrypted). This keeps the passphrase out
--- of the environment, the argument list and the disk.
--- @param cmd string[]
--- @param passphrase string
--- @param input? string[] content to write after the passphrase
--- @param opts? vim.SystemOpts
--- @param on_exit? fun(obj: vim.SystemCompleted)
--- @return vim.SystemObj
local function run_with_passphrase(cmd, passphrase, input, opts, on_exit)
	local all = vim.tbl_extend("force", opts or {}, { stdin = true })
	local obj = vim.system(cmd, all, on_exit)

	obj:write(passphrase .. "\n")

	if input and #input > 0 then
		obj:write(table.concat(input, "\n") .. "\n")
	end

	obj:write(nil)

	return obj
end

--- Check if a specific key (or default) is unlocked in gpg-agent.
--- A failed decrypt clears the cache so the next attempt prompts again.
--- @param id string?
--- @return boolean
local function is_key_unlocked(id)
	return cache:key_unlocked(id, function(key)
		local cmd = { "gpg", "--batch", "--pinentry-mode=error", "--no-tty", "--sign" }
		if key then
			table.insert(cmd, 3, "--local-user")
			table.insert(cmd, 4, key)
		end

		return vim.system(cmd):wait().code == 0
	end)
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

--- Cache the passphrase for a specific key (or default).
---@param pass string
---@param id string?
---@return boolean? ok
---@return vim.SystemCompleted? err
local function cache_passphrase(pass, id)
	local cmd = {
		"gpg",
		"--batch",
		"--yes",
		"--pinentry-mode=loopback",
		"--passphrase-fd",
		PASSPHRASE_FD,
		"--sign",
	}

	if id then
		table.insert(cmd, 7, "--local-user")
		table.insert(cmd, 8, id)
	end

	local result = run_with_passphrase(cmd, pass):wait()

	if result.code ~= 0 then
		return nil, result
	end

	cache:mark_key_unlocked(id)

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

--- Drops the passphrase a buffer holds for a symmetric note, so the next
--- attempt prompts again.
--- @param bufnr? integer
local function forget_symmetric_passphrase(bufnr)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.b[bufnr].memo_symmetric_passphrase = nil
	end
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
	return cache:packets(path, function(checked)
		local obj = vim.system(
			{ "gpg", "--batch", "--list-packets", "--pinentry-mode=loopback", "--no-tty", checked },
			{ text = true }
		):wait()

		-- The packets go to stdout, the recipient key IDs to stderr.
		local stderr = obj.stderr or ""
		local packets = {
			symmetric = ((obj.stdout or "") .. stderr):find("symkey enc packet", 1, true) ~= nil,
			key_ids = {},
		}

		for id in stderr:gmatch("ID ([%w%d]+)") do
			table.insert(packets.key_ids, id:upper())
		end

		-- A failed read is handed back but not kept, so the next call tries
		-- again instead of trusting an empty answer.
		return packets, obj.code == 0
	end)
end

--- Whether a note is encrypted with a passphrase instead of a key.
--- @param path string
--- @return boolean
local function is_symmetric(path)
	return read_packets(path).symmetric
end

--- Prompt user for passphrase
--- Important to be importable for overriding in tests!
---@param label string
---@return string
function M.prompt_passphrase(label)
	return vim.fn.inputsecret("GPG Passphrase for " .. label .. ": ")
end

--- Turns a failed signing operation into a useful key-unlock error.
---@param result vim.SystemCompleted
---@return string
local function unlock_failure_reason(result)
	local stderr = result.stderr or ""

	if stderr:find("Bad passphrase", 1, true) then
		return "GPG: incorrect passphrase"
	end

	if stderr:find("No secret key", 1, true) then
		return "GPG: no secret key available"
	end

	local trimmed = vim.trim(stderr)

	return trimmed ~= "" and ("GPG: could not unlock key: " .. trimmed) or "GPG: could not unlock key"
end

--- Makes sure gpg-agent holds a key the note can be read with.
---@param target_path string?
---@return boolean? ok
---@return string? err nil when the prompt was dismissed
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
	elseif is_key_unlocked() then
		return true
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
		return nil
	end

	local ok, result = cache_passphrase(pass, target_id)

	if not ok then
		return nil, result and unlock_failure_reason(result) or "GPG: could not unlock key"
	end

	return true
end

--- Get the Key IDs used for a specific file
--- Important to be importable for overriding in tests!
--- @param path string
--- @return string[]
function M.get_file_key_ids(path)
	-- A copy: the answer is cached, and callers sort and edit what they get.
	return vim.deepcopy(read_packets(path).key_ids)
end

--- Returns how an encrypted note is protected.
---@param path string
---@return "key" | "passphrase"
function M.get_encryption_mode(path)
	return is_symmetric(path) and "passphrase" or "key"
end

--- Drops the cached keys, so the next attempt probes gpg-agent again.
--- @param keyids string[]
local function forget_unlocked_keys(keyids)
	cache:forget_unlocked_keys(keyids)
end

--- Encrypts content into a note.
---@class GpgEncryptOpts
---@field mode? "passphrase"|"key" how to encrypt a new note, "key" when
---omitted; an existing note always keeps the way it was encrypted
---@field confirm? boolean confirm a passphrase when replacing an existing note

---@class GpgEncryptRequest: GpgEncryptOpts
---@field bufnr? integer buffer holding the passphrase of a passphrase note

--- @param path string the note to write to
--- @param input string[] the content to encrypt
--- @param opts? GpgEncryptRequest
--- @return vim.SystemCompleted? result the command result, nil when none ran
--- @return string? fail why no command ran, nil when the prompt was dismissed
function M.encrypt(path, input, opts)
	opts = opts or {}

	-- A note with no content is new, so `mode` decides its encryption; an
	-- existing note keeps the encryption its file already uses. "Has content"
	-- rather than "exists" matches how the plugin treats a zero-byte file as
	-- not yet written.
	local new_passphrase = opts.mode == "passphrase"
		and (opts.confirm or not require("memo.utils").file_has_content(path))
	local passphrase_mode = new_passphrase or is_symmetric(path)

	if not passphrase_mode then
		return vim.system({ "memo", "encrypt", path }, { stdin = input }):wait()
	end

	local passphrase, err = get_symmetric_passphrase(path, opts.bufnr, new_passphrase or opts.confirm)

	if not passphrase then
		-- A dismissed prompt is a cancellation; a mismatch is a failure the
		-- caller reports.
		if err == NO_PASSPHRASE then
			return nil
		end

		return nil, err
	end

	return run_with_passphrase(
		{ "memo", "encrypt", "--symmetric", path, "--passphrase-fd", PASSPHRASE_FD },
		passphrase,
		input
	):wait()
end

--- Decrypts a note with its passphrase or an unlocked key.
--- The callback reports only a decryption process that actually ran.
--- @param path string the note to decrypt
--- @param bufnr? integer buffer that keeps the passphrase of a passphrase note
--- @param opts? vim.SystemOpts
--- @param on_exit? fun(obj: vim.SystemCompleted) called when decryption finishes
--- @return vim.SystemObj? obj the decrypt process, nil when none started
--- @return string? err key-unlock failure; nil when cancelled
function M.decrypt(path, bufnr, opts, on_exit)
	opts = vim.tbl_extend("keep", opts or {}, { timeout = DECRYPT_TIMEOUT_MS })

	local packets = read_packets(path)

	if packets.symmetric then
		local passphrase = get_symmetric_passphrase(path, bufnr, false)

		if not passphrase then
			return nil
		end

		local cmd = { "memo", "decrypt", path, "--passphrase-fd", PASSPHRASE_FD }

		return run_with_passphrase(cmd, passphrase, nil, opts, function(result)
			if result.code ~= 0 then
				vim.schedule(function()
					forget_symmetric_passphrase(bufnr)
				end)
			end

			if on_exit then
				on_exit(result)
			end
		end)
	end

	local unlocked, err = M.unlock_key(path)

	if not unlocked then
		return nil, err
	end

	local keyids = packets.key_ids

	return vim.system({ "memo", "decrypt", path }, opts, function(result)
		-- A cached unlock that no longer holds makes the decrypt fail; drop it.
		if result.code ~= 0 then
			forget_unlocked_keys(keyids)
		end

		if on_exit then
			on_exit(result)
		end
	end)
end

return M
