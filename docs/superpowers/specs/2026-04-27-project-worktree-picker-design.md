# Project And Worktree Picker Design

## Goal

Add a fast Neovim picker for jumping between project roots and git worktree roots, modeled after the user's existing terminal workflow.

## Context

- The Neovim config already uses `telescope.nvim` and `telescope-fzf-native.nvim`.
- Repositories live under `~/dev`.
- `worktrunk` creates worktrees under `~/dev/worktrees/{{ repo }}/{{ branch | sanitize }}`.
- The main user need is quick navigation between repo roots and worktree roots.
- The picker must support two outcomes:
  - switch the current Neovim session to the selected root
  - open the selected root in a new Neovim session

## Chosen Approach

Implement a small custom Telescope picker instead of adding `project.nvim`.

This is the best fit because the user's filesystem layout is already structured and predictable. A custom picker can scan real directories directly, which makes worktrees first-class entries instead of relying on project history or generic root detection.

## Alternatives Considered

### 1. Custom Telescope picker

Recommended.

Pros:
- fits the existing Telescope-based config
- directly models repo roots and worktree roots from disk
- deterministic: if a repo or worktree exists in the expected paths, it appears
- easy to control labels, ranking, and actions

Cons:
- requires a small amount of custom Lua
- no built-in recent-project history unless added later

### 2. `project.nvim` with Telescope integration

Pros:
- built-in project history and root detection
- minimal custom code for generic project switching

Cons:
- no dedicated git worktree model
- worktrees would only appear as normal project roots
- more centered on project history than explicit repo/worktree navigation
- opening a new Neovim session would still need custom behavior

### 3. `sesh`-backed picker in Neovim

Pros:
- closest parity with the existing terminal workflow
- can reuse external project/session knowledge

Cons:
- adds an external runtime dependency to the Neovim flow
- ties editor behavior to `sesh` rather than the actual directory layout
- unnecessary because the directory structure already provides the needed data

## Discovery Model

The picker will build entries from two sources:

1. repository roots under `~/dev`
2. worktree roots under `~/dev/worktrees`

Expected worktree shape:

- `~/dev/worktrees/<repo>/<branch>`

Expected repo shape:

- direct child directories that represent actual repositories under `~/dev`

The implementation should avoid treating the `worktrees` container itself as a normal repo root.

## Entry Model

Each entry should include:

- absolute path
- entry type: `repo` or `worktree`
- repo name
- branch/worktree name for worktrees
- display label suitable for fuzzy matching

Display examples:

- `repo      calculation                     ~/dev/tengella/calculation`
- `worktree  calculation / feature-auth     ~/dev/worktrees/calculation/feature-auth`

The display should make it obvious when the user is selecting a worktree instead of a main repo root.

## Picker Behavior

Primary keybindings:

- `<leader>sp` opens the picker
- optional `<M-s>` can be added later if terminal key handling is reliable

Inside the picker:

- `<CR>` switches the current Neovim session to the selected root
- `<C-o>` opens the selected root in a new Neovim session

## Action Semantics

### Switch current session

When switching the current session:

- set the current working directory to the selected root
- update Neovim state so future file searches use the new root
- refresh Neo-tree if it is open or available
- keep the operation scoped to the current Neovim session, not a global desktop workflow

### Open new Neovim session

When opening a new session:

- launch `nvim` with the selected root as its starting directory
- do not disrupt the current session
- use a simple shell command so behavior is predictable and easy to change later

The first version does not need to integrate tmux or sesh directly.

## Integration Points

Implementation will likely live in a new plugin or helper file under `lua/kickstart/plugins/` and reuse:

- `telescope.pickers`
- `telescope.finders`
- `telescope.config.values`
- `telescope.actions`
- `telescope.actions.state`

This keeps the feature aligned with the rest of the config rather than introducing a separate project-management plugin.

## Error Handling

The picker should handle these cases cleanly:

- missing `~/dev` or `~/dev/worktrees` directories
- empty result sets
- stale paths that no longer exist
- failure to spawn a new Neovim process

In each case, prefer a short `vim.notify` message over silent failure.

## Testing

Verification should cover:

- picker opens from the configured keybinding
- repos under `~/dev` appear
- worktrees under `~/dev/worktrees` appear
- `<CR>` changes the current working directory/root
- Neo-tree reflects the new root after switching
- `<C-o>` launches a new Neovim session rooted at the selected directory
- Telescope fuzzy matching remains responsive with both repo and worktree entries

## Scope Boundaries

Included in scope:

- discovery of repo roots and worktree roots
- Telescope UI for selection
- switch current session action
- open new session action

Explicitly out of scope for the first version:

- `project.nvim`
- direct `sesh` integration
- tmux integration
- persistent project history
- branch metadata beyond the worktree directory name

## Follow-Up Notes

If the first version works well, future enhancements could include:

- optional recency sorting
- optional tmux/session metadata in the picker
- optional `sesh`-backed source mode
- alternate keybinding for `Alt-s`
