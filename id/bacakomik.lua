-- ── Метаданные ──

id       = "bacakomik"
name     = "BacaKomik"
version  = "1.1.0"
baseUrl  = "https://bacakomik.my/"
language = "id"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/bacakomik.png"
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

-- URL книги как есть, если пустой/заканчивается на / или .html, иначе + "/"
local function normalizeBookUrl(bookUrl)
    if not bookUrl or bookUrl == "" then return bookUrl end
    if bookUrl:find("/$") or bookUrl:find("%.html$") then return bookUrl end
    return bookUrl .. "/"
end

-- Обложки: data-lazy-src (каталог) или прямой src (поиск)
local function extractCover(el)
    if not el then return "" end
    local lazy = el:attr("data-lazy-src") or ""
    if lazy ~= "" and not lazy:find("data:image") then return lazy end
    local src = el:attr("src") or el.src or ""
    if src ~= "" and not src:find("data:image") then return src end
    return ""
end

-- Ищем обложку в контейнере (.limit, .thumb и т.д.)
local function findCoverInContainer(parent)
    if not parent then return "" end
    local img = parent:selectFirst("img")
    if img then
        local cover = extractCover(img)
        if cover ~= "" then return cover end
    end
    local noscriptImg = parent:selectFirst("noscript > img")
    if noscriptImg then
        local src = noscriptImg:attr("src") or noscriptImg.src or ""
        if src ~= "" and not src:find("data:image") then return src end
    end
    return ""
end

local function cleanTitle(title)
    if not title then return "" end
    return string_clean(title)
end

-- Значения жанров из формы фильтра на /daftar-komik/
local GENRES = {
    "actio", "action", "action-adventure", "action-adventure-comedy-drama-fantasy",
    "adult", "adventure", "comedy", "crime", "demons", "doujinshi", "drama",
    "drama-romance", "ecchi", "fantasy", "fantasy-shounen-supernatural",
    "fantasy-slice-of-life", "fantasy-shounen", "game", "gender-bender",
    "genderswap", "girls-love", "harem", "historical",
    "historical-martial-arts-shounen", "horror", "isekai", "josei", "life",
    "loli", "lolicon", "magic", "magical-girls", "martial-arts", "mature",
    "mecha", "medical", "military", "monster-girls", "monsters", "music",
    "mystery", "mystery-psychological-romance-thriller", "ninja",
    "philosophical", "psychological", "reincarnation", "romance",
    "romance-shoujo", "school", "school-life", "sci-fi", "seinen", "shotacon",
    "shoujo", "shoujo-ai", "shounen", "shounen-ai", "slice-of-life", "smut",
    "sports", "superhero", "supernatural", "thriller", "tragedy", "wuxia",
    "yuri",
}

-- Карточка каталога/поиска → элемент items
local function parseCards(doc)
    if not doc then return {} end
    local items = {}
    -- Селектор по div-контейнеру, не по <a>: сайт вкладывает блочные div (bigors, adds)
    -- внутрь <a>, а HTML-парсеры (jsoup) выносят их из <a>. div.animposx
    -- в любом парсере остаётся целостной карточкой.
    local cards = doc:select("div.animepost > div.animposx")
    for _, card in ipairs(cards) do
        local titleEl = card:selectFirst(".tt h4")
        if titleEl then
            local linkEl = card:selectFirst("a[itemprop='url']")
            local limitEl = card:selectFirst(".limit")
            local ratingEl = card:selectFirst(".rating i")
            local rating = ratingEl and cleanTitle(ratingEl:text()) or ""
            local item = {
                title = cleanTitle(titleEl:text()),
                url   = linkEl and absUrl(linkEl.href or linkEl:attr("href") or "") or "",
                cover = findCoverInContainer(limitEl),
            }
            -- Рейтинг на сайте по шкале 10 (bestRating=10) → формат "Rating: X/10"
            if rating ~= "" then item.rating = "Rating: " .. rating .. "/10" end
            table.insert(items, item)
        end
    end
    return items
end

local function hasNextPage(html)
    local p = detect_pagination(html)
    return p.hasNext
end

-- ── Каталог ──

function getCatalogList(index)
    local page = index + 1
    local url
    if page == 1 then
        url = baseUrl .. "daftar-komik/"
    else
        url = baseUrl .. "daftar-komik/page/" .. page .. "/"
    end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local doc = r:toHtml()
    local items = parseCards(doc)
    return { items = items, hasNext = hasNextPage(r.body) }
end

function getCatalogSearch(index, query)
    -- Пагинации в поиске нет
    if index >= 1 then return { items = {}, hasNext = false } end

    local url = baseUrl .. "?s=" .. url_encode(query)

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    -- Обрезаем html до сайдбара, чтобы не подхватить виджеты (serieslist):
    -- в jsoup html_select по .animepost вернёт и их
    local body = r.body
    local pos = body:find("id=\"sidebar\"")
    if pos then body = body:sub(1, pos - 1) end

    local doc = html_parse(body)
    local items = parseCards(doc)
    -- Пагинации в поиске нет
    return { items = items, hasNext = false }
end

-- ── Фильтры ──

function getFilterList()
    local genreOptions = {}
    for _, g in ipairs(GENRES) do
        -- label = человекочитаемый: "action-adventure" → "Action Adventure"
        local label = tostring(g):gsub("(%S+)", function(w)
            return w:sub(1, 1):upper() .. w:sub(2)
        end):gsub("%-", " ")
        table.insert(genreOptions, { value = g, label = label })
    end

    -- Сортировка/тип первыми — пользователь их меняет чаще всего
    return {
        { type = "select", key = "order", label = "Order", defaultValue = "", options = {
            { value = "", label = "All" },
            { value = "title", label = "A-Z" },
            { value = "titlereverse", label = "Z-A" },
            { value = "update", label = "Latest Update" },
            { value = "latest", label = "Latest Added" },
            { value = "popular", label = "Popular" },
        }},
        { type = "select", key = "type", label = "Jenis", defaultValue = "", options = {
            { value = "", label = "All" },
            { value = "Manga", label = "Manga" },
            { value = "Manhwa", label = "Manhwa" },
            { value = "Manhua", label = "Manhua" },
            { value = "Comic", label = "Comic" },
        }},
        { type = "select", key = "status", label = "Status", defaultValue = "", options = {
            { value = "", label = "All" },
            { value = "Ongoing", label = "Ongoing" },
            { value = "Completed", label = "Completed" },
            { value = "Hiatus", label = "Hiatus" },
        }},
        { type = "checkbox", key = "genres", label = "Genre", multiselect = true, options = genreOptions },
        { type = "select", key = "format", label = "Format", defaultValue = "", options = {
            { value = "", label = "All" },
            { value = "0", label = "Hitam Putih" },
            { value = "1", label = "Berwarna" },
        }},
        { type = "select", key = "project", label = "Project", defaultValue = "", options = {
            { value = "", label = "All" },
            { value = "no", label = "No" },
            { value = "yes", label = "Yes" },
        }},
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    local url
    if page == 1 then
        url = baseUrl .. "daftar-komik/?"
    else
        url = baseUrl .. "daftar-komik/page/" .. page .. "/?"
    end

    local params = {}

    -- genres — checkbox → key_included; добавляем только если != defaultValue {}
    local genres = filters["genres_included"] or filters["genres"] or {}
    if #genres > 0 then
        for i, v in ipairs(genres) do
            table.insert(params, "genre[" .. (i - 1) .. "]=" .. v)
        end
    end

    local function addParam(key, value, defaultValue)
        if value ~= defaultValue and value ~= nil and value ~= "" then
            table.insert(params, key .. "=" .. value)
        end
    end

    addParam("order", filters["order"] or "", "")
    addParam("status", filters["status"] or "", "")
    addParam("type", filters["type"] or "", "")
    addParam("format", filters["format"] or "", "")
    addParam("project", filters["project"] or "", "")

    if #params > 0 then
        url = url .. table.concat(params, "&")
    else
        url = url:gsub("%?$", "")
    end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local doc = r:toHtml()
    local items = parseCards(doc)
    return { items = items, hasNext = hasNextPage(r.body) }
end

-- ── Детали книги ──

function getBookTitle(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return nil end
    local el = doc:selectFirst("h1.entry-title")
    if not el then return nil end
    -- На странице h1 = "Komik Nano Machine" — убираем префикс
    return cleanTitle(el:text()):gsub("^Komik%s+", "")
end

function getBookCoverImageUrl(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return nil end
    -- Ищем контейнер .thumb, затем noscript > img внутри него
    local thumbEl = doc:selectFirst(".thumb")
    if not thumbEl then thumbEl = doc:selectFirst(".infoanime .thumb") end
    if not thumbEl then thumbEl = doc:selectFirst(".infoanime") end
    if thumbEl then
        local cover = findCoverInContainer(thumbEl)
        if cover ~= "" then return cover end
    end
    return nil
end

function getBookDescription(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return nil end
    local el = doc:selectFirst(".entry-content.entry-content-single")
    return el and html_text(el) or nil
end

function getBookGenres(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return {} end
    local genres = {}
    local els = doc:select("div.genre-info a")
    for _, el in ipairs(els) do
        table.insert(genres, cleanTitle(el:text()))
    end
    return genres
end

-- ── Rating ──

function getBookRating(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return nil end
    local el = doc:selectFirst("i[itemprop='ratingValue']")
    if not el then return nil end
    -- Рейтинг по шкале 10 (bestRating=10) → "Rating: X/10": приложение
    -- нормализует в 0..5 (X/2); число >5 приложение клампит до 5
    return "Rating: " .. cleanTitle(el:text()) .. "/10"
end

-- ── Status / Last update ──

function getBookStatus(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return nil end
    local spans = doc:select(".infox .spe span")
    for _, span in ipairs(spans) do
        local text = span:text() or ""
        if text:find("Status:") then
            -- "Status: Berjalan" → "Berjalan"
            return cleanTitle(text:gsub("^.*Status:%s*", ""))
        end
    end
    return nil
end

function getBookLastUpdate(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return nil end
    local el = doc:selectFirst("meta[property='article:modified_time']")
    if el then
        local content = el:attr("content") or ""
        if content ~= "" then
            -- "2026-09-17T07:13:35+00:00" → "2026-09-17"
            return content:sub(1, 10)
        end
    end
    return nil
end

-- ── Список глав ──

function getChapterList(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return {} end

    local chapters = {}
    local links = doc:select("#chapter_list span.lchx a")
    for _, link in ipairs(links) do
        local href = link.href or link:attr("href") or ""
        if href ~= "" then
            table.insert(chapters, {
                title = cleanTitle(link:text()),
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
    local r = http_get(normalizeBookUrl(bookUrl))
    if not r.success then return nil end
    local doc = r:toHtml()
    if not doc then return nil end
    local link = doc:selectFirst("#chapter_list span.lchx a")
    if link and link.href and link.href ~= "" then
        return link.href
    end
    return nil
end

-- ── Текст главы (manga: getChapterText → заглушка, getPageList основной) ──

function getChapterText(html, url)
    local pages = getPageList(html, url)
    local imgs = {}
    for _, src in ipairs(pages) do
        table.insert(imgs, '<img src="' .. src:gsub("&", "&amp;") .. '">')
    end
    return table.concat(imgs, "\n")
end

function getPageList(html, url)
    -- Regex-извлечение из noscript: обход Jsoup 1.23.1 (не парсит noscript content)
    -- Ищем noscript <img> начиная с позиции #anjay_ini_id_kh
    local pages = {}
    local containerStart = html:find('id="anjay_ini_id_kh"')
    if not containerStart then containerStart = html:find("id='anjay_ini_id_kh'") end
    if containerStart then
        -- Ищем <noscript> только в части HTML после контейнера
        local afterContainer = html:sub(containerStart)
        local pos = 1
        while true do
            local nsStart = afterContainer:find("<noscript>", pos)
            if not nsStart then break end
            local nsEnd = afterContainer:find("</noscript>", nsStart)
            if not nsEnd then break end
            local content = afterContainer:sub(nsStart + 10, nsEnd - 1)
            local src = content:match('src="([^"]+)"') or content:match("src='([^']+)'")
            if src and not src:find("data:image") then
                table.insert(pages, src)
            end
            pos = nsEnd + 11
        end
    end

    -- Fallback: css selector noscript > img (работает в тестах JVM)
    if #pages == 0 then
        local imgs = html_select(html, "#anjay_ini_id_kh noscript > img")
        if #imgs == 0 then imgs = html_select(html, ".chapter-content noscript > img") end
        local seen = {}
        for _, img in ipairs(imgs) do
            local src = img:attr("src") or ""
            if src ~= "" and not seen[src] and not src:find("data:image") then
                seen[src] = true
                table.insert(pages, src)
            end
        end
    end

    -- Fallback 2: img с data-lazy-src (если noscript пуст)
    if #pages == 0 then
        local imgs = html_select(html, "#anjay_ini_id_kh img")
        local seen = {}
        for _, img in ipairs(imgs) do
            local src = extractCover(img)
            if src ~= "" and not seen[src] then
                seen[src] = true
                table.insert(pages, src)
            end
        end
    end

    return pages
end