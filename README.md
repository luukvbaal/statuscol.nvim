# statuscol.nvim

Status column plugin that provides a configurable ['statuscolumn'](https://neovim.io/doc/user/options.html#'statuscolumn') and click handlers.
Requires Neovim >= 0.9.

<!-- panvimdoc-ignore-start -->

## Install

Install with [packer](https://github.com/wbthomason/packer.nvim):

```lua
use({
  "luukvbaal/statuscol.nvim",
  config = function() require("statuscol").setup() end
})
```

<!-- panvimdoc-ignore-end -->

## Usage

Passing `setopt = true` to the [`setup()`](#Configuration) function will configure the `'statuscolumn'` option for you.
The builtin status column format can be configured through various configuration variables in the setup table.

Alternatively this plugin exposes four global lua functions. These can be used by those who need more flexibility, but still want to make use of the number format function or click handlers this plugin provides.

`ScFa`, `ScSa` and `ScLa` are to be used as `%@` click-handlers for the fold, sign and line number segments in your `'statuscolumn'` string respectively. `ScLn` will return the line number string, which can be configured through the `setup()` function. They can be used like so:

    vim.o.statuscolumn = "%@v:lua.ScFa@%C%T%@v:lua.ScLa@%s%T@v:lua.ScNa@%=%{v:lua.ScLn()}%T"

## Configuration

### Default options

```lua
local builtin = require("statuscol.builtin")
local cfg = {
  separator = false,     -- separator between line number and buffer text ("│" or extra " " padding)
  -- Builtin line number string options for ScLn() segment
  thousands = false,     -- or line number thousands separator string ("." / ",")
  relculright = false,   -- whether to right-align the cursor line number with 'relativenumber' set
  -- Custom line number string options for ScLn() segment
  lnumfunc = nil,        -- custom function called by ScLn(), should return a string
  reeval = false,        -- whether or not the string returned by lnumfunc should be reevaluated
  -- Custom fold column string options for ScFc() segment
  foldfunc = nil,        -- nil for "%C" segment, "builtin" for builtin function, or custom function
                         -- called by ScFc(), should return a string
  -- Builtin 'statuscolumn' options
  setopt = false,        -- whether to set the 'statuscolumn', providing builtin click actions
  order = "FSNs",        -- order of the fold, sign, line number and separator segments
  ft_ignore = nil,       -- lua table with filetypes for which 'statuscolumn' will be unset
  -- Click actions
  Lnum                   = builtin.lnum_click,
  FoldPlus               = builtin.foldplus_click,
  FoldMinus              = builtin.foldminus_click,
  FoldEmpty              = builtin.foldempty_click,
  DapBreakpointRejected  = builtin.toggle_breakpoint,
  DapBreakpoint          = builtin.toggle_breakpoint,
  DapBreakpointCondition = builtin.toggle_breakpoint,
  DiagnosticSignError    = builtin.diagnostic_click,
  DiagnosticSignHint     = builtin.diagnostic_click,
  DiagnosticSignInfo     = builtin.diagnostic_click,
  DiagnosticSignWarn     = builtin.diagnostic_click,
  GitSignsTopdelete      = builtin.gitsigns_click,
  GitSignsUntracked      = builtin.gitsigns_click,
  GitSignsAdd            = builtin.gitsigns_click,
  GitSignsChangedelete   = builtin.gitsigns_click,
  GitSignsDelete         = builtin.gitsigns_click,
}
```

### Custom click actions

The configuration table can contain, besides the options, a list of sign/click action pairs.
Each entry is the name of a sign, or `Lnum` and `FoldPlus/Minus/Empty` for the number and fold columns.
To modify the default actions, pass a table with the actions you want to overwrite to the `setup()` function:

```lua
local cfg = {
  order = "FNSs",
  --- The click actions have the following signature:
  ---@param args (table): {
  ---   minwid = minwid,            -- 1st argument to 'statuscolumn' %@ callback
  ---   clicks = clicks,            -- 2nd argument to 'statuscolumn' %@ callback
  ---   button = button,            -- 3rd argument to 'statuscolumn' %@ callback
  ---   mods = mods,                -- 4th argument to 'statuscolumn' %@ callback
  ---   mousepos = f.getmousepos()  -- getmousepos() table, containing clicked line number/window id etc.
  --- }
  Lnum = function(args)
    if args.button == "l" and args.mods:find("c") then
      print("I Ctrl-left clicked on line "..args.mousepos.line)
    end
  end,
}

require("statuscol").setup(cfg)
```

### Custom line number function

The `lnumfunc` entry can be a lua function that returns a custom line number string:

```lua
require("statuscol").setup({ setopt = true, reeval = true, lnumfunc = function()
    return ((vim.v.lnum % 2 > 0) and "%#DiffDelete#%=" or "%#DiffAdd#%=")..vim.v.lnum
end })
```

When `nil`, the builtin line number function is used which can be configured through `thousands` and `relculright`.

### Custom fold column function

The `foldfunc` entry can be:
* `nil`: use the default `%C` `'statuscolumn'` item.
* `"builtin"`: use the builtin fold column function.
* lua function: this function is passed a `foldinfo = {start,level,llevel,lines}` table and `width` argument and should return a fold column string.

## Default click actions

**Sign/click action pair suggestions are welcome!**

Currently the following builtin actions are supported (optional dependencies required):

|Sign|Button|Modifier|Action|
|----|------|--------|------|
|Lnum|Left||Toggle [DAP](https://github.com/mfussenegger/nvim-dap) breakpoint|
|Lnum|Left|<kbd>Ctrl</kbd>|Toggle DAP conditional breakpoint|
|Lnum|Middle||Yank line|
|Lnum|Right||Paste line|
|Lnum|Right x2||Delete line|
|FoldPlus|Left||Open fold|
|FoldPlus|Left|<kbd>Ctrl</kbd>|Open fold recursively|
|FoldMinus|Left||Close fold|
|FoldMinus|Left|<kbd>Ctrl</kbd>|Close fold recursively|
|FoldPlus/Minus|Right||Delete fold|
|FoldPlus/Minus|Right|<kbd>Ctrl</kbd>|Delete fold recursively|
|Fold*|Middle||Create fold in range(click twice)|
|Diagnostic*|Left||Open diagnostic [float](https://neovim.io/doc/user/diagnostic.html#vim.diagnostic.open_float())|
|Diagnostic*|Middle||Select available [code action](https://neovim.io/doc/user/lsp.html#vim.lsp.buf.code_action())|
|[GitSigns](https://github.com/lewis6991/gitsigns.nvim)*|Left||Preview hunk|
|GitSigns*|Middle||Reset hunk|
|GitSigns*|Right||Stage hunk|
