-- lazygit.nvim - Neovim integration for lazygit
-- Provides a floating window for lazygit with keybindings

---@module 'lazy'
---@type LazySpec
return {
  'kdheepak/lazygit.nvim',
  lazy = true,
  cmd = {
    'LazyGit',
    'LazyGitConfig',
    'LazyGitCurrentFile',
    'LazyGitFilter',
    'LazyGitFilterCurrentFile',
  },
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  keys = {
    { '<leader>gg', '<cmd>LazyGit<cr>', desc = 'Open laz[y]git' },
    { '<leader>gf', '<cmd>LazyGitCurrentFile<cr>', desc = 'Open laz[y]git (current file)' },
  },
}
