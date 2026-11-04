-- ── Метаданные ──

id       = "komikdewasa"
name     = "Komik Dewasa"
version  = "1.1.0"
baseUrl  = "https://komikdewasa.art/"
language = "id"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/komikdewasa.png"
content_type = "manga"

-- ── Хелперы ──

local _bookDocCache = {}

local function absUrl(href)
    if not href or href == "" then return "" end
    if href:find("^http") then return href end
    if href:find("^//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Страницы книги кэшируем в виде Document (OOP Shosetsu)
local function fetchBookDoc(url)
    if _bookDocCache[url] then return _bookDocCache[url] end
    local r = http_get(url)
    if not r.success then return nil end
    local doc = r:toHtml()
    if doc then _bookDocCache[url] = doc end
    return doc
end

-- URL книги как есть, если пустой/заканчивается на / или .html, иначе + "/".
-- Книга без завершающего слэша отдаёт 301.
local function normalizeBookUrl(bookUrl)
    if not bookUrl or bookUrl == "" then return bookUrl end
    if bookUrl:find("/$") or bookUrl:find("%.html$") then return bookUrl end
    return bookUrl .. "/"
end

-- Карточка каталога: div.bsx > a > .limit img / .bigor .tt / .rt .numscore
local function parseCards(doc)
    if not doc then return {} end
    local items = {}
    local cards = doc:select("div.listupd div.bs div.bsx a[href*='/komik/']")
    for _, card in ipairs(cards) do
        local titleEl = card:selectFirst(".bigor .tt")
        local title = ""
        if titleEl then
            title = string_clean(titleEl:text())
        elseif card.title and card.title ~= "" then
            title = string_clean(card.title)
        end
        if title ~= "" then
            local imgEl   = card:selectFirst(".limit img")
            local rEl     = card:selectFirst(".rt .numscore")
            local item    = { title = title, url = absUrl(card.href or card:attr("href") or "") }
            if imgEl then
                local src = imgEl:attr("src") or imgEl.src or ""
                if src ~= "" then item.cover = absUrl(src) end
            end
            if rEl then
                local r = string_clean(rEl:text())
                if r ~= "" then item.rating = "Rating: " .. r .. "/10" end
            end
            table.insert(items, item)
        end
    end
    return items
end

-- ── Каталог ──

function getCatalogList(index)
    -- index 0 → /komik/, index N → /komik/?page=N+1
    local url = baseUrl .. "komik/"
    if index > 0 then
        url = url .. "?page=" .. (index + 1)
    end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local doc = r:toHtml()
    local items = parseCards(doc)
    -- Полные страницы = 20 карточек, последняя страница = 13
    return { items = items, hasNext = #items >= 20 }
end

function getCatalogSearch(index, query)
    -- Пагинации в поиске нет: страница 2 отдаёт "No Post Found"
    if index >= 1 then return { items = {}, hasNext = false } end

    -- title-фильтр каталога; обычный ?s= закрыт Cloudflare-челленджем
    local url = baseUrl .. "komik/?title=" .. url_encode(query)

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local doc = r:toHtml()
    local items = parseCards(doc)
    return { items = items, hasNext = false }
end

-- ── Фильтры ──

function getFilterList()
    -- Сортировка/тип первыми — пользователь их меняет чаще всего
    return {
        { type = "select", key = "order", label = "Urutkan", defaultValue = "update", options = {
            { value = "", label = "Semua" },
            { value = "title", label = "Judul A-Z" },
            { value = "titlereverse", label = "Judul Z-A" },
            { value = "update", label = "Update" },
            { value = "latest", label = "Terbaru" },
            { value = "popular", label = "Terpopuler" },
        }},
        { type = "select", key = "type", label = "Tipe", defaultValue = "", options = {
            { value = "", label = "Semua" },
            { value = "manga",  label = "Manga" },
            { value = "manhwa", label = "Manhwa" },
            { value = "manhua", label = "Manhua" },
            { value = "comic",  label = "Comic" },
        }},
        { type = "checkbox", key = "genres", label = "Genre", multiselect = true, options = {
            { value = "257",  label = "3D" },
            { value = "4857", label = "A Sole Female" },
            { value = "4998", label = "Abnormal Sex" },
            { value = "3424", label = "Abusing" },
            { value = "6650", label = "Action" },
            { value = "3011", label = "Adik Kakak" },
            { value = "3400", label = "Adult" },
            { value = "5549", label = "Adventure" },
            { value = "3112", label = "Affair" },
            { value = "4181", label = "Affectionate Corruption" },
            { value = "6457", label = "Age Difference" },
            { value = "4106", label = "Age Gap" },
            { value = "4855", label = "Age Progression" },
            { value = "4859", label = "Age Regression" },
            { value = "5429", label = "Aggressive Female" },
            { value = "5569", label = "Aggressive Wife" },
            { value = "3496", label = "Ahegao" },
            { value = "3883", label = "Ahegao Big Ass" },
            { value = "5731", label = "AI Generated" },
            { value = "2805", label = "Anal" },
            { value = "5677", label = "Anal Sex" },
            { value = "2896", label = "Angel" },
            { value = "6336", label = "Animal" },
            { value = "4802", label = "Animal Ears" },
            { value = "4541", label = "Anomalous Sex" },
            { value = "2956", label = "Another World" },
            { value = "3831", label = "Antihero" },
            { value = "8263", label = "Ara Ara" },
            { value = "3670", label = "Armed Girl" },
            { value = "4685", label = "Army" },
            { value = "3184", label = "Ass" },
            { value = "2891", label = "Assault" },
            { value = "6031", label = "At Your Own Pace" },
            { value = "3153", label = "BDSM" },
            { value = "5933", label = "Bad Ending" },
            { value = "3523", label = "Barbarian" },
            { value = "6006", label = "Beast Girl" },
            { value = "4056", label = "Beautiful Female Teacher" },
            { value = "6362", label = "Big Ass" },
            { value = "4489", label = "Big Breast" },
            { value = "4467", label = "Big Cock" },
            { value = "3150", label = "Big Dick" },
        }},
    }
end

function getCatalogFiltered(index, filters)
    local genres = filters["genres_included"] or filters["genres"] or {}
    if type(genres) == "string" then genres = { genres } end

    -- Жанр пагинируется как каталог: genre[]=X&page=N (проверено, N=2..3 дают новые 20).

    local params = {}
    for _, v in ipairs(genres) do
        table.insert(params, "genre[]=" .. tostring(v))
    end

    local ftype = filters["type"] or ""
    if ftype ~= "" then table.insert(params, "type=" .. ftype) end

    local order = filters["order"] or "update"
    if order ~= "update" and order ~= "" then table.insert(params, "order=" .. order) end

    if index > 0 then
        table.insert(params, "page=" .. (index + 1))
    end

    local url = baseUrl .. "komik/"
    if #params > 0 then
        url = url .. "?" .. table.concat(params, "&")
    end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local doc = r:toHtml()
    local items = parseCards(doc)
    local hasNext = #items >= 20
    return { items = items, hasNext = hasNext }
end

-- ── Детали книги ──

function getBookTitle(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return nil end
    local el = doc:selectFirst("h1.entry-title")
    return el and string_clean(el:text()) or nil
end

function getBookCoverImageUrl(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return nil end
    local el = doc:selectFirst(".thumb img")
    if not el then return nil end
    local src = el:attr("src") or el.src or ""
    return src ~= "" and absUrl(src) or nil
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
    local els = doc:select(".seriestugenre a[rel='tag']")
    for _, el in ipairs(els) do
        table.insert(genres, string_clean(el:text()))
    end
    return genres
end

-- ── Rating ──

function getBookRating(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return nil end
    -- На странице рейтинг в div.num[itemprop='ratingValue'][content] (шкала 10)
    local el = doc:selectFirst("[itemprop='ratingValue']")
    if not el then return nil end
    local v = el:attr("content") or ""
    if v == "" then v = el:text() or "" end
    v = string_clean(v)
    if v == "" then return nil end
    return "Rating: " .. v .. "/10"
end

-- ── Status / Last update ──

function getBookStatus(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return nil end
    local rows = doc:select(".infotable tr")
    for _, row in ipairs(rows) do
        local cells = row:select("td")
        if #cells >= 2 and string_trim(cells[1]:text()) == "Status" then
            return string_clean(cells[2]:text())
        end
    end
    return nil
end

function getBookLastUpdate(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return nil end
    local el = doc:selectFirst("time[itemprop='dateModified']")
    if el then
        local v = el:attr("datetime") or ""
        if v ~= "" then
            -- "2026-09-18T19:47:06+07:00" → "2026-09-18"
            return v:sub(1, 10)
        end
    end
    return nil
end

-- ── Список глав ──

function getChapterList(bookUrl)
    local doc = fetchBookDoc(normalizeBookUrl(bookUrl))
    if not doc then return {} end

    local chapters = {}
    local lis = doc:select("div#chapterlist.eplister ul.clstyle li[data-num]")
    for _, li in ipairs(lis) do
        local a = li:selectFirst(".eph-num a")
        if a then
            local href = a.href or a:attr("href") or ""
            if href ~= "" then
                local numEl = li:selectFirst("span.chapternum")
                local title = numEl and string_clean(numEl:text()) or ""
                if title == "" then title = string_clean(a:text()) end
                table.insert(chapters, {
                    title = title,
                    url   = absUrl(href),
                })
            end
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
    local a = doc:selectFirst("ul.clstyle li[data-num] .eph-num a")
    if a then
        local href = a.href or a:attr("href") or ""
        -- Первая запись = самая новая глава
        if href ~= "" then
            return href
        end
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
    -- Только #readerarea: реклама и svg-заглушка лежат вне этого контейнера
    local imgs = html_select(html, "#readerarea img")
    local pages = {}
    for _, img in ipairs(imgs) do
        if (img.src or "") ~= "" then
            table.insert(pages, img.src)
        end
    end
    return pages
end