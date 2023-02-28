local a = vim.api
local f = vim.fn
local g = vim.g
local o = vim.o
local Ol = vim.opt_local
local S = vim.schedule
local format = string.format
local M = {}
local signs = {}
local callargs = {}
local formatstr = ""
local formatargs = {}
local formatargret = {}
local formatargcount = 0
local builtin, ffi, error
local cfg = {
	-- Builtin line number string options
	thousands = false,
	relculright = false,
	-- Builtin 'statuscolumn' options
	setopt = true,
	ft_ignore = nil,
	clickhandlers = {},
}

--- Store defined signs without whitespace.
local function update_sign_defined()
	for _, sign in ipairs(f.sign_getdefined()) do
		if sign.text then
			signs[sign.name] = sign.text:gsub("%s","")
		end
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
local function get_fold_action(minwid, clicks, button, mods)
	local args = get_click_args(minwid, clicks, button, mods)
	local char = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
	local fcs = callargs[args.mousepos.winid].fcs
	local type = char == fcs.foldopen and "FoldOpen"
							 or char == fcs.foldclose and "FoldClose" or "FoldOther"
	S(function() cfg.clickhandlers[type](args) end)
end

--- Execute sign column click callback.
local function get_sign_action(minwid, clicks, button, mods)
	local args = get_click_args(minwid, clicks, button, mods)
	local sign = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
	-- If clicked on empty space in the sign column, try one cell to the left
	if sign == ' ' then
		sign = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol - 1)
	end

	if not signs[sign] then update_sign_defined() end
	for name, text in pairs(signs) do
		if text == sign and cfg.clickhandlers[name] then
			S(function() cfg.clickhandlers[name](args) end)
			break
		end
	end
end

--- Execute line number click callback.
local function get_lnum_action(minwid, clicks, button, mods)
	local args = get_click_args(minwid, clicks, button, mods)
	S(function() cfg.clickhandlers.Lnum(args) end)
end

-- Call argument if it is a function and return it's result or itself.
local function trycall(arg, win)
	if type(arg) == "function" then return arg(callargs[win]) end
	return arg
end

local function set_callargs(win)
	local fcs = Ol.fillchars:get()
	fcs.foldopen = fcs.foldopen or "-"
	fcs.foldclose = fcs.foldclose or "+"
	fcs.foldsep = fcs.foldsep or "│"
	callargs[win] = {
		win = win,
		wp = ffi.C.find_window_by_handle(win, error),
		thousands = cfg.thousands,
		culright = cfg.relculright,
		nu = a.nvim_win_get_option(win, "nu"),
		rnu = a.nvim_win_get_option(win, "rnu"),
		fcs = fcs
	}
end

--- Return 'statuscolumn' option value (%! item).
local function get_statuscol_string()
	local win = g.statusline_winid
	if not callargs[win] then set_callargs(win) end

	for i = 1, formatargcount do
		formatargret[i] = trycall(formatargs[i][2], win) and trycall(formatargs[i][1], win) or ""
	end

	return format(formatstr, unpack(formatargret))
end

function M.setup(user)
	ffi = require("statuscol.ffidef")
	builtin = require("statuscol.builtin")
	error = ffi.new("Error")

	cfg.clickhandlers = {
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
		GitSignsChangedelete   = builtin.gitsigns_click,
		GitSignsDelete         = builtin.gitsigns_click,
	}
	if user then cfg = vim.tbl_deep_extend("force", cfg, user) end
	builtin.init(cfg)

	cfg.segments = cfg.segments or {
		-- Default segments (fold -> sign -> line number -> separator)
		{ text = { "%C" }, click = "v:lua.ScFa" },
		{ text = { "%s" }, click = "v:lua.ScSa" },
		{
			text = { builtin.lnumfunc, " " },
			condition = { true, builtin.not_empty },
			click = "v:lua.ScLa",
		}
	}

	-- To improve performance of the 'statuscolumn' evaluation, we parse the
	-- "segments" here and convert it to a format string. Only the variable
	-- elements are evaluated each redraw.
	for i = 1, #cfg.segments do
		local segment = cfg.segments[i]
		if segment.hl then formatstr = formatstr.."%%#"..segment.hl.."#" end
		if segment.click then formatstr = formatstr.."%%@"..segment.click.."@" end
		for j = 1, #segment.text do
			local condition = segment.condition and segment.condition[j]
			if condition == nil then condition = true end
			if condition then
				local text = segment.text[j]
				if type(text) == "string" then text = text:gsub("%%", "%%%%") end
				if type(text) == "function" or type(condition) == "function" then
					formatstr = formatstr.."%s"
					formatargcount = formatargcount + 1
					formatargs[formatargcount] = { text, condition }
				else
					formatstr = formatstr..text
				end
			end
		end
		if segment.click then formatstr = formatstr.."%%T" end
		if segment.hl then formatstr = formatstr.."%%*" end
	end

	_G.ScFa = get_fold_action
	_G.ScSa = get_sign_action
	_G.ScLa = get_lnum_action

	local id = a.nvim_create_augroup("StatusCol", {})

	if cfg.setopt then
		_G.StatusCol = get_statuscol_string
		o.statuscolumn = "%!v:lua.StatusCol()"
		a.nvim_create_autocmd("OptionSet", {
			group = id,
			pattern = { "number", "relativenumber", "fillchars" },
			callback = function()
				set_callargs(a.nvim_get_current_win())
			end
		})
		a.nvim_create_autocmd("WinClosed", {
			group = id,
			callback = function(args)
				callargs[args.file] = nil
			end
		})
	end

	if cfg.ft_ignore then
		a.nvim_create_autocmd("FileType", { pattern = cfg.ft_ignore, group = id,
			command = "set statuscolumn="
		})
	end
end

return M
