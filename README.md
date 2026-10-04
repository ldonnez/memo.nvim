# memo.nvim

Seamless Neovim interface for [memo](https://github.com/ldonnez/memo), a CLI-based notes system with transparent GPG encryption. Create, read, and update encrypted files without leaving your editor.

- Transparent encryption: `.asc` files in your notes directory are decrypted into the buffer and re-encrypted on write; plaintext never touches disk.
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
- [memo](https://github.com/ldonnez/memo) CLI >= 0.11.0 on your `PATH`, configured with a GPG key
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
    vim.g.memo_default_capture_file = "journal.md.asc" -- default: inbox.md.asc
  end,
  keys = {
    {
      mode = { "n", "v" },
      "<leader>mc",
      function()
        require("memo").capture({
          target_header = "# " .. os.date("%Y-%m-%d"),
          header_padding = 1,
        })
      end,
      desc = "Memo: Capture to braindump",
    },
    {
      "<leader>mo",
      function()
        require("memo").open({
          window = {
            split = "vsplit",
          },
        })
      end,
      desc = "Memo: Open default capture file",
    },
    {
      "<leader>ms",
      function()
        require("memo").scratch("horizontal")
      end,
      desc = "Memo: Scratch horizontal",
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
      "<leader>mp",
      function()
        require("memo.pickers.fzf_lua").scratch_files_picker()
      end,
      desc = "Memo: Scratch files",
    },
    {
      "<leader>mw",
      function()
        require("memo.pickers.fzf_lua").cwd_scratch_files_picker()
      end,
      desc = "Memo: Cwd Scratch files",
    },
    {
      mode = { "n", "v" },
      "<leader>mS",
      function()
        require("memo").save_as_note()
      end,
      desc = "Memo: Save as note",
    },
    {
      "<leader>mf",
      function()
        require("memo.pickers.fzf_lua").files_picker()
      end,
      desc = "Memo: Files",
    },
    {
      mode = { "n", "v" },
      "<leader>mn",
      function()
        require("memo").new_note({
          window = { split = "split" },
        })
      end,
      desc = "Memo: New note",
    },
  },
}
```

Every mapping is optional, drop the ones you do not want.
`g:memo_default_capture_file` is what ties the two together: `<leader>mc`
captures into that note, under a `target_header` for the day, and
`<leader>mo` opens the very same note. The three pickers need
[fzf-lua](https://github.com/ibhagwan/fzf-lua).

### vim.pack

Set configuration before loading the plugin.

```lua
vim.g.memo_notes_dir = "~/my-notes-dir" -- default: ~/notes
vim.g.memo_scratch_dir = "~/.local/state/memo-scratch" -- default: stdpath("data")/memo-scratch
vim.g.memo_default_capture_file = "journal.md.asc" -- default: inbox.md.asc

vim.pack.add({
  { src = "https://github.com/ldonnez/memo.nvim", version = vim.version.range("*") },
})

vim.keymap.set({ "n", "v" }, "<leader>mc", function()
  require("memo").capture({
    target_header = "# " .. os.date("%Y-%m-%d"),
    header_padding = 1,
  })
end, { desc = "Memo: Capture to braindump" })

vim.keymap.set("n", "<leader>mo", function()
  require("memo").open({
    window = {
      split = "vsplit",
    },
  })
end, { desc = "Memo: Open default capture file" })

vim.keymap.set("n", "<leader>ms", function()
  require("memo").scratch("horizontal")
end, { desc = "Memo: Scratch horizontal" })

vim.keymap.set("n", "<leader>mv", function()
  require("memo").scratch("vertical")
end, { desc = "Memo: Scratch vertical" })

vim.keymap.set("n", "<leader>mt", function()
  require("memo").scratch("tab")
end, { desc = "Memo: Scratch tab" })

vim.keymap.set("n", "<leader>mp", function()
  require("memo.pickers.fzf_lua").scratch_files_picker()
end, { desc = "Memo: Scratch files" })

vim.keymap.set("n", "<leader>mw", function()
  require("memo.pickers.fzf_lua").cwd_scratch_files_picker()
end, { desc = "Memo: Cwd Scratch files" })

vim.keymap.set({ "n", "v" }, "<leader>mS", function()
  require("memo").save_as_note()
end, { desc = "Memo: Save as note" })

vim.keymap.set("n", "<leader>mf", function()
  require("memo.pickers.fzf_lua").files_picker()
end, { desc = "Memo: Files" })

vim.keymap.set({ "n", "v" }, "<leader>mn", function()
  require("memo").new_note({
    window = { split = "split" },
  })
end, { desc = "Memo: New note" })
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

### `g:memo_default_capture_file`

The note `:Memo` and `require("memo").open()` open when no path is given, and
the one `require("memo").capture()` writes to when no `capture_file` is
given. A path relative to `<notes_dir>`, with or without a note extension.

- Default: `inbox.md.asc`.

```lua
vim.g.memo_default_capture_file = "inbox.md.asc"
```

A subdirectory keeps captures out of the way, and the extension is optional:

```lua
vim.g.memo_default_capture_file = "quick/inbox.md.asc"
```

The first capture creates the note and any missing parent directories;
`:Memo` reports an error until then, since there is nothing to open yet.

Read the default back with `:Memo` or `require("memo").open()`:

```lua
vim.keymap.set("n", "<leader>mo", function()
  require("memo").open()
end, { desc = "Memo: Open the default capture file" })
```

Pair it with `target_header` and one note becomes a dated journal, with
`<leader>mc` writing to it and `:Memo` opening it:

```lua
vim.g.memo_default_capture_file = "journal.md.asc"
```

```lua
vim.keymap.set({ "n", "v" }, "<leader>mc", function()
  require("memo").capture({
    target_header = "# " .. os.date("%Y-%m-%d"),
    header_padding = 1,
  })
end, { desc = "Memo: Capture to today" })
```

This is only the fallback: `require("memo").capture({ capture_file = ... })`
and `:MemoNewNote <path>` still take an explicit path and ignore the default.

### `g:memo_extension`

Extension used for new notes, new scratch buffers, and notes saved from a
buffer whose path has no note extension yet. `.asc` (armored ASCII) and
`.gpg` are both read, and any other value is read as well, so the extension
you pick is always recognized on the way back in.

- Default: `asc`

```lua
vim.g.memo_extension = "gpg"
```

An existing note always keeps its own extension, so notes created by an
older version keep working: a `note.md.gpg` note opens, decrypts, and is
written back to `note.md.gpg` even with the `asc` default. The extension is
appended once, so a note is never named `note.md.pgp.pgp`.

Paths in `g:memo_default_capture_file` and note paths passed to
`require("memo")` may include a note extension or omit it; when omitted,
`g:memo_extension` applies.

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

| Command                | Description                                        |
| ---------------------- | -------------------------------------------------- |
| `:Memo`                | Open the default capture file.                     |
| `:MemoScratch`         | Open a new encrypted scratch buffer.               |
| `:MemoNewNote`         | Create a new encrypted note in the notes dir.      |
| `:MemoScratchFiles`    | Browse and open encrypted scratch files.           |
| `:MemoScratchFilesCwd` | Browse and open scratch files for the current dir. |
| `:MemoSaveAsNote`      | Save the buffer or selection as an encrypted note. |
| `:MemoFiles`           | Browse and open files in the notes directory.      |
| `:MemoSync`            | Sync the git backend (`memo sync git`).            |

## Features

### Transparent editing

`memo.nvim` acts as a transparent wrapper around your notes directory via autocommands:

- Opening a file inside the notes directory triggers asynchronous decryption; the editor stays responsive even for large files.
- Writing a buffer re-encrypts the file automatically.
- New files in the notes directory are encrypted on first write.
- Decrypted content lives only in the Neovim buffer.
- Files matching `g:memo_ignore_patterns` are treated as regular files.

This means your usual workflows (search, LSP, macros) operate on plaintext while the data on disk stays encrypted.

### Notes encrypted with a passphrase

A note encrypted symmetrically, with `gpg --symmetric` instead of a key, opens
without needing a key in the keyring:

- Opening one asks for the passphrase of that file, e.g. `GPG Passphrase for
note inbox.md.asc (symmetric):`.
- Writing it back encrypts it with the same passphrase, so it stays
  symmetric instead of being re-encrypted to your key. The passphrase is kept
  in the buffer, so it is asked for once per buffer rather than once per write.
- Reading and writing them goes through `memo encrypt --symmetric` and
  `memo decrypt`, so a note is exactly what the CLI writes. The passphrase is
  handed over in the child process environment, not on the command line.
- A wrong passphrase reports a decryption failure and the buffer is dropped.
- The passphrase lives in `b:memo_symmetric_passphrase` for the life of the
  buffer. Avoid `:mksession` with `sessionoptions` containing `globals`, which
  would write it out.

The [memo CLI](https://github.com/ldonnez/memo) creates these notes with
`memo encrypt --symmetric`, and keeps them symmetric when you open them with
`memo FILE`, so both tools can work on the same notes.

### Formatting with conform.nvim

`prettier` cannot infer a parser from `.asc` filenames. If you use [conform.nvim](https://github.com/stevearc/conform.nvim) to format notes, map each filetype to its parser:

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

`prettierd` infers the parser from the filename and cannot be made to work on `.asc` buffers without overriding the formatter entirely.

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

- Prompts for a note path, defaulting to `<notes_dir>/<buffer_name>.asc`.
- Relative paths are resolved against `<notes_dir>` and must stay inside it; saving elsewhere, overwriting an existing note, or using an empty path will not work.
- Pairs naturally with scratch buffers: write something ephemeral, then promote it to a permanent note.
- A visual selection is detected automatically and saves only the selected lines.

```lua
vim.keymap.set({"n", "v"}, "<leader>mS", function()
  require("memo").save_as_note()
end, { desc = "Memo: Save buffer as note" })
```

### Open a note

Open a note by path, with the same `window` options as a new note. Paths are
resolved against `<notes_dir>` and may carry a note extension or leave it
off:

```lua
require("memo").open({ path = "journals/2026-01-01.md" })

-- Beside the buffer, instead of replacing it
require("memo").open({
  path = "journals/2026-01-01.md",
  window = { split = "vsplit", size = 0.4 },
})
```

`:Memo` and `require("memo").open()` without a path open
`g:memo_default_capture_file`, which is the same note a capture writes to:

```lua
require("memo").open()
```

A path that is missing, outside `<notes_dir>` or does not exist reports an
error instead of opening an empty buffer.

### Create a new note

Start an empty encrypted note with `:MemoNewNote` (or
`require("memo").new_note()`):

- Prompts for a note path, defaulting to the full path
  `<notes_dir>/YYYY-MM-DD.md.asc`, so it is clear where the note lands. The
  prompt is the same for the command and `require("memo").new_note()`, and an
  emptied prompt aborts.
- A path can be passed instead, e.g. `:MemoNewNote journals/2026-01-01.md`.
  Relative paths resolve against `<notes_dir>` and may contain subdirectories.
  Paths must stay inside `<notes_dir>`.
- With a visual selection or a range, e.g. `:'<,'>MemoNewNote`, the selected
  lines are inserted at the template's `|` marker. A template without a marker
  has nowhere to insert, so the selection becomes the whole note.
- Missing parent directories are created. An existing note is only replaced
  after you confirm the overwrite.
  `:MemoFiles` right away.

A template can be passed to prefill the note. Templates accept `os.date`
formats and a `|` marker that is removed and used as the cursor position:

```lua
require("memo").new_note({
  path = "meetings/2026-01-01.md",
  template = "# %Y-%m-%d\n\nAttendees:\n- |\n\nNotes:\n",
})
```

A `window` opens the note in a split, with the same options
`require("memo").capture()` takes. Every option has a default, so `split`
alone is enough. Without a `window` the note takes over the current
window:

```lua
require("memo").new_note({
  window = {
    split = "vsplit", -- "split" (default) | "vsplit" | "tab"
    size = 0.5, -- a share of the screen, 0 to 1; defaults to 0.5
    -- position defaults to "botright"
  },
})
```

A `tab` is opened after the current one and takes the whole screen, so `size`
and `position` do not apply to it.

When a template and a selection are both given, the selection is inserted at
the `|` marker and the cursor lands right after it. For example, selecting
`Ada Lovelace` with `"## Agenda\n- | (carried over)"` produces
`## Agenda` followed by `- Ada Lovelace (carried over)`. Without a marker there
is nowhere to insert, so the selection becomes the whole note.

Notes in subdirectories are opened and written transparently, so nested paths
such as `journals/2026-01-01.md.asc` behave like top-level notes.

### Quick capture

Wire a keybinding to write down text in a temporary buffer. On saving and
closing the window, the content is appended to your configured `capture_file`,
under the `target_header` (prepended if it does not exist).

```lua
vim.keymap.set("n", "<leader>mc", function()
  require("memo").capture({
    capture_file = "inbox.md.asc",
    target_header = "# inbox", -- captures are inserted below this header
    header_padding = 1, -- blank lines between capture content and target header
    template = "## %Y-%m-%d %H:%M\n\n|\n", -- '|' marks the cursor
    window = {
      split = "split", -- "split" (default) | "vsplit"
      size = 0.5, -- a share of the screen, 0 to 1; defaults to 0.5
      position = "botright", -- "botright" (default) | "topleft" | "leftabove" | "rightbelow"
    },
  })
end, { desc = "Memo: Quick capture" })
```

A visual selection is detected automatically: select text in visual mode and
call `require("memo").capture()` to pre-fill the capture window:

```lua
vim.keymap.set("v", "<leader>mc", function()
  require("memo").capture({ capture_file = "inbox.md.asc" })
end, { desc = "Memo: Quick capture selection" })
```

With a template that has a `|`, the selection is inserted at that marker instead
of replacing the template, so a selected capture keeps its date header. A
template without a marker has nowhere to insert, so the selection still
becomes the whole capture window.

Turn a capture file into a journal with dynamic headers:

```lua
require("memo").capture({
  capture_file = "journal.md.asc",
  target_header = "# " .. os.date("%Y-%m-%d"),
  header_padding = 1,
})
```

Or create a journal file for each day automatically:

```lua
require("memo").capture({
  capture_file = "journals/" .. os.date("%Y-%m-%d") .. ".md.asc",
  target_header = "# " .. os.date("%Y-%m-%d"),
  header_padding = 1,
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

Scratch files are stored under the obfuscated name `<encoded-cwd>-<timestamp>-<hash>.asc`, so the scratch pickers decode the cwd path for display and show `<cwd-path>-<timestamp>-<hash>.asc`. The cwd picker shows the scratch files created in the current working directory.

## Development

- `make dev` — install dev dependencies (mini.nvim, memo, emmylua_check) and symlink the plugin into `~/.local/share/nvim/site/pack/local/opt`.
- `make test` — run the test suite locally (requires `make deps/memo` and `~/.local/bin` on `PATH`).
- `make test_file FILE=tests/test_gpg.lua` — run a single test file locally.
- `make emmylua_check` — Lua type check.

### Docker workflow (recommended)

- `make docker/build-image` — build the CI-like image.
- `make docker/shell` — drop into a shell with the project mounted at `/opt` and your local `memo` binary available.
- `make docker/test` / `make docker/test_file` — run tests inside the Docker image directly.

## License

MIT License

Copyright (c) 2025 Lenny Donnez
