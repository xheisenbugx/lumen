# News

What changed for you, newest first. `:Lumen update` shows the sections newer than the version you
were running, and `:Lumen news` shows them all.

## 0.5.2

- **Remembered toggles hold in org files (and other plugin filetypes).** org.nvim's indent mode turns
  `wrap` on every time an org buffer is shown, after Lumen had re-applied your pick. Lumen now
  re-applies it once filetype plugins are done, in every window showing the buffer.

## 0.5.1

- **Toggles you flip in markdown, text or gitcommit buffers are remembered.** Lumen turns `wrap`
  and `spell` on for prose filetypes, so turning wrap off in a markdown file matched the global
  value and wasn't saved; the next start turned it back on. A wrap, spelling, conceal or relative
  number toggle over a value the filetype set is now remembered for that filetype.

## 0.5.0

- **Lumen remembers what you pick.** The colorscheme (`<leader>uC`, night / dawn with `<leader>ub`),
  the `<leader>u` toggles (wrap, spelling, line numbers, conceal, diagnostics, format on save,
  indent guides, smooth scroll, inlay hints, auto pairs, git signs, inline blame) and the
  diagnostics display (`<leader>uv`) now survive a restart. Change that setting in your config and
  the config wins again. `:Lumen forget` drops everything you picked, and `remember = false` turns
  it off.

## 0.4.0

- **The `yazi` pack replaces the explorer.** With it enabled, `<leader>e` opens yazi at the project
  root and `<leader>E` at the cwd, the Snacks explorer sidebar is turned off, and yazi opens
  directories (`nvim .`, `:e some/dir`). `<leader>y` still opens yazi at the current file;
  `<leader>Y` is gone (it's `<leader>E` now).

## 0.3.2

- **`<C-/>` hides the terminal that's shown, from any window.** With the terminal on screen and
  the cursor in another window whose root differs (a scratch buffer, the explorer, a root the LSP
  found since), it opened a second terminal next to the first.

## 0.3.1

Fixes from a full audit, plus a test that presses every keymap Lumen defines.

- **`<C-/>` no longer opens a second terminal** when you press it inside the terminal while
  Neovim's cwd isn't the project root: it hides the terminal you're in, as it should.
- **Colorschemes:** switching from Lumen to a scheme that sets 'background' while it loads
  (habamax, slate…) no longer snaps back to Lumen.
- **Keymaps:**
  - `<leader>?` (buffer keymaps) no longer errors when it's the key that loads which-key.
  - `<leader>xt` (todos in Trouble) works: it needed plenary.nvim, which Lumen now installs
    (loaded only when used).
  - `]]` / `[[` are normal-mode only: in terminals they ate `[[` / `]]` typed into the shell and
    slowed down every `[` / `]` (lazygit tabs).
  - `]q` `[q` `]b` `[b` `]d` `[d` `]e` `[e` `]w` `[w` take a count (`3]d`), and `]q` on an empty
    list shows a plain `E42` instead of a Lua traceback.
  - `<A-j>` / `<A-k>` on the last / first line no longer error.
  - `<leader>up`, `<leader>uG` and `<leader>uB` exist from startup, not only once their plugin
    has loaded; `:TodoQuickFix` and `:TodoLocList` load todo-comments.
  - `<leader>mw` works in visual-block mode, and its message points at `<leader>mc` (Lumen's
    `<C-l>` moves to the right window, it doesn't clear cursors).
  - `]d` and friends no longer print "opts.float is deprecated" on every jump (Neovim 0.12+).
  - `<leader>gg` without lazygit installed says so, instead of a Lua error.
- **UI:**
  - Inactive windows' winbar no longer shows the file name as active.
  - Breadcrumbs refresh after edits made while a symbol request was in flight, and in a buffer
    you leave right after editing.
  - Breadcrumbs and crumb clicks use the server's offset encoding (non-ASCII lines, clangd).
  - Folded comments keep their color.
  - The scrollbar's search marks respect 'smartcase'.
  - Lumen's statusline stays in the quickfix window.
  - The search count shows `>999` instead of a wrong exact number.
  - Diagnostics turned off with `<leader>ud` also leave the statusline and scrollbar.
- **Updates:**
  - The stable channel no longer crashes on a plugin you disabled.
  - The stable channel no longer overrides a plugin spec's own `commit`, `tag`, `pin` or
    `version`.
  - Snapshots follow lazy.nvim's `lockfile` option.
  - The verification Neovim no longer starts installs it would leave half-done.
- **Mason:**
  - Language servers install on the very first launch: they used to wait for a restart.
  - A package two packs share installs once.
  - An unreachable registry is reported as such, not as "unknown package".
- **Tasks:**
  - Quickfix paths resolve against the task's folder.
  - Background tasks use 'shellcmdflag'.
  - Script names with spaces are quoted.
  - A malformed entry in `tasks = {}` is skipped with a warning instead of crashing the picker.
- **Project settings:** `:Lumen trust` trusts the buffer you reviewed, not a newer file on disk.
  `:Lumen packs disable` says why a pack stays on (another pack extends it, or `.lumen.lua`).
- **Other:**
  - `:Lumen why` survives a linter definition that throws.
  - `install.sh --repo` only accepts `owner/name`.

## 0.3.0

- **Packs turn on without a restart.** Enabling a pack that only configures servers, parsers,
  Mason tools, formatters and linters applies it to the running Neovim. Packs that add plugins
  (and disabling a pack) still ask for a restart.
- **Pack suggestions don't interrupt you.** Opening a file of a language you haven't enabled shows
  a notification instead of a prompt: `:Lumen packs enable <name>` turns it on,
  `:Lumen packs dismiss <name>` stops the suggestion.
- **Packs say what they need.** A new `requires` field lists toolchains Mason can't install (`go`,
  `cargo`, `java`, `node`…). Missing ones show in `:checkhealth lumen`, `:Lumen why` and the
  suggestion.
- **Packs build on each other.** A new `extends` field enables other packs along with a pack:
  `vue` and `astro` now extend `typescript`.
- **Per-project settings.** A `.lumen.lua` in a project adds packs and tasks and overrides
  settings for that project, once you trust it (`:Lumen project`, `:Lumen trust`).
- **Tasks:** `.vscode/tasks.json` tasks show up in the task picker, and `<leader>rw` watches the
  last task: it re-runs in the background on every save in its folder.
- **Safer updates.** The check after `:Lumen update` waits for parsers to finish updating and also
  catches errors Neovim prints (Lua errors in autocmds and callbacks). A rollback brings parsers
  back in line with the restored nvim-treesitter.
- **Help:** `:help lumen`.
- `:Lumen doctor json` replaces your home directory with `~`, including in log lines and roots.
- Fixes: language servers installed by Mason attach to open files through `vim.lsp.enable`
  instead of an internal Neovim augroup; servers with a function `cmd` no longer trigger a Mason
  check on every start; the vue pack finds the Vue TypeScript plugin under a custom Mason
  `install_root_dir`; nvim-lint no longer resolves linters on every `InsertLeave`; closing a
  utility window right after it opens no longer leaves an error.
