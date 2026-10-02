# AGENTS.md

Guide for AI coding agents (and humans) working on Lumen. Read it before you change anything.

## What Lumen is

Lumen is a Neovim distribution packaged as a **lazy.nvim plugin**, the same way LazyVim is. A user's
`~/.config/nvim` is a small starter (`starter/`) whose `init.lua` bootstraps lazy.nvim and imports
`{ "<source>", name = "lumen", import = "lumen.plugins" }`. Lumen provides options, keymaps, a
built-in theme (`lumen`, `lumen-night`, `lumen-dawn`), its own UI with no plugin dependencies
(statusline, tabline, winbar, scrollbar, fold text), native LSP setup, declarative language packs,
a task runner and `:Lumen update` with snapshot and rollback. It needs Neovim 0.11+ (0.12+ recommended).

## Architecture

Startup has two phases (see the header of `lua/lumen/init.lua`):

1. **`require("lumen").init()`** runs while lazy.nvim imports `lumen.plugins`. lazy sorts modules by
   name, so `lua/lumen/plugins/init.lua` is imported first and calls `init()` before any other spec
   is read. It:
   - loads settings: `lua/lumen/config.lua` merges its defaults with the user's `lua/config/lumen.lua`
     (and the legacy `lua/user/config.lua`, read first);
   - applies `lumen.options`, then the user's `config.options` (and the legacy `user.options`);
   - registers the `LazyFile` event (`BufReadPost`, `BufNewFile`, `BufWritePre`), and
     `User LumenFileIdle`, fired one tick after the first file opens (after it is drawn) for
     plugins that attach to open buffers on their own (gitsigns).
2. **`require("lumen").setup(opts)`** is the `config` of the `lumen` plugin spec (`lazy = false`,
   `priority = 900`, so it runs after snacks.nvim at 1000). It merges the spec's `opts` (`packs` is
   ignored there), then runs the colors compat adapter, the colorscheme, autocmds, keymaps,
   commands and the UI modules. User `config.autocmds` and `config.keymaps` (and the legacy
   `user.*` modules) load last so they win.

Module map (`lua/lumen/`):

| Module | Role |
| --- | --- |
| `init.lua` | `init()` / `setup()` entry points, `version` |
| `config.lua` | defaults, merging user settings, proxy table (`require("lumen.config").accent`) |
| `options.lua` | vim options, leader, `winborder`, ui2 (feature-detected) |
| `keymaps.lua` | core keymaps (plugin keymaps live in their specs) |
| `autocmds.lua` | core autocmds, including the `ensure_filetype` safety net |
| `commands.lua` | `:Lumen` subcommands: packs, health, profile, update, rollback, why, tasks, theme, config, keys |
| `health.lua` | `:checkhealth lumen` |
| `lsp.lua` | `vim.lsp.config`/`vim.lsp.enable`, on_attach keymaps, Mason auto-install |
| `diagnostics.lua` | diagnostic display modes `text` / `lines` / `signs` and cycling between them |
| `packs.lua` + `packs/*.lua` | language packs, their state file, suggestions and the picker |
| `tasks.lua` | task discovery (npm, make, cargo, go…), terminal and background runs, quickfix |
| `why.lua` | `:Lumen why` / `:Lumen doctor` (deep: binaries, Mason, root trace, LSP log, JSON); `<CR>` runs a line's fix |
| `update.lua` | `:Lumen update` (snapshot, stable/latest channel, headless verify) and `:Lumen rollback` |
| `icons.lua` | shared icons |
| `colors/palettes.lua` | night/dawn palettes |
| `colors/theme.lua` | highlight group definitions |
| `colors/compat.lua` | keeps `Lumen*` UI groups styled under non-Lumen colorschemes |
| `colors/init.lua` | `load(variant)`, `blend`, `palette` (used by `colors/lumen*.lua`) |
| `ui/statusline.lua` · `ui/tabline.lua` · `ui/winbar.lua` · `ui/scrollbar.lua` · `ui/fold.lua` | Lumen's own UI, no plugin dependencies |
| `ui/statuscolumn.lua` | windowed sign lookup patched into Snacks' statuscolumn (it otherwise fetches every sign of the buffer on each redraw) |
| `util/init.lua` | the global `Lumen` helpers (`map`, `notify`, `try_require`…) |
| `util/root.lua` | project root detection (LSP, then markers, then cwd), cached per buffer |
| `plugins/*.lua` | lazy.nvim specs: `init` (lumen itself), coding, colorschemes, editor, format, lsp, treesitter, ui, `packs` (pack specs) |

Other top-level pieces:

- `colors/lumen.lua`, `colors/lumen-night.lua`, `colors/lumen-dawn.lua` are the colorscheme entry points.
- `starter/` is the template for a user's config dir: `init.lua` (loads `{ "xheisenbugx/lumen", name = "lumen",
  import = "lumen.plugins" }`), `lua/config/lumen.lua` (settings) and `lua/plugins/example.lua`.
- `install.sh` copies `starter/` into `~/.config/<appname>` (backing up whatever is there). It works from a
  checkout or piped from `curl` (it then clones the repo for the starter). It rewrites the Lumen spec line
  (the one matching `name = "lumen", import = "lumen.plugins"`) for `--repo owner/name` or `--dev` (a `dir =`
  spec pointing at the local checkout). Other flags: `--appname`, `--fresh`, `--help`. It validates values
  before touching anything (`--appname` must be a plain name: an empty one would point at `~/.config`
  itself), renames symlinks instead of removing them, and warns when `rg`, the `tree-sitter` CLI or a C
  compiler is missing. `scripts/env.sh` applies the same `dir =` rewrite to build the test sandbox, so keep
  that line's shape stable.

## Language packs

A pack is a **declarative data table** in `lua/lumen/packs/<name>.lua` (type `lumen.Pack`, defined in
`lua/lumen/packs.lua`). Fields: `desc`, `ft`, `parsers`, `servers`, `tools`, `formatters`,
`formatter_opts`, `linters`, `plugins`, `setup`.

`packs.specs()`, which `lua/lumen/plugins/packs.lua` returns, turns each enabled pack into lazy.nvim
spec fragments that **extend the core specs**: parsers go to nvim-treesitter `ensure_installed`,
servers to nvim-lspconfig `servers`, tools to mason `ensure_installed`, formatters to conform,
linters to nvim-lint, and `plugins` are appended as-is. `setup()` runs at spec time.

- lazy.nvim deep-merges `opts`, and list values are **replaced, not appended**, unless the core spec
  declares `opts_extend`. The core specs declare it for treesitter `ensure_installed`
  (`plugins/treesitter.lua`), mason `ensure_installed` (`plugins/lsp.lua`), which-key `spec`
  (`plugins/ui.lua`) and blink `sources.default` (`plugins/coding.lua`). If you add a new list-valued
  option that packs contribute to, add it to `opts_extend`.
- Enabled packs are `config.packs` (from `lua/config/lumen.lua`), adjusted by `:Lumen packs` state in
  `stdpath("state")/lumen/packs.json`. `packs` in the spec `opts` is ignored because packs are needed
  while specs are built, before any `opts` exist.
- Discovery (`packs.available()`) globs the plugin's **own directory** (via `debug.getinfo`) plus the
  user's `stdpath("config")/lua/lumen/packs/*.lua`. It does not use the runtimepath, because Lumen
  isn't on the rtp yet while lazy imports specs.

**Adding a pack:** copy a small pack such as `packs/go.lua` or `packs/rust.lua`, fill in only the
fields you need, and run `./scripts/test.sh`. **Every name must actually exist:** treesitter parser
names, lspconfig server names that have a Mason mapping (or set `mason = false` on the server), Mason
package names in `tools`, conform formatter names and nvim-lint linter names. The smoke test
"every pack reference resolves" enforces this; "every language pack is well-formed" checks that `ft`,
`parsers`, `tools`, `plugins` and `servers` are tables.

## Testing & tooling

- `./scripts/test.sh` runs the headless smoke suite (`tests/smoke.lua`) in an isolated sandbox built
  from the real `starter/`, with Lumen loaded from this checkout. Run it with **bash** (it's executable;
  `bash scripts/test.sh` also works), never with `sh` or `zsh`, and don't source `scripts/env.sh`
  from zsh: it relies on `BASH_SOURCE`. The sandbox defaults to `.tests/` (gitignored). Set `LUMEN_TEST_DIR=/some/dir` to put
  it elsewhere. The first run installs every plugin, parser and server, so it is slow.
- `./scripts/bench.sh [runs]` prints the median startup time (default 10 runs) for an empty start and for opening a file.
- Formatting: `stylua .` to format, `stylua --check .` to check (`stylua.toml`: 2 spaces, 120 columns).
  `.luarc.json` declares the globals `vim`, `Snacks`, `Lumen` and `MiniIcons`.
- CI (`.github/workflows/ci.yml`) runs `stylua --check .` plus `./scripts/test.sh` on Neovim **stable and nightly**.
- **Stable update channel**: `.github/workflows/stable-lock.yml` runs nightly (and on demand). It
  resolves the newest version of every plugin with all packs enabled (`scripts/vetted-lock.sh resolve`),
  verifies that exact set on stable and nightly Neovim (`scripts/vetted-lock.sh verify`: restore, load
  every plugin, run the suite), and only then commits `lumen-lock.json`. `update.lua` applies it with
  `merge_lock()`: vetted plugins are pinned, plugins only the user has update to latest. Don't hand-edit
  `lumen-lock.json`; run the workflow.

Rules:

- **Every bug fix gets a smoke test** in `tests/smoke.lua` (use `check(name, fn)` and `wait(ms, cond)`).
- Keep the performance budgets green: statusline and tabline render in **< 150 µs**, and scrollbar
  refresh in **< 1 ms**, and a fresh statuscolumn sign lookup in **< 500 µs**, on a 20k-line buffer
  with 3k diagnostics. Keep the **WCAG contrast floor**
  green too (4.5:1 for text colors, 3.5 for `comment`, 2.5 for `gutter`, in both variants).
- **Never test against the user's real dirs** (`~/.config/nvim`, `~/.config/lumen`,
  `~/.local/share/<app>`, `~/.local/state/<app>`, `~/.cache/<app>`) and never run `install.sh`
  for testing. Always use the sandbox, i.e. source `scripts/env.sh` or use the scripts.

## Hard-won lessons / gotchas

- **Never call `vim.lsp.enable()` synchronously after VimEnter from inside a BufReadPost/LazyFile
  chain.** It fires `FileType` for open buffers, which sets `did_filetype()`, so Neovim's `:setf`
  silently skips the buffer being opened. That buffer then gets no filetype, no treesitter and no
  LSP. `lsp.lua` defers the call with `vim.schedule` when `vim.v.vim_did_enter == 1`, and
  `autocmds.lua` (`ensure_filetype`) re-runs `filetype detect` on BufReadPost as a safety net.
  Tests that pass the file on the command line don't catch this. The smoke test "opening a file
  after startup" starts a child Neovim and `:edit`s a file afterwards.
- Use **`vim.go.errorformat`** (global), not `vim.o.errorformat`. `vim.o` returns the current
  buffer's local value, e.g. cargo's from a Rust buffer (see `tasks.lua`).
- **`vim.diagnostic.get()` deep-copies every diagnostic**, about 9 ms for 5k items. Never call it on
  hot paths (scroll, redraw, statusline). Cache per buffer and invalidate on `DiagnosticChanged`,
  as `ui/statusline.lua` and `ui/scrollbar.lua` do.
  **`nvim_buf_get_extmarks()` on an empty namespace still scans the whole mark tree**, about
  0.3 ms on busy buffers, and `limit` doesn't help, so throttle it (see the multicursor counts).
- `vim.ui.select` and `vim.ui.input` are replaced by Snacks only once a UI attaches. In headless
  tests they are Neovim's **blocking** built-ins, so never trigger them from a headless test
  (pack suggestions, `prompt_restart`, `:Lumen` without arguments…).
- `Snacks.win`'s `ft` only adds highlighting; the filetype stays `snacks_win`. Set `bo.filetype`
  when a real filetype is needed, e.g. for render-markdown (see `why.lua`).
- `vim.hl.on_yank` is deprecated on 0.13 in favor of `hl_op` (`autocmds.lua` uses `hl.hl_op or hl.on_yank`).
  Lumen supports 0.11+, so **feature-detect** newer APIs: `vim.api.nvim_mcursor`, `vim._core.ui2`,
  `:restart` (`vim.fn.exists(":restart") == 2`) and `winborder` (`vim.fn.exists("+winborder")`).
- Theme: **UI** highlight groups use `p.accent`; **syntax** groups keep fixed hues, so changing the
  accent never recolors code. The compat adapter (`colors/compat.lua`) re-applies only groups
  matching `^Lumen` (plus `MCursor`) when a non-Lumen colorscheme is active. Never let it touch
  that scheme's own groups.
- **Nerd Font glyphs can be silently stripped by editing tools.** Private-use glyphs
  (U+E000–U+F8FF, 3-byte UTF-8) may vanish when written through some file-editing tools. Insert
  them by code point (Python `chr(0xF00D)` or Lua `"\u{f00d}"`) and check the bytes with `od -c`.
  4-byte glyphs (U+F0000 and above) survive.
- lazy.nvim: a spec with only `name = "x"` is invalid. A bare short name such as `{ "lumen", ... }`
  refers to an existing plugin by name, which is how `plugins/init.lua` extends the user's spec. That's
  why **the user's spec must name Lumen `lumen`** (`name = "lumen"`).
- Lua `a and nil or b` **always** yields `b`. Write `(not a) and b or nil`.
- **Don't stack toasts for background work.** nvim-treesitter echoes 3–4 lines per parser, which
  ui2 keeps on screen. Lumen's background parser installs go through the `install()` helper in
  `plugins/treesitter.lua`, which mutes those lines (`Logger.lumen_quiet`, still in `:TSLog`) and
  shows one notification. Mason installs are batched the same way in `lsp.lua`. For progress, call
  `Lumen.notify(msg, level, { id = … })` with a stable id so snacks updates it in place.
- `:restart` restores the session into the **current window**. When it follows a pack change,
  lazy.nvim's install float is the current window during startup, so `init.lua` closes that float
  at VimEnter when `v:startreason` is `restart`.

- **lazy.nvim's lockfile is cached, and its cache is sticky.** `require("lazy.manage.lock").load()`
  is a no-op once it has run, so after writing `lazy-lock.json` yourself, set `Lock.lock` (and
  `Lock._loaded = true`) to the same data, or `restore()` uses the old commits (`update.lua`'s
  `write_lock`). And run lazy's update/restore **blocking** (`wait = true`): an async runner can record
  the lockfile from the *current* commits before its checkout runs, silently undoing a pin or rollback.
  The real-lazy test "rollback really moves plugins" guards both. Mocked tests did not catch either.
- **Headless tests must stub every prompt.** `prompt_restart` and anything else that ends in
  `vim.ui.select` blocks a headless run forever (it's Neovim's `inputlist()` there). Watch for prompts
  that are *scheduled*: restore the stub only after a `vim.wait()` lets them fire.

## Conventions

- Lua style is enforced by stylua: 2 spaces and 120 columns. Run `stylua .` before you finish.
  Match the comment density of the surrounding code: short comments that explain *why*.
- Statusline, tabline, winbar, scrollbar and fold text have no plugin dependencies. Keep it that
  way and don't add plugin dependencies where Lumen currently has none.
- Lazy-load everything: use `event = "LazyFile"` / `"VeryLazy"`, `keys`, `cmd` or `ft`. Never add
  work to startup without checking `./scripts/bench.sh`. Defer slow work (Mason registry refresh,
  installs) past startup.
- Plugin keymaps belong in their spec in `lua/lumen/plugins/*`. Core keymaps go in `keymaps.lua`,
  with a `desc` so which-key can show them.
- Commit messages follow Conventional Commits with a scope, e.g. `feat(packs): add elm pack`,
  `fix(lsp): …`, `perf(scrollbar): …`, `docs: …`, `test: …`, `chore: …`.
- Keep `README.md` truthful. When you add or change a feature, update the README, the starter
  comments (`starter/lua/config/lumen.lua`) and the defaults' comments in `config.lua`, and add
  smoke tests in the same change.
