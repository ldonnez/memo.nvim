# memo.nvim

Seamless Neovim interface for [memo](https://github.com/ldonnez/memo), a CLI-based notes system with transparent GPG encryption. Create, read, and update encrypted files without leaving your editor, and keep your notes in sync with git.

- Transparent encryption: `.gpg` files in your notes directory are decrypted into the buffer and re-encrypted on write; plaintext never touches disk.
- Encrypted scratch buffers for throwaway, sensitive content.
- Quick capture workflow that appends to a capture file (e.g. a journal).
- fzf-lua pickers for browsing notes and scratch files.
- Git sync via `memo sync git`.
- Zero required configuration; set a few globals to customize.

<a href="https://github.com/ldonnez/memo.nvim/actions"><img src="https://github.com/ldonnez/memo.nvim/actions/workflows/ci.yml/badge.svg?branch=main" alt="Build Status"></a>
<a href="http://github.com/ldonnez/memo.nvim/releases"><img src="https://img.shields.io/github/v/tag/ldonnez/memo.nvim" alt="Version"></a>
<a href="https://github.com/ldonnez/memo.nvim?tab=MIT-1-ov-file#readme"><img src="https://img.shields.io/github/license/ldonnez/memo.nvim" alt="License"></a>

## Requirements

- Neovim >= 0.11
- [memo](https://github.com/ldonnez/memo) CLI on your `PATH`, configured with a GPG key
- Optional: [fzf-lua](https://github.com/ibhagwan/fzf-lua) for the pickers

Check with `:checkhealth memo` to verify everything is set up correctly.

## Installation

### lazy.nvim

```lua
{
  "ldonnez/memo.nvim",
  init = function()
    vim.g.memo_notes_dir = "~/my-notes-dir" -- default: ~/notes
    vim.g.memo_scratch_dir = "~/.local/state/memo-scratch" -- default: stdpath("data")/memo-scratch
  end,
  keys = {
    {
      mode = { "n", "v" },
      "<leader>mc",
      function()
        require("memo").register_capture({ capture_file = "inbox.md.gpg" })
      end,
      desc = "Memo: Capture to braindump",
    },
    {
      "<leader>ms",
      function()
        require("memo").scratch("horizontal")
      end,
      desc = "Memo: Scratch horizontal",
    },
    {
      "<leader>mS",
      function()
        require("memo").save_as_note()
      end,
      desc = "Memo: Save as note",
    },
    {
      "<leader>mv",
      function()
        require("memo").scratch("vertical")
      end,
      desc = "Memo: Scratch vertical",
    },
    {
      "<leader>mt",
      function()
        require("memo").scratch("tab")
      end,
      desc = "Memo: Scratch tab",
    },
    {
      "<leader>mf",
      function()
        require("memo.pickers.fzf_lua").files_picker()
      end,
      desc = "Memo: Files",
    },
    {
      "<leader>mp",
      function()
        require("memo.pickers.fzf_lua").scratch_files_picker()
      end,
      desc = "Memo: Scratch files",
    },
  },
}
```

### vim.pack

Set configuration before loading the plugin.

```lua
vim.g.memo_notes_dir = "~/my-notes-dir" -- default: ~/notes
vim.g.memo_scratch_dir = "~/.local/state/memo-scratch" -- default: stdpath("data")/memo-scratch

vim.pack.add({
  { src = "https://github.com/ldonnez/memo.nvim", version = vim.version.range("*") },
})

vim.keymap.set({ "n", "v" }, "<leader>mc", function()
   require("memo").register_capture({ capture_file = "inbox.md.gpg" })
end, { desc = "Memo: Capture to braindump" })

vim.keymap.set("n", "<leader>ms", function()
  require("memo").scratch("horizontal")
end, { desc = "Memo: Scratch horizontal" })

vim.keymap.set("n", "<leader>mS", function()
  require("memo").save_as_note()
end, { desc = "Memo: Save as note" })

vim.keymap.set("n", "<leader>mv", function()
  require("memo").scratch("vertical")
end, { desc = "Memo: Scratch vertical" })

vim.keymap.set("n", "<leader>mt", function()
  require("memo").scratch("tab")
end, { desc = "Memo: Scratch tab" })

vim.keymap.set("n", "<leader>mf", function()
  require("memo.pickers.fzf_lua").files_picker()
end, { desc = "Memo: Files" })

vim.keymap.set("n", "<leader>mp", function()
  require("memo.pickers.fzf_lua").scratch_files_picker()
end, { desc = "Memo: Scratch files" })
```

## Configuration

All settings are optional and set via global variables before `memo.nvim` loads.

### `g:memo_notes_dir`

Directory containing your encrypted notes.

- Default: `~/notes`

```lua
vim.g.memo_notes_dir = "~/my-notes"
```

### `g:memo_scratch_dir`

Directory where encrypted scratch files are stored.

- Default: `vim.fn.stdpath("data")/memo-scratch` (e.g. `~/.local/share/nvim/memo-scratch`)

```lua
vim.g.memo_scratch_dir = "~/.local/state/memo-scratch"
```

### `g:memo_ignore_patterns`

Additional `.gitignore`-style glob patterns to leave as plaintext. Files matching these patterns are not decrypted on open and not encrypted on write. Custom patterns are merged with the defaults below.

```lua
{
  "**/.git/**",
  "**/.githooks/**",
  "**/.gitignore",
  "**/.gitattributes",
  "**/.gitmodules",
  "**/.ignore",
}
```

Example:

```lua
vim.g.memo_ignore_patterns = {
  "**/.env",
  "**/tmp/**",
  "**/node_modules/**",
}
```

## Commands

| Command             | Description                                        |
| ------------------- | -------------------------------------------------- |
| `:MemoScratch`      | Open a new encrypted scratch buffer.               |
| `:MemoScratchFiles` | Browse and open encrypted scratch files.           |
| `:MemoScratchFilesCwd` | Browse and open scratch files for the current dir. |
| `:MemoSaveAsNote`   | Save the buffer or selection as an encrypted note. |
| `:MemoFiles`        | Browse and open files in the notes directory.      |
| `:MemoSync`         | Sync the git backend (`memo sync git`).            |

## Features

### Transparent editing

`memo.nvim` acts as a transparent wrapper around your notes directory via autocommands:

- Opening a file inside the notes directory triggers asynchronous decryption; the editor stays responsive even for large files.
- Writing a buffer re-encrypts the file automatically.
- New files in the notes directory are encrypted on first write.
- Decrypted content lives only in the Neovim buffer.
- Files matching `g:memo_ignore_patterns` are treated as regular files.

This means your usual workflows (search, LSP, macros) operate on plaintext while the data on disk stays encrypted.

### Formatting with conform.nvim

`prettier` cannot infer a parser from `.gpg` filenames. If you use [conform.nvim](https://github.com/stevearc/conform.nvim) to format notes, map each filetype to its parser:

```lua
require("conform").setup({
  formatters = {
    prettier = {
      options = {
        ft_parsers = {
          markdown = "markdown",
          json = "json",
          yaml = "yaml",
        },
      },
    },
  },
})
```

`prettierd` infers the parser from the filename and cannot be made to work on `.gpg` buffers without overriding the formatter entirely.

### Encrypted scratch buffers

Create encrypted scratch buffers for throwaway, sensitive content:

```lua
vim.keymap.set("n", "<leader>ms", function()
  require("memo").scratch("horizontal")
end, { desc = "Memo: New scratch buffer (horizontal split)" })

vim.keymap.set("n", "<leader>mv", function()
  require("memo").scratch("vertical")
end, { desc = "Memo: New scratch buffer (vertical split)" })

vim.keymap.set("n", "<leader>mt", function()
  require("memo").scratch("tab")
end, { desc = "Memo: New scratch buffer (new tab)" })
```

Or use the command `:MemoScratch <horizontal|vertical|tab>`.

Notes:

- Files are stored encrypted in `g:memo_scratch_dir`, named after the `cwd` plus a timestamp, so buffers from different projects never collide.
- The buffer reuses the regular memo read/write autocommands, so files persist across restarts and sessions (e.g. [auto-session](https://github.com/rmagatti/auto-session)).
- Scratch content is throwaway by design: deleting or wiping the buffer (`:bd`/`:bwipeout`) also deletes its encrypted file. The encrypted file is only created once you write content.

### Save a buffer as a note

Turn any buffer into a note in your notes directory with `:MemoSaveAsNote` (or `require("memo").save_as_note()`):

- Prompts for a note path, defaulting to `<notes_dir>/<buffer_name>.gpg`.
- Relative paths are resolved against `<notes_dir>` and must stay inside it; saving elsewhere, overwriting an existing note, or using an empty path will not work.
- Pairs naturally with scratch buffers: write something ephemeral, then promote it to a permanent note.
- A visual selection is detected automatically and saves only the selected lines.

```lua
vim.keymap.set({"n", "v"}, "<leader>msn", function()
  require("memo").save_as_note()
end, { desc = "Memo: Save buffer as note" })
```

### Quick capture

Wire a keybinding to write down text in a temporary buffer. On saving and closing the window, the content is appended to your configured `capture_file`, under the `target_header` (prepended if it does not exist).

```lua
vim.keymap.set("n", "<leader>mc", function()
  require("memo").register_capture({
    capture_file = "inbox.md.gpg",
    capture_template = {
      template = "## %Y-%m-%d %H:%M\n\n|\n", -- '|' marks the cursor position in the capture window
      target_header = "# inbox",
      header_padding = 1, -- blank lines between capture content and target header
    },
    window = {
      split = "split", -- "split" | "vsplit"
      size = 10,
      position = "botright", -- "botright" | "topleft" | "leftabove" | "rightbelow"
    },
  })
end, { desc = "Memo: Quick capture" })
```

A visual selection is detected automatically: select text in visual mode and call `register_capture` to pre-fill the capture window:

```lua
vim.keymap.set("v", "<leader>mc", function()
  require("memo").register_capture({ capture_file = "inbox.md.gpg" })
end, { desc = "Memo: Quick capture selection" })
```

Turn a capture file into a journal with dynamic headers:

```lua
require("memo").register_capture({
  capture_file = "journal.md.gpg",
  capture_template = {
    target_header = "# " .. os.date("%Y-%m-%d"),
    header_padding = 1,
  },
})
```

Or create a journal file for each day automatically:

```lua
require("memo").register_capture({
  capture_file = "journals/" .. os.date("%Y-%m-%d") .. ".md.gpg",
  capture_template = {
    target_header = "# " .. os.date("%Y-%m-%d"),
    header_padding = 1,
  },
})
```

### fzf-lua pickers

memo.nvim includes pickers built on `require("fzf-lua").files` that scope the search to your notes directory or your encrypted scratch files.

```lua
require("memo.pickers.fzf_lua").files_picker()             -- notes directory
require("memo.pickers.fzf_lua").scratch_files_picker()     -- all scratches
require("memo.pickers.fzf_lua").cwd_scratch_files_picker() -- current cwd
```

The scratch pickers additionally bind `ctrl-x` to delete the selected scratch files (multi-select with `tab`/`alt-a`) without closing the picker; any buffer holding a deleted file is wiped too.

Scratch files are stored under the obfuscated name `<encoded-cwd>-<timestamp>-<hash>.gpg`, so the scratch pickers decode the cwd path for display and show `<cwd-path>-<timestamp>-<hash>.gpg`. The cwd picker shows the scratch files created in the current working directory.

## Development

- `make dev` — install dev dependencies (mini.nvim, memo, emmylua_check) and symlink the plugin into `~/.local/share/nvim/site/pack/local/opt`.
- `make test` — run the test suite (mini.test). Requires `make deps/memo` and `~/.local/bin` on `PATH`.
- `make test_file FILE=tests/test_gpg.lua` — run a single test file.
- `make emmylua_check` — Lua type check.

### Docker workflow (recommended)

- `make docker/build-image` — build the CI-like image.
- `make docker/shell` — drop into a shell with the project mounted at `/opt` and your local `memo` binary available.

## License

MIT License

Copyright (c) 2025 Lenny Donnez
