local a = vim.api
local f = vim.fn
local o = vim.o
local O = vim.opt
local S = vim.schedule
local M = {}
local signs = {}
local builtin, ffi
local cfg = {
	separator = " ",
	-- Builtin line number string options
	thousands = false,
	relculright = false,
	-- Custom line number string options
	lnumfunc = nil,
	reeval = false,
	-- Custom fold column string options
	foldfunc = nil,
	-- Builtin 'statuscolumn' options
	setopt = false,
	order = "FSNs",
	ft_ignore = nil,
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
	local fillchars = O.fillchars:get()
	local fo = fillchars.foldopen or "-"
	local fc = fillchars.foldclose or "+"
	local args = get_click_args(minwid, clicks, button, mods)
	local char = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
	local type = char == fo and "FoldOpen" or char == fc and "FoldClose" or "FoldOther"

	S(function() cfg[type](args) end)
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
		if text == sign and cfg[name] then
			S(function() cfg[name](args) end)
			break
		end
	end
end

--- Execute line number click callback.
local function get_lnum_action(minwid, clicks, button, mods)
	local args = get_click_args(minwid, clicks, button, mods)
	S(function() cfg.Lnum(args) end)
end

--- Return custom or builtin line number string.
local function get_lnum_string()
	return cfg.lnumfunc(o.number, o.relativenumber, cfg.thousands, cfg.relculright)
end

--- Return custom or builtin fold column string.
local function get_fold_string()
	local wp = ffi.C.find_window_by_handle(0, ffi.new("Error"))
	local width = ffi.C.compute_foldcolumn(wp, 0)
	local foldinfo

	if width > 0 then
		foldinfo = ffi.C.fold_info(wp, vim.v.lnum)
	else
		foldinfo = { start = 0, level = 0, llevel = 0, lines = 0 }
	end

	return cfg.foldfunc(foldinfo, width)
end

-- Only return separator if the statuscolumn is non empty.
local function get_separator_string()
	local textoff = ffi.C.win_col_off(ffi.C.find_window_by_handle(0, ffi.new("Error")))
	return textoff > 0 and cfg.separator or ""
end

function M.setup(user)
	ffi = require("statuscol.ffidef")
	builtin = require("statuscol.builtin")
	if user then cfg = vim.tbl_deep_extend("force", cfg, user) end
	cfg = vim.tbl_deep_extend("keep", cfg, builtin.clickhandlers)

	if not cfg.lnumfunc then cfg.lnumfunc = builtin.lnumfunc end
	if cfg.foldfunc then
		if cfg.foldfunc == "builtin" then cfg.foldfunc = builtin.foldfunc end
	end

	_G.ScFa = get_fold_action
	_G.ScFc = get_fold_string
	_G.ScSa = get_sign_action
	_G.ScLa = get_lnum_action
	_G.ScLn = get_lnum_string
	_G.ScSp = get_separator_string

	if cfg.setopt then
		local stc = ""
		local reeval = cfg.reeval or not cfg.relculright

		for i = 1, #cfg.order do
			local segment = cfg.order:sub(i, i)
			if segment == "F" then
				local fold = cfg.foldfunc and "%{%v:lua.ScFc()%}" or "%C"
				stc = stc.."%@v:lua.ScFa@"..fold.."%T"
			elseif segment == "S" then
				stc = stc.."%@v:lua.ScSa@%s%T"
			elseif segment == "N" then
				stc = stc.."%@v:lua.ScLa@"..(cfg.relculright and "%=" or "")
				stc = stc..(reeval and "%{%v:lua.ScLn()%}" or "%{v:lua.ScLn()}")
				-- End the click execute label if separator is not next
				if cfg.order:sub(i + 1, i + 1) ~= "s" then
					stc = stc.."%T"
				end
			elseif segment == "s" then
				-- Add click execute label if line number was not previous
				if cfg.order:sub(i - 1, i - 1) == "N" then
					stc = stc.."%{v:lua.ScSp()}%T"
				else
					stc = stc.."%@v:lua.ScLa@%{v:lua.ScSp()}%T"
				end
			end
		end

		o.statuscolumn = stc
	end

	if cfg.ft_ignore then
		local group = a.nvim_create_augroup("StatusCol", { clear = true })
		a.nvim_create_autocmd("FileType", { pattern = cfg.ft_ignore, group = group,
			command = "set statuscolumn="
		})
	end
end

return M
