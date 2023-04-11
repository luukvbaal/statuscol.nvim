# statuscol.nvim

Status column plugin that provides a configurable ['statuscolumn'](https://neovim.io/doc/user/options.html#'statuscolumn') and click handlers.
Requires Neovim >= 0.9.

<!-- panvimdoc-ignore-start -->

![image](https://user-images.githubusercontent.com/31730729/230627808-de0b1e97-116d-4016-b4ba-cb709dfcd980.png)

_Status column containing a fold column without fold depth digits, a custom sign segment that will only show diagnostic signs, a number column with right aligned relativenumbers and a sign segment that is only 1 cell wide that shows all other signs._

## Install

For example with lazy.nvim:

```lua
{
  "luukvbaal/statuscol.nvim", config = function()
    -- local builtin = require("statuscol.builtin")
    require("statuscol").setup({
      -- configuration goes here, for example:
      -- relculright = true,
      -- segments = {
      --   { text = { builtin.foldfunc }, click = "v:lua.ScFa" },
      --   {
      --     sign = { name = { "Diagnostic" }, maxwidth = 2, auto = true },
      --     click = "v:lua.ScSa"
      --   },
      --   { text = { builtin.lnumfunc }, click = "v:lua.ScLa", },
      --   {
      --     sign = { name = { ".*" }, maxwidth = 2, colwidth = 1, auto = true },
      --     click = "v:lua.ScSa"
      --   },
      -- }
    })
  end,
}
```

<!-- panvimdoc-ignore-end -->

## Usage

By default, the `setup()` function will configure the `'statuscolumn'` option for you.
This will yield a clickable 'statuscolumn' that looks the same as default neovim, still obeying most of neovim's options that modify the way the "gutter" looks.
Further customization is possible through various configuration variables in the `setup()` table.

## Configuration

### Default options

```lua
local builtin = require("statuscol.builtin")
local cfg = {
  setopt = true,         -- Whether to set the 'statuscolumn' option, may be set to false for those who
                         -- want to use the click handlers in their own 'statuscolumn': _G.Sc[SFL]a().
                         -- Although I recommend just using the segments field below to build your
                         -- statuscolumn to benefit from the performance optimizations in this plugin.
  -- builtin.lnumfunc number string options
  thousands = false,     -- or line number thousands separator string ("." / ",")
  relculright = false,   -- whether to right-align the cursor line number with 'relativenumber' set
  -- Builtin 'statuscolumn' options
  ft_ignore = nil,       -- lua table with filetypes for which 'statuscolumn' will be unset
  bt_ignore = nil,       -- lua table with 'buftype' values for which 'statuscolumn' will be unset
  -- Default segments (fold -> sign -> line number + separator), explained below
  segments = {
    { text = { "%C" }, click = "v:lua.ScFa" },
    { text = { "%s" }, click = "v:lua.ScSa" },
    {
      text = { builtin.lnumfunc, " " },
      condition = { true, builtin.not_empty },
      click = "v:lua.ScLa",
    }
  },
  clickmod = "c",         -- modifier used for certain actions in the builtin clickhandlers:
                          -- "a" for Alt, "c" for Ctrl and "m" for Meta.
  clickhandlers = {       -- builtin click handlers
    Lnum                   = builtin.lnum_click,
    FoldClose              = builtin.foldclose_click,
    FoldOpen               = builtin.foldopen_click,
    FoldOther              = builtin.foldother_click,
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
    GitSignsChange         = builtin.gitsigns_click,
    GitSignsChangedelete   = builtin.gitsigns_click,
    GitSignsDelete         = builtin.gitsigns_click,
  },
}
```

### Custom segments

The status column can be customized through the `segments` table.
Each segment can contain the following elements:

```lua
{
  text = { "%C" },      -- table of strings or functions returning a string
  click = "v:lua.ScFa", -- %@ click function label, applies to each text element
  hl = "FoldColumn",    -- %# highlight group label, applies to each text element
  condition = { true }, -- table of booleans or functions returning a boolean
  sign = {              -- table of fields that configure a sign segment
    name = { ".*" },    -- table of lua patterns to match the sign name against (required)
    -- below values list the default when omitted:
    maxwidth = 1,       -- maximum number of signs that will be displayed in this segment
    colwidth = 2,       -- number of display cells per sign in this segment
    auto = false,       -- when true, the segment will not be drawn if no signs matching
                        -- the pattern are currently placed in the buffer.
    fillchar = " ",     -- character used to fill a segment with less signs than maxwidth
  }
}
```

* The `text` and `sign` elements are mutually exclusive, except for when `text` contains `builtin.lnumfunc`. In this case a sign segment can be added to control what is displayed in the number segment for `'signcolumn' == "number"`.
* The `text` and `condition` elements should have the same length.
* Custom function example for the `text` element:

```lua
local builtin = require("statuscol.builtin")
require("statuscol").setup({
  segments = {
    {
      text = {
        " ",               -- whitespace padding
        function()         -- custom line number highlight function
          return ((vim.v.lnum % 2 > 0) and "%#DiffDelete#%=" or "%#DiffAdd#%=").."%l"
        end,
        " ",               -- whitespace padding
      },
      condition = {
        true,              -- always shown
        function(args)     -- shown only for the current window
          return vim.api.nvim_get_current_win() == args.win
        end,
        builtin.notempty,  -- only shown when the rest of the statuscolumn is not empty
      },
    }
  }
})
```

### Builtin segments

This plugin provides a few builtin functions that can be used as segment elements.

#### builtin.lnumfunc

This is the line number function used by default that obeys `'(relative)number'` and can be configured through a few options.

#### builtin.foldfunc

This is a fold column replacement that does not print the fold depth digits.

#### builtin.not_empty

This is a helper function that will return true or false depending on whether the status column is currently empty.
It can be used to conditionally print static `text` elements. The default segments uses it for a `" "` separator.

Feature requests/additions for the builtin providers are welcome if they can reasonably be made to be configurable.

### Custom click actions

Custom sign/click action pairs can be passed through the `clickhandlers` table.
Each element is the name of a sign, or `Lnum` and `FoldClose/Open/Other` for the number and fold columns.
To modify the default actions, pass a table with the actions you want to overwrite to the `setup()` function:

```lua
local cfg = {
  --- The click actions have the following signature:
  ---@param args (table): {
  ---   minwid = minwid,            -- 1st argument to 'statuscolumn' %@ callback
  ---   clicks = clicks,            -- 2nd argument to 'statuscolumn' %@ callback
  ---   button = button,            -- 3rd argument to 'statuscolumn' %@ callback
  ---   mods = mods,                -- 4th argument to 'statuscolumn' %@ callback
  ---   mousepos = f.getmousepos()  -- getmousepos() table, containing clicked line number/window id etc.
  --- }
  clickhandlers = {
    FoldOther = false,  -- Disable builtin clickhandler
    Lnum = function(args)
      if args.button == "l" and args.mods:find("c") then
        print("I Ctrl-left clicked on line "..args.mousepos.line)
      end
    end,
  }
}

require("statuscol").setup(cfg)
```

## Default click actions

Note that some of the default actions are for optional dependencies, and that right click requires [`'mousemodel' == "extend"`](https://neovim.io/doc/user/options.html#'mousem')
Below follows a list of builtin click actions.
**Sign/click action pair suggestions are welcome!**

|Sign|Button|Modifier|Action|
|----|------|--------|------|
|Lnum|Left||Toggle DAP breakpoint|
|Lnum|Left|<kbd>clickmod</kbd>|Toggle DAP conditional breakpoint|
|Lnum|Middle||Yank line|
|Lnum|Right||Paste line|
|Lnum|Right x2||Delete line|
|FoldClose|Left||Open fold|
|FoldClose|Left|<kbd>clickmod</kbd>|Open fold recursively|
|FoldOpen|Left||Close fold|
|FoldOpen|Left|<kbd>clickmod</kbd>|Close fold recursively|
|FoldClose/Other|Right||Delete fold|
|FoldClose/Other|Right|<kbd>clickmod</kbd>|Delete fold recursively|
|Fold*|Middle||Create fold in range(click twice)|
|Diagnostic*|Left||Open diagnostic float|
|Diagnostic*|Middle||Select available code action|
|GitSigns*|Left||Preview hunk|
|GitSigns*|Middle||Reset hunk|
|GitSigns*|Right||Stage hunk|

Optional dependencies:

* [nvim-dap](https://github.com/mfussenegger/nvim-dap)
* [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)
