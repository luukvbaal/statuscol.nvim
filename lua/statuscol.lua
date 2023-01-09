local a = vim.api
local f = vim.fn
local o = vim.o
local O = vim.opt
local S = vim.schedule
local M = {}
local signs = {}
local builtin

local cfg = {
	separator = " ",
	-- Builtin line number string options
	thousands = false,
	relculright = false,
	-- Custom line number string options
	lnumfunc = nil,
	reeval = false,
	-- Builtin 'statuscolumn' options
	setopt = false,
	order = "FSNs",
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
local function get_fold_action(minwid, clicks, button, mods)
	local foldopen = O.fillchars:get().foldopen or "-"
	local args = get_click_args(minwid, clicks, button, mods)
	local char = f.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
	local type = char == " " and "FoldEmpty" or char == foldopen and "FoldOpen" or "FoldClose"

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
	if cfg.lnumfunc then
		return cfg.lnumfunc()
	else
		return builtin.lnumfunc(o.number, o.relativenumber, cfg.thousands, cfg.relculright)
	end
end

-- Only return separator if the statuscolumn is non empty.
local function get_separator_string()
	local textoff = vim.fn.getwininfo(a.nvim_get_current_win())[1].textoff
	return tonumber(textoff) > 0 and cfg.separator or ""
end

function M.setup(user)
	builtin = require("statuscol.builtin")
	if user then cfg = vim.tbl_deep_extend("force", cfg, user) end
	cfg = vim.tbl_deep_extend("keep", cfg, builtin.clickhandlers)

	_G.ScFa = get_fold_action
	_G.ScSa = get_sign_action
	_G.ScLa = get_lnum_action
	_G.ScLn = get_lnum_string
	_G.ScSp = get_separator_string

	if cfg.setopt then
		local reeval = cfg.reeval or cfg.relculright
		local stc = ""

		for i = 1, #cfg.order do
			local segment = cfg.order:sub(i, i)
			if segment == "F" then
				stc = stc.."%@v:lua.ScFa@%C%T"
			elseif segment == "S" then
				stc = stc.."%@v:lua.ScSa@%s%T"
			elseif segment == "N" then
				stc = stc.."%@v:lua.ScLa@"
				stc = stc..(reeval and "%=%{v:lua.ScLn()}" or "%{%v:lua.ScLn()%}")
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
end

return M
