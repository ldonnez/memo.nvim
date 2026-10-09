local M = {}

function M.write_file(path, content)
	local f = io.open(path, "w")

	if f == nil then
		return
	end

	f:write(content)
	f:close()
end

--- @param path string
--- @param content string
--- @param opts vim.SystemOpts?
--- @return vim.SystemCompleted
function M.encrypt_file(path, content, opts)
	local cmd = {
		"memo",
		"encrypt",
		path,
	}

	return vim.system(cmd, vim.tbl_deep_extend("force", { stdin = content }, opts or {})):wait()
end

--- Encrypts with a passphrase instead of a key, the way a symmetric note on
--- disk is.
--- @param path string
--- @param content string
--- @param passphrase string
--- @return vim.SystemCompleted
function M.encrypt_symmetric_file(path, content, passphrase)
	local cmd = {
		"gpg",
		"--batch",
		"--quiet",
		"--yes",
		"--armor",
		"-z",
		"0",
		"--compress-algo",
		"none",
		"--cipher-algo",
		"AES256",
		"--pinentry-mode=loopback",
		"--passphrase",
		passphrase,
		"--symmetric",
		"-o",
		path,
	}

	return vim.system(cmd, { stdin = content }):wait()
end

--- Whether a file on disk is encrypted with a passphrase rather than a key.
--- @param path string
--- @return boolean
function M.is_symmetric_file(path)
	local cmd = { "gpg", "--list-packets", "--batch", "--no-tty", path }
	local result = vim.system(cmd):wait()
	local packets = (result.stdout or "") .. (result.stderr or "")

	return packets:find("symkey enc packet", 1, true) ~= nil
end

--- Decrypts a symmetric file with a passphrase.
--- @param path string
--- @param passphrase string
--- @return vim.SystemCompleted
function M.decrypt_symmetric_file(path, passphrase)
	local cmd = {
		"gpg",
		"--batch",
		"--quiet",
		"--yes",
		"--pinentry-mode=loopback",
		"--passphrase",
		passphrase,
		"--decrypt",
		path,
	}

	return vim.system(cmd):wait()
end

--- @param path string
--- @return vim.SystemCompleted
function M.decrypt_file(path)
	local cmd = {
		"memo",
		"decrypt",
		path,
	}

	return vim.system(cmd):wait()
end

local function determine_gen_key_string(keyid, passphrase)
	local lines = {}

	if not passphrase or passphrase == "" then
		table.insert(lines, "%no-protection")
	end

	table.insert(lines, "Key-Type: RSA")
	table.insert(lines, "Key-Length: 3072")
	table.insert(lines, "Name-Real: Mock Test Key")
	table.insert(lines, "Name-Email: " .. keyid)
	table.insert(lines, "Expire-Date: 0")

	if passphrase and passphrase ~= "" then
		table.insert(lines, "Passphrase: " .. passphrase)
	end

	table.insert(lines, "%commit")

	return table.concat(lines, "\n")
end

function M.create_gpg_key(keyid, passphrase)
	local existing = vim.system({ "gpg", "--with-colons", "--list-secret-keys", keyid }, { text = true }):wait()

	if existing.code == 0 and existing.stdout then
		local key = existing.stdout:match("\nfpr:::::::::([%w%d]+):")
		return key and key:sub(-16)
	end

	local batch_content = determine_gen_key_string(keyid, passphrase)
	local batch_file = vim.fn.tempname()

	vim.fn.writefile(vim.split(batch_content, "\n"), batch_file)

	local obj = vim.system({
		"gpg",
		"--batch",
		"--status-fd",
		"1",
		"--pinentry-mode",
		"loopback",
		"--gen-key",
		batch_file,
	}, { text = true }):wait()

	if obj.code ~= 0 then
		print("GPG Error: " .. (obj.stderr or "Unknown error"))
		return
	end

	os.remove(batch_file)

	if obj.stdout then
		local fingerprint = obj.stdout:match("KEY_CREATED [^ ]+ ([%w%d]+)")
		if fingerprint then
			return fingerprint:sub(-16) -- Returns the 16-char Long ID (e.g., DC66CDB28DC727BC)
		end
	end
end

--- Resolves the full fingerprint of a key. Batch mode only deletes by
--- fingerprint, not by key ID, so the full one is needed to delete a key.
--- @param keyid string
--- @return string?
local function gpg_fingerprint(keyid)
	local listed = vim.system({ "gpg", "--with-colons", "--list-secret-keys", keyid }, { text = true }):wait()

	return (listed.stdout or ""):match("fpr:::::::::([%w]+):")
end

--- Deletes a key and its public half, leaving the keyring without it.
--- @param keyid string
--- @return vim.SystemCompleted
function M.delete_gpg_key(keyid)
	return vim.system({ "gpg", "--batch", "--yes", "--delete-secret-and-public-key", gpg_fingerprint(keyid) }):wait()
end

--- Deletes only the secret half of a key. The public half stays, so the key is
--- still a valid recipient even though nothing can read what is encrypted to it.
--- @param keyid string
--- @return vim.SystemCompleted
function M.delete_gpg_secret_key(keyid)
	return vim.system({ "gpg", "--batch", "--yes", "--delete-secret-keys", gpg_fingerprint(keyid) }):wait()
end

function M.cache_gpg_password(password)
	local cmd = {
		"gpg",
		"--batch",
		"--yes",
		"--no-tty",
		"--pinentry-mode=loopback",
		"--passphrase",
		password,
		"--sign",
	}

	return vim.system(cmd):wait()
end

--- Stops the daemons gpg started for the test homedir, keyboxd included. It has
--- to happen before the homedir goes away: gpgconf finds a running agent through
--- its socket, which lives in there.
function M.kill_gpg_agent()
	local cmd = {
		"gpgconf",
		"--kill",
		"all",
	}

	return vim.system(cmd):wait()
end

--- Directory the test env is rooted at. Never the developer's real `$HOME`.
local TEST_HOME = "/tmp/memo.nvim"

--- @return string
local function test_home()
	return vim.fn.resolve(TEST_HOME)
end

function M.setup_test_env()
	local home = test_home()
	local notes_dir = home .. "/notes"
	local scratch_dir = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "memo-scratch")

	vim.env.HOME = home
	vim.env.GNUPGHOME = home .. "/.gnupg"
	vim.env.NOTES_DIR = notes_dir
	vim.env.SCRATCH_DIR = scratch_dir

	vim.fn.mkdir(home, "p")
	vim.fn.mkdir(notes_dir, "p")
	vim.fn.mkdir(scratch_dir, "p")
	vim.fn.mkdir(home .. "/.gnupg", "p")
	vim.fn.system({ "chmod", "700", home .. "/.gnupg" })
end

function M.cleanup_test_env()
	M.kill_gpg_agent()
	vim.fn.delete(test_home(), "rf")
end

--- @param notes_dir string
function M.register_autocmds(notes_dir)
	vim.g.memo_notes_dir = notes_dir
	require("plugin.memo")
end

function M.new_child_neovim()
	local child = MiniTest.new_child_neovim()

	--- @param condition fun()
	--- @param timeout? integer
	--- @param interval? integer
	child.wait_until = function(condition, timeout, interval)
		local max = timeout or 5000
		local inc = interval or 100
		for _ = 0, max, inc do
			if condition() then
				return
			else
				--- @diagnostic disable-next-line: undefined-field
				vim.uv.sleep(inc)
			end
		end

		error(
			string.format(
				"Timed out waiting for condition after %d ms\n\n%s\n\n",
				max,
				tostring(child.cmd_capture("messages"))
			)
		)
	end

	child.sleep = function(ms)
		--- @diagnostic disable-next-line: undefined-field
		vim.uv.sleep(math.max(ms, 1))
	end

	return child
end

--- Track autocmd events in a child neovim instance
--- @param child table The child neovim instance
--- @param events string[] The events to track (e.g., {"BufReadPre", "BufReadPost"})
--- @param pattern? string The autocmd pattern (default: "*")
function M.track_autocmds(child, events, pattern)
	pattern = pattern or "*"

	child.cmd("lua _G.autocmd_fired = {}")
	for _, event in ipairs(events) do
		child.cmd(string.format([[autocmd %s %s lua _G.autocmd_fired["%s"] = true]], event, pattern, event))
	end
end

--- Check if a tracked autocmd event fired
--- @param child table The child neovim instance
--- @param event string The event to check
--- @return boolean
function M.autocmd_fired(child, event)
	return child.lua_get("_G.autocmd_fired[...] or false", { event })
end

return M
