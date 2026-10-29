# memo.nvim

Seamless Neovim interface for [memo](https://github.com/ldonnez/memo), a CLI-based notes system with transparent GPG encryption. Create, read, and update encrypted files without leaving your editor.

- Transparent encryption: `.asc` files in your notes directory are decrypted into the buffer and re-encrypted on write; plaintext never touches disk.
- Passphrase-mode encryption for notes, refile targets, and scratch buffers.
- One encrypted scratch buffer per directory for throwaway, sensitive content.
- Quick refile workflow that appends to a refile target (e.g. a journal).
- Archive selected text into companion encrypted archive files.
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
    vim.g.memo_default_refile_target = "journal.md.asc" -- default: inbox.md.asc
  end,
  keys = {
    {
      mode = { "n", "v" },
      "<leader>mc",
      function()
        require("memo").refile({
          template = "## ${date:%Y-%m-%d} ${time:%H:%M}\n\n${cursor}\n",
          padding = { top = 1, bottom = 1 },
        })
      end,
      desc = "Memo: Refile to braindump",
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
      desc = "Memo: Open default refile target",
    },
    {
      "<leader>ms",
      function()
        require("memo").scratch({ window = { split = "split" } })
      end,
      desc = "Memo: Scratch horizontal",
    },
    {
      "<leader>mv",
      function()
        require("memo").scratch({ window = { split = "vsplit" } })
      end,
      desc = "Memo: Scratch vertical",
    },
    {
      "<leader>mt",
      function()
        require("memo").scratch({ window = { split = "tab" } })
      end,
      desc = "Memo: Scratch tab",
    },
    {
      "<leader>mP",
      function()
        require("memo").scratch({ encryption = { mode = "passphrase" } })
      end,
      desc = "Memo: Scratch (passphrase)",
    },
    {
      mode = { "n", "v" },
      "<leader>mC",
      function()
        require("memo").refile({
          target_header = "# " .. os.date("%Y-%m-%d"),
          encryption = { mode = "passphrase" },
        })
      end,
      desc = "Memo: Refile to braindump (passphrase)",
    },
    {
      "<leader>mp",
      function()
        require("memo.pickers.fzf_lua").scratch_files()
      end,
      desc = "Memo: Scratch files",
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
      mode = "x",
      "<leader>ma",
      function()
        require("memo").archive()
      end,
      desc = "Memo: Archive selected text",
    },
    {
      "<leader>mf",
      function()
        require("memo.pickers.fzf_lua").files()
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
`g:memo_default_refile_target` is the destination used by `refile()` when
no path prompt is requested, and `<leader>mo` opens the very same note. The
three pickers need [fzf-lua](https://github.com/ibhagwan/fzf-lua).

### vim.pack

Set configuration before loading the plugin.

```lua
vim.g.memo_notes_dir = "~/my-notes-dir" -- default: ~/notes
vim.g.memo_scratch_dir = "~/.local/state/memo-scratch" -- default: stdpath("data")/memo-scratch
vim.g.memo_default_refile_target = "journal.md.asc" -- default: inbox.md.asc

vim.pack.add({
  { src = "https://github.com/ldonnez/memo.nvim", version = vim.version.range("*") },
})

vim.keymap.set({ "n", "v" }, "<leader>mc", function()
  require("memo").refile({
    target_header = "# " .. os.date("%Y-%m-%d"),
    padding = { top = 1 },
  })
end, { desc = "Memo: Refile to braindump" })

vim.keymap.set("n", "<leader>mo", function()
  require("memo").open({
    window = {
      split = "vsplit",
    },
  })
end, { desc = "Memo: Open default refile target" })

vim.keymap.set("n", "<leader>ms", function()
  require("memo").scratch({ window = { split = "split" } })
end, { desc = "Memo: Scratch horizontal" })

vim.keymap.set("n", "<leader>mv", function()
  require("memo").scratch({ window = { split = "vsplit" } })
end, { desc = "Memo: Scratch vertical" })

vim.keymap.set("n", "<leader>mt", function()
  require("memo").scratch({ window = { split = "tab" } })
end, { desc = "Memo: Scratch tab" })

vim.keymap.set("n", "<leader>mP", function()
  require("memo").scratch({ encryption = { mode = "passphrase" } })
end, { desc = "Memo: Scratch (passphrase)" })

vim.keymap.set({ "n", "v" }, "<leader>mC", function()
  require("memo").refile({
    target_header = "# " .. os.date("%Y-%m-%d"),
    encryption = { mode = "passphrase" },
  })
end, { desc = "Memo: Refile to braindump (passphrase)" })

vim.keymap.set("n", "<leader>mp", function()
  require("memo.pickers.fzf_lua").scratch_files()
end, { desc = "Memo: Scratch files" })

vim.keymap.set({ "n", "v" }, "<leader>mS", function()
  require("memo").save_as_note()
end, { desc = "Memo: Save as note" })

vim.keymap.set("x", "<leader>ma", function()
  require("memo").archive()
end, { desc = "Memo: Archive selected text" })

vim.keymap.set("n", "<leader>mf", function()
  require("memo.pickers.fzf_lua").files()
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

### `g:memo_default_refile_target`

The note `:Memo` and `require("memo").open()` open when no path is given, and
the destination `require("memo").refile()` writes to by default. A path
relative to `<notes_dir>`, with or without a note extension.

- Default: `inbox.md.asc`.

```lua
vim.g.memo_default_refile_target = "inbox.md.asc"
```

A subdirectory keeps refile entries out of the way, and the extension is optional:

```lua
vim.g.memo_default_refile_target = "quick/inbox.md.asc"
```

The first refile creates the note and any missing parent directories;
`:Memo` reports an error until then, since there is nothing to open yet.

Read the default back with `:Memo` or `require("memo").open()`:

```lua
vim.keymap.set("n", "<leader>mo", function()
  require("memo").open()
end, { desc = "Memo: Open the default refile target" })
```

Pair it with `target_header` and one note becomes a dated journal, with
`<leader>mc` writing to it and `:Memo` opening it:

```lua
vim.g.memo_default_refile_target = "journal.md.asc"
```

```lua
vim.keymap.set({ "n", "v" }, "<leader>mc", function()
  require("memo").refile({
    target_header = "# " .. os.date("%Y-%m-%d"),
    padding = { top = 1 },
  })
end, { desc = "Memo: Refile to today" })
```

Set `prompt_path = true` on `refile()` when you want to choose a destination
for an individual operation. `:MemoNewNote <path>` has its own explicit path.

### `g:memo_extension`

Extension used for new notes, the encrypted extension of new scratch buffers,
and notes saved from a buffer whose path has no note extension yet. `.asc`
(armored ASCII) and `.gpg` are both read, and any other value is read as
well, so the extension you pick is always recognized on the way back in.

- Default: `asc`

```lua
vim.g.memo_extension = "gpg"
```

An existing note always keeps its own extension. A `note.md.gpg` note opens, decrypts, and is
written back to `note.md.gpg` even with the `asc` default.

Paths in `g:memo_default_refile_target` and note paths passed to
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

| Command             | Description                                        |
| ------------------- | -------------------------------------------------- |
| `:Memo`             | Open the default refile target.                     |
| `:MemoScratch`      | Open or create the scratch buffer for the cwd.     |
| `:MemoNewNote`      | Create a new encrypted note in the notes dir.      |
| `:MemoScratchFiles` | Browse and open encrypted scratch files.           |
| `:MemoSaveAsNote`   | Save the buffer or selection as an encrypted note. |
| `:MemoArchive`      | Move the selection into the note archive.          |
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

### Notes encrypted with a passphrase

A note encrypted symmetrically, with `gpg --symmetric` instead of a key, opens
without needing a key in the keyring:

- Opening one prompts for the passphrase of that file, e.g. `GPG Passphrase for
note inbox.md.asc (symmetric):`.
- Writing it back encrypts it with the same passphrase, so it stays
  symmetric instead of being re-encrypted to your key. The passphrase is kept
  in the buffer, so it is entered once per buffer rather than once per write.
- Reading and writing them goes through `memo encrypt --symmetric` and
  `memo decrypt`, so a note is exactly what the CLI writes. The passphrase is
  handed over on stdin, so it never reaches the command line, the environment
  or the disk.
- A wrong passphrase reports a decryption failure and the buffer is dropped.
- The passphrase lives in `b:memo_symmetric_passphrase` for the life of the
  buffer. Avoid `:mksession` with `sessionoptions` containing `globals`, which
  would write it out.

The [memo CLI](https://github.com/ldonnez/memo) creates these notes with
`memo encrypt --symmetric`, and keeps them symmetric when you open them with
`memo FILE`, so both tools can work on the same notes.

A new note, refile target, or scratch buffer encrypts with your key unless the
passphrase mode is configured. The passphrase is confirmed when creating a new
note or refile target; the note is only created once it is confirmed.

Both commands take it as an argument and complete to `passphrase` and
`key`, which is the default:

```vim
:MemoNewNote passphrase journals/2026-01-01.md
:MemoSaveAsNote passphrase
```

```lua
require("memo").new_note({
  path = "journals/2026-01-01.md",
  encryption = { mode = "passphrase" },
})

require("memo").save_as_note({
  encryption = { mode = "passphrase" },
})

require("memo").refile({
  prompt_path = true,
  encryption = { mode = "passphrase" },
})

require("memo").scratch({
  encryption = { mode = "passphrase" },
})
```

Or map them:

```lua
vim.keymap.set("n", "<leader>mp", function()
  require("memo").new_note({ encryption = { mode = "passphrase" } })
end, { desc = "Memo: New passphrase note" })

vim.keymap.set({ "n", "v" }, "<leader>mP", function()
  require("memo").save_as_note({ encryption = { mode = "passphrase" } })
end, { desc = "Memo: Save buffer as passphrase note" })

vim.keymap.set({ "n", "v" }, "<leader>mC", function()
  require("memo").refile({
    prompt_path = true,
    encryption = { mode = "passphrase" },
  })
end, { desc = "Memo: Refile passphrase note" })
```

An existing note keeps its encryption: writing it or refiling into it does
not switch a passphrase note to key encryption, or the other way around. The
mode option picks the encryption of a new note only.

Passphrases for key-encrypted notes are handed straight to gpg-agent with
`--pinentry-mode=loopback`, so no pinentry program pops up. gpg-agent caches
that passphrase for its `default-cache-ttl` (10 minutes by default); raise it
in `~/.gnupg/gpg-agent.conf` to be prompted less, e.g. `default-cache-ttl
86400`.

memo.nvim remembers a key as unlocked for ten minutes, matching gpg-agent's
own default, so browsing from one note to the next does not re-probe the
agent each time. gpg-agent stays the real gate: if a decrypt fails,
the cached answer is dropped and the next attempt asks again.

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

Open an encrypted scratch buffer for throwaway, sensitive content. Each
directory has one scratch file at a fixed path: the first call creates it, and
later calls reopen the same file, including any unsaved content:

```lua
vim.keymap.set("n", "<leader>ms", function()
  require("memo").scratch({ window = { split = "split" } })
end, { desc = "Memo: Scratch buffer (horizontal split)" })

vim.keymap.set("n", "<leader>mv", function()
  require("memo").scratch({ window = { split = "vsplit" } })
end, { desc = "Memo: Scratch buffer (vertical split)" })

vim.keymap.set("n", "<leader>mt", function()
  require("memo").scratch({ window = { split = "tab" } })
end, { desc = "Memo: Scratch buffer (new tab)" })
```

The window config accepts the same `split`, `size` and `position` fields as
`require("memo").new_note()`: `{ split = "split" | "vsplit" | "tab",
size = 0.5, position = "botright" }`. A scratch always opens a window, the
default is a horizontal split next to the current one. When creating the
scratch file, pass `encryption = { mode = "passphrase" }` to encrypt with a
passphrase instead of your key:

```lua
vim.keymap.set("n", "<leader>mP", function()
  require("memo").scratch({
    encryption = { mode = "passphrase" },
  })
end, { desc = "Memo: New passphrase scratch buffer" })
```

Give the scratch a content extension with `extension`, e.g. `md` for a
Markdown buffer. The note extension still follows it, so the file becomes
`<cwd-key>-scratch.md.<note extension>`:

```lua
require("memo").scratch({ extension = "md" })
```

Like the encryption mode, `extension` only applies when the scratch file is
first created.

Or use the command `:MemoScratch [passphrase|key] [split|vsplit|tab]`, e.g.
`:MemoScratch passphrase vsplit`. The encryption mode only applies when the
scratch file is first created.

Notes:

- Files are stored encrypted in `g:memo_scratch_dir` as `<cwd-key>-scratch[.<content extension>].<note extension>`, one per `cwd`, so buffers from different projects never collide.
- Pass `extension = "md"` when first creating a scratch to give it a content extension and filetype.
- The buffer reuses the regular memo read/write autocommands, so files persist across restarts and sessions (e.g. [auto-session](https://github.com/rmagatti/auto-session)).
- Use `ctrl-x` in the scratch picker to delete scratch files.

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

### Templates

`refile()`, `new_note()` and `archive()` accept a `template` that
prefills the buffer. Placeholders use the form `${name}` or
`${name:format}` and are expanded when the buffer opens.

- `${cursor}`: insertion point. The first occurrence is removed and
  sets the cursor. With a selection, the selection is inserted there;
  later occurrences stay literal.
- `${date}`: current local date, `YYYY-MM-DD`.
- `${datetime}`: current local date and time, `YYYY-MM-DD HH:MM`.
- `${timestamp}`: Org-style date, `<YYYY-MM-DD Day>`.
- `${timestamp:time}`: Org-style date and time,
  `<YYYY-MM-DD Day HH:MM>`.
- `${date:FORMAT}`: local date using an `os.date()` format, for
  example `${date:%Y-%m-%d}`.
- `${time:FORMAT}`: local time using an `os.date()` format, for
  example `${time:%H:%M}`.
- `${clipboard}`: clipboard contents, preferring the `*` register and
  falling back to `+` when empty.
- `${yank}`: contents of the unnamed register.
- `${filename}`: source file name, including its extension.
- `${filepath}`: source file path.
- `${capture}`: Markdown link to the source file at the source line.

The filename, filepath and capture placeholders are empty when no
source file is available. Unknown placeholders are left unchanged.

In Lua strings, escape a placeholder with `\\` to keep it literal:
`"\\${date}"` produces `${date}`, and `"\\\\"` produces one literal
backslash.

### Archive selected text

Use a Visual-mode mapping or `require("memo").archive()` to move a selection
into a companion archive file. Character-wise, line-wise, and block-wise
selections are supported. The `:MemoArchive` command archives its line range.
The buffer must be in the notes directory.

For example, `projects/plan.md.asc` is archived to
`projects/plan.archive.md.asc`, and `projects/plan.md` to
`projects/plan.archive.md.asc`. Every archive is GPG-encrypted, including
archives created from plaintext notes. Entries are appended as-is, separated
by a blank line, and existing entries are retained.

Pass `template` to add metadata or formatting around an entry. The archived
lines are inserted at the template's `${cursor}` marker, or appended after
the template when there is no marker. Templates use the placeholders
described in "Templates" above.

The operation is also available through `require("memo").archive()`.
When called from a Visual-mode mapping, it detects the active selection, so no
options are needed:

```lua
vim.keymap.set("x", "<leader>ma", function()
  require("memo").archive()
end, { desc = "Memo: Archive selected text" })
```

When calling the function outside Visual mode, pass `range = 1`, `line1`, and
`line2` to archive a line range:

```lua
require("memo").archive({ range = 1, line1 = 2, line2 = 4 })
```

Add a timestamp and source path with a template:

```lua
require("memo").archive({
  range = 1, line1 = 2, line2 = 4,
  template = "\n---\n\nArchived ${date:%Y-%m-%d}\n"
    .. "Source: ${filename}\n\n${cursor}",
})
```

### Refile selected text

Move or copy a selection into another note, or create a new entry, with
`:MemoRefile` or `require("memo").refile()`. An editable window opens with
the selected text when a selection exists; without a selection it opens an
empty or template-filled entry.

Write the window to save to `g:memo_default_refile_target`; set
`prompt_path = true` to choose a different destination. Content is appended
by default, or prepended with `prepend = true`. The original selection is
kept by default. Set `remove_from_source = true` to remove it after a
successful write instead of copying.

If the destination does not exist, it is created. Existing notes keep their
encryption mode. Use `padding` to configure blank lines before and after the
moved content. A `template` can add context around new or selected content;
see "Templates" above. Without a `${cursor}` marker, a selection becomes the
entire initial content.

New destinations use key encryption by default; set
`encryption.mode = "passphrase"` to use passphrase encryption. Existing
destinations keep their current encryption mode.

```lua
require("memo").refile({
  prompt_path = true,
  template = "## ${date:%Y-%m-%d}\n\n- ${cursor}\n",
  padding = { top = 1, bottom = 1 },
  encryption = { mode = "passphrase" },
})
```

```lua
vim.keymap.set("x", "<leader>mr", function()
  require("memo").refile({ padding = { top = 1, bottom = 1 } })
end, { desc = "Memo: Refile selected text" })
```

The command also accepts a line range, e.g. `:'<,'>MemoRefile`. Paths are
resolved relative to the notes directory and cannot escape it.

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
`g:memo_default_refile_target`, which is also the default refile destination:

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
  lines are inserted at the template's `${cursor}` marker. A template
  without a marker has nowhere to insert, so the selection becomes the whole
  note.
- Missing parent directories are created. An existing note is only replaced
  after you confirm the overwrite.
  `:MemoFiles` right away.

A template can be passed to prefill the note. Templates accept the
placeholders described in "Templates" above, including a `${cursor}` marker
that is removed and used as the cursor position:

```lua
require("memo").new_note({
  path = "meetings/2026-01-01.md",
  template = "# ${date:%Y-%m-%d}\n\nAttendees:\n- ${cursor}\n\nNotes:\n",
})
```

A `window` opens the note in a split, with the same options
`require("memo").refile()` takes. Every option has a default, so `split`
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
the `${cursor}` marker and the cursor lands right after the inserted
selection. For example, selecting `Ada Lovelace` with
`"## Agenda\n- ${cursor} (carried over)"` produces `## Agenda` followed by
`- Ada Lovelace (carried over)`. Without a marker there is nowhere to insert,
so the selection becomes the whole note.

Notes in subdirectories are opened and written transparently, so nested paths
such as `journals/2026-01-01.md.asc` behave like top-level notes.

### Quick refile

Use the same `refile()` workflow to create a new entry or move/copy a
selection. Without a selection it opens a blank or template-filled entry;
writing saves it to `g:memo_default_refile_target`. Use `target_header` to
insert below a specific header, or `prompt_path = true` to choose a
destination. With `target_header`, `padding.top` controls spacing after the
header and `padding.bottom` controls spacing after the entry. Blank lines
already at the edges of the selected content count toward that padding, and
existing content remains separated by at least one blank line.

```lua
vim.keymap.set("n", "<leader>mc", function()
  require("memo").refile({
    target_header = "# inbox", -- content is inserted below this header
    padding = { top = 1, bottom = 1 }, -- blank lines above and below the content
    template = "## ${date:%Y-%m-%d} ${time:%H:%M}\n\n${cursor}\n", -- ${cursor} marks the insertion point
    window = {
      split = "split", -- "split" (default) | "vsplit"
      size = 0.5, -- a share of the screen, 0 to 1; defaults to 0.5
      position = "botright", -- "botright" (default) | "topleft" | "leftabove" | "rightbelow"
    },
  })
end, { desc = "Memo: Quick refile" })
```

A visual selection is detected automatically: select text in visual mode and
call `require("memo").refile()` to pre-fill the refile window:

```lua
vim.keymap.set("v", "<leader>mc", function()
  require("memo").refile()
end, { desc = "Memo: Quick refile selection" })
```

With a template that has `${cursor}`, the selection is inserted at that
marker instead of replacing the template. A template without a marker has
nowhere to insert, so the selection becomes the whole initial content.
Without a selection, the template is used as-is.

Turn the default refile target into a journal with dynamic headers:

```lua
require("memo").refile({
  target_header = "# " .. os.date("%Y-%m-%d"),
  padding = { top = 1 },
})
```

### fzf-lua pickers

memo.nvim includes pickers built on `require("fzf-lua").files` that scope the search to your notes directory or your encrypted scratch files.

```lua
require("memo.pickers.fzf_lua").files()         -- notes directory
require("memo.pickers.fzf_lua").scratch_files() -- all scratches
```

The scratch picker additionally binds `ctrl-x` to delete the selected scratch
files (multi-select with `tab`/`alt-a`) without closing the picker; any buffer
holding a deleted file is wiped too.

Each picker can show a preview pane with the decrypted note, off by default. Pass `{ previewer = true }` to turn it on:

```lua
require("memo.pickers.fzf_lua").files({ previewer = true })
```

When the note is already open in a buffer the pane previews the buffer; otherwise it is decrypted asynchronously, so the picker stays responsive while the plaintext streams in. A decrypt is given 30 seconds before it is abandoned. Moving to another note abandons an in-flight decrypt, and a note's decrypted preview is reused so revisiting it does not decrypt again. The encrypted bytes on disk are never shown.

Scratch files are stored under the obfuscated name `<encoded-cwd>-scratch[.<content extension>].<ext>`, so the scratch picker decodes the cwd path for display and shows `<cwd-path>-scratch[.<content extension>].<ext>`.

## Development

- `make dev` — install dev dependencies (mini.nvim, memo, emmylua_check) and symlink the plugin into `~/.local/share/nvim/site/pack/local/opt`.
- `make test` — run the test suite locally (requires `make deps/memo` and `~/.local/bin` on `PATH`).
- `make test_file FILE=tests/test_gpg.lua` — run a single test file locally.
- `make emmylua_check` — Lua type check.

### Docker workflow (recommended)

- `make docker/build-image` — build the image.
- `make docker/shell` — drop into a shell with the project mounted at `/opt` and your local `memo` binary available.
- `make docker/test` / `make docker/test_file FILE=tests/test_gpg.lua` — run tests inside the Docker image directly.

## License

MIT License

Copyright (c) 2025 Lenny Donnez
