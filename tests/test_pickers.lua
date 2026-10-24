local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

local NOTES_DIR = "/tmp/memo-picker-notes"

describe("pickers", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		-- The plugin is sourced during startup and caches the config before this
		-- runs, so setup is repeated with the notes dir below.
		child.lua(
			[[
      vim.g.memo_notes_dir = ...
      require("memo.config").setup()
      vim.fn.mkdir(vim.g.memo_notes_dir, "p")
      vim.fn.mkdir(require("memo.config").scratch_dir, "p")
    ]],
			{ NOTES_DIR }
		)
	end)

	after_each(function()
		child.stop()
	end)

	describe("without fzf-lua", function()
		before_each(function()
			child.lua([[ M = require("memo.pickers.fzf_lua") ]])
		end)

		it("does not error when fzf-lua is missing", function()
			child.lua("M.files_picker()")
		end)

		it("does not error for the scratch picker when fzf-lua is missing", function()
			child.lua("M.scratch_files_picker()")
		end)

		it("loads the previewer module without the optional dependency", function()
			child.lua([[ require("memo.pickers.fzf_gpg_previewer") ]])
		end)
	end)

	describe("with fzf-lua", function()
		before_each(function()
			-- Loaded here, not in the parent hook, so the previewer subclass sees
			-- the dependency while `memo.pickers.fzf_lua` is first required.
			child.lua([[ vim.cmd("set rtp+=deps/fzf-lua") ]])
			child.lua([[ M = require("memo.pickers.fzf_lua") ]])

			-- fzf-lua checks for an `fzf` executable while normalizing options.
			-- It is only asked for `--version`, so a fake on PATH is enough and
			-- the fzf binary is not a test dependency.
			local bin_dir = "/tmp/memo-picker-fakebin"
			helpers.write_fake_binary(bin_dir, "fzf", "0.60.3")
			child.lua([[ vim.env.PATH = ... .. ":" .. vim.env.PATH ]], { bin_dir })
		end)

		---Builds `builder`'s options and resolves them with fzf-lua itself.
		---@param builder string
		---@param opts table?
		local function resolve(builder, opts)
			child.lua(
				[[
          local name, opts = ...
          _G.resolved = require("fzf-lua.config").normalize_opts(M[name](opts), "files")
        ]],
				{ builder, opts }
			)
		end

		it("builds notes picker options fzf-lua accepts", function()
			resolve("files_picker_opts")

			MiniTest.expect.equality(child.lua_get("_G.resolved.cwd"), NOTES_DIR)
			MiniTest.expect.equality(child.lua_get("_G.resolved.previewer"), false)
			MiniTest.expect.equality(child.lua_get("_G.resolved.winopts.preview.delay"), 300)
		end)

		it("forwards the gpg previewer class when previews are requested", function()
			resolve("files_picker_opts", { previewer = true })

			MiniTest.expect.equality(
				child.lua_get([[
          _G.resolved.previewer.populate_preview_buf == require("memo.pickers.fzf_gpg_previewer").populate_preview_buf
        ]]),
				true
			)
			MiniTest.expect.equality(child.lua_get("type(_G.resolved.previewer.new)"), "function")
		end)

		it("builds scratch picker options with actions and transforms", function()
			resolve("scratch_files_picker_opts")

			MiniTest.expect.equality(
				child.lua_get("_G.resolved.cwd"),
				child.lua_get("require('memo.config').scratch_dir")
			)
			MiniTest.expect.equality(child.lua_get("_G.resolved.actions['ctrl-x'].reload"), true)
			MiniTest.expect.equality(child.lua_get("type(_G.resolved.actions['ctrl-x'].fn)"), "function")
			MiniTest.expect.equality(child.lua_get("_G.resolved.multiprocess"), false)
			MiniTest.expect.equality(child.lua_get("type(_G.resolved.fn_transform)"), "function")
			MiniTest.expect.equality(child.lua_get("type(_G.resolved._fmt.from)"), "function")
		end)

		it("deletes scratch entries that have no buffer", function()
			resolve("scratch_files_picker_opts")

			child.lua([[
        local dir = require("memo.config").scratch_dir
        _G.scratch_file = dir .. "/scratch-delete-me.md.asc"
        vim.fn.writefile({ "body" }, _G.scratch_file)
        _G.resolved.actions["ctrl-x"].fn({ _G.scratch_file }, _G.resolved)
      ]])

			MiniTest.expect.equality(child.lua_get("vim.fn.filereadable(_G.scratch_file)"), 0)
		end)

		it("deletes scratch entries that have an open buffer", function()
			resolve("scratch_files_picker_opts")

			child.lua([[
        local dir = require("memo.config").scratch_dir
        _G.scratch_file = dir .. "/scratch-delete-me.md.asc"
        vim.fn.writefile({ "body" }, _G.scratch_file)
        vim.cmd("edit " .. vim.fn.fnameescape(_G.scratch_file))
        _G.resolved.actions["ctrl-x"].fn({ _G.scratch_file }, _G.resolved)
      ]])

			MiniTest.expect.equality(child.lua_get("vim.fn.filereadable(_G.scratch_file)"), 0)
			MiniTest.expect.equality(child.lua_get("vim.fn.bufexists(_G.scratch_file)"), 0)
		end)

		it("loads the previewer module with the dependency", function()
			child.lua([[ require("memo.pickers.fzf_gpg_previewer") ]])
		end)
	end)
end)
