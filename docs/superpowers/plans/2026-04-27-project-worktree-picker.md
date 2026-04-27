# Project Worktree Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Telescope-based picker that lists repository roots and git worktree roots from `~/dev`, lets the user switch the current Neovim session to the selected root, or open the selected root in a new Neovim session.

**Architecture:** Add one focused helper module that discovers candidate directories and opens a custom Telescope picker with two actions. Wire it into Neovim through a small plugin spec that defines keymaps and refreshes Neo-tree after switching roots.

**Tech Stack:** Neovim Lua, telescope.nvim, telescope-fzf-native.nvim, neo-tree.nvim, plenary.nvim

---

## File Structure

- Create: `lua/kickstart/project_picker.lua`
  - Owns discovery of repo roots and worktree roots.
  - Builds Telescope entries and actions.
  - Exposes one public `open()` function.
- Create: `lua/kickstart/plugins/project-picker.lua`
  - Registers keymaps for the picker.
  - Loads no extra dependencies beyond Telescope and plenary.
- Modify: `init.lua`
  - Import the new plugin spec alongside other kickstart plugins.
- Test manually in Neovim
  - No existing automated test harness is set up for config modules, so verification is command-based.

### Task 1: Add The Picker Helper Module

**Files:**
- Create: `lua/kickstart/project_picker.lua`

- [ ] **Step 1: Write the helper module with directory discovery and a public `open()` function**

```lua
local M = {}

local scan = require 'plenary.scandir'

local dev_root = vim.fn.expand '~/dev'
local worktrees_root = vim.fs.joinpath(dev_root, 'worktrees')

local function is_dir(path)
  return vim.fn.isdirectory(path) == 1
end

local function path_exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

local function repo_entries()
  local entries = {}

  if not is_dir(dev_root) then
    return entries
  end

  for _, child in ipairs(scan.scan_dir(dev_root, { hidden = false, depth = 2, only_dirs = true })) do
    local git_dir = vim.fs.joinpath(child, '.git')
    if path_exists(git_dir) and child ~= worktrees_root and not child:find('/worktrees/', 1, true) then
      table.insert(entries, {
        type = 'repo',
        repo = vim.fs.basename(child),
        worktree = nil,
        path = child,
      })
    end
  end

  return entries
end

local function worktree_entries()
  local entries = {}

  if not is_dir(worktrees_root) then
    return entries
  end

  for _, child in ipairs(scan.scan_dir(worktrees_root, { hidden = false, depth = 2, only_dirs = true })) do
    local git_dir = vim.fs.joinpath(child, '.git')
    if path_exists(git_dir) then
      local repo = vim.fs.basename(vim.fs.dirname(child))
      table.insert(entries, {
        type = 'worktree',
        repo = repo,
        worktree = vim.fs.basename(child),
        path = child,
      })
    end
  end

  return entries
end

local function all_entries()
  local entries = {}

  vim.list_extend(entries, repo_entries())
  vim.list_extend(entries, worktree_entries())

  table.sort(entries, function(a, b)
    if a.type ~= b.type then
      return a.type == 'worktree'
    end

    if a.repo ~= b.repo then
      return a.repo < b.repo
    end

    return a.path < b.path
  end)

  return entries
end

function M.open()
  return all_entries()
end

return M
```

- [ ] **Step 2: Run a Lua syntax check for the new module**

Run: `nvim --headless "+lua require('kickstart.project_picker')" +q`
Expected: command exits successfully with no Lua errors

- [ ] **Step 3: Tighten discovery if the initial scan is too broad**

```lua
local function repo_entries()
  local entries = {}

  if not is_dir(dev_root) then
    return entries
  end

  for _, org_dir in ipairs(scan.scan_dir(dev_root, { hidden = false, depth = 1, only_dirs = true })) do
    if org_dir ~= worktrees_root then
      for _, repo_dir in ipairs(scan.scan_dir(org_dir, { hidden = false, depth = 1, only_dirs = true })) do
        if path_exists(vim.fs.joinpath(repo_dir, '.git')) then
          table.insert(entries, {
            type = 'repo',
            repo = vim.fs.basename(repo_dir),
            worktree = nil,
            path = repo_dir,
          })
        end
      end
    end
  end

  return entries
end
```

- [ ] **Step 4: Re-run the module load check**

Run: `nvim --headless "+lua vim.print(require('kickstart.project_picker').open())" +q`
Expected: prints a Lua table with repo and worktree entries and exits successfully

- [ ] **Step 5: Commit**

```bash
git add lua/kickstart/project_picker.lua
git commit -m "feat: add project root discovery for telescope picker"
```

### Task 2: Turn The Helper Into A Telescope Picker

**Files:**
- Modify: `lua/kickstart/project_picker.lua`

- [ ] **Step 1: Replace the temporary `open()` return value with a real Telescope picker**

```lua
local actions = require 'telescope.actions'
local action_state = require 'telescope.actions.state'
local conf = require('telescope.config').values
local finders = require 'telescope.finders'
local pickers = require 'telescope.pickers'

local function entry_maker(entry)
  local label

  if entry.type == 'worktree' then
    label = string.format('worktree  %s / %s    %s', entry.repo, entry.worktree, entry.path)
  else
    label = string.format('repo      %s    %s', entry.repo, entry.path)
  end

  return {
    value = entry,
    display = label,
    ordinal = string.format('%s %s %s', entry.type, entry.repo, entry.path),
  }
end

local function refresh_neotree(path)
  local ok, manager = pcall(require, 'neo-tree.sources.manager')
  if not ok then
    return
  end

  local state = manager.get_state 'filesystem'
  if not state then
    return
  end

  vim.cmd('Neotree close')
  vim.cmd('Neotree reveal dir=' .. vim.fn.fnameescape(path) .. ' position=left')
end

local function switch_to_path(path)
  vim.cmd.cd(path)
  refresh_neotree(path)
  vim.notify('Switched project root to ' .. path)
end

local function open_in_new_nvim(path)
  local command = string.format('nvim %s', vim.fn.shellescape(path))
  vim.fn.jobstart(command, { detach = true })
end

function M.open()
  local entries = all_entries()

  if vim.tbl_isempty(entries) then
    vim.notify('No projects or worktrees found under ~/dev', vim.log.levels.WARN)
    return
  end

  pickers.new({}, {
    prompt_title = 'Projects And Worktrees',
    finder = finders.new_table {
      results = entries,
      entry_maker = entry_maker,
    },
    sorter = conf.generic_sorter {},
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        switch_to_path(selection.value.path)
      end)

      map({ 'i', 'n' }, '<C-o>', function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        open_in_new_nvim(selection.value.path)
      end)

      return true
    end,
  }):find()
end
```

- [ ] **Step 2: Verify the picker opens in headless-safe startup without syntax errors**

Run: `nvim --headless "+lua require('kickstart.project_picker')" +q`
Expected: exits successfully with no Lua errors

- [ ] **Step 3: Add failure handling for stale paths and failed `jobstart()`**

```lua
local function switch_to_path(path)
  if not is_dir(path) then
    vim.notify('Path no longer exists: ' .. path, vim.log.levels.ERROR)
    return
  end

  vim.cmd.cd(path)
  refresh_neotree(path)
  vim.notify('Switched project root to ' .. path)
end

local function open_in_new_nvim(path)
  if not is_dir(path) then
    vim.notify('Path no longer exists: ' .. path, vim.log.levels.ERROR)
    return
  end

  local job_id = vim.fn.jobstart({ 'nvim', path }, { detach = true })
  if job_id <= 0 then
    vim.notify('Failed to open new Neovim session for ' .. path, vim.log.levels.ERROR)
  end
end
```

- [ ] **Step 4: Manually verify picker behavior in interactive Neovim**

Run: `nvim`
Expected:
- `<leader>sp` is not wired yet, but `:lua require('kickstart.project_picker').open()` opens a Telescope picker
- `<CR>` switches cwd to the selected root
- `<C-o>` launches a new Neovim instance rooted at the selected path

- [ ] **Step 5: Commit**

```bash
git add lua/kickstart/project_picker.lua
git commit -m "feat: add telescope project and worktree picker"
```

### Task 3: Wire The Picker Into The Neovim Config

**Files:**
- Create: `lua/kickstart/plugins/project-picker.lua`
- Modify: `init.lua:993-999`

- [ ] **Step 1: Create the plugin spec with keybindings**

```lua
---@module 'lazy'
---@type LazySpec
return {
  'nvim-telescope/telescope.nvim',
  keys = {
    {
      '<leader>sp',
      function()
        require('kickstart.project_picker').open()
      end,
      desc = '[S]earch [P]rojects',
    },
  },
}
```

- [ ] **Step 2: Import the plugin spec from `init.lua`**

```lua
  require 'kickstart.plugins.neo-tree',
  require 'kickstart.plugins.lazygit',
  require 'kickstart.plugins.project-picker',
  -- require 'kickstart.plugins.gitsigns', -- adds gitsigns recommended keymaps
```

- [ ] **Step 3: Verify startup and keymap registration**

Run: `nvim --headless "+lua vim.print(vim.fn.maparg('<leader>sp', 'n'))" +q`
Expected: prints a non-empty mapping definition

- [ ] **Step 4: Manually verify full flow in interactive Neovim**

Run: `nvim`
Expected:
- pressing `<leader>sp` opens the picker
- worktree and repo entries are both visible
- selecting a repo root updates current working directory
- selecting a worktree root updates current working directory
- Neo-tree reflects the selected root after switching
- pressing `<C-o>` on a selection opens another Neovim session without closing the current one

- [ ] **Step 5: Commit**

```bash
git add init.lua lua/kickstart/plugins/project-picker.lua
git commit -m "feat: add keymap for project and worktree picker"
```

### Task 4: Final Verification And Cleanup

**Files:**
- Modify: `lua/kickstart/project_picker.lua` if verification reveals issues
- Modify: `lua/kickstart/plugins/project-picker.lua` if keymaps or loading need adjustment

- [ ] **Step 1: Run final headless verification**

Run: `nvim --headless "+lua require('kickstart.project_picker')" +q`
Expected: exits successfully with no errors

- [ ] **Step 2: Run final interactive verification checklist**

Run: `nvim`
Expected:
- `<leader>sp` opens quickly
- fuzzy matching finds both repo names and worktree branch names
- empty or missing directories produce a short notify instead of a traceback
- switching roots leaves Neovim usable for `find_files`, Neo-tree, and normal editing

- [ ] **Step 3: Trim any unnecessary code discovered during implementation**

```lua
-- Keep only these public pieces:
local M = {}

function M.open()
  -- picker implementation
end

return M
```

- [ ] **Step 4: Check worktree and repo discovery against the live filesystem**

Run: `find ~/dev -maxdepth 3 -type d | grep -E '/worktrees/|/tengella/'`
Expected: output includes representative repo roots and worktree roots that match the picker entries

- [ ] **Step 5: Commit**

```bash
git add lua/kickstart/project_picker.lua lua/kickstart/plugins/project-picker.lua init.lua
git commit -m "refactor: finalize project and worktree navigation picker"
```
