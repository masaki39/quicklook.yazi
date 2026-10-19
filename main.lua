--- @since 25.2.7

-- Preview any file macOS Quick Look can thumbnail (Office documents, iWork,
-- etc.) by rendering it to a PNG with `qlmanage -t` and showing that image.
-- Quick Look only renders the first page, so there is no paging.
-- Legacy binary formats (.xls/.doc/.ppt) go through Quick Look's HTML preview
-- instead; see `M:render_html`.

local M = {}

local LEGACY = { xls = true, doc = true, ppt = true }

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	local ok, err = self:preload(job)
	if not ok or err then
		return ya.preview_widget(job, err)
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))
	local _, show_err = ya.image_show(cache, job.area)
	ya.preview_widget(job, show_err)
end

function M:seek() end

function M:preload(job)
	local cache = ya.file_cache(job)
	if not cache or fs.cha(cache) then
		return true
	end

	-- qlmanage writes its output into `-o <dir>` under a name derived from the
	-- source, so give each render its own scratch directory and move the
	-- result into place.
	local scratch = Url(tostring(cache) .. ".ql")
	fs.create("dir_all", scratch)

	local size = math.max(rt.preview.max_width, rt.preview.max_height)
	local png, err
	if LEGACY[(job.file.url.ext or ""):lower()] then
		png, err = self:render_html(job.file, scratch, size)
	else
		png, err = self:render_thumbnail(job.file, scratch, size)
	end

	if not png then
		fs.remove("dir_all", scratch)
		return true, err
	end

	local ok, rename_err = fs.rename(png, cache)
	fs.remove("dir_all", scratch)
	if not ok then
		return true, Err("Failed to cache thumbnail, error: %s", rename_err)
	end
	return true
end

local function run(name, args)
	local output, err = Command(name):arg(args):stdout(Command.NULL):stderr(Command.NULL):output()
	if not output then
		return nil, Err("Failed to start `%s`, error: %s", name, err)
	end
	return output
end

function M:render_thumbnail(file, scratch, size)
	local output, err = run("qlmanage", { "-t", "-s", tostring(size), "-o", tostring(scratch), tostring(file.url) })
	if not output then
		return nil, err
	end

	local png = scratch:join(file.name .. ".png")
	if not fs.cha(png) then
		return nil, Err("Quick Look produced no thumbnail for this file")
	end
	return png
end

-- Quick Look's *thumbnails* of the legacy binary formats drop CJK text whose
-- font isn't installed (e.g. ＭＳ 明朝), but its *previews* of them are HTML,
-- and WebKit falls back to an installed font the way Finder's space-bar
-- preview does. So for those, dump the HTML preview and rasterize it with
-- the `html2png` helper (built from `html2png/` in this repo) instead.
function M:render_html(file, scratch, size)
	local output, err = run("qlmanage", { "-p", "-o", tostring(scratch), tostring(file.url) })
	if not output then
		return nil, err
	end

	local dir = scratch:join(file.name .. ".qlpreview")
	local html = dir:join("Preview.html")
	local f = io.open(tostring(html), "r")
	if not f then
		return nil, Err("Quick Look produced no preview for this file")
	end
	-- Spreadsheets wrap the first sheet in an iframe under a tab bar; render
	-- the sheet itself so it gets the whole viewport.
	local sheet = f:read("*a"):match('<iframe id="SheetFrame" src="([^"]+)"')
	f:close()
	if sheet then
		html = dir:join(sheet)
	end

	local png = scratch:join("preview.png")
	output, err = run("html2png", { tostring(html), tostring(png), tostring(size) })
	if not output then
		return nil, err
	elseif not fs.cha(png) then
		return nil, Err("Failed to render Quick Look's HTML preview")
	end
	return png
end

return M
