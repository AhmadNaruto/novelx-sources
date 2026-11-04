-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "baca_lightnovel"
name     = "Baca Lightnovel"
version  = "1.2.0"
baseUrl  = "https://bacalightnovel.co/"
language = "id"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/bacalightnovel.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local _bookDocCache = {}

local function fetchBookDoc(url)
  if _bookDocCache[url] then return _bookDocCache[url] end
  local r = http_get(url)
  if not r.success then return nil end
  local doc = r:toHtml()
  if doc then _bookDocCache[url] = doc end
  return doc
end

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Bab\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Penerjemah|Editor|Proofreader|Baca\\s+(di|di+sini))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

local function parseCatalogItems(doc, preferDataSrc)
  if not doc then return {} end
  local items = {}
  for _, card in ipairs(doc:select(".listupd > .maindet")) do
    local a = card:selectFirst(".mdthumb a")
    if a then
      local bookUrl = absUrl(a.href)
      local img = a:selectFirst("img")
      local title = ""
      if img then
        title = img:attr("title")
        if title == "" then title = img:attr("alt") end
      end
      local cover = ""
      if preferDataSrc and img then
        cover = img:attr("data-src")
      end
      if cover == "" and img then
        cover = img:attr("src")
      end
      local rEl = card:selectFirst(".mdinfodet .mdminf")
      local rating = rEl and ("Rating: " .. string_clean(rEl:text()) .. "/10") or nil
      if bookUrl ~= "" then
        table.insert(items, {
          title  = string_clean(title),
          url    = bookUrl,
          cover  = absUrl(cover),
          rating = rating
        })
      end
    end
  end
  return items
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url
  if index == 0 then
    url = baseUrl .. "series/"
  else
    url = baseUrl .. "series/?page=" .. tostring(index + 1) .. "&order=populer"
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local doc = r:toHtml()
  local items = parseCatalogItems(doc, true)
  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local url
  if index == 0 then
    url = baseUrl:gsub("/$", "") .. "/?s=" .. url_encode(query)
  else
    url = baseUrl:gsub("/$", "") .. "/page/" .. tostring(index + 1) .. "/?s=" .. url_encode(query)
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local doc = r:toHtml()
  local items = parseCatalogItems(doc, false)
  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst("h1.entry-title")
  return el and string_clean(el:text()) or nil
end

function getBookCoverImageUrl(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst(".sertothumb img")
  if el then
    local src = el:attr("src")
    if src == "" then src = el:attr("data-src") end
    return src ~= "" and absUrl(src) or nil
  end
  return nil
end

function getBookDescription(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst(".entry-content")
  return el and string_trim(el:text()) or nil
end

-- ── Список глав (NONE + reverseChapters) ─────────────────────────────────────

function getChapterList(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local doc = r:toHtml()
  if not doc then return {} end

  local chapters = {}
  for _, a in ipairs(doc:select(".eplister li > a:not(.dlpdf)")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      local titleEl = a:selectFirst(".epl-title")
      table.insert(chapters, {
        title = titleEl and string_clean(titleEl:text()) or string_clean(a:text()),
        url   = chUrl
      })
    end
  end

  local reversed = {}
  for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
  return reversed
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local doc = r:toHtml()
  local el = doc and doc:selectFirst(".epcurlast")
  return el and string_clean(el:text()) or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads")
  local el = html_select_first(cleaned, ".epcontent[itemprop=text] .text-left")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Жанры книги ───────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return {} end
  local genres = {}
  for _, a in ipairs(doc:select(".sertogenre a")) do
    local g = string_trim(a:text())
    if g ~= "" then table.insert(genres, g) end
  end
  return genres
end

-- ── Рейтинг книги ──────────────────────────────────────────────────────────────

function getBookRating(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  -- строго .rating.serrate .numscore: те же классы без .serrate есть в виджетах «популярное»
  local el = doc:selectFirst(".rating.serrate .numscore")
  if el then return "Rating: " .. string_clean(el:text()) .. "/10" end
  return nil
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "order",
      label        = "Order by",
      defaultValue = "",
      options = {
        { value = "",           label = "Default"   },
        { value = "title",      label = "A-Z"       },
        { value = "titlereverse",label = "Z-A"      },
        { value = "update",     label = "Updated"   },
        { value = "latest",     label = "Latest"    },
        { value = "popular",    label = "Popular"   },
        { value = "rating",     label = "Rating"    },
      }
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "",
      options = {
        { value = "",           label = "All"       },
        { value = "ongoing",    label = "Ongoing"   },
        { value = "hiatus",     label = "Hiatus"    },
        { value = "completed",  label = "Completed" },
      }
    },
    {
      type    = "checkbox",
      key     = "genre",
      label   = "Genres",
      options = {
        { value = "action",       label = "Action"       },
        { value = "adult",        label = "Adult"        },
        { value = "adventure",    label = "Adventure"    },
        { value = "antihero",     label = "Antihero"     },
        { value = "comedy",       label = "Comedy"       },
        { value = "drama",        label = "Drama"        },
        { value = "ecchi",        label = "Ecchi"        },
        { value = "fantasy",      label = "Fantasy"      },
        { value = "gender-bender",label = "Gender Bender"},
        { value = "harem",        label = "Harem"        },
        { value = "historical",   label = "Historical"   },
        { value = "horror",       label = "Horror"       },
        { value = "isekai",       label = "Isekai"       },
        { value = "josei",        label = "Josei"        },
        { value = "martial-arts", label = "Martial Arts" },
        { value = "mature",       label = "Mature"       },
        { value = "mecha",        label = "Mecha"        },
        { value = "mystery",      label = "Mystery"      },
        { value = "psychological",label = "Psychological"},
        { value = "romance",      label = "Romance"      },
        { value = "school-life",  label = "School Life"  },
        { value = "sci-fi",       label = "Sci-fi"       },
        { value = "seinen",       label = "Seinen"       },
        { value = "shoujo",       label = "Shoujo"       },
        { value = "shoujo-ai",    label = "Shoujo Ai"    },
        { value = "shounen",      label = "Shounen"      },
        { value = "shounen-ai",   label = "Shounen Ai"   },
        { value = "slice-of-life",label = "Slice of Life"},
        { value = "sports",       label = "Sports"       },
        { value = "superhero",    label = "Superhero"    },
        { value = "supernatural", label = "Supernatural" },
        { value = "tragedy",      label = "Tragedy"      },
        { value = "wuxia",        label = "Wuxia"        },
        { value = "xianxia",      label = "Xianxia"      },
        { value = "xuanhuan",     label = "Xuanhuan"     },
        { value = "yaoi",         label = "Yaoi"         },
        { value = "yuri",         label = "Yuri"         },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page   = index + 1
  local order  = filters["order"]  or ""
  local status = filters["status"] or ""
  local genres = filters["genre_included"] or {}

  local url = baseUrl .. "series/?"
  for _, g in ipairs(genres) do
    url = url .. "genre%5B%5D=" .. url_encode(g) .. "&"
  end
  if status ~= "" then url = url .. "status=" .. url_encode(status) .. "&" end
  if order  ~= "" then url = url .. "order="  .. url_encode(order)  .. "&" end
  if page > 1     then url = url .. "page="   .. tostring(page)     .. "&" end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local doc = r:toHtml()
  local items = parseCatalogItems(doc, false)
  return { items = items, hasNext = #items > 0 }
end
