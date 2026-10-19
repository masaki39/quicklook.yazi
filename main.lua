--- @since 25.2.7

-- Preview any file macOS Quick Look can thumbnail (Office documents, iWork,
-- etc.) by rendering it to a PNG with `qlmanage -t` and showing that image.
-- Quick Look only renders the first page, so there is no paging.
-- Legacy binary formats (.xls/.doc/.ppt) go through Quick Look's HTML preview
-- instead; see `M:render_html`.
-- Files Quick Look can't render fall back to Yazi's built-in `file` previewer,
-- so this is safe to use as a catch-all (`url = "*"`) previewer.

local M = {}

local LEGACY = { xls = true, doc = true, ppt = true }

-- `qlmanage` never exits for files no Quick Look extension handles, so every
-- call is bounded by a timeout. Common binaries are skipped up front so
-- browsing them doesn't stall on that timeout.
local TIMEOUT = 3
local SKIP_MIMES = {
	["application/octet-stream"] = true,
	["application/x-mach-binary"] = true,
	["application/x-executable"] = true,
	["application/x-sharedlib"] = true,
	["application/x-object"] = true,
	["application/vnd.sqlite3"] = true,
}

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	local ok, err, unsupported = self:preload(job)
	if unsupported then
		return require("file"):peek(job)
	elseif not ok or err then
		return ya.preview_widget(job, err)
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))
	local _, show_err = ya.image_show(cache, job.area)
	ya.preview_widget(job, show_err)
end

function M:seek() end

function M:spot(job) require("file"):spot(job) end

-- Returns `ok, err, unsupported`; `unsupported` means Quick Look can't render
-- this file, and is remembered with a marker next to the cache so the timeout
-- is only paid once per file.
function M:preload(job)
	local cache = ya.file_cache(job)
	if not cache or fs.cha(cache) then
		return true
	end

	local marker = Url(tostring(cache) .. ".none")
	if SKIP_MIMES[job.mime or ""] or fs.cha(marker) then
		return true, nil, true
	end

	-- qlmanage writes its output into `-o <dir>` under a name derived from the
	-- source, so give each render its own scratch directory and move the
	-- result into place.
	local scratch = Url(tostring(cache) .. ".ql")
	fs.create("dir_all", scratch)

	local size = math.max(rt.preview.max_width, rt.preview.max_height)
	local png, err, unsupported
	if LEGACY[(job.file.url.ext or ""):lower()] then
		png, err, unsupported = self:render_html(job.file, scratch, size)
	else
		png, err, unsupported = self:render_thumbnail(job.file, scratch, size)
	end

	if not png then
		fs.remove("dir_all", scratch)
		if unsupported then
			fs.write(marker, "")
		end
		return true, err, unsupported
	end

	local ok, rename_err = fs.rename(png, cache)
	fs.remove("dir_all", scratch)
	if not ok then
		return true, Err("Failed to cache thumbnail, error: %s", rename_err)
	end
	return true
end

-- Run `name` to completion, killing it after `TIMEOUT` seconds. Returns
-- `true` on exit, or `nil, err, timed_out`.
local function run(name, args)
	local child, err = Command(name):arg(args):stdout(Command.NULL):stderr(Command.NULL):spawn()
	if not child then
		return nil, Err("Failed to start `%s`, error: %s", name, err)
	end

	local deadline = ya.time() + TIMEOUT
	while true do
		local status, wait_err = child:try_wait()
		if status then
			return true
		elseif wait_err then
			return nil, Err("Error while running `%s`: %s", name, wait_err)
		elseif ya.time() > deadline then
			child:start_kill()
			return nil, Err("`%s` timed out", name), true
		end
		ya.sleep(0.05)
	end
end

function M:render_thumbnail(file, scratch, size)
	local ok, err, timed_out = run("qlmanage", { "-t", "-s", tostring(size), "-o", tostring(scratch), tostring(file.url) })
	if not ok then
		return nil, err, timed_out
	end

	local png = scratch:join(file.name .. ".png")
	if not fs.cha(png) then
		return nil, Err("Quick Look produced no thumbnail for this file"), true
	end
	return png
end

-- Quick Look's *thumbnails* of the legacy binary formats drop CJK text whose
-- font isn't installed (e.g. ＭＳ 明朝), but its *previews* of them are HTML,
-- and WebKit falls back to an installed font the way Finder's space-bar
-- preview does. So for those, dump the HTML preview and rasterize it with
-- the `html2png` helper (built from `html2png/` in this repo) instead.
function M:render_html(file, scratch, size)
	local ok, err, timed_out = run("qlmanage", { "-p", "-o", tostring(scratch), tostring(file.url) })
	if not ok then
		return nil, err, timed_out
	end

	local dir = scratch:join(file.name .. ".qlpreview")
	local html = dir:join("Preview.html")
	local f = io.open(tostring(html), "r")
	if not f then
		return nil, Err("Quick Look produced no preview for this file"), true
	end
	-- Spreadsheets wrap the first sheet in an iframe under a tab bar; render
	-- the sheet itself so it gets the whole viewport.
	local sheet = f:read("*a"):match('<iframe id="SheetFrame" src="([^"]+)"')
	f:close()
	if sheet then
		html = dir:join(sheet)
	end

	local png = scratch:join("preview.png")
	ok, err = run("html2png", { tostring(html), tostring(png), tostring(size) })
	if not ok then
		return nil, err
	elseif not fs.cha(png) then
		return nil, Err("Failed to render Quick Look's HTML preview")
	end
	return png
end

return M
