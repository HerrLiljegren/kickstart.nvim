local function discover_projects()
  local scan = require 'plenary.scandir'
  local dev_root = vim.fn.expand '~/dev'
  local worktrees_root = vim.fs.joinpath(dev_root, 'worktrees')
  local projects = {}
  local seen = {}

  local function add_project(path, kind, name)
    if seen[path] or not vim.uv.fs_stat(vim.fs.joinpath(path, '.git')) then
      return
    end

    seen[path] = true
    table.insert(projects, {
      kind = kind,
      name = name,
      path = path,
      display = string.format('%-9s %-35s %s', kind, name, vim.fn.fnamemodify(path, ':~')),
    })
  end

  if vim.fn.isdirectory(dev_root) ~= 1 then
    return projects
  end

  for _, path in ipairs(scan.scan_dir(dev_root, { hidden = false, depth = 2, only_dirs = true })) do
    if path ~= worktrees_root and not vim.startswith(path, worktrees_root .. '/') then
      local name = path:gsub('^' .. vim.pesc(dev_root .. '/'), '')
      add_project(path, 'repo', name)
    end
  end

  if vim.fn.isdirectory(worktrees_root) == 1 then
    for _, path in ipairs(scan.scan_dir(worktrees_root, { hidden = false, depth = 2, only_dirs = true })) do
      local name = path:gsub('^' .. vim.pesc(worktrees_root .. '/'), '')
      if name:find('/', 1, true) then
        add_project(path, 'worktree', name)
      end
    end
  end

  table.sort(projects, function(a, b)
    if a.kind ~= b.kind then
      return a.kind == 'worktree'
    end

    return a.name < b.name
  end)

  return projects
end

local function set_project_root(path)
  vim.cmd('cd ' .. vim.fn.fnameescape(path))
  vim.g.project_picker_root = path
  vim.notify('Project root: ' .. path)
end

local function reveal_project_root()
  local root = vim.g.project_picker_root or vim.fn.getcwd()
  vim.cmd('Neotree reveal dir=' .. vim.fn.fnameescape(root) .. ' position=left')
end

local function open_picker()
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local conf = require('telescope.config').values
  local finders = require 'telescope.finders'
  local pickers = require 'telescope.pickers'
  local builtin = require 'telescope.builtin'
  local projects = discover_projects()

  if vim.tbl_isempty(projects) then
    vim.notify('No projects found under ~/dev', vim.log.levels.WARN)
    return
  end

  pickers.new({}, {
    prompt_title = 'Projects',
    finder = finders.new_table {
      results = projects,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.name .. ' ' .. entry.path,
        }
      end,
    },
    sorter = conf.generic_sorter {},
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)

        local selection = action_state.get_selected_entry()
        if not selection or vim.fn.isdirectory(selection.value.path) ~= 1 then
          vim.notify('Project path is no longer available', vim.log.levels.ERROR)
          return
        end

        set_project_root(selection.value.path)
        builtin.find_files { cwd = selection.value.path }
      end)

      return true
    end,
  }):find()
end

---@module 'lazy'
---@type LazySpec
return {
  'nvim-telescope/telescope.nvim',
  keys = {
    {
      '<leader>sp',
      open_picker,
      desc = '[S]earch [P]rojects',
    },
    {
      '<M-s>',
      open_picker,
      desc = 'Search projects',
    },
    {
      '<leader>e',
      reveal_project_root,
      desc = '[E]xplorer',
    },
  },
}
