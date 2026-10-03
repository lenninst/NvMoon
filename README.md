# NvMoon

Personal Neovim configuration (neo-tree `v3.x` branch, `lazy.nvim`, catppuccin mocha).

```sh
mvim              # open in the current directory
mvim <dir>        # open and show neo-tree at <dir>
mvim <file>       # open a file
```

`mvim` is an alias: `NVIM_APPNAME=NvMoon nvim` (defined in `~/.zshrc`).

> When opening with `mvim <dir>`, the neo-tree cursor starts on **line 1 (the root node = the directory)**.
> Move down with `j` to a file before pressing `<CR>`; on the root node `<CR>` only expands/collapses.

---

## Index

- [Group quick reference](#group-quick-reference)
- [Global](#global)
- [Windows and panes](#windows-and-panes)
- [Text movement](#text-movement)
- [Indentation and selection](#indentation-and-selection)
- [Buffers](#buffers)
- [Search / Files](#search--files)
- [Explorer](#explorer)
- [Projects](#projects)
- [LSP](#lsp)
- [Diagnostics and lists (Trouble)](#diagnostics-and-lists-trouble)
- [Git](#git)
- [Hunks (buffer-local)](#hunks-buffer-local)
- [Harpoon](#harpoon)
- [AI, Codex and Terminal](#ai-codex-and-terminal)
- [Remote (Distant)](#remote-distant)
- [Debug](#debug)
- [Flash](#flash)
- [UI / Colors](#ui--colors)
- [Completion](#completion)
- [Mappings inside neo-tree](#mappings-inside-neo-tree)
- [Inherited plugin mappings](#inherited-plugin-mappings)
- [Migration from the old scheme](#migration-from-the-old-scheme)

---

## Group quick reference

`leader` = `space`. Press `space ?` to see this same table inside Neovim.

| Key | Group | Contents |
|-----|-------|----------|
| `space a` | AI (Opencode) | ask, model, agent, context |
| `space b` | Buffers | cycle, jump, close, sort |
| `space c` | Codex | codex sessions |
| `space d` | Debug | breakpoints, dap-view, python tests |
| `space e` | Explorer | neo-tree, wayfinder |
| `space f` | Search | snacks picker |
| `space g` | Git | neogit |
| `space h` | Hunks / Harpoon | gitsigns + harpoon marks |
| `space l` | LSP | code actions, format, hover, symbols |
| `space p` | Projects | neovim-project |
| `space r` | Remote | distant.nvim |
| `space t` | Terminal | toggleterm |
| `space u` | UI | color picker |
| `space x` | Trouble | diagnostics, symbols, loclist, qflist |

---

## Global

| Mapping | Description | Mode |
|---------|-------------|------|
| `space w` | Write file | normal |
| `space q` | Quit / close window | normal |
| `space ?` | Which Key (all mappings) | normal |
| `g y` | Copy to system clipboard (`+` register) | normal, visual |
| `g p` | Paste from system clipboard | normal, visual |
| `[ q` | Previous error (quickfix) | normal |
| `] q` | Next error (quickfix) | normal |

---

## Windows and panes

| Mapping | Description | Mode |
|---------|-------------|------|
| `C-h` `C-j` `C-k` `C-l` | Window left / down / up / right | normal |
| `C-h` `C-j` `C-k` `C-l` | Same, jumping to normal from the terminal | terminal |
| `Alt-Up` `Alt-Down` `Alt-Left` `Alt-Right` | Move between windows without leaving insert | insert |
| `C-Up` / `C-Down` | Decrease / increase window height | normal |
| `C-Left` / `C-Right` | Decrease / increase window width | normal |

---

## Text movement

| Mapping | Description | Mode |
|---------|-------------|------|
| `Alt-j` | Move the line **down** and re-indent | normal, insert |
| `Alt-k` | Move the line **up** and re-indent | normal, insert |
| `Alt-j` / `Alt-k` | Move the visual block down / up | visual |

---

## Indentation and selection

| Mapping | Description | Mode |
|---------|-------------|------|
| `<` | Indent keeping the selection | visual |
| `>` | Dedent keeping the selection | visual |

---

## Buffers

| Mapping | Description |
|---------|-------------|
| `space b b` | Previous buffer |
| `space b n` | Next buffer |
| `space b j` | Jump to a buffer (list) |
| `space b e` | Pick which buffer to close |
| `space b h` | Close all buffers to the left |
| `space b l` | Close all buffers to the right |
| `space b L` | Sort by language |
| `space b D` | Sort by directory |
| `space b W` | Save **without** formatting (`noautocmd w`) |
| `Shift-h` / `Shift-l` | Previous / next buffer |

> The empty `[No Name]` startup buffer is automatically hidden from the bar.

---

## Search / Files

| Mapping | Description |
|---------|-------------|
| `space f f` | Find files |
| `space f g` | Live grep in the project |
| `space f w` | Grep the word under the cursor |
| `space f b` | Search across buffers |
| `space f r` | Recent files |
| `space f h` | Help tags |

---

## Explorer

| Mapping | Description |
|---------|-------------|
| `space e` | Open / close neo-tree |
| `space e f` | Wayfinder (find file by name in the tree) |

neo-tree sits on the **right**, width 30, and follows the current file.
The top selector has three sources: `Files`, `Buffers`, `Git` (also with `<` / `>`).

---

## Projects

| Mapping | Description |
|---------|-------------|
| `space p` | Recent projects |
| `space p o` | Open project (Zed-like) |
| `space p r` | Project history |

Detects projects in `~/dev/*` and `~/*` via `.git`, `.hg`, `.svn`, `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `.project`.

---

## LSP

| Mapping | Description |
|---------|-------------|
| `space l a` | Code action |
| `space l i` | Hover documentation |
| `space l f` | Format buffer (conform, with LSP fallback) |
| `space l l` | Run CodeLens |
| `space l S` | Document symbols |
| `space l s` | Workspace symbols |
| `space l o` | Outline (aerial) |
| `space l j` | Next diagnostic |
| `space l k` | Previous diagnostic |
| `space l d` | Buffer diagnostics → loclist |
| `space l q` | Buffer diagnostics → quickfix |

**Servers installed by mason:** `lua_ls`, `ts_ls`, `eslint`, `lemminx` (XML), `basedpyright`, `ruff`, `rust-analyzer`, `csharp-language-server`.

**Formatters:** stylua, prettier, ruff, csharpier (automatic on save).

---

## Diagnostics and lists (Trouble)

| Mapping | Description |
|---------|-------------|
| `space x x` | Diagnostics (all) |
| `space x X` | Diagnostics (buffer) |
| `space x s` | Document symbols |
| `space x d` | LSP definitions |
| `space x r` | LSP references |
| `space x l` | Location list |
| `space x q` | Quickfix list |

---

## Git (Neogit)

| Mapping | Description |
|---------|-------------|
| `space g g` | Repository status |
| `space g c` | Commit |
| `space g p` | Push |
| `space g l` | Pull |

Neogit opens in a new tab (`kind = "tab"`) and integrates with `diffview`.

---

## Hunks (buffer-local)

Only exist in buffers inside a git repository.

| Mapping | Description |
|---------|-------------|
| `space h s` | Stage hunk |
| `space h r` | Reset hunk |
| `space h u` | Undo stage hunk |
| `space h p` | Preview hunk |
| `space h b` | Blame the current line (full) |
| `space h B` | Toggle inline line blame |
| `space h d` | Diff this file |
| `] c` / `[ c` | Next / previous hunk |

---

## Harpoon

| Mapping | Description |
|---------|-------------|
| `space h a` | Add the current file to the list |
| `space h m` | Open the quick menu for the list |
| `space h 1` … `space h 4` | Jump to harpoon file 1–4 |

---

## AI, Codex and Terminal

**Opencode**

| Mapping | Description |
|---------|-------------|
| `space a` | Ask with `@this:` context |
| `space a o` | Ask without context |
| `space a m` | Select model |
| `space a a` | Select agent |
| `space a n` | Add context (`@`) |
| `space a s` | General menu |

**Codex (float)**

| Mapping | Description |
|---------|-------------|
| `space c` | Toggle codex |
| `space c x` | New codex instance |

**Terminal (toggleterm)**

| Mapping | Description |
|---------|-------------|
| `space t` | Toggle floating terminal |
| `space t h` | Terminal in a horizontal split |
| `space t v` | Terminal in a vertical split |

---

## Remote (Distant)

| Mapping | Description |
|---------|-------------|
| `space r m` | Connect over SSH |
| `space r o` | Open a remote path |
| `space r d` | Disconnect |
| `space r s` | Open a remote shell |

---

## Debug

| Mapping | Description |
|---------|-------------|
| `space d r` | Run / continue |
| `space d s` | Step over |
| `space d i` | Step into |
| `space d o` | Step out |
| `space d t` | Terminate |
| `space d b` | Toggle breakpoint |
| `space d v` | Toggle dap-view |
| `space d p` | Debug the current python test method |
| `F5` | Run / continue (alias of `space d r`) |

Debuggers configured: `debugpy` (Python) and `netcoredbg` (C#).

---

## Flash

| Mapping | Description | Mode |
|---------|-------------|------|
| `s` | Flash jump | normal, visual, operator |
| `S` | Flash jump via treesitter | normal, visual, operator |
| `r` | Flash remote | operator |
| `R` | Treesitter search | operator, visual |

---

## UI / Colors

| Mapping | Description |
|---------|-------------|
| `space u c` | Color picker (minty) |
| `space u s` | Color shades (minty) |

---

## Completion

| Mapping | Description | Mode |
|---------|-------------|------|
| `Tab` / `Shift-Tab` | Accept / dismiss suggestion | insert |
| `Enter` | Accept suggestion | insert |

`blink.cmp` with `lsp`, `path`, `snippets`, `buffer` sources, auto documentation and signature help enabled.

---

## Mappings inside neo-tree

| Mapping | Description |
|---------|-------------|
| `<CR>` | Open |
| `space` | Expand / collapse node |
| `a` / `A` | New file / new directory |
| `d` | Delete |
| `r` | Rename |
| `c` / `m` | Copy to another destination / move |
| `y` / `x` / `p` | Copy / cut / paste |
| `C-r` | Clear the internal clipboard |
| `C` / `z` | Close node / close all |
| `R` | Refresh |
| `q` | Close the window |
| `?` | neo-tree help |
| `<` / `>` | Previous / next source |
| `s` / `S` / `t` | Open in vsplit / split / new tab |
| `w` | Open with window picker |
| `P` / `l` | Preview / focus preview |
| `C-f` / `C-b` | Scroll the preview |
| `e` | Auto-expand width |

---

## Inherited plugin mappings

Useful to know what is "inherited" so you do not break it by accident.

**Comment.nvim** — `gcc` current line · `gbc` block · `gc` line · `gco` below · `gcO` above · `gcA` at end · `gb` block (visual)

**Neovim / default LSP**

| Mapping | Description |
|---------|-------------|
| `g r n` | Rename symbol |
| `g r a` | Code action |
| `g r r` | References |
| `g r i` | Implementation |
| `g r t` | Type definition |
| `g r x` | Run CodeLens |
| `g x` | Open path / URL under the cursor |
| `] d` / `[ d` | Next / previous diagnostic |
| `[%` / `]%` | Previous / next block |
| `[b` / `]b` | Previous / next buffer |
| `[l` / `]l` | Previous / next loclist |

**Trouble (internal)** — `q` close · `r` rename · `p` preview · `<CR>` jump · `x`/`X` diagnostics · `f`/`F` filter

---

## Migration from the old scheme

The `<leader>` namespaces were reorganized so that every prefix has exactly one
meaning. These are the keys that moved:

| Old | New | Reason |
|-----|-----|--------|
| `space f s` | `space f w` | words vs. search symmetry |
| `space f o` | `space f r` | `r` for recent |
| `space f p` | `space p o` | projects left the search group |
| `space o` | `space p o` | projects left the global namespace |
| `space u f` | `space e f` | wayfinder belongs to the explorer |
| `space c l` | `space x d` / `space x r` | trouble owns the `x` prefix |
| `space c p` | `space u c` | colors moved out of the codex prefix |
| `space c s` | `space u s` | colors moved out of the codex prefix |
| `space h h` | `space h m` | `h m` = harpoon menu |
| `space 1`…`space 4` | `space h 1`…`space h 4` | harpoon marks live under `h` |
| `space t b` | `space h B` | inline blame belongs with hunks |
| `space l w` | removed | duplicated `space l q` |
| `F1` / `F2` / `F3` | `space d i` / `space d s` / `space d o` | `F1` is `:help`; step keys under the debug prefix |
| `space d c` / `space d o` / `space d d` / `space d s` | `space r m` / `space r o` / `space r d` / `space r s` | distant moved to the `r` (remote) prefix |
| `space d p r` | `space d p` | flat debug prefix |

Everything else kept its key. No duplicate mappings remain (verified with
`nvim_get_keymap` across the `n v x s o i` modes).

---

## Structure

```
init.lua
lazy-lock.json
lua/lenn/
├── lazy.lua            # lazy.nvim setup
├── core/
│   ├── init.lua
│   ├── options.lua     # options, diagnostics, colorscheme
│   └── keymaps.lua     # global + LSP mappings
└── plugins/
    ├── init.lua        # plugin registration
    ├── neotree.lua  bufferline.lua  lualine.lua  snacks.lua
    ├── which-key.lua  projects.lua  noice.lua   ui.lua
    ├── lsp.lua        completion.lua treesitter.lua formatting.lua
    ├── git.lua        neogit.lua    trouble.lua  wayfinder.lua
    ├── codex.lua      distant.lua   minty.lua    dap.lua
    ├── dap-python.lua  aerial.lua   autopairs.lua flash.lua
    ├── harpoon.lua    mason-tools.lua
```