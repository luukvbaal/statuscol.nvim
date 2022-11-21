local a = vim.api
local f = vim.fn
local c = vim.cmd
local S = vim.schedule
local M = {}
local signs = {}
local builtin = require("statuscol.builtin")

local cfg = {
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

--- Store defined signs without whitespace
local function update_sign_defined()
	for _, sign in ipairs(f.sign_getdefined()) do
		signs[sign.name] = sign.text:gsub("%s","")
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
		mousepos = f.getmousepos()
	}
	a.nvim_set_current_win(args.mousepos.winid)
	a.nvim_win_set_cursor(0, {args.mousepos.line, 0})
	return args
end

--- Run fold action
function M.get_fold_action(minwid, clicks, button, mods)
	local args = get_click_args(minwid, clicks, button, mods)
	local type = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
	type = type == " " and "FoldEmpty" or type == "+" and "FoldPlus" or "FoldMinus"

	if (cfg[type]) then
		S(function() cfg[type](args) end)
	end
end

--- Run line number action
function M.get_lnum_action(minwid, clicks, button, mods)
	local args = get_click_args(minwid, clicks, button, mods)
	if (cfg.Lnum) then
		S(function() cfg.Lnum(args) end)
	end
end

--- Run sign action
function M.get_sign_action(minwid, clicks, button, mods)
	local args = get_click_args(minwid, clicks, button, mods)
	local sign = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
	if sign == ' ' then
		sign = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol - 1)
	end

	if not signs[sign] then update_sign_defined() end
	for name, text in pairs(signs) do
		if text == sign and cfg[name] then
			S(function() cfg[name](args) end)
			break
		end
	end
end

function M.setup(setup_cfg)
	if setup_cfg then cfg = vim.tbl_deep_extend("force", cfg, setup_cfg) end

	c([[
	function! StcFold(a, b, c, d)
	call v:lua.require("statuscol").get_fold_action(a:a, a:b, a:c, a:d)
	endfunction
	function! StcSign(a, b, c, d)
	call v:lua.require("statuscol").get_sign_action(a:a, a:b, a:c, a:d)
	endfunction
	function! StcLNum(a, b, c, d)
	call v:lua.require("statuscol").get_lnum_action(a:a, a:b, a:c, a:d)
	endfunction
	]])
end

return M
