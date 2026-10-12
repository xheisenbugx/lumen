# News

What changed for you, newest first. `:Lumen update` shows the sections newer than the version you
were running, and `:Lumen news` shows them all.

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
