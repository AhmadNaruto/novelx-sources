id       = "readfrom"
name     = "Read From Net"
version  = "1.6.0"
baseUrl  = "https://readfrom.net/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/readfrom.png"

function getUserAgentPreset()
  return "Safari Mobile"
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

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function getRelPath(url)
  local path = url:gsub("^https?://[^/]+/", "")
  return path:gsub("^/", "")
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

local function parseCatalogCard(card, isSearch)
  local a = card:selectFirst("h2.title a")
  if not a then return nil end
  local title = string_clean(a:text())
  if title == "" then return nil end
  local coverEl = card:selectFirst("a.highslide img")
  local genres = {}
  local author = ""
  local description = ""
  if isSearch then
    local authorEl = card:selectFirst("h5.title a")
    if authorEl then author = string_clean(authorEl:text()) end
    local descEl = card:selectFirst("div.text5")
    if descEl then description = string_trim(html_text(descEl.html)) end
  else
    for _, g in ipairs(card:select("h2 a[title*='Genre']") or {}) do
      table.insert(genres, string_clean(g:text()))
    end
    local authorEl = card:selectFirst("h4 a")
    if authorEl then author = string_clean(authorEl:text()) end
    local descEl = card:selectFirst("div.text3")
    if descEl then description = string_trim(html_text(descEl.html)) end
  end
  local href = a:attr("href")
  return {
    title = title,
    url = absUrl(href),
    cover = coverEl and absUrl(coverEl:attr("src")) or nil,
    description = description,
    genres = genres,
    author = author,
    path = getRelPath(absUrl(href)),
  }
end

local function parseCatalogPage(doc, isSearch)
  local items = {}
  local sel = isSearch and "div.text article.box.story.shortstory" or "#dle-content > article.box.story.shortstory"
  for _, card in ipairs(doc:select(sel) or {}) do
    local item = parseCatalogCard(card, isSearch)
    if item then table.insert(items, item) end
  end
  return items
end

function getCatalogList(index)
  local page = (index or 0) + 1
  local r = http_get(baseUrl .. "allbooks/page/" .. page .. "/")
  if not r.success then return { items = {}, hasNext = false } end
  local doc = r:toHtml()
  local items = parseCatalogPage(doc, false)
  local hasNext = #doc:select("div.navigation span.page_next a") > 0
  return { items = items, hasNext = hasNext }
end

function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end
  local r = http_get(baseUrl .. "build_in_search/?q=" .. url_encode(query))
  if not r.success then return { items = {}, hasNext = false } end
  local doc = r:toHtml()
  local items = parseCatalogPage(doc, true)
  return { items = items, hasNext = false }
end

function getBookTitle(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst("h2.title")
  if not el then return nil end
  local text = el:text()
  local cleaned = regex_replace(text, ",\\s+[Pp]age\\s+\\d+\\s*$", "")
  if cleaned ~= text then
    return string_clean(cleaned)
  end
  return string_clean(text)
end

function getBookCoverImageUrl(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst("a.highslide img")
  local src = el and el:attr("src") or ""
  return src ~= "" and absUrl(src) or nil
end

function getBookDescription(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return "" end
  local el = doc:selectFirst("meta[name='description']")
  if el then
    local desc = el:attr("content") or ""
    if desc ~= "" and not string_starts_with(desc, "Chapter") then
      return string_trim(desc)
    end
  end
  return ""
end

function getBookGenres(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return {} end
  local genres = {}
  for _, g in ipairs(doc:select("h2 a[title*='Genre']") or {}) do
    table.insert(genres, string_clean(g:text()))
  end
  return genres
end

function getChapterList(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return {} end
  local chapters = {}
  table.insert(chapters, { title = "1", url = bookUrl })
  local navEl = doc:selectFirst("div.splitnewsnavigation2 div.pages")
  if navEl then
    for _, a in ipairs(navEl:select("a") or {}) do
      local href = a:attr("href")
      if href and href ~= "" then
        table.insert(chapters, {
          title = string_clean(a:text()),
          url = absUrl(href)
        })
      end
    end
  end
  return chapters
end

function getChapterListHash(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local navEl = doc:selectFirst("div.splitnewsnavigation2 div.pages")
  if not navEl then return nil end
  local pages = navEl:select("a")
  local last = pages[#pages]
  return last and last:attr("href") or nil
end

function getChapterText(html, url)
  local function extractText(body)
    local cleaned = html_remove(body, "script", "style")
    cleaned = html_remove(cleaned, "a.highslide")
    cleaned = html_remove(cleaned, "div.sharethis-inline-share-buttons")
    local el = html_select_first(cleaned, "#textToRead.text")
    if not el then return nil end
    local inner = regex_replace(el.html, "(?is)<center[^>]*>.*$", "")
    return html_text(inner)
  end
  local text = extractText(html)
  if not text or text == "" then
    local r = http_get(url)
    if r.success then text = extractText(r.body) end
  end
  if not text or text == "" then return "" end
  text = regex_replace(text, "_([^_]+)_", "<i>%1</i>")
  return applyStandardContentTransforms(text)
end
