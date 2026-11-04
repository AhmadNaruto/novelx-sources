-- ── Метаданные ──

id       = "komikcast"
name     = "Komikcast"
version  = "1.2.0"
baseUrl  = "https://v1.komikcast.ac/"
language = "id"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/komikcast.webp"
content_type = "manga"

-- ── Хелперы ──

local _bookDocCache = {}

local function absUrl(href)
    if not href or href == "" then return "" end
    if href:find("^http") then return href end
    if href:find("^//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function fetchBookDoc(url)
    if _bookDocCache[url] then return _bookDocCache[url] end
    local r = http_get(url)
    if not r.success then return nil end
    local doc = r:toHtml()
    if doc then _bookDocCache[url] = doc end
    return doc
end

local function cleanTitle(title)
    if not title then return "" end
    title = title:gsub("^%s+", ""):gsub("%s+$", "")
    return title
end

local function stripQuery(url)
    if not url then return "" end
    return url:gsub("%?.*$", "")
end

-- Извлечение slug из URL книги (/manga/{slug})
local function extractSlug(bookUrl)
    if not bookUrl then return "" end
    local slug = bookUrl:match("/manga/([^/]+)")
    return slug or ""
end

-- ── Каталог ──

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "explore?page=" .. page

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local doc = r:toHtml()
    local items = {}
    local cards = doc:select("a[href*='/manga/']")
    for _, card in ipairs(cards) do
        local href = card.href or card:attr("href") or ""
        if href:find("/manga/[^/]+$") then
            local titleEl = card:selectFirst("h3")
            local imgEl = card:selectFirst("img")
            if titleEl then
                local cover = ""
                if imgEl then
                    cover = stripQuery(imgEl:attr("src") or imgEl.src or "")
                end
                table.insert(items, {
                    title = cleanTitle(titleEl:text()),
                    url   = absUrl(href),
                    cover = cover,
                })
            end
        end
    end

    -- hasNext: если найдено 42 карточки — есть следующая страница
    local hasNext = #cards >= 42
    return { items = items, hasNext = hasNext }
end

function getCatalogSearch(index, query)
    -- Используем JSON API поиска
    local url = baseUrl .. "api/search?q=" .. url_encode(query)

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local data = json_parse(r.body)
    if not data or not data.results then return { items = {}, hasNext = false } end

    local items = {}
    for _, item in ipairs(data.results) do
        table.insert(items, {
            title = cleanTitle(item.title),
            url   = absUrl("/manga/" .. (item.slug or "")),
            cover = item.cover or "",
        })
    end

    -- API не возвращает пагинацию, но results обычно < 42
    return { items = items, hasNext = false }
end

-- ── Фильтры ──

function getFilterList()
    return {
        { type = "select", key = "type", label = "Tipe", defaultValue = "", options = {
            { value = "", label = "Semua" },
            { value = "manga", label = "Manga" },
            { value = "manhwa", label = "Manhwa" },
            { value = "manhua", label = "Manhua" },
        }},
        { type = "select", key = "status", label = "Status", defaultValue = "", options = {
            { value = "", label = "Semua" },
            { value = "ongoing", label = "Berjalan (Ongoing)" },
            { value = "completed", label = "Tamat (Completed)" },
        }},
        { type = "select", key = "order", label = "Urutkan", defaultValue = "", options = {
            { value = "", label = "Terbaru" },
            { value = "new", label = "Baru Ditambahkan" },
            { value = "popular", label = "Terpopuler" },
            { value = "title", label = "Judul A-Z" },
        }},
        { type = "checkbox", key = "dewasa", label = "Konten Dewasa", multiselect = false, options = {
            { value = "1", label = "Tampilkan 18+" },
        }},
        { type = "checkbox", key = "genre", label = "Genre", multiselect = true, options = {
            { value = "action", label = "Action" },
            { value = "adventure", label = "Adventure" },
            { value = "comedy", label = "Comedy" },
            { value = "crime", label = "Crime" },
            { value = "demons", label = "Demons" },
            { value = "drama", label = "Drama" },
            { value = "ecchi", label = "Ecchi" },
            { value = "fantasy", label = "Fantasy" },
            { value = "game", label = "Game" },
            { value = "gender-bender", label = "Gender Bender" },
            { value = "harem", label = "Harem" },
            { value = "historical", label = "Historical" },
            { value = "horror", label = "Horror" },
            { value = "isekai", label = "Isekai" },
            { value = "josei", label = "Josei" },
            { value = "knight", label = "Knight" },
            { value = "magic", label = "Magic" },
            { value = "mangatoon", label = "Mangatoon" },
            { value = "manhwa", label = "Manhwa" },
            { value = "martial-arts", label = "Martial Arts" },
            { value = "mature", label = "Mature" },
            { value = "mecha", label = "Mecha" },
            { value = "medical", label = "Medical" },
            { value = "military", label = "Military" },
            { value = "monsters", label = "Monsters" },
            { value = "murim", label = "Murim" },
            { value = "music", label = "Music" },
            { value = "mystery", label = "Mystery" },
            { value = "one-shot", label = "One-Shot" },
            { value = "psychological", label = "Psychological" },
            { value = "regression", label = "Regression" },
            { value = "reincarnation", label = "Reincarnation" },
            { value = "romance", label = "Romance" },
            { value = "school-life", label = "School Life" },
            { value = "sci-fi", label = "Sci-fi" },
            { value = "seinen", label = "Seinen" },
            { value = "shoujo", label = "Shoujo" },
            { value = "shoujo-ai", label = "Shoujo Ai" },
            { value = "shounen", label = "Shounen" },
            { value = "slice-of-life", label = "Slice of Life" },
            { value = "slow-life", label = "Slow Life" },
            { value = "smut", label = "Smut" },
            { value = "sports", label = "Sports" },
            { value = "strategy", label = "Strategy" },
            { value = "supernatural", label = "Supernatural" },
            { value = "sword-fight", label = "Sword Fight" },
            { value = "sword-master", label = "Sword Master" },
            { value = "thriller", label = "Thriller" },
            { value = "tragedy", label = "Tragedy" },
        }},
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    local url = baseUrl .. "explore?page=" .. page

    local params = {}
    local genres = filters["genre_included"] or {}
    if #genres > 0 then
        table.insert(params, "genre=" .. table.concat(genres, ","))
        if #genres > 1 then
            table.insert(params, "mode=and")
        end
    end

    local ftype = filters["type"] or ""
    if ftype ~= "" then table.insert(params, "type=" .. ftype) end

    local status = filters["status"] or ""
    if status ~= "" then table.insert(params, "status=" .. status) end

    local order = filters["order"] or ""
    if order ~= "" then table.insert(params, "order=" .. order) end

    local dewasa = filters["dewasa"] or {}
    if type(dewasa) == "table" then
        for _, v in ipairs(dewasa) do
            if v == "1" then table.insert(params, "dewasa=1") end
        end
    elseif dewasa == "1" then
        table.insert(params, "dewasa=1")
    end

    if #params > 0 then
        url = url .. "&" .. table.concat(params, "&")
    end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local doc = r:toHtml()
    local items = {}
    local cards = doc:select("a[href*='/manga/']")
    for _, card in ipairs(cards) do
        local href = card.href or card:attr("href") or ""
        if href:find("/manga/[^/]+$") then
            local titleEl = card:selectFirst("h3")
            local imgEl = card:selectFirst("img")
            if titleEl then
                local cover = ""
                if imgEl then
                    cover = stripQuery(imgEl:attr("src") or imgEl.src or "")
                end
                table.insert(items, {
                    title = cleanTitle(titleEl:text()),
                    url   = absUrl(href),
                    cover = cover,
                })
            end
        end
    end

    local hasNext = #cards >= 42
    return { items = items, hasNext = hasNext }
end

-- ── Детали книги ──

function getBookTitle(bookUrl)
    local doc = fetchBookDoc(bookUrl)
    if not doc then return nil end
    local el = doc:selectFirst("h1")
    return el and cleanTitle(el:text()) or nil
end

function getBookCoverImageUrl(bookUrl)
    local doc = fetchBookDoc(bookUrl)
    if not doc then return nil end
    local el = doc:selectFirst("aside img")
    if el then
        local src = el:attr("src") or el.src or ""
        return stripQuery(src)
    end
    return nil
end

function getBookDescription(bookUrl)
    local doc = fetchBookDoc(bookUrl)
    if not doc then return nil end
    local el = doc:selectFirst("p.whitespace-pre-line")
    return el and el:text() or nil
end

function getBookStatus(bookUrl)
    local doc = fetchBookDoc(bookUrl)
    if not doc then return nil end
    -- Статус в aside: "Status" → значение
    local spans = doc:select("aside span")
    for i, span in ipairs(spans) do
        if span:text() == "Status" then
            -- Следующий span содержит значение
            local nextSpan = spans[i + 1]
            if nextSpan then
                return nextSpan:text()
            end
        end
    end
    return nil
end

-- ── Список глав ──

function getChapterList(bookUrl)
    local doc = fetchBookDoc(bookUrl)
    if not doc then return {} end

    local slug = extractSlug(bookUrl)
    local chapters = {}
    local links = doc:select("a[href*='" .. slug .. "-chapter-']")
    for _, link in ipairs(links) do
        local href = link.href or link:attr("href") or ""
        local titleEl = link:selectFirst("span")
        if titleEl and href ~= "" then
            table.insert(chapters, {
                title = cleanTitle(titleEl:text()),
                url   = absUrl(href),
            })
        end
    end

    -- Сайт отдаёт новые главы сверху — разворачиваем в хронологический порядок
    local reversed = {}
    for i = #chapters, 1, -1 do
        table.insert(reversed, chapters[i])
    end
    return reversed
end

function getChapterListHash(bookUrl)
    -- Прямой http_get, не fetchBookDoc: кэш делает хеш неактуальным
    local r = http_get(bookUrl)
    if not r.success then return nil end

    local doc = r:toHtml()
    if not doc then return nil end
    local slug = extractSlug(bookUrl)
    local a = doc:selectFirst("a[href*='" .. slug .. "-chapter-']")
    return a and (a.href or a:attr("href")) or nil
end

-- ── Текст главы (manga: getChapterText → заглушка,.getPageList основной) ──

function getChapterText(html, url)
    local pages = getPageList(html, url)
    local imgs = {}
    for _, src in ipairs(pages) do
        table.insert(imgs, '<img src="' .. src:gsub("&", "&amp;") .. '">')
    end
    return table.concat(imgs, "\n")
end

function getPageList(html, url)
    local imgs = html_select(html, "img.reader-img")
    local pages = {}
    for _, img in ipairs(imgs) do
        local src = img.src or ""
        if src ~= "" then
            table.insert(pages, src)
        end
    end
    -- Fallback: все img с alt="Halaman"
    if #pages == 0 then
        local allImgs = html_select(html, "img")
        for _, img in ipairs(allImgs) do
            local src = img.src or ""
            local alt = img.alt or ""
            if src ~= "" and alt:find("^Halaman") then
                table.insert(pages, src)
            end
        end
    end
    return pages
end
