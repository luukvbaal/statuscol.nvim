local c = vim.cmd
local d = vim.diagnostic
local l = vim.lsp
local v = vim.v
local foldmarker
local M = {}

-- Return line number in configured format.
function M.lnumfunc(number, relativenumber, thousands, relculright)
	if v.wrap or (not relativenumber and not number) then return "" end
	local lnum = v.lnum

	if relativenumber then
		lnum = v.relnum > 0 and v.relnum or (number and lnum or 0)
	end

	if thousands and lnum > 999 then
		lnum = string.reverse(lnum):gsub("%d%d%d", "%1"..thousands):reverse():gsub("^%"..thousands, "")
	end

	if not relculright then
		if relativenumber then
			lnum = (v.relnum > 0 and "%=" or "")..lnum..(v.relnum > 0 and "" or "%=")
		else
			lnum = "%="..lnum
		end
	end

	return lnum
end

--- Create new fold by Ctrl-clicking the range.
local function create_fold(args)
	if foldmarker then
		c("norm! zf"..foldmarker.."G")
		foldmarker = nil
	else
		foldmarker = args.mousepos.line
	end
end

local function fold_click(args, open, empty)
	if not args.mods:find("c") then foldmarker = nil end
	-- Create fold on middle click
	if args.button == "m" then create_fold(args) end
	if empty then return end

	if args.button == "l" then  -- Open/Close (recursive) fold on (Ctrl)-click
		if open then
			c("norm! z"..(args.mods:find("c") and "O" or "o"))
		else
			c("norm! z"..(args.mods:find("c") and "C" or "c"))
		end
	elseif args.button == "r" then  -- Delete (recursive) fold on (Ctrl)-right click
		c("norm! z"..(args.mods:find("c") and "D" or "d"))
	end
end

--- Handler for clicking '+' in fold column.
local function foldplus_click(args)
	fold_click(args, true)
end

--- Handler for clicking '-' in fold column.
local function foldminus_click(args)
	fold_click(args, false)
end

--- Handler for clicking ' ' in fold column.
local function foldempty_click(args)
	fold_click(args, false, true)
end

--- Handler for clicking a Diagnostc* sign.
local function diagnostic_click(args)
	if args.button == "l" then
		d.open_float()       -- Open diagnostic float on left click
	elseif args.button == "m" then
		l.buf.code_action()  -- Open code action on middle click
	end
end

--- Handler for clicking a GitSigns* sign.
local function gitsigns_click(args)
	if args.button == "l" then
		require("gitsigns").preview_hunk()
	elseif args.button == "m" then
		require("gitsigns").reset_hunk()
	elseif args.button == "r" then
		require("gitsigns").stage_hunk()
	end
end

--- Toggle a (conditional) DAP breakpoint.
local function toggle_breakpoint(args)
	local dap = vim.F.npcall(require, "dap")
	if not dap then return end
	if args.mods:find("c") then
		vim.ui.input({ prompt = "Breakpoint condition: " }, function(input)
			dap.set_breakpoint(input)
		end)
	else
		dap.toggle_breakpoint()
	end
end

--- Handler for clicking the line number.
local function lnum_click(args)
	if args.button == "l" then
		-- Toggle DAP (conditional) breakpoint on (Ctrl-)left click
		toggle_breakpoint(args)
	elseif args.button == "m" then
		c("norm! yy")  -- Yank on middle click
	elseif args.button == "r" then
		if args.clicks == 2 then
			c("norm! dd")  -- Cut on double right click
		else
			c("norm! p")   -- Paste on right click
		end
	end
end

M.clickhandlers = {
	Lnum                   = lnum_click,
	FoldPlus               = foldplus_click,
	FoldMinus              = foldminus_click,
	FoldEmpty              = foldempty_click,
	DapBreakpointRejected  = toggle_breakpoint,
	DapBreakpoint          = toggle_breakpoint,
	DapBreakpointCondition = toggle_breakpoint,
	DiagnosticSignError    = diagnostic_click,
	DiagnosticSignHint     = diagnostic_click,
	DiagnosticSignInfo     = diagnostic_click,
	DiagnosticSignWarn     = diagnostic_click,
	GitSignsTopdelete      = gitsigns_click,
	GitSignsUntracked      = gitsigns_click,
	GitSignsAdd            = gitsigns_click,
	GitSignsChangedelete   = gitsigns_click,
	GitSignsDelete         = gitsigns_click,
}

return M
