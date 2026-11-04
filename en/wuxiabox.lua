id       = "wuxiabox"
name     = "WuxiaBox"
version  = "1.2.0"
baseUrl  = "https://www.wuxiabox.com/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/wuxiabox.png"

-- ── Хелперы ──

local function absUrl(href)
	if not href or href == "" then return "" end
	if string_starts_with(href, "http") then return href end
	if string_starts_with(href, "//") then return "https:" .. href end
	return url_resolve(baseUrl, href)
end

-- ── Session Document Cache ───────────────────────────────────────────────────
local _bookDocCache = {}

local function fetchBookDoc(url)
	if _bookDocCache[url] then return _bookDocCache[url] end
	local r = http_get(url)
	if r.success then
		local doc = r:toHtml()
		_bookDocCache[url] = doc
		return doc
	end
	return nil
end

local function applyStandardContentTransforms(str)
	if not str or str == "" then return "" end
	str = string_normalize(str)
	local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/+$", "")
	str = regex_replace(str, "(?i)" .. domain .. ".*?\\n", "")
	str = regex_replace(str, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+|Глава\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
	str = regex_replace(str, "(?im)^\\s*(Translator|Editor|Proofreader|T/N|E/N|Перевод|Редакция|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
	return string_trim(str)
end

-- Относительная дата ("N days ago") -> YYYY-MM-DD (текущая дата минус N).
local function normalizeUpdateDate(relative)
	if not relative or relative == "" then return nil end
	local n, unit = string.match(relative, "(%d+)%s+(%w+)%s+ago")
	if not n then return nil end
	local mult = {
		minute = 60, minutes = 60,
		hour = 3600, hours = 3600,
		day = 86400, days = 86400,
		week = 7 * 86400, weeks = 7 * 86400,
		month = 30 * 86400, months = 30 * 86400,
		year = 365 * 86400, years = 365 * 86400,
	}
	local secs = mult[unit]
	if not secs then return nil end
	return os.date("%Y-%m-%d", os.time() - n * secs)
end

local function getSlug(bookUrl)
	return string.match(bookUrl, "([^/]+)%.html")
end

local function parseItems(doc)
	local items = {}
	local cards = doc:select("ul.novel-list li.novel-item")
	for _, card in ipairs(cards) do
		local a = card:selectFirst("a[href]")
		if a then
			local title = card:selectFirst("h4.novel-title")
			local img = card:selectFirst("figure.novel-cover img, .cover img")
			local cover = img and (img:attr("data-src") ~= "" and img:attr("data-src") or img:attr("src")) or ""
			table.insert(items, {
				title = string_clean(title and title:text() or ""),
				url = absUrl(a:attr("href")),
				cover = absUrl(cover),
			})
		end
	end
	return { items = items, hasNext = false }
end

local function hasNextCatalog(doc, index)
	local pageLinks = doc:select("ul.pagination a[href]")
	local target = "-" .. tostring(index + 1) .. ".html"
	for _, l in ipairs(pageLinks) do
		if string_ends_with(l:attr("href") or "", target) then
			return true
		end
	end
	return false
end

-- ── Каталог ──

function getCatalogList(index)
	local page = index or 0
	local url = baseUrl .. "list/all/all-onclick-" .. tostring(page) .. ".html"
	local r = http_get(url)
	if not r.success then return { items = {}, hasNext = false } end
	local doc = r:toHtml()
	local res = parseItems(doc)
	res.hasNext = hasNextCatalog(doc, page)
	return res
end

-- ── Поиск (EMPire: POST -> redirect -> result) ──

function getCatalogSearch(index, query)
	local page = index or 0
	if page > 0 then return { items = {}, hasNext = false } end
	local url = baseUrl .. "e/search/index.php"
	local r = http_post(url, "show=title&tempid=1&tbname=news&keyboard=" .. url_encode(query),
		{ headers = { ["Content-Type"] = "application/x-www-form-urlencoded" } })
	if not r.success then return { items = {}, hasNext = false } end
	local doc = r:toHtml()
	local res = parseItems(doc)
	res.hasNext = false
	return res
end

-- ── Детали книги ──

function getBookTitle(bookUrl)
	local doc = fetchBookDoc(bookUrl)
	if not doc then return nil end
	local el = doc:selectFirst("h1.novel-title")
	return el and string_clean(el:text()) or nil
end

function getBookCoverImageUrl(bookUrl)
	local doc = fetchBookDoc(bookUrl)
	if not doc then return nil end
	local img = doc:selectFirst(".cover img")
	if not img then return nil end
	local cover = img:attr("data-src")
	if cover == "" then cover = img:attr("src") end
	return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
	local doc = fetchBookDoc(bookUrl)
	if not doc then return nil end
	local el = doc:selectFirst("p.description")
	if not el then el = doc:selectFirst(".summary .content") end
	return el and string_trim(el:text()) or nil
end

function getBookGenres(bookUrl)
	local doc = fetchBookDoc(bookUrl)
	if not doc then return nil end
	local tags = doc:select(".categories ul li a.property-item")
	local genres = {}
	for _, t in ipairs(tags) do
		local val = string_clean(t:text())
		if val ~= "" then table.insert(genres, val) end
	end
	return #genres > 0 and genres or nil
end

-- ── Status / Last update ──

function getBookStatus(bookUrl)
	local doc = fetchBookDoc(bookUrl)
	if not doc then return nil end
	local el = doc:selectFirst(".header-stats span:nth-child(2) strong")
	return el and string_clean(el:text()) or nil
end

function getBookLastUpdate(bookUrl)
	local doc = fetchBookDoc(bookUrl)
	if not doc then return nil end
	local times = doc:select("ul.chapter-list time.chapter-update")
	if #times == 0 then return nil end
	local last = times[#times]
	return normalizeUpdateDate(string_trim(last:text()))
end

-- ── Список глав (parsePage, AJAX fy.php) ──

local _totalPagesCache = {}

function parsePage(bookUrl, page)
	local slug = getSlug(bookUrl)
	if not slug then return { chapters = {}, totalPages = 1 } end

	if not _totalPagesCache[bookUrl] then
		local doc = fetchBookDoc(bookUrl)
		if doc then
			local nextLinks = doc:select("ul.pagination a[href]")
			local totalPages = 1
			for _, l in ipairs(nextLinks) do
				local txt = l:text()
				local href = l:attr("href") or ""
				if string_trim(txt) == ">>" and string.find(href, "fy.php") then
					local num = tonumber(string.match(href, "page=(%d+)"))
					if num then totalPages = num + 1 end
				end
			end
			_totalPagesCache[bookUrl] = totalPages
		else
			_totalPagesCache[bookUrl] = 1
		end
	end
	local totalPages = _totalPagesCache[bookUrl]

	local sitePage = page - 1
	local url = baseUrl .. "e/extend/fy.php?page=" .. tostring(sitePage) .. "&wjm=" .. slug
	local r = http_get(url, { headers = { ["X-Requested-With"] = "XMLHttpRequest", Accept = "text/html" } })
	if not r.success then return { chapters = {}, totalPages = totalPages } end
	local doc = r:toHtml()

	local chapters = {}
	local links = doc:select("ul.chapter-list li a[href]")
	for _, a in ipairs(links) do
		local title = a:selectFirst("strong.chapter-title")
		table.insert(chapters, {
			title = title and string_clean(title:text()) or "",
			url = absUrl(a:attr("href")),
		})
	end
	return { chapters = chapters, totalPages = totalPages }
end

-- ── Текст главы ──

function getChapterText(html, url)
	html_remove(html, "script", "style", "div[align=center]", ".ads", ".advertisement", "iframe", "ins")
	local el = html_select_first(html, ".chapter-content")
	if not el then return nil end
	local text = html_text(el.html)
	text = applyStandardContentTransforms(text)
	-- Вырезаем авторскую заметку и маркер конца главы в конце текста.
	text = regex_replace(text, "(?s)\\s*\\([^)]*\\)\\s*\\(End of this chapter\\)\\s*$", "")
	text = regex_replace(text, "(?s)\\s*\\(End of this chapter\\)\\s*$", "")
	return string_trim(text)
end

-- ── Фильтры ──

function getFilterList()
	local genreOptions = {
		{ value = "all", label = "All" },
		{ value = "fan-fiction", label = "Fan-Fiction" },
		{ value = "faloo", label = "Faloo" },
		{ value = "action", label = "Action" },
		{ value = "adventure", label = "Adventure" },
		{ value = "comedy", label = "Comedy" },
		{ value = "contemporary-romance", label = "Contemporary Romance" },
		{ value = "drama", label = "Drama" },
		{ value = "eastern-fantasy", label = "Eastern Fantasy" },
		{ value = "fantasy", label = "Fantasy" },
		{ value = "fantasy-romance", label = "Fantasy Romance" },
		{ value = "gender-bender", label = "Gender Bender" },
		{ value = "harem", label = "Harem" },
		{ value = "historical", label = "Historical" },
		{ value = "horror", label = "Horror" },
		{ value = "josei", label = "Josei" },
		{ value = "lolicon", label = "Lolicon" },
		{ value = "magical-realism", label = "Magical Realism" },
		{ value = "martial-arts", label = "Martial Arts" },
		{ value = "mecha", label = "Mecha" },
		{ value = "mystery", label = "Mystery" },
		{ value = "psychological", label = "Psychological" },
		{ value = "romance", label = "Romance" },
		{ value = "school-life", label = "School Life" },
		{ value = "sci-fi", label = "Sci-fi" },
		{ value = "seinen", label = "Seinen" },
		{ value = "shoujo", label = "Shoujo" },
		{ value = "shounen", label = "Shounen" },
		{ value = "shounen-ai", label = "Shounen Ai" },
		{ value = "slice-of-life", label = "Slice of Life" },
		{ value = "sports", label = "Sports" },
		{ value = "supernatural", label = "Supernatural" },
		{ value = "tragedy", label = "Tragedy" },
		{ value = "video-games", label = "Video Games" },
		{ value = "wuxia", label = "Wuxia" },
		{ value = "xianxia", label = "Xianxia" },
		{ value = "xuanhuan", label = "Xuanhuan" },
		{ value = "yaoi", label = "Yaoi" },
		{ value = "two-dimensional", label = "Two-dimensional" },
		{ value = "erciyuan", label = "Erciyuan" },
		{ value = "game", label = "Game" },
		{ value = "military", label = "Military" },
		{ value = "urban-life", label = "Urban Life" },
		{ value = "yuri", label = "Yuri" },
		{ value = "chinese", label = "Chinese" },
		{ value = "japanese", label = "Japanese" },
		{ value = "hentai", label = "Hentai" },
		{ value = "isekai", label = "Isekai" },
		{ value = "magic", label = "Magic" },
		{ value = "shoujo-ai", label = "Shoujo Ai" },
		{ value = "urban", label = "Urban" },
		{ value = "virtual-reality", label = "Virtual Reality" },
		{ value = "wuxia_xianxia", label = "Wuxia Xianxia" },
		{ value = "official_circles", label = "Official Circles" },
		{ value = "science_fiction", label = "Science Fiction" },
		{ value = "suspense_thriller", label = "Suspense Thriller" },
		{ value = "travel_through_time", label = "Travel Through Time" },
	}
	return {
		{
			key = "genre",
			label = "Genre",
			type = "select",
			defaultValue = "all",
			options = genreOptions,
		},
		{
			key = "status",
			label = "Status",
			type = "select",
			defaultValue = "all",
			options = {
				{ value = "all", label = "All" },
				{ value = "ongoing", label = "Ongoing" },
				{ value = "completed", label = "Completed" },
			},
		},
		{
			key = "sort",
			label = "Sort By",
			type = "select",
			defaultValue = "onclick",
			options = {
				{ value = "onclick", label = "Popular" },
				{ value = "newstime", label = "New" },
				{ value = "lastdotime", label = "Updates" },
			},
		},
	}
end

function getCatalogFiltered(index, filters)
	local page = index or 0
	local genre = filters and filters["genre"] or "all"
	local status = filters and filters["status"] or "all"
	local sort = filters and filters["sort"] or "onclick"
	local url = baseUrl .. "list/" .. genre .. "/" .. status .. "-" .. sort .. "-" .. tostring(page) .. ".html"
	local r = http_get(url)
	if not r.success then return { items = {}, hasNext = false } end
	local doc = r:toHtml()
	local res = parseItems(doc)
	res.hasNext = hasNextCatalog(doc, page)
	return res
end
