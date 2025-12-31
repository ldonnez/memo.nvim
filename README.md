# memo.nvim

Seamless Neovim interface for [memo](https://github.com/ldonnez/memo) a CLI-based system featuring transparent GPG encryption.
`memo.nvim` bridges the gap between secure file management and your editing workflow, allowing you to create, read, and update encrypted files without ever leaving your editor.

---

<a href="https://github.com/ldonnez/memo.nvim/actions"><img src="https://github.com/ldonnez/memo.nvim/actions/workflows/ci.yml/badge.svg?branch=main" alt="Build Status"></a>
<a href="http://github.com/ldonnez/memo.nvim/releases"><img src="https://img.shields.io/github/v/tag/ldonnez/memo.nvim" alt="Version"></a>
<a href="https://github.com/ldonnez/memo.nvim?tab=MIT-1-ov-file#readme"><img src="https://img.shields.io/github/license/ldonnez/memo.nvim" alt="License"></a>

## Table of Contents

- [Installation with example configuration](#installation-with-default-configuration)
  - [Install with lazy.nvim](#install-with-lazynvim)
- [Features](#features)
  - [Transparant editing](#transparant-editing)
  - [Capture workflow](#capture-workflow)
  - [Fzf lua picker](#fzf-lua-picker)
- [Requirements](#requirements)
- [User commands](#user-commands)
- [Development](#development-guide)
  - [Prerequisites](#prerequisites)
  - [Dev setup](#dev-setup)
  - [Docker workflow](#docker-workflow-recommended)
  - [Run tests](#run-tests)
- [License](#License)

## Installation with default configuration

### Install with [lazy.nvim](https://lazy.folke.io/)

```lua
{
  "ldonnez/memo.nvim",
  event = { "VeryLazy" },
  opts = {
    notes_dir = "~/notes",
  },
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
        require("memo").fzf_lua_picker()
      end,
      desc = "Fzf lua picker",
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

### Fzf lua picker

memo.nvim provides a built-in picker to quickly browse and open your encrypted files. It leverages `require("fzf-lua").files` while scoping the search your configured notes directory.

#### Usage

```lua
  require("memo").fzf_lua_picker()
```

#### Keybinding example

```lua
vim.keymap.set("n", "<leader>mf", function()
  require("memo").fzf_lua_picker()
end, { desc = "Memo: file picker" })
```

or as keys with **lazy.nvim** package manager

```lua
{
  "<leader>mf",
  function()
    require("memo").fzf_lua_picker()
  end,
  desc = "Memo: file picker",
},
```

## Requirements

- Neovim >= 0.11.0
- [memo](https://github.com/ldonnez/memo)
- GPG

## User commands

| Command      | Lua function               | Description                                                            |
| ------------ | -------------------------- | ---------------------------------------------------------------------- |
| `:MemoSetup` | `require("memo").setup()`  | Initializes configuration and registers required autocmds.             |
| `:MemoSync`  | require("memo").sync_git() | Calls `memo sync git` to trigger a synchronisation of the git backend. |

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
