-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "shuba69"
name     = "69shuba"
version  = "1.0.5"
baseUrl  = "https://www.69shuba.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/69shuba.png"

-- ── Каталог и Поиск ──────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "novels/monthvisit_0_0_" .. tostring(page) .. ".htm"
    
    local r = http_get(url, { charset = "GBK" })
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, li in ipairs(html_select(r.body, "ul#article_list_content li")) do
        local titleEl = html_select_first(li.html, "div.newnav h3 a")
        local imgEl   = html_select_first(li.html, "a.imgbox img")
        
        if titleEl then
            table.insert(items, {
                title = string_trim(titleEl.text),
                url   = titleEl.href,
                cover = html_attr(li.html, "a.imgbox img", "data-src")
            })
        end
    end

    return { items = items, hasNext = #items > 0 }
end

function getCatalogSearch(index, query)
    -- Сайт поддерживает только одну страницу поиска через POST
    if index > 0 then return { items = {}, hasNext = false } end

    local searchUrl = "https://www.69shuba.com/modules/article/search.php"
    local payload = "searchkey=" .. url_encode_charset(query, "GBK") .. "&searchtype=all"
    
    local r = http_post(searchUrl, payload, {
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        charset = "GBK"
    })

    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, li in ipairs(html_select(r.body, "div.newbox ul li")) do
        local titleEl = html_select_first(li.html, "h3 a:last-child")
        
        if titleEl then
            table.insert(items, {
                title = string_trim(titleEl.text),
                url   = titleEl.href,
                cover = html_attr(li.html, "a.imgbox img", "data-src")
            })
        end
    end

    return { items = items, hasNext = false }
end

-- ── Детали книги ─────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local r = http_get(bookUrl, { charset = "GBK" })
    if not r.success then return nil end
    local el = html_select_first(r.body, "div.booknav2 h1 a")
    return el and string_trim(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local r = http_get(bookUrl, { charset = "GBK" })
    if not r.success then return nil end
    return html_attr(r.body, "div.bookimg2 img", "src")
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl, { charset = "GBK" })
    if not r.success then return nil end
    local el = html_select_first(r.body, "div.navtxt")
    return el and string_trim(el.text) or nil
end

-- ── Список глав ──────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    -- Логика из Kotlin: замена /txt/A43616.htm -> /A43616/
    local chapterListUrl = regex_replace(bookUrl, "/txt/", "/")
    chapterListUrl = regex_replace(chapterListUrl, "%.htm", "/")

    local r = http_get(chapterListUrl, { charset = "GBK" })
    if not r.success then return {} end

    local chapters = {}
    local elements = html_select(r.body, "div#catalog ul li a")
    
    -- Сайт отдает новые главы первыми, инвертируем для правильного порядка
    for i = #elements, 1, -1 do
        local a = elements[i]
        table.insert(chapters, {
            title = string_trim(a.text),
            url   = a.href
        })
    end

    return chapters
end

function getChapterListHash(bookUrl)
    local r = http_get(bookUrl, { charset = "GBK" })
    if not r.success then return nil end
    -- Используем текст инфо-листа (там обычно дата или глава)
    local el = html_select_first(r.body, ".infolist li:nth-child(2)")
    return el and el.text or nil
end

-- ── Текст главы ──────────────────────────────────────────────────────────────

function getChapterText(html)
    -- Очистка от мусора (реклама, скрипты, навигация)
    local cleaned = html_remove(html, 
        "h1", "div.txtinfo", "div.bottom-ad", "div.bottem2", ".visible-xs", "script"
    )
    
    local el = html_select_first(cleaned, "div.txtnav")
    if not el then return "" end

    -- html_text автоматически сконвертирует блоки в <p> для читалки
    return html_text(el.html)
end