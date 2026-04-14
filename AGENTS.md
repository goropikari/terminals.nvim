# Repository Guidelines

## Project Structure & Module Organization

`terminals.nvim` is a Neovim plugin. Core plugin code lives in `lua/terminals/`: `init.lua` handles setup and commands, `terminal.lua` manages terminal lifecycle, `state.lua` tracks tab-local state, and `ui/` contains winbar and drag behavior. `plugin/terminals.lua` registers the plugin at startup. Tests live in `tests/`, with `tests/terminals_spec.lua` as the main Plenary spec and `tests/minimal_init.lua` as the headless test bootstrap. `dev/init.lua` is the local development config, and `features/` holds behavior notes in Gherkin-style `.feature` files.

## Build, Test, and Development Commands

- `make nvim` launches Neovim with `dev/init.lua` and the plugin on `runtimepath`.
- `make test` runs the Plenary test suite headlessly against `tests/`.
- `make fmt` formats Lua with `stylua` and Markdown/TOML/YAML/JSON with `dprint`.
- `make lint` runs `typos` for spelling checks.
- `make clean` removes the local `nvim.log`.

Run commands from the repository root.

## Coding Style & Naming Conventions

Lua uses 2-space indentation, Unix line endings, and `stylua` formatting from `.stylua.toml`. Prefer single quotes where `stylua` keeps them. Keep modules small and focused; follow the existing split between core state, terminal behavior, and UI helpers. Use lowercase snake_case for local variables and functions, and keep public module names aligned with file paths such as `require('terminals.state')`.

## Testing Guidelines

Tests use `plenary.nvim` with Busted-style `describe`/`it` blocks. Add coverage in `tests/terminals_spec.lua` for user-facing behavior changes, especially around tabpage isolation, window policies, and command behavior. Name new specs by behavior, for example `it('restores the active terminal after toggle', ...)`. Run `make test` before opening a PR.

## Commit & Pull Request Guidelines

Recent history favors short, imperative subjects, often with Conventional Commit prefixes such as `feat:`. Keep commit titles concise and specific, for example `feat: support ratio-based terminal height`. Pull requests should describe the behavior change, note any command or config surface affected, link related issues, and include screenshots or short recordings for winbar or mouse-interaction changes.

## Contributor Notes

Do not edit `deps/` unless intentionally updating vendored dependencies. If you change commands, defaults, or UX, update `README.md` in the same branch.
