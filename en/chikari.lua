-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "chikari"
name     = "Chikari"
version  = "1.1.0"
baseUrl  = "https://chikari.moe/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/chikari.png"

-- Chikari — текстовые новеллы. Каталог, поиск и фильтрация новелл перенесены
-- на объединённый эндпоинт /api/series?type=novel. Детали, список глав и текст
-- по-прежнему доступны через /api/novels/<slug>*.

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- Chikari — SPA на SvelteKit; все /api/* — AJAX-эндпоинты.
-- Шлём легитимные заголовки Accept + Origin.
local API_HEADERS = {
  Accept = "application/json",
  Origin = "https://chikari.moe",
}

local function fetchJson(url)
  local lastErr = nil
  for attempt = 1, 3 do
    local r = http_get(url, { headers = API_HEADERS })
    if r.success then
      local bodyLen = r.body and #r.body or 0
      log_info("[chikari] fetchJson OK url=" .. tostring(url)
               .. " code=" .. tostring(r.code) .. " bodyLen=" .. bodyLen
               .. " attempt=" .. attempt)
      local ok, data = pcall(json_parse, r.body)
      if ok and type(data) == "table" then
        return data
      end
    end
    lastErr = r.error
    log_error("[chikari] fetchJson FAIL url=" .. tostring(url)
              .. " code=" .. tostring(r.code) .. " err=" .. tostring(r.error)
              .. " attempt=" .. attempt)
    if attempt < 3 then sleep(300) end
  end
  log_error("[chikari] fetchJson GAVE UP url=" .. tostring(url) .. " err=" .. tostring(lastErr))
  return nil
end

-- bookUrl может прийти как "shadow-slave", "/novel/shadow-slave" или "/novels/shadow-slave"
local function novelSlug(bookUrl)
  if not bookUrl then return nil end
  return bookUrl:match("([^/]+)/?$")
end

-- Форматирование номера главы (1.0 -> "1", 12.5 -> "12.5")
local function formatChapterNum(n)
  if not n then return "0" end
  local s = tostring(n)
  if s:sub(-2) == ".0" then
    return s:sub(1, -3)
  end
  return s
end

-- Кэш карточки новеллы в рамках одного вызова (getBook* дёргаются по отдельности)
local _detailCache = {}
local function getDetail(bookUrl)
  if _detailCache[bookUrl] then return _detailCache[bookUrl] end
  local slug = novelSlug(bookUrl)
  if not slug then return nil end
  local d = fetchJson(baseUrl .. "api/novels/" .. slug)
  _detailCache[bookUrl] = d
  return d
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- ── Каталог ────────────────────────────────────────────────────────────────────

local function buildItems(d)
  local items = {}
  if not d or not d.items then return items end
  for _, it in ipairs(d.items) do
    local slug = it.slug
    items[#items + 1] = {
      title  = string_clean(it.title or ""),
      url    = slug and absUrl("/novels/" .. slug) or "",
      cover  = it.cover_url or "",
      rating = it.rating and (tostring(it.rating) .. "/10") or nil,
    }
  end
  return items
end

local function hasNext(d, offset, fetched)
  local total = d and d.total or 0
  return (offset + fetched) < total
end

function getCatalogList(index)
  index = index or 0
  sleep(150)
  local limit = 48
  local offset = index * limit
  local url = baseUrl .. "api/series?type=novel&sort=popular&limit=" .. limit .. "&offset=" .. offset
  local d = fetchJson(url)
  local items = buildItems(d)
  return { items = items, hasNext = hasNext(d, offset, #items) }
end

function getCatalogSearch(index, query)
  index = index or 0
  sleep(150)
  local limit = 36
  local offset = index * limit
  local url = baseUrl .. "api/series?type=novel&sort=popular&q=" .. url_encode(query) .. "&limit=" .. limit .. "&offset=" .. offset
  local d = fetchJson(url)
  local items = buildItems(d)
  return { items = items, hasNext = hasNext(d, offset, #items) }
end

-- ── Фильтры ────────────────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Sort By",
      defaultValue = "popular",
      options = {
        { value = "popular",         label = "Popular" },
        { value = "trending",        label = "Trending" },
        { value = "top_rated",       label = "Top Rated" },
        { value = "updated",         label = "Recently Updated" },
        { value = "added",           label = "Recently Added" },
        { value = "most_bookmarked", label = "Most Bookmarked" },
        { value = "views",           label = "Most Views" },
        { value = "rating",          label = "Rating" },
      },
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "",
      options = {
        { value = "",          label = "All" },
        { value = "releasing", label = "Ongoing" },
        { value = "completed", label = "Completed" },
        { value = "hiatus",    label = "On Hiatus" },
        { value = "cancelled", label = "Cancelled" },
      },
    },
    {
      type        = "checkbox",
      key         = "genres",
      label       = "Genres",
      multiselect = true,
      options = {
        { value = "action",        label = "Action" },
        { value = "adult",         label = "Adult" },
        { value = "adventure",     label = "Adventure" },
        { value = "comedy",        label = "Comedy" },
        { value = "drama",         label = "Drama" },
        { value = "ecchi",         label = "Ecchi" },
        { value = "fantasy",       label = "Fantasy" },
        { value = "gender_bender", label = "Gender Bender" },
        { value = "harem",         label = "Harem" },
        { value = "historical",    label = "Historical" },
        { value = "horror",        label = "Horror" },
        { value = "josei",         label = "Josei" },
        { value = "martial_arts",  label = "Martial Arts" },
        { value = "mature",        label = "Mature" },
        { value = "mecha",         label = "Mecha" },
        { value = "mystery",       label = "Mystery" },
        { value = "psychological", label = "Psychological" },
        { value = "romance",       label = "Romance" },
        { value = "school_life",   label = "School Life" },
        { value = "sci-fi",        label = "Sci-Fi" },
        { value = "seinen",        label = "Seinen" },
        { value = "shoujo",        label = "Shoujo" },
        { value = "shoujo_ai",     label = "Shoujo Ai" },
        { value = "shounen",       label = "Shounen" },
        { value = "shounen_ai",    label = "Shounen Ai" },
        { value = "slice_of_life", label = "Slice of Life" },
        { value = "sports",        label = "Sports" },
        { value = "supernatural",  label = "Supernatural" },
        { value = "suspense",      label = "Suspense" },
        { value = "thriller",      label = "Thriller" },
        { value = "tragedy",       label = "Tragedy" },
        { value = "yaoi",          label = "Yaoi" },
        { value = "yuri",          label = "Yuri" },
      },
    },
  }
end

function getCatalogFiltered(index, filters)
  index = index or 0
  filters = filters or {}
  local limit = 48
  local offset = index * limit
  local sort = filters["sort"] or "popular"
  local url = baseUrl .. "api/series?type=novel&sort=" .. url_encode(sort) .. "&limit=" .. limit .. "&offset=" .. offset
  local status = filters["status"]
  if status and status ~= "" then
    url = url .. "&status=" .. url_encode(status)
  end
  local genres = filters["genres_included"] or {}
  for _, g in ipairs(genres) do
    if g and g ~= "" then
      url = url .. "&genre=" .. url_encode(g)
    end
  end
  local d = fetchJson(url)
  local items = buildItems(d)
  return { items = items, hasNext = hasNext(d, offset, #items) }
end

-- ── Карточка книги ─────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local d = getDetail(bookUrl)
  if not d then return nil end
  return d.title and string_clean(d.title) or nil
end

function getBookCoverImageUrl(bookUrl)
  local d = getDetail(bookUrl)
  if not d then return nil end
  return d.cover_url
end

function getBookDescription(bookUrl)
  local d = getDetail(bookUrl)
  if not d or not d.description then return nil end
  return string_trim(d.description)
end

function getBookGenres(bookUrl)
  local d = getDetail(bookUrl)
  if not d or not d.genres then return {} end
  local names = {}
  for _, g in ipairs(d.genres) do
    if g.name and g.name ~= "" then
      names[#names + 1] = g.name
    end
  end
  return names
end

function getBookStatus(bookUrl)
  local d = getDetail(bookUrl)
  if not d or not d.status then return nil end
  local map = {
    releasing = "Ongoing",
    completed = "Completed",
    hiatus    = "On Hiatus",
    cancelled = "Cancelled",
  }
  return map[d.status] or d.status
end

function getBookRating(bookUrl)
  local d = getDetail(bookUrl)
  if not d or not d.rating then return nil end
  return tostring(d.rating) .. "/10"
end

function getBookLastUpdate(bookUrl)
  local d = getDetail(bookUrl)
  if not d or not d.last_chapter_at then return nil end
  local y, m, day = string.match(d.last_chapter_at, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if not y then return nil end
  return y .. "-" .. m .. "-" .. day
end

-- ── Список глав ────────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local slug = novelSlug(bookUrl)
  log_info("[chikari] getChapterList bookUrl=" .. tostring(bookUrl) .. " slug=" .. tostring(slug))
  if not slug then return {} end
  local chapters = {}
  local limit = 500
  local offset = 0
  while true do
    local url = baseUrl .. "api/novels/" .. slug .. "/chapters?order=asc&limit=" .. limit .. "&offset=" .. offset
    local d = fetchJson(url)
    local got = (d and d.items) and #d.items or 0
    log_info("[chikari] getChapterList page offset=" .. offset .. " got=" .. got .. " items")
    if not d or not d.items then
      log_error("[chikari] getChapterList BREAK url=" .. url .. " d=" .. (d and "no-items" or "nil"))
      break
    end
    for _, ch in ipairs(d.items) do
      local numStr = formatChapterNum(ch.number)
      chapters[#chapters + 1] = {
        title  = string_clean(ch.title or ("Chapter " .. numStr)),
        url    = baseUrl .. "api/novels/" .. slug .. "/chapters/" .. numStr .. "/read",
        volume = (ch.volume and ch.volume ~= "") and ch.volume or nil,
      }
    end
    if #d.items < limit then break end
    offset = offset + limit
    sleep(100)
  end
  log_info("[chikari] getChapterList DONE total=" .. #chapters)
  return chapters
end

function getChapterListHash(bookUrl)
  local slug = novelSlug(bookUrl)
  if not slug then return nil end
  local r = http_get(baseUrl .. "api/novels/" .. slug, { headers = API_HEADERS })
  if not r or not r.success then return nil end
  local ok, d = pcall(json_parse, r.body)
  if not ok or type(d) ~= "table" then return nil end
  return tostring(d.last_chapter_at or "") .. "#" .. tostring(d.latest_number or d.chapter_count or "")
end

-- ── Текст главы ────────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local data = nil

  -- 1. Быстрый путь: пробуем извлечь JSON из переданного HTML
  if html and #html > 0 then
    local jsonStr = html:match("(%b{})")
    if jsonStr then
      local ok, parsed = pcall(json_parse, jsonStr)
      if ok and type(parsed) == "table" and parsed.body then
        data = parsed
      end
    end
  end

  -- 2. Фолбэк: прямой сетевой запрос по url главы
  if not data or not data.body then
    local r = http_get(url, { headers = API_HEADERS })
    if r and r.success then
      local ok, parsed = pcall(json_parse, r.body)
      if ok and type(parsed) == "table" then
        data = parsed
      end
    end
  end

  if not data or not data.body then return "" end
  return applyStandardContentTransforms(data.body)
end
