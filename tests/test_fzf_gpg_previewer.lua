local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

local NOTES_DIR = "/tmp/memo-fzf-gpg-previewer-notes"

local ARMORED_NOTE = table.concat({
	"-----BEGIN PGP MESSAGE-----",
	"ciphertext",
	"-----END PGP MESSAGE-----",
}, "\n") .. "\n"

describe("fzf_gpg_previewer", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua(
			[[
      vim.fn.delete(..., "rf")
      vim.g.memo_notes_dir = ...
      require("memo.config").setup()
      vim.fn.mkdir(vim.g.memo_notes_dir, "p")

      -- The previewer is optional: load fzf-lua before the module so the
      -- subclass is built from the installed dependency.
      vim.cmd("set rtp+=deps/fzf-lua")
      _G.builtin = require("fzf-lua.previewer.builtin")
      _G.Previewer = require("memo.pickers.fzf_gpg_previewer")
    ]],
			{ NOTES_DIR }
		)
	end)

	after_each(function()
		child.stop()
		vim.fn.delete(NOTES_DIR, "rf")
	end)

	---Creates a previewer while keeping the real fzf-lua methods that do not
	---need a live preview window. The window-facing methods are recorded so
	---tests can inspect the buffer the previewer picked.
	---@param opts? table
	local function new_previewer(opts)
		child.lua(
			[[
      _G.previewer = Previewer({}, ...)
      _G.previewer.get_tmp_buffer = function()
        if not _G.tmpbuf or not vim.api.nvim_buf_is_valid(_G.tmpbuf) then
          _G.tmpbuf = vim.api.nvim_create_buf(false, true)
        end
        return _G.tmpbuf
      end
      _G.previewer.set_preview_buf = function(_, buf)
        _G.shown_buf = buf
      end
      _G.previewer.preview_buf_post = function(_, entry)
        _G.posted_entry = entry
        _G.posted = true
      end
    ]],
			{ opts or vim.empty_dict() }
		)
	end

	---@param name string
	---@param content? string
	---@return string
	local function write_note(name, content)
		local path = NOTES_DIR .. "/" .. name

		helpers.write_file(path, content or ARMORED_NOTE)

		return path
	end

	describe("fzf-lua API compatibility", function()
		it("subclasses the builtin buffer/file previewer", function()
			MiniTest.expect.equality(child.lua_get("type(builtin.buffer_or_file)"), "table")
			MiniTest.expect.equality(child.lua_get("Previewer.super == builtin.buffer_or_file"), true)
			MiniTest.expect.equality(child.lua_get("Previewer ~= builtin.buffer_or_file"), true)
			MiniTest.expect.equality(child.lua_get("type(Previewer.new)"), "function")
		end)

		it("still provides every builtin method the previewer calls", function()
			child.lua(
				[[
          local names = ...
          _G.missing = {}

          for _, name in ipairs(names) do
            if type(Previewer[name]) ~= "function" then
              _G.missing[#_G.missing + 1] = name
            end
          end
        ]],
				{
					{
						"new",
						"populate_preview_buf",
						"entry_to_file",
						"get_tmp_buffer",
						"set_preview_buf",
						"preview_buf_post",
						"_stop_preview_job",
						"_apply_cached_preview",
						"stop_ueberzug",
					},
				}
			)

			MiniTest.expect.equality(child.lua_get("_G.missing"), {})
		end)

		it("constructs through the builtin constructor and cache", function()
			new_previewer({ cwd = NOTES_DIR })

			MiniTest.expect.equality(child.lua_get("previewer.type"), "builtin")
			MiniTest.expect.equality(child.lua_get("previewer.opts.cwd"), NOTES_DIR)
			MiniTest.expect.equality(child.lua_get("type(previewer.bcache)"), "table")
			MiniTest.expect.equality(child.lua_get("type(previewer.bcache.check)"), "function")
		end)

		it("resolves entries with fzf-lua's path API", function()
			local path = NOTES_DIR .. "/note.md.gpg"

			new_previewer({ cwd = NOTES_DIR })
			child.lua([[ _G.entry = _G.previewer:entry_to_file(...) ]], { path })

			MiniTest.expect.equality(child.lua_get("_G.entry.path"), path)
		end)
	end)

	describe("populate_preview_buf", function()
		it("decrypts an armored note into the preview buffer", function()
			local path = write_note("secret.md.gpg")

			new_previewer({ cwd = NOTES_DIR })
			child.lua(
				[[
          local path = ...
          require("memo.crypto").decrypt_to_buffer = function(_, bufnr, on_exit)
            vim.bo[bufnr].modifiable = true
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "decrypted body" })
            vim.schedule(function()
              on_exit({ code = 0 }, nil)
            end)

            return { kill = function() _G.killed = true end }
          end

          _G.previewer:populate_preview_buf(path)
        ]],
				{ path }
			)

			child.wait_until(function()
				return child.lua_get("_G.posted == true")
			end)

			MiniTest.expect.equality(
				child.lua_get("vim.api.nvim_buf_get_lines(_G.tmpbuf, 0, -1, false)"),
				{ "decrypted body" }
			)
			MiniTest.expect.equality(child.lua_get("_G.previewer._last_entry"), path)
			MiniTest.expect.equality(child.lua_get("_G.previewer.stop_job == nil"), true)
			MiniTest.expect.equality(child.lua_get("_G.posted_entry.filetype"), "markdown")
			MiniTest.expect.equality(child.lua_get("type(_G.posted_entry.tick)"), "string")
		end)

		it("shows the decryption error in the preview buffer", function()
			local path = write_note("secret.md.gpg")

			new_previewer({ cwd = NOTES_DIR })
			child.lua(
				[[
          local path = ...
          require("memo.crypto").decrypt_to_buffer = function(_, _, on_exit)
            vim.schedule(function()
              on_exit(nil, "GPG: incorrect passphrase")
            end)

            return { kill = function() end }
          end

          _G.previewer:populate_preview_buf(path)
        ]],
				{ path }
			)

			child.wait_until(function()
				return child.lua_get("_G.previewer.stop_job == nil")
			end)

			MiniTest.expect.equality(
				child.lua_get("vim.api.nvim_buf_get_lines(_G.tmpbuf, 0, -1, false)"),
				{ "GPG: incorrect passphrase" }
			)
			MiniTest.expect.equality(child.lua_get("_G.posted == true"), false)
		end)

		it("shows a placeholder while decryption is in flight", function()
			local path = write_note("pending.md.gpg")

			new_previewer({ cwd = NOTES_DIR })
			child.lua(
				[[
          local path = ...
          require("memo.crypto").decrypt_to_buffer = function()
            return { kill = function() _G.killed = true end }
          end

          _G.previewer:populate_preview_buf(path)
        ]],
				{ path }
			)

			MiniTest.expect.equality(
				child.lua_get("vim.api.nvim_buf_get_lines(_G.tmpbuf, 0, -1, false)"),
				{ "Decrypting..." }
			)
			MiniTest.expect.equality(child.lua_get("_G.shown_buf == _G.tmpbuf"), true)
			MiniTest.expect.equality(child.lua_get("type(_G.previewer.stop_job)"), "function")
		end)

		it("kills the decrypt job when the preview buffer is wiped", function()
			local path = write_note("pending.md.gpg")

			new_previewer({ cwd = NOTES_DIR })
			child.lua(
				[[
          local path = ...
          require("memo.crypto").decrypt_to_buffer = function()
            return { kill = function() _G.killed = true end }
          end

          _G.previewer:populate_preview_buf(path)
          vim.api.nvim_buf_delete(_G.tmpbuf, { force = true })
        ]],
				{ path }
			)

			MiniTest.expect.equality(child.lua_get("_G.killed"), true)
			MiniTest.expect.equality(child.lua_get("_G.previewer.stop_job == nil"), true)
			MiniTest.expect.equality(child.lua_get("_G.previewer._preview_request_id"), 2)
		end)

		it("ignores callbacks from an outdated preview request", function()
			local path = write_note("secret.md.gpg")

			new_previewer({ cwd = NOTES_DIR })
			child.lua(
				[[
          local path = ...
          _G.exit_callbacks = {}
          require("memo.crypto").decrypt_to_buffer = function(_, _, on_exit)
            _G.exit_callbacks[#_G.exit_callbacks + 1] = on_exit
            return { kill = function() end }
          end

          _G.previewer:populate_preview_buf(path)
          _G.previewer:populate_preview_buf(path)
          _G.exit_callbacks[1]({ code = 0 }, nil)
        ]],
				{ path }
			)

			MiniTest.expect.equality(child.lua_get("_G.posted == true"), false)

			child.lua("_G.exit_callbacks[2]({ code = 0 }, nil)")

			MiniTest.expect.equality(child.lua_get("_G.posted == true"), true)
		end)

		it("delegates non-encrypted files to the builtin previewer", function()
			local path = NOTES_DIR .. "/plain.txt"
			helpers.write_file(path, "plain body\n")

			new_previewer({ cwd = NOTES_DIR })
			child.lua(
				[[
          local path = ...
          local super = Previewer.super
          local original = super.populate_preview_buf

          super.populate_preview_buf = function(_, entry_str)
            _G.super_entry = entry_str
            return true
          end

          local ok, err = pcall(function()
            _G.previewer:populate_preview_buf(path)
          end)

          super.populate_preview_buf = original
          _G.fallback = { ok = ok, err = err }
        ]],
				{ path }
			)

			MiniTest.expect.equality(child.lua_get("_G.super_entry"), path)
			MiniTest.expect.equality(child.lua_get("_G.fallback.ok"), true)
		end)

		it("reuses the cached preview for an unchanged note", function()
			local path = write_note("cached.md.gpg")

			new_previewer({ cwd = NOTES_DIR })
			child.lua(
				[[
          local path = ...
          _G.previewer.bcache:set({
            path = path,
            tick = require("memo.utils").file_signature(path),
          }, vim.api.nvim_create_buf(false, true))

          _G.previewer._apply_cached_preview = function(_, entry, cached)
            _G.applied_cache = { entry = entry, cached = cached }
          end

          require("memo.crypto").decrypt_to_buffer = function()
            _G.decrypted = true
            return nil
          end

          _G.previewer:populate_preview_buf(path)
        ]],
				{ path }
			)

			MiniTest.expect.equality(child.lua_get("type(_G.applied_cache)"), "table")
			MiniTest.expect.equality(child.lua_get("_G.applied_cache.entry.path"), path)
			MiniTest.expect.equality(child.lua_get("_G.decrypted == nil"), true)
		end)

		it("decrypts again when the cached note changed", function()
			local path = write_note("cached.md.gpg")

			new_previewer({ cwd = NOTES_DIR })
			child.lua(
				[[
          local path = ...
          _G.previewer.bcache:set({
            path = path,
            tick = "an outdated signature",
          }, vim.api.nvim_create_buf(false, true))

          _G.previewer._apply_cached_preview = function()
            _G.applied_cache = true
          end

          require("memo.crypto").decrypt_to_buffer = function(_, bufnr, on_exit)
            vim.bo[bufnr].modifiable = true
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "fresh body" })
            vim.schedule(function()
              on_exit({ code = 0 }, nil)
            end)

            return { kill = function() end }
          end

          _G.previewer:populate_preview_buf(path)
        ]],
				{ path }
			)

			child.wait_until(function()
				return child.lua_get("_G.posted == true")
			end)

			MiniTest.expect.equality(
				child.lua_get("vim.api.nvim_buf_get_lines(_G.tmpbuf, 0, -1, false)"),
				{ "fresh body" }
			)
			MiniTest.expect.equality(child.lua_get("_G.applied_cache == nil"), true)
		end)
	end)
end)
