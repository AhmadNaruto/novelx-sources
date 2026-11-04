-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "ifreedom"
name     = "iFreedom"
version  = "1.2.0"
baseUrl  = "https://ifreedom.su/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/ifreedom.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function normalizeNovelUrl(url)
  if not url or url == "" then return "" end
  if url:find("%?") then return url end
  if url:sub(-1) ~= "/" then
    return url .. "/"
  end
  return url
end

local _bookDocCache = {}

local function fetchBookDoc(url)
  url = normalizeNovelUrl(url)
  if _bookDocCache[url] then return _bookDocCache[url] end
  local r = http_get(url)
  if r.success then
    local doc = r:toHtml()
    _bookDocCache[url] = doc
    return doc
  end
  return nil
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Перевод|Переводчик|Редакция|Редактор|Аннотация|Сайт|Источник|Студия)[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

local function parseCards(doc)
  if not doc then return {} end
  local items = {}
  for _, card in ipairs(doc:select(".booksearch .item-book-slide")) do
    local titleEl = card:selectFirst(".block-book-slide-title")
    local aEl = card:selectFirst("a")
    local imgEl = card:selectFirst("img")
    local bookUrl = aEl and normalizeNovelUrl(absUrl(aEl:attr("href"))) or ""
    local cover   = imgEl and absUrl(imgEl:attr("src")) or ""
    if titleEl and bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(titleEl:text()),
        url   = bookUrl,
        cover = cover
      })
    end
  end
  return items
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url = baseUrl .. "vse-knigi/?sort=" .. url_encode("По рейтингу")
              .. "&bpage=" .. tostring(index + 1)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCards(r:toHtml())
  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local url = baseUrl .. "vse-knigi/?searchname=" .. url_encode(query) .. "&bpage=" .. tostring(index + 1)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCards(r:toHtml())
  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst("h1")
  return el and string_clean(el:text()) or nil
end

function getBookCoverImageUrl(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst("div.book-img.block-book-slide-img > img")
  if el then
    local src = el:attr("src")
    if src and src ~= "" then return absUrl(src) end
  end
  return nil
end

function getBookDescription(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst("[data-name=\"Описание\"]")
  return el and string_trim(el:text()) or nil
end

function getBookGenres(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return {} end

  local genres = {}
  for _, block in ipairs(doc:select("div.book-info-list")) do
    local icon = block:selectFirst("svg.icon-tabler-tag")
    if icon then
      for _, a in ipairs(block:select("a")) do
        local label = string_trim(a:text())
        if label ~= "" then table.insert(genres, label) end
      end
    end
  end

  if #genres == 0 then
    for _, a in ipairs(doc:select("div.genreslist a")) do
      local label = string_trim(a:text())
      if label ~= "" then table.insert(genres, label) end
    end
  end

  return genres
end

-- ── Статус и дата обновления ──────────────────────────────────────────────────

-- Статус книги — текст внутри блока .book-info-list (напр. «Книга завершена»,
-- «Перевод активен»). В блоке может быть несколько записей (автор, жанры),
-- статус — та, что содержит ключевые слова статуса. Проверено на живом сайте.
function getBookStatus(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local blocks = doc:select(".book-info-list")
  for _, b in ipairs(blocks) do
    local t = string_clean(b:text())
    if t ~= "" and (
        string.find(t, "заверш", 1, true) or string.find(t, "перевод", 1, true)
     or string.find(t, "статус", 1, true)  or string.find(t, "продолжа", 1, true)
     or string.find(t, "издан", 1, true)   or string.find(t, "выпущен", 1, true)) then
      return t
    end
  end
  return nil
end

function getBookLastUpdate(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end

  -- Дата последнего обновления = дата самой свежей главы. Список глав на
  -- странице отсортирован от новых к старым, поэтому первая .chapterinfo —
  -- самая новая. Дата лежит в span.timechapter в формате ДД.ММ.ГГ (иногда ГГГГ).
  local firstChapter = doc:selectFirst("div.chapterinfo")
  if not firstChapter then return nil end
  local timeEl = firstChapter:selectFirst("span.timechapter")
  if not timeEl then return nil end
  local ds = string_trim(timeEl:text())
  if ds == "" then return nil end

  -- Абсолютная дата: ДД.ММ.ГГ или ДД.ММ.ГГГГ
  local d, m, y = string.match(ds, "(%d+)%.(%d+)%.(%d+)")
  if d and m and y then
    if #y == 2 then y = "20" .. y end
    return string.format("%04d-%02d-%02d", tonumber(y), tonumber(m), tonumber(d))
  end

  -- Запасной вариант: относительная дата «N часов/дней/... назад»
  local num, unit = string.match(ds, "(%d+)%s*(%a+)%s+назад")
  if num and unit then
    local mult = {
      ["час"]   = 3600,    ["день"]  = 86400,  ["недел"] = 604800,
      ["месяц"] = 2592000, ["год"]   = 31536000
    }
    local secs = nil
    for k, v in pairs(mult) do
      if string_starts_with(unit, k) then secs = v; break end
    end
    if secs then
      return os.date("%Y-%m-%d", os.time() - tonumber(num) * secs)
    end
  end

  return nil
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return {} end

  local chapters = {}
  for _, a in ipairs(doc:select("div.chapterinfo a")) do
    local href = a:attr("href")
    local chUrl = href and absUrl(href) or ""
    -- Платные главы ведут на /koshelek/ (страница абонемента), а не на главу —
    -- пропускаем их, иначе движок откроет страницу оплаты вместо текста
    if chUrl ~= "" and not chUrl:find("koshelek") then
      table.insert(chapters, {
        title = string_clean(a:text()),
        url   = chUrl
      })
    end
  end

  local reversed = {}
  for i = #chapters, 1, -1 do
    table.insert(reversed, chapters[i])
  end
  return reversed
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst("div.book-info-list:has(svg.icon-tabler-list-check) div")
  return el and string_clean(el:text()) or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads", ".pc-adv", ".mob-adv")
  local el = html_select_first(cleaned, ".chapter-content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Сортировка",
      defaultValue = "По рейтингу",
      options = {
        { value = "По дате добавления",  label = "По дате добавления"  },
        { value = "По дате обновления",  label = "По дате обновления"  },
        { value = "По количеству глав",  label = "По количеству глав"  },
        { value = "По названию",         label = "По названию"         },
        { value = "По просмотрам",       label = "По просмотрам"       },
        { value = "По рейтингу",         label = "По рейтингу"         },
      }
    },
    {
      type  = "checkbox",
      key   = "status",
      label = "Статус",
      options = {
        { value = "Перевод активен",        label = "Перевод активен"        },
        { value = "Перевод приостановлен",  label = "Перевод приостановлен"  },
        { value = "Произведение завершено", label = "Произведение завершено" },
      }
    },
    {
      type  = "checkbox",
      key   = "lang",
      label = "Язык",
      options = {
        { value = "Английский", label = "Английский" },
        { value = "Китайский",  label = "Китайский"  },
        { value = "Корейский",  label = "Корейский"  },
        { value = "Японский",   label = "Японский"   },
      }
    },
    {
      type  = "checkbox",
      key   = "genre",
      label = "Жанры",
      options = {
        { value = "Боевик",              label = "Боевик"              },
        { value = "Боевые Искусства",    label = "Боевые Искусства"    },
        { value = "Вампиры",             label = "Вампиры"             },
        { value = "Виртуальный Мир",     label = "Виртуальный Мир"     },
        { value = "Гарем",               label = "Гарем"               },
        { value = "Героическое фэнтези", label = "Героическое фэнтези" },
        { value = "Детектив",            label = "Детектив"            },
        { value = "Дзёсэй",              label = "Дзёсэй"              },
        { value = "Драма",               label = "Драма"               },
        { value = "Игра",                label = "Игра"                },
        { value = "История",             label = "История"             },
        { value = "Киберпанк",           label = "Киберпанк"           },
        { value = "Комедия",             label = "Комедия"             },
        { value = "ЛитРПГ",              label = "ЛитРПГ"              },
        { value = "Меха",                label = "Меха"                },
        { value = "Милитари",            label = "Милитари"            },
        { value = "Мистика",             label = "Мистика"             },
        { value = "Научная Фантастика",  label = "Научная Фантастика"  },
        { value = "Повседневность",      label = "Повседневность"      },
        { value = "Постапокалипсис",     label = "Постапокалипсис"     },
        { value = "Приключения",         label = "Приключения"         },
        { value = "Психология",          label = "Психология"          },
        { value = "Романтика",           label = "Романтика"           },
        { value = "Сверхъестественное",  label = "Сверхъестественное"  },
        { value = "Сёдзё",              label = "Сёдзё"               },
        { value = "Сёнэн",              label = "Сёнэн"               },
        { value = "Сёнэн-ай",           label = "Сёнэн-ай"            },
        { value = "Спорт",               label = "Спорт"               },
        { value = "Сэйнэн",             label = "Сэйнэн"              },
        { value = "Сюаньхуа",            label = "Сюаньхуа"            },
        { value = "Трагедия",            label = "Трагедия"            },
        { value = "Триллер",             label = "Триллер"             },
        { value = "Ужасы",               label = "Ужасы"               },
        { value = "Фантастика",          label = "Фантастика"          },
        { value = "Фэнтези",             label = "Фэнтези"             },
        { value = "Школьная жизнь",      label = "Школьная жизнь"      },
        { value = "Экшн",                label = "Экшн"                },
        { value = "Эротика",             label = "Эротика"             },
        { value = "Этти",                label = "Этти"                },
        { value = "Яой",                 label = "Яой"                 },
        { value = "Adult",               label = "Adult"               },
        { value = "Mature",              label = "Mature"              },
        { value = "Xianxia",             label = "Xianxia"             },
        { value = "Xuanhuan",            label = "Xuanhuan"            },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page   = index + 1
  local sort   = filters["sort"] or "По рейтингу"
  local status = filters["status_included"] or {}
  local lang   = filters["lang_included"] or {}
  local genre  = filters["genre_included"] or {}

  local url = baseUrl .. "vse-knigi/?sort=" .. url_encode(sort)
              .. "&bpage=" .. tostring(page)

  for _, v in ipairs(status) do url = url .. "&status[]=" .. url_encode(v) end
  for _, v in ipairs(lang)   do url = url .. "&lang[]="   .. url_encode(v) end
  for _, v in ipairs(genre)  do url = url .. "&genre[]="  .. url_encode(v) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCards(r:toHtml())
  return { items = items, hasNext = #items > 0 }
end
