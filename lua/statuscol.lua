local a = vim.api
local f = vim.fn
local g = vim.g
local o = vim.o
local Ol = vim.opt_local
local S = vim.schedule
local v = vim.v
local contains = vim.tbl_contains
local M = {}
local builtin, ffi, error, C, lnumfunc, callargs
local cfg = {
  -- Builtin line number string options
  thousands = false,
  relculright = false,
  -- Builtin 'statuscolumn' options
  setopt = true,
  ft_ignore = nil,
  bt_ignore = nil,
  clickmod = "c",
  clickhandlers = {},
}
local lastid = 1
local nsmap = setmetatable({}, {
  __index = function(nsmap, key)
    local id = lastid
    local nextid = C.next_namespace_id
    local namemap = {}
    for name, nsid in pairs(a.nvim_get_namespaces()) do
      namemap[nsid] = name
    end
    while id < nextid do
      nsmap[id] = namemap[id] or ""
      id = id + 1
    end
    lastid = id - 1
    return nsmap[key]
  end,
})

local signsegments, signsegmentcount
--- Assign a sign to a segment based on name, text or namespace.
local function sign_assign_segment(s, win)
  local segment = 1
  while segment <= signsegmentcount do
    local ss = signsegments[segment]
    if ss.lnum and not ss.wins[win].sclnu then goto next end
    if s.sign_name then -- legacy sign
      for j = 1, ss.notnamecount do
        if s.sign_name:find(ss.notname[j]) then goto next end
      end
      for j = 1, ss.namecount do
        if s.sign_name:find(ss.name[j]) then goto found end
      end
    else -- extmark sign
      for j = 1, ss.nottextcount do
        if s.wtext:find(ss.nottext[j]) then goto next end
      end
      for j = 1, ss.notnamespacecount do
        if s.ns:find(ss.notnamespace[j]) then goto next end
      end
      for j = 1, ss.textcount do
        if s.wtext:find(ss.text[j]) then goto found end
      end
      for j = 1, ss.namespacecount do
        if s.ns:find(ss.namespace[j]) then goto found end
      end
    end
    ::next::
    segment = segment + 1
  end
  ::found::
  return segment <= signsegmentcount and segment
end

local sign_cache = {}
--- Update sign cache and assign segment to signs.
local function sign_cache_add(win, s, name)
  if not s.sign_name then s.ns = nsmap[s.ns_id] end
  s.wtext = s.sign_text:gsub("%s", "")
  s.segment = sign_assign_segment(s, win)
  if s.segment and signsegments[s.segment].colwidth == 1 then s.sign_text = s.wtext end
  sign_cache[name] = s
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
  local text = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
  -- When empty space is clicked try one cell to the left
  args.text = text ~= " " and text or f.screenstring(args.mousepos.screenrow, args.mousepos.screencol - 1)
  a.nvim_set_current_win(args.mousepos.winid)
  a.nvim_win_set_cursor(0, {args.mousepos.line, 0})
  return args
end

local function call_click_func(name, args)
  for pat, func in pairs(cfg.clickhandlers) do
    local handler = cfg.clickhandlers[name] or name:match(pat) and func
    if handler then
      S(function() handler(args) end)
      break
    end
  end
end

--- Execute fold column click callback.
local function get_fold_action(minwid, clicks, button, mods)
  local args = get_click_args(minwid, clicks, button, mods)
  local fold = callargs[args.mousepos.winid].fold
  local type = args.text == fold.open and "FoldOpen" or args.text == fold.close and "FoldClose" or "FoldOther"
  call_click_func(type, args)
end

local function get_sign_action_inner(args)
  local row = args.mousepos.line - 1
  for _, s in ipairs(a.nvim_buf_get_extmarks(0, -1, {row, 0}, {row, -1}, {type = "sign", details = true})) do
    if s[4].sign_text and s[4].sign_text:gsub("%s", "") == args.text then
      call_click_func(s[4].sign_name or nsmap[s[4].ns_id], args)
      return true
    end
  end
  return false
end

--- Execute sign column click callback.
local function get_sign_action(minwid, clicks, button, mods)
  local args = get_click_args(minwid, clicks, button, mods)
  get_sign_action_inner(args)
end

--- Execute line number click callback.
local function get_lnum_action(minwid, clicks, button, mods)
  local args = get_click_args(minwid, clicks, button, mods)
  local cargs = callargs[args.mousepos.winid]
  if lnumfunc and cargs.sclnu and get_sign_action_inner(args) then return end
  call_click_func("Lnum", args)
end

--- Place signs with sign text in sign segments.
local function place_signs(win, signs)
  local lines = {}
  for i = 1, #signs do
    local s = signs[i][4]
    if not s.sign_text then goto nextsign end

    local name = s.sign_name or s.sign_text
    if not s.sign_hl_group then s.sign_hl_group = "NoTexthl" end
    if not s.sign_name then name = name..s.sign_hl_group end
    if not sign_cache[name] then sign_cache_add(win, s, name) end
    local sign = sign_cache[name]
    if not sign.segment then goto nextsign end

    local ss = signsegments[sign.segment]
    local wss = ss.wins[win]
    local sss = wss.signs
    local lnum = signs[i][2] + 1

    if ss.foldclosed then
      a.nvim_win_call(win, function()
        if not lines[lnum] then lines[lnum] = f.foldclosed(lnum) end
        if lines[lnum] > 0 then
          lnum = lines[lnum]
          for j = lnum + 1, f.foldclosedend(lnum) do lines[j] = lnum end
        end
      end)
    end

    if not sss[lnum] then sss[lnum] = {} end
    -- Insert by priority. Potentially remove when nvim_buf_get_extmarks() can return sorted list.
    for j = 1, ss.maxwidth do
      if not sss[lnum][j] or s.priority > sss[lnum][j].priority then
        sss[lnum][ss.maxwidth] = nil
        table.insert(sss[lnum], j, sign)
        if wss.width < j then wss.width = j end
        break
      end
    end
    ::nextsign::
  end
end

local opts = {}
-- Update arguments passed to function text segments
local function update_callargs(args, win, tick)
  local buf = a.nvim_win_get_buf(win)
  args.buf = buf
  args.tick = tick
  opts.win = win
  args.nu = a.nvim_get_option_value("nu", opts)
  args.nuw = a.nvim_get_option_value("nuw", opts)
  args.rnu = a.nvim_get_option_value("rnu", opts)
  local culopt = a.nvim_get_option_value("culopt", opts)
  args.cul = a.nvim_get_option_value("cul", opts) and (culopt:find("nu") or culopt:find("bo"))
  args.sclnu = lnumfunc and a.nvim_get_option_value("scl", opts):find("nu")
  args.fold.width = C.compute_foldcolumn(args.wp, 0)
  if args.fold.width > 0 then
    local fcs = a.nvim_win_call(args.win, function() return Ol.fcs:get() end)
    args.fold.sep = fcs.foldsep or "│"
    args.fold.open = fcs.foldopen or "-"
    args.fold.close = fcs.foldclose or "+"
  end
  args.empty = C.win_col_off(args.wp) == 0
  if signsegmentcount - ((lnumfunc and not args.sclnu) and 1 or 0) > 0 then
    -- Retrieve signs for the entire buffer and store in "signsegments"
    -- by line number. Only do this if a "signs" segment was configured.
    local signs = a.nvim_buf_get_extmarks(buf, -1, 0, -1, {details = true, type = "sign"})
    for i = 1, signsegmentcount do
      local ss = signsegments[i]
      local wss = ss.wins[win]
      if ss.lnum and args.sclnu ~= wss.sclnu then
        sign_cache = {}
        wss.sclnu = args.sclnu
      end
      wss.width = 0
      wss.signs = {}
    end
    place_signs(win, signs)
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

local formatstr, formatargret, segments, segmentcount
--- Return 'statuscolumn' option value (%! item).
M.get_statuscol_string = function()
  -- Restored session may set 'statuscolumn' and call this before setup().
  if not callargs then return "" end
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

  for i = 1, segmentcount do
    local s = segments[i]
    formatargret[i] = (s.cond == true or s.cond(args))
      and (s.textfunc and s.text(args, s) or s.text) or ""
  end

  return formatstr:format(unpack(formatargret))
end

function M.setup(user)
  if f.has("nvim-0.10") == 0 then
    vim.notify("statuscol.nvim requires Neovim version >= 0.10", vim.log.levels.WARN)
    return
  end

  ffi = require("statuscol.ffidef")
  builtin = require("statuscol.builtin")
  error = ffi.new("Error")
  C = ffi.C
  callargs = {}
  formatstr = ""
  segments = {}
  signsegments = {}
  formatargret = {}
  segmentcount = 0
  signsegmentcount = 0

  cfg.clickhandlers = {
    Lnum                    = builtin.lnum_click,
    FoldClose               = builtin.foldclose_click,
    FoldOpen                = builtin.foldopen_click,
    FoldOther               = builtin.foldother_click,
    DapBreakpointRejected   = builtin.toggle_breakpoint,
    DapBreakpoint           = builtin.toggle_breakpoint,
    DapBreakpointCondition  = builtin.toggle_breakpoint,
    ["diagnostic/signs"]    = builtin.diagnostic_click,
    gitsigns                = builtin.gitsigns_click,
  }
  if user then cfg = vim.tbl_deep_extend("force", cfg, user) end
  builtin.init(cfg)

  local cfgsegments = cfg.segments or {
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
  for i = 1, #cfgsegments do
    local segment = cfgsegments[i]
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
      ss.foldclosed = ss.foldclosed or false
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
          if type(condition) == "boolean" then text = text:gsub("%%", "%%%%") end
        end
        if type(text) == "function" or type(condition) == "function" then
          formatstr = formatstr.."%s"
          segmentcount = segmentcount + 1
          segments[segmentcount] = {
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
  -- This list is used in sign_assign_segment() to make sure that signs that
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
    -- Go through all already open windows to set the option value.
    local stc = "%!v:lua.require('statuscol').get_statuscol_string()"
    a.nvim_set_option_value("stc", stc, {scope = 'global'})
    for _, tab in ipairs(a.nvim_list_tabpages()) do
      for _, win in ipairs(a.nvim_tabpage_list_wins(tab)) do
        local buf = a.nvim_win_get_buf(win)
        if not contains(cfg.ft_ignore or {}, a.nvim_get_option_value("ft", {buf = buf}))
          and not contains(cfg.bt_ignore or {}, a.nvim_get_option_value("bt", {buf = buf})) then
          a.nvim_set_option_value("stc", stc, {win = win})
        end
      end
    end
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
