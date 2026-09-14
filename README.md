# memo.nvim

Seamless Neovim interface for [memo](https://github.com/ldonnez/memo) a CLI-based system featuring transparent GPG encryption.
`memo.nvim` bridges the gap between secure file management and your editing workflow, allowing you to create, read, and update encrypted files without ever leaving your editor.

---

<a href="https://github.com/ldonnez/memo.nvim/actions"><img src="https://github.com/ldonnez/memo.nvim/actions/workflows/ci.yml/badge.svg?branch=main" alt="Build Status"></a>
<a href="http://github.com/ldonnez/memo.nvim/releases"><img src="https://img.shields.io/github/v/tag/ldonnez/memo.nvim" alt="Version"></a>
<a href="https://github.com/ldonnez/memo.nvim?tab=MIT-1-ov-file#readme"><img src="https://img.shields.io/github/license/ldonnez/memo.nvim" alt="License"></a>

## Table of Contents

- [Installation with example configuration](#installation-with-default-configuration)
  - [Install with vim.pack](#install-with-vimpack)
  - [Install with lazy.nvim](#install-with-lazynvim)
- [Features](#features)
- [Transparant editing](#transparant-editing)
- [Encrypted scratch buffers](#encrypted-scratch-buffers)
- [Save a buffer as a note](#save-a-buffer-as-a-note)
- [Capture workflow](#capture-workflow)
- [Fzf lua pickers](#fzf-lua-pickers)
- [Requirements](#requirements)
- [User commands](#user-commands)
- [Development](#development-guide)
  - [Prerequisites](#prerequisites)
  - [Dev setup](#dev-setup)
  - [Docker workflow](#docker-workflow-recommended)
  - [Run tests](#run-tests)
- [License](#License)

## Installation with default configuration

Lazy loading is already handled inside the plugin!

### Install with vim.pack

```lua

-- Should be set before running vim.pack.add!
vim.g.memo_notes_dir = "~/my-notes-dir" -- Default is ~/notes when not set.
vim.g.memo_scratch_dir = "~/.local/state/memo-scratch" -- Default is stdpath('data')/memo-scratch when not set.

vim.pack.add({
	{ src = "https://github.com/ldonnez/memo.nvim", version = vim.version.range("*") },
})

local keymap = vim.keymap

keymap.set("n", "<leader>mc", function()
  require("memo").register_capture({
    -- default capture file relative path from notes_dir. Will be created if it does not exist.
    capture_file = "inbox.md.gpg",
    -- optional default values
    capture_template = {
      template = "",
      header_padding = 0,
    },
    window = {
      split = "split", -- "split" | "vsplit"
      size = 10,
      position = "botright", -- "botright" | "topleft" | "leftabove" | "rightbelow"
    },
  })
end, { desc = "Capture to braindump" })

keymap.set("n", "<leader>mf", function()
  require("memo.pickers.fzf_lua").files_picker()
end, { desc = "Memo files picker" })

keymap.set("n", "<leader>ms", function()
  require("memo").sync_git()
end, { desc = "Sync with git" })

```

### Install with [lazy.nvim](https://lazy.folke.io/)

```lua
{
  "ldonnez/memo.nvim",
  init = function()
    vim.g.memo_notes_dir = "~/my-notes-dir" -- Default is ~/notes when not set.
    vim.g.memo_scratch_dir = "~/.local/state/memo-scratch" -- Default is stdpath('data')/memo-scratch when not set.
  end,
  keys = {
    {
      "<leader>mc",
      function()
        require("memo").register_capture({
          -- default capture file relative path from notes_dir. Will be created if it does not exist.
          capture_file = "inbox.md.gpg",
          -- optional default values
          capture_template = {
            template = "",
            header_padding = 0,
          },
          window = {
            split = "split", -- "split" | "vsplit"
            size = 10,
            position = "botright", -- "botright" | "topleft" | "leftabove" | "rightbelow"
          },
        })
      end,
      desc = "Capture to inbox",
    },
    {
      "<leader>mf",
      function()
        require("memo.pickers.fzf_lua").files_picker()
      end,
      desc = "Fzf lua files picker",
    },
  },
}
```

> [!IMPORTANT]
> Check with `:checkhealth memo` to verify if dependencies are met and to ensure the plugin is correctly loaded.

## Features

### Transparant editing

**memo.nvim** operates as a transparent wrapper around your notes directory. Instead of manually decrypting files, the plugin automates the lifecycle, using Neovim autocommands (autocmd):

- Detection: When you open a file within your configured notes directory, the plugin detects the path.
- Auto-Encryption: Any new file created within the notes directory is automatically encrypted upon writing.
- Security: The decrypted content exists only in your Neovim buffer.
- Asynchronous decryption: All decryption operations run in the background. This ensures that the editor remains responsive and non-blocking, even when processing large files.

> [!NOTE]
> This "transparent" approach means you can use your favorite Neovim workflows (searching, LSP, macros) on your files, while keeping the underlying data fully encrypted.

### Formatting with conform.nvim

If you want to format your notes with `prettier` via [conform.nvim](https://github.com/stevearc/conform.nvim), you'll need one extra option. Since memo notes are stored with a `.gpg` extension, `prettier` cannot infer the parser from the filename. Set `ft_parsers` for the `prettier` formatter so memo buffers are formatted with the right parser — **you must add an entry for every filetype you want to format inside the notes** (the key is the buffer filetype, the value is prettier's parser name):

```lua
-- in your conform.nvim config
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

**memo.nvim** provides an encrypted scratch buffer for throwaway, sensitive content. Content is encrypted with your GPG key on each write into a `.gpg` file under a configurable scratch directory (`vim.g.memo_scratch_dir`; defaults to `data/memo-scratch/`, where `data` is `vim.fn.stdpath("data")`, e.g. `~/.local/share/nvim`), avoiding plaintext on disk and keeping it out of your notes git sync. Each file is named after the `cwd` it was created in plus a timestamp, so buffers opened from different projects never collide. Because the buffer is an ordinary file in your scratch directory, it reuses the regular memo read/write autocmds: the file is transparently decrypted when opened and re-encrypted on write. The encrypted files persist, so scratch buffers survive restarts and sessions (e.g. [auto-session](https://github.com/rmagatti/auto-session)) like any other memo note.

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

Or use the built-in command: `:MemoScratch <horizontal|vertical|tab>`.

To browse and reopen existing scratch files (e.g. after a restart), use the fzf-lua scratch picker:

```lua
vim.keymap.set("n", "<leader>mfs", function()
  require("memo.pickers.fzf_lua").scratch_files_picker()
end, { desc = "Memo: Scratch files picker" })
```

Or use the built-in command: `:MemoScratchFiles`.

The scratch picker also supports deleting the selected scratch files (scratch content is throwaway by design): multi-select with `tab`/`alt-a`, then confirm with `ctrl-x`. Any buffer holding a deleted file is wiped too, so no orphaned state remains.

> [!NOTE]
> Scratch content is throwaway by design: deleting or wiping the buffer (`:bd`/`:bwipeout`) also deletes its encrypted file. Leaving the buffer open keeps it around, and the encrypted file is only created once you write content.

### Save a buffer as a note

**memo.nvim** lets you turn any buffer into a note in your notes directory with `:MemoSaveAsNote` (or `require("memo").save_as_note()`). It prompts for a note path (defaulting to `<notes_dir>/<name>.gpg`, where `<name>` is the current buffer's name without the `.gpg` extension) so it is clear where the note will be stored. A relative path is resolved against `<notes_dir>`, and the resolved path must stay inside `<notes_dir>` — saving elsewhere is refused, as is overwriting an existing note or using an empty path.

This pairs naturally with scratch buffers: write something ephemeral in a `:MemoScratch` window, then promote it to a permanent note. The current buffer is left open afterward, whether it is a scratch buffer or a regular one, so you can keep working.

```lua
vim.keymap.set("n", "<leader>msn", function()
  require("memo").save_as_note()
end, { desc = "Memo: Save buffer as note" })
```

Or use the built-in command: `:MemoSaveAsNote`.

### Capture workflow

**memo.nvim** includes a feature that allows you to quickly write down text into a temporary buffer. Once you save and close the window, the content is automatically appended to your configured `capture_file`.

#### Usage

You can register a capture command with custom behavior, such as dynamic headers (e.g., timestamps), cursor position with `|`, `header_padding` to configure the padding between capture and target header, and configure how capture window will split (`split`/`vsplit`).
When target header does not exist it will be prepended to the capture file.

This will prepend the following under the `# inbox` header in `inbox.md.gpg`.

```markdown
## <date> <time>
```

```lua
require("memo").register_capture({
  capture_file = "inbox.md.gpg",
  capture_template = {
    template = "## %Y-%m-%d %H:%M\n\n|\n", -- you can configure where cursor position in the capture window with '|'.
    target_header = "# inbox", -- will be prepended if it does not exist.
    header_padding = 1, -- padding between capture content and target header.
  },
})
```

#### Journal example

You can turn a capture file into a journal by using dynamic headers. This setup automatically groups your notes under a heading for the current day.

```lua
require("memo").register_capture({
  capture_file = "journal.md.gpg",
  capture_template = {
    target_header = "# " .. os.date("%Y-%m-%d"),
    header_padding = 1,
  },
})
```

Or create a journal file for each day automatically.

```lua
require("memo").register_capture({
  capture_file = "journals/" .. os.date("%Y-%m-%d") .. ".md.gpg",
  capture_template = {
    target_header = "# " .. os.date("%Y-%m-%d"),
    header_padding = 1,
  },
})
```

#### Keybindings

```lua
vim.keymap.set("n", "<leader>mc", function()
  require("memo").register_capture({ capture_file = "inbox.md.gpg" })
end, { desc = "Memo: Quick Capture" })
```

A visual selection is detected automatically: select text in visual mode (or select then leave visual mode) and call `register_capture` — the selected lines are pre-filled into the capture window.

```lua
vim.keymap.set("v", "<leader>mc", function()
  require("memo").register_capture({ capture_file = "inbox.md.gpg" })
end, { desc = "Memo: Quick Capture selection" })
```

or as keys with **lazy.nvim** package manager

```lua
{
  "<leader>mc",
  function()
    require("memo").register_capture({
      capture_file = "inbox.md.gpg",
    })
  end,
  desc = "Capture to inbox",
},
```

### Fzf lua pickers

memo.nvim provides a built-in picker to quickly browse and open your encrypted files. It leverages `require("fzf-lua").files` while scoping the search to your configured notes directory (or your encrypted scratch files). The scratch picker additionally binds `ctrl-x` to delete the selected scratch files (multi-select with `tab`) without closing the picker.

#### Usage

```lua
  require("memo.pickers.fzf_lua").files_picker()          -- notes dir
  require("memo.pickers.fzf_lua").scratch_files_picker()  -- scratch dir
```

#### Keybinding example

```lua
vim.keymap.set("n", "<leader>mf", function()
  require("memo.pickers.fzf_lua").files_picker()
end, { desc = "Memo: file picker" })

vim.keymap.set("n", "<leader>mFs", function()
  require("memo.pickers.fzf_lua").scratch_files_picker()
end, { desc = "Memo: scratch files picker" })
```

or as keys with **lazy.nvim** package manager

```lua
{
  "<leader>mf",
  function()
    require("memo.pickers.fzf_lua").files_picker()
  end,
  desc = "Memo: file picker",
},
{
  "<leader>mFs",
  function()
    require("memo.pickers.fzf_lua").scratch_files_picker()
  end,
  desc = "Memo: scratch files picker",
},
```

## User commands

| Command            | Lua function                | Description                                                            |
| ------------------ | --------------------------- | ---------------------------------------------------------------------- |
| `:MemoScratch`     | `require("memo").scratch()` | Opens a new encrypted scratch buffer, durable across sessions.         |
| `:MemoScratchFiles` | `require("memo.pickers.fzf_lua").scratch_files_picker()` | Browse and open encrypted scratch files.          |
| `:MemoSaveAsNote`  | `require("memo").save_as_note()` | Prompts for a note path (defaults to `<notes_dir>/<name>.gpg`) and encrypts the current buffer there. |
| `:MemoSetup`       | `require("memo").setup()`   | Initializes configuration and registers required autocmds.             |
| `:MemoSync`        | require("memo").sync_git()  | Calls `memo sync git` to trigger a synchronisation of the git backend. |

## Development

This project uses a Makefile to automate setup and testing. Development is primarily supported via Docker to ensure a consistent, isolated environment.

### Prerequisites

Make sure the following dependencies are installed before building or testing:

- [memo](https://github.com/ldonnez/memo)
- [Docker](https://www.docker.com/)

### Dev setup

- Installs **mini.nvim** test for supporting the test suite
- Installs **memo**
- Installs **emmylua_check** from [emmylua-analayzer-rust](https://github.com/EmmyLuaLs/emmylua-analyzer-rust)

```bash
make dev
```

### Docker workflow (recommended)

The project supports Docker for isolated builds and tests.

- Build the image

  ```bash
  make docker/build-image
  ```

- Launch a Bash shell inside the container with the project directory mounted at /opt.

> [!NOTE]
> Your locally installed version of memo is mounted inside the shell.

```bash
make docker/shell
```

### Run tests

Tests can be executed either locally (if your environment is set up) or inside the Docker container. We use mini.test for our test suite.

```bash
make test
```

## [License](LICENSE)

MIT License

Copyright (c) 2025 Lenny Donnez
