local a = vim.api
local f = vim.fn
local g = vim.g
local o = vim.o
local Ol = vim.opt_local
local S = vim.schedule
local v = vim.v
local contains = vim.tbl_contains
local M = {}
local idmap = {}
local lastid = 1
local sign_cache = {}
local formatstr, formatargret, formatargs, formatargcount
local signsegments, signsegmentcount
local builtin, ffi, error, C, lnumfunc, callargs
local cfg = {
  -- Builtin line number string options
  thousands = false,
  relculright = false,
  -- Builtin 'statuscolumn' options
  setopt = true,
  ft_ignore = nil,
  clickmod = "c",
  clickhandlers = {},
}

--- Update namespace id -> name map.
local function update_nsidmap()
  local id = lastid
  local nextid = C.next_namespace_id
  local namemap = {}
  for name, nsid in pairs(a.nvim_get_namespaces()) do
    namemap[nsid] = name
  end
  while id < nextid do
    idmap[id] = namemap[id] or ""
    id = id + 1
  end
  lastid = id - 1
end

--- Update sign cache and assign segment to defined legacy signs or placed extmark signs.
local function update_sign_defined(win, ext, reassign)
  local signs = ext or f.sign_getdefined()
  for i = 1, #signs do
    local s = ext and signs[i][4] or signs[i]
    local name = ext and s.sign_text and s.sign_text..s.sign_hl_group or s.name
    if s.sign_text or s.text then
      if ext then
        s.text = s.sign_text
        if not idmap[s.ns_id] then update_nsidmap() end
        s.ns = idmap[s.ns_id]
      end
      s.wtext = s.text:gsub("%s", "")
      s.texthl = ext and s.sign_hl_group or s.texthl or "NoTexthl"
      if not reassign and sign_cache[name] then
        s.segment = sign_cache[name].segment
        goto nextsign
      end
      for j = 1, signsegmentcount do
        local ss = signsegments[j]
        if ss.lnum and not ss.wins[win].sclnu then goto nextsegment end
        if ext then -- extmarks: match by sign text or namespace
          for k = 1, ss.nottextcount do
            if s.wtext:find(ss.nottext[k]) then goto nextsegment end
          end
          for k = 1, ss.notnamespacecount do
            if s.ns:find(ss.notnamespace[k]) then goto nextsegment end
          end
          for k = 1, ss.textcount do
            if s.wtext:find(ss.text[k]) then
              s.segment = j
              goto nextsign
            end
          end
          for k = 1, ss.namespacecount do
            if s.ns:find(ss.namespace[k]) then
              s.segment = j
              goto nextsign
            end
          end
        else -- legacy sign: match by sign name
          for k = 1, ss.notnamecount do
            if s.name:find(ss.notname[k]) then goto nextsegment end
          end
          for k = 1, ss.namecount do
            if s.name:find(ss.name[k]) then
              s.segment = j
              goto nextsign
            end
          end
        end
        ::nextsegment::
      end
    end
    ::nextsign::
    if s.segment then
      if signsegments[s.segment].colwidth == 1 then s.text = s.wtext end
    end
    if name then sign_cache[name] = s end
  end
end

--- Store click args and fn.getmousepos() in table.
--- Set current window and mouse position to clicked line.
local function get_click_args(minwid, clicks, button, mods)
  local args = {
    minwid = minwid,
    clicks = clicks,
    button = button,
    mods = mods,
    mousepos = f.getmousepos(),
  }
  -- Avoid handling cmdline click, may be removed in 0.9.1: https://github.com/neovim/neovim/pull/23163
  if args.mousepos.winid == 0 then return end
  a.nvim_set_current_win(args.mousepos.winid)
  a.nvim_win_set_cursor(0, {args.mousepos.line, 0})
  return args
end

local function call_click_func(name, hl, args)
  local handler = cfg.clickhandlers[name] or cfg.clickhandlers[hl]
  if handler then S(function() handler(args) end) end
end

--- Execute fold column click callback.
local function get_fold_action(minwid, clicks, button, mods)
  local args = get_click_args(minwid, clicks, button, mods)
  if not args then return end
  local char = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
  local fold = callargs[args.mousepos.winid].fold
  local type = char == fold.open and "FoldOpen"
      or char == fold.close and "FoldClose" or "FoldOther"
  call_click_func(type, type, args)
end

local function get_sign_action_inner(args)
  local sign = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
  -- When empty space is clicked in the sign column, try one cell to the left
  if sign == " " then
    sign = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol - 1)
  end

  for name, s in pairs(sign_cache) do
    if s.wtext == sign then
      call_click_func(s.ns or name, s.texthl, args)
      return
    end
  end

  update_sign_defined(args.mousepos.winid)
  for name, s in pairs(sign_cache) do
    if s.wtext == sign then
      call_click_func(s.ns or name, s.texthl, args)
      return
    end
  end
end

--- Execute sign column click callback.
local function get_sign_action(minwid, clicks, button, mods)
  local args = get_click_args(minwid, clicks, button, mods)
  if not args then return end
  get_sign_action_inner(args)
end

--- Execute line number click callback.
local function get_lnum_action(minwid, clicks, button, mods)
  local args = get_click_args(minwid, clicks, button, mods)
  if not args then return end
  local cargs = callargs[args.mousepos.winid]
  if lnumfunc and cargs.sclnu then
    local placed = f.sign_getplaced(cargs.buf, {group = "*", lnum = args.mousepos.line})
    if #placed[1].signs > 0 then
      get_sign_action_inner(args)
      return
    end
  end
  call_click_func("Lnum", "Lnum", args)
end

--- Place (extmark) signs in sign segments.
local function place_signs(win, signs, ext)
  for i = 1, #signs do
    local s = ext and signs[i][4] or signs[i]
    local name = ext and s.sign_text and s.sign_text..s.sign_hl_group or s.name
    if ext and not name then goto nextsign end
    if not sign_cache[name] then update_sign_defined(win, ext and signs) end
    local sign = sign_cache[name]
    if not sign or not sign.segment then goto nextsign end
    local ss = signsegments[sign.segment]
    local wss = ss.wins[win]
    local sss = wss.signs
    local lnum = ext and signs[i][2] + 1 or s.lnum
    local width = (sss[lnum] and #sss[lnum] or 0) + 1
    if width > ss.maxwidth then
      if not ext then
        for j = 1, width - 1 do
          if sss[lnum][j].priority and s.priority > sss[lnum][j].priority then
            table.insert(sss[lnum], j, sign)
            sss[lnum][width] = nil
            goto nextsign
          end
        end
      end
      goto nextsign
    end
    if not sss[lnum] then sss[lnum] = {} end
    if wss.width < width then wss.width = width end
    sss[lnum][width] = sign
    ::nextsign::
  end
end

-- Update arguments passed to function text segments
local function update_callargs(args, win, tick)
  local fcs = Ol.fcs:get()
  local culopt = a.nvim_get_option_value("culopt", {win = win})
  local buf = a.nvim_win_get_buf(win)
  args.buf = buf
  args.tick = tick
  args.nu = a.nvim_get_option_value("nu", {win = win})
  args.rnu = a.nvim_get_option_value("rnu", {win = win})
  args.cul = a.nvim_get_option_value("cul", {win = win}) and (culopt:find("nu") or culopt:find("bo"))
  args.sclnu = lnumfunc and a.nvim_get_option_value("scl", {win = win}):find("nu")
  args.fold.sep = fcs.foldsep or "│"
  args.fold.open = fcs.foldopen or "-"
  args.fold.close = fcs.foldclose or "+"
  args.fold.width = C.compute_foldcolumn(args.wp, 0)
  args.empty = C.win_col_off(args.wp) == 0
  if signsegmentcount - ((lnumfunc and not args.sclnu) and 1 or 0) > 0 then
    -- Retrieve signs for the entire buffer and store in "signsegments"
    -- by line number. Only do this if a "signs" segment was configured.
    local extsigns = a.nvim_buf_get_extmarks(buf, -1, 0, -1, {details = true, type = "sign"})
    for i = 1, signsegmentcount do
      local ss = signsegments[i]
      local wss = ss.wins[win]
      if ss.lnum and args.sclnu ~= wss.sclnu then
        wss.sclnu = args.sclnu
        update_sign_defined(win, nil, true)
        update_sign_defined(win, extsigns, true)
      end
      wss.width = 0
      wss.signs = {}
    end
    place_signs(win, extsigns, true)
    place_signs(win, f.sign_getplaced(buf, {group = "*"})[1].signs, false)
    for i = 1, signsegmentcount do
      local ss = signsegments[i]
      local wss = ss.wins[win]
      if ss.auto then
        wss.empty = ss.fillchar:rep(wss.width * ss.colwidth)
        wss.padwidth = ss.wins[win].width
      end
    end
  end
end

--- Return 'statuscolumn' option value (%! item).
local function get_statuscol_string()
  local win = g.statusline_winid
  local args = callargs[win]
  local tick = C.display_tick

  if not args then
    args = {win = win, wp = C.find_window_by_handle(win, error), fold = {}, tick = 0}
    callargs[win] = args
    for i = 1, signsegmentcount do
      local ss = signsegments[i]
      ss.wins[win] = {padwidth = ss.maxwidth, empty = ss.fillchar:rep(ss.maxwidth * ss.colwidth)}
    end
    tick = 1
  end

  -- faster if segments only index args rather than vim.v
  args.lnum = v.lnum
  args.relnum = v.relnum
  args.virtnum = v.virtnum

  -- once per window per redraw
  if args.tick < tick then
    update_callargs(args, win, tick)
  end

  for i = 1, formatargcount do
    local fa = formatargs[i]
    formatargret[i] = (fa.cond == true or fa.cond(args))
      and (fa.textfunc and fa.text(args, fa) or fa.text) or ""
  end

  return formatstr:format(unpack(formatargret))
end

function M.setup(user)
  if f.has("nvim-0.9") == 0 then
    vim.notify("statuscol.nvim requires Neovim version >= 0.9", vim.log.levels.WARN)
    return
  end

  ffi = require("statuscol.ffidef")
  builtin = require("statuscol.builtin")
  error = ffi.new("Error")
  C = ffi.C
  callargs = {}
  formatstr = ""
  formatargs = {}
  signsegments = {}
  formatargret = {}
  formatargcount = 0
  signsegmentcount = 0

  cfg.clickhandlers = {
    Lnum                    = builtin.lnum_click,
    FoldClose               = builtin.foldclose_click,
    FoldOpen                = builtin.foldopen_click,
    FoldOther               = builtin.foldother_click,
    DapBreakpointRejected   = builtin.toggle_breakpoint,
    DapBreakpoint           = builtin.toggle_breakpoint,
    DapBreakpointCondition  = builtin.toggle_breakpoint,
    DiagnosticSignError     = builtin.diagnostic_click,
    DiagnosticSignHint      = builtin.diagnostic_click,
    DiagnosticSignInfo      = builtin.diagnostic_click,
    DiagnosticSignWarn      = builtin.diagnostic_click,
    GitSignsTopdelete       = builtin.gitsigns_click,
    GitSignsUntracked       = builtin.gitsigns_click,
    GitSignsAdd             = builtin.gitsigns_click,
    GitSignsChange          = builtin.gitsigns_click,
    GitSignsChangedelete    = builtin.gitsigns_click,
    GitSignsDelete          = builtin.gitsigns_click,
    gitsigns_extmark_signs_ = builtin.gitsigns_click,
  }
  if user then cfg = vim.tbl_deep_extend("force", cfg, user) end
  if cfg.order then
    vim.notify('The "order" configuration key is deprecated. Refer to the "segments" key in |statuscol-configuration| instead.', vim.log.levels.WARN)
  end
  builtin.init(cfg)

  local segments = cfg.segments or {
    -- Default segments (fold -> sign -> line number -> separator)
    {text = {"%C"}, click = "v:lua.ScFa"},
    {text = {"%s"}, click = "v:lua.ScSa"},
    {
      text = {builtin.lnumfunc, " "},
      condition = {true, builtin.not_empty},
      click = "v:lua.ScLa",
    },
  }

  -- To improve performance of the 'statuscolumn' evaluation, we parse the
  -- "segments" here and convert it to a format string. Only the variable
  -- elements are evaluated each redraw.
  local setscl
  for i = 1, #segments do
    local segment = segments[i]
    if segment.text and contains(segment.text, builtin.lnumfunc) then
      lnumfunc = true
      segment.sign = segment.sign or {name = {".*"}, text = {".*"}}
      segment.sign.lnum = true
    end
    local ss = segment.sign
    if ss then
      signsegmentcount = signsegmentcount + 1
      signsegments[signsegmentcount] = ss
      ss.wins = {}
      ss.name = ss.name or {}
      ss.text = ss.text or {}
      ss.namespace = ss.namespace or {}
      ss.namecount = #ss.name
      ss.textcount = #ss.text
      ss.namespacecount = #ss.namespace
      ss.auto = ss.auto or false
      ss.maxwidth = ss.maxwidth or 1
      ss.colwidth = ss.colwidth or 2
      ss.fillchar = ss.fillchar or " "
      if ss.fillcharhl then ss.fillcharhl = "%#"..ss.fillcharhl.."#" end
      if setscl ~= false then setscl = true end
      if not segment.text then segment.text = {builtin.signfunc} end
    end
    if segment.hl then formatstr = formatstr.."%%#"..segment.hl.."#" end
    if segment.click then formatstr = formatstr.."%%@"..segment.click.."@" end
    for j = 1, #segment.text do
      local condition = segment.condition and segment.condition[j]
      if condition == nil then condition = true end
      if condition then
        local text = segment.text[j]
        if type(text) == "string" then
          if text:find("%%s") then setscl = false end
          text = text:gsub("%%", "%%%%")
        end
        if type(text) == "function" or type(condition) == "function" then
          formatstr = formatstr.."%s"
          formatargcount = formatargcount + 1
          formatargs[formatargcount] = {
            text = text,
            textfunc = type(text) == "function",
            cond = condition,
            sign = ss,
          }
        else
          formatstr = formatstr..text
        end
      end
    end
    if segment.click then formatstr = formatstr.."%%T" end
    if segment.hl then formatstr = formatstr.."%%*" end
  end
  if setscl and o.scl ~= "number" then o.scl = "no" end
  -- For each sign segment, store the name patterns from other sign segments.
  -- This list is used in update_sign_defined() to make sure that signs that
  -- have a dedicated segment do not get placed in a wildcard(".*") segment.
  if signsegmentcount > 0 then
    for i = 1, signsegmentcount do
      local ss = signsegments[i]
      ss.notname = {}
      ss.nottext = {}
      ss.notnamespace = {}
      ss.notnamecount = 0
      ss.nottextcount = 0
      ss.notnamespacecount = 0
      for j = 1, signsegmentcount do
        if j ~= i then
          local sso = signsegments[j]
          for k = 1, #sso.name do
            if sso.name[k] ~= ".*" then
              ss.notnamecount = ss.notnamecount + 1
              ss.notname[ss.notnamecount] = sso.name[k]
            end
          end
          for k = 1, #sso.text do
            if sso.text[k] ~= ".*" then
              ss.nottextcount = ss.nottextcount + 1
              ss.nottext[ss.nottextcount] = sso.text[k]
            end
          end
          for k = 1, #sso.namespace do
            if sso.namespace[k] ~= ".*" then
              ss.notnamespacecount = ss.notnamespacecount + 1
              ss.notnamespace[ss.notnamespacecount] = sso.namespace[k]
            end
          end
        end
      end
    end
    a.nvim_set_hl(0, "NoTexthl", {fg = "NONE"})
  end

  _G.ScFa = get_fold_action
  _G.ScSa = get_sign_action
  _G.ScLa = get_lnum_action

  local id = a.nvim_create_augroup("StatusCol", {})

  if cfg.setopt then
    _G.StatusCol = get_statuscol_string
    o.statuscolumn = "%!v:lua.StatusCol()"
    a.nvim_create_autocmd("WinClosed", {
      group = id,
      callback = function(args)
        callargs[args.file] = nil
        for i = 1, signsegmentcount do
          signsegments[i].wins[args.file] = nil
        end
      end,
    })
  end

  if cfg.ft_ignore then
    a.nvim_create_autocmd("FileType", {group = id, pattern = cfg.ft_ignore, command = "setlocal stc="})
    a.nvim_create_autocmd("BufWinEnter", {
      group = id,
      callback = function()
        if contains(cfg.ft_ignore, a.nvim_get_option_value("ft", {scope = "local"})) then
          a.nvim_set_option_value("stc", "", {scope = "local"})
        end
      end,
    })
  end

  if cfg.bt_ignore then
    a.nvim_create_autocmd("OptionSet", {
      group = id,
      pattern = "buftype",
      callback = function()
        if contains(cfg.bt_ignore, vim.v.option_new) then
          a.nvim_set_option_value("stc", "", {scope = "local"})
        end
      end,
    })
    a.nvim_create_autocmd("BufWinEnter", {
      group = id,
      callback = function()
        if contains(cfg.bt_ignore, a.nvim_get_option_value("bt", {scope = "local"})) then
          a.nvim_set_option_value("stc", "", {scope = "local"})
        end
      end,
    })
  end
end

return M
