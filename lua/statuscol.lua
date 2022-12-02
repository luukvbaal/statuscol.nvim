local a = vim.api
local f = vim.fn
local c = vim.cmd
local o = vim.o
local S = vim.schedule
local M = {}
local signs = {}
local builtin = require("statuscol.builtin")

local cfg = {
	separator = " ",
	-- Builtin line number string options
	thousands = false,
	relculright = false,
	-- Custom line number string options
	lnumfunc = nil,
	reeval = false,
	-- Builtin 'statuscolumn' options
	statuscolumn = false,
	order = "FSNs",
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

--- Store defined signs without whitespace.
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

--- Execute fold column click callback.
function M.get_fold_action(minwid, clicks, button, mods)
	local args = get_click_args(minwid, clicks, button, mods)
	local type = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
	type = type == " " and "FoldEmpty" or type == "+" and "FoldPlus" or "FoldMinus"

	S(function() cfg[type](args) end)
end

--- Execute sign column click callback.
function M.get_sign_action(minwid, clicks, button, mods)
	local args = get_click_args(minwid, clicks, button, mods)
	local sign = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
	-- If clicked on empty space in the sign column, try one cell to the left
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

--- Execute line number click callback.
function M.get_lnum_action(minwid, clicks, button, mods)
	local args = get_click_args(minwid, clicks, button, mods)
	S(function() cfg.Lnum(args) end)
end

--- Return custom or builtin line number string
function M.get_lnum_string()
	if cfg.lnumfunc then
		return cfg.lnumfunc()
	else
		return builtin.lnumfunc(o.number, o.relativenumber, cfg.thousands, cfg.relculright)
	end
end

function M.setup(user)
	if user then cfg = vim.tbl_deep_extend("force", cfg, user) end

	c([[
		function! ScFa(a, b, c, d)
			call v:lua.require("statuscol").get_fold_action(a:a, a:b, a:c, a:d)
		endfunction
		function! ScSa(a, b, c, d)
			call v:lua.require("statuscol").get_sign_action(a:a, a:b, a:c, a:d)
		endfunction
		function! ScLa(a, b, c, d)
			call v:lua.require("statuscol").get_lnum_action(a:a, a:b, a:c, a:d)
		endfunction
		function! ScLn()
			return v:lua.require("statuscol").get_lnum_string()
		endfunction
	]])

	if cfg.statuscolumn then
		local reeval = cfg.reeval or cfg.relculright
		local stc = ""

		for i = 1, #cfg.order do
			local segment = cfg.order:sub(i, i)
			if segment == "F" then
				stc = stc.."%@ScFa@%C%T"
			elseif segment == "S" then
				stc = stc.."%@ScSa@%s%T"
			elseif segment == "N" then
				stc = stc.."%@ScLa@"
				stc = stc..(reeval and "%=%{ScLn()}" or "%{%ScLn()%}")
				-- End the click execute label if separator is not next
				if cfg.order:sub(i + 1, i + 1) ~= "s" then
					stc = stc.."%T"
				end
			elseif segment == "s" then
				-- Add click execute label if line number was not previous
				if cfg.order:sub(i - 1, i - 1) == "N" then
					stc = stc..cfg.separator.."%T"
				else
					stc = stc.."%@ScLa@"..cfg.separator.."%T"
				end
			end
		end

		o.statuscolumn = stc
	end
end

return M
