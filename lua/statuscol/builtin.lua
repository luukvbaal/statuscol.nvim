local c = vim.cmd
local d = vim.diagnostic
local l = vim.lsp
local foldmarker
local M = {}

--- Create new fold by Ctrl-clicking the range
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

--- Handler for clicking '+' in fold column
function M.foldplus_click(args)
	fold_click(args, true)
end

--- Handler for clicking '-' in fold column
function M.foldminus_click(args)
	fold_click(args, false)
end

--- Handler for clicking ' ' in fold column
function M.foldempty_click(args)
	fold_click(args, false, true)
end

function M.diagnostic_click(args)
	if args.button == "l" then
		d.open_float()       -- Open diagnostic float on left click
	elseif args.button == "m" then
		l.buf.code_action()  -- Open code action on middle click
	end
end

function M.gitsigns_click(args)
	if args.button == "l" then
		require("gitsigns").preview_hunk()
	elseif args.button == "m" then
		require("gitsigns").reset_hunk()
	elseif args.button == "r" then
		require("gitsigns").stage_hunk()
	end
end

function M.toggle_breakpoint(args)
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

--- Handler for clicking the line number
function M.lnum_click(args)
	if args.button == "l" then
		-- Toggle DAP (conditional) breakpoint on (Ctrl-)left click
		M.toggle_breakpoint(args)
	elseif args.button == "m" then
		if args.clicks == 2 then
			c("norm! p")   -- Paste on double middle click
		else
			c("norm! yy")  -- Yank/Delete on middle click
		end
	elseif args.button == "r" then
		if args.clicks == 2 then
			c("norm! dd")  -- Cut on double right click
		end
	end
end

return M
