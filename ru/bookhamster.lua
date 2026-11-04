-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "bookhamster"
name     = "Bookhamster"
version  = "1.3.0"
baseUrl  = "https://bookhamster.ru/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/bookhamster.png"

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

-- ── Хелперы ───────────────────────────────────────────────────────────────────

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
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Перевод|Переводчик|Редакция|Редактор|Аннотация|Сайт|Источник|Студия)[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- Месяцы на русском → номер для формата YYYY-MM-DD
local MONTHS = {
  ["января"] = "01", ["февраля"] = "02", ["марта"] = "03", ["апреля"] = "04",
  ["мая"]    = "05", ["июня"]    = "06", ["июля"] = "07", ["августа"] = "08",
  ["сентября"] = "09", ["октября"] = "10", ["ноября"] = "11", ["декабря"] = "12"
}

-- Даты глав на bookhamster бывают двух видов:
--   "26.08.2025"        → DD.MM.YYYY (старые главы)
--   "22 марта"          → D месяц без года (недавние главы текущего года)
-- Возвращает YYYY-MM-DD или nil. Год для формата без года берётся текущий,
-- кроме случая, когда полученная дата оказывается в будущем — тогда год -1.
local function parseBookDate(s)
  if not s or s == "" then return nil end
  local d, m, y = string.match(s, "(%d+)%.(%d+)%.(%d+)")
  if y then
    return string.format("%04d-%02d-%02d", tonumber(y), tonumber(m), tonumber(d))
  end
  local day = regex_match(s, "\\d+")
  local mon = regex_match(s, "[А-Яа-яёЁ]+")
  if day and day[1] and mon and mon[1] then
    local mn = MONTHS[mon[1]]
    if mn then
      local nday = tonumber(day[1])
      local now = os.time()
      local curY = tonumber(os.date("%Y", now))
      local curM = string.format("%02d", tonumber(os.date("%m", now)))
      local curD = tonumber(os.date("%d", now))
      local yr = curY
      if mn > curM or (mn == curM and nday > curD) then yr = curY - 1 end
      return string.format("%04d-%s-%02d", yr, mn, nday)
    end
  end
  return nil
end

local function parseCards(doc)
  local items = {}
  for _, card in ipairs(doc:select("div.one-book-home")) do
    local titleEl = card:selectFirst("div.title-home a")
    local linkEl  = card:selectFirst("div.img-home > a")
    local imgEl   = card:selectFirst("div.img-home > a > img")
    local bookUrl = linkEl and absUrl(linkEl:attr("href")) or ""
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
  local doc = r:toHtml()
  local items = parseCards(doc)

  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local url = baseUrl .. "vse-knigi/?searchname=" .. url_encode(query) .. "&bpage=" .. tostring(index + 1)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end
  local doc = r:toHtml()
  local items = parseCards(doc)

  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst("h1.entry-title")
  if el then return string_clean(el:text()) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst("div.img-ranobe > img")
  if el then return absUrl(el:attr("src")) end
  return nil
end

function getBookDescription(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local meta = doc:selectFirst("meta[name=description]")
  local desc = meta and meta:attr("content") or ""
  if desc ~= "" then return string_trim(desc) end
  return nil
end

function getBookGenres(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return {} end

  local genres = {}
  for _, block in ipairs(doc:select("div.data-ranobe")) do
    local icon = block:selectFirst("span[class*=dashicons-book]:not([class*=book-alt])")
    if icon then
      local valueEl = block:selectFirst("div.data-value")
      if valueEl then
        for _, a in ipairs(valueEl:select("a")) do
          local label = string_trim(a:text())
          if label ~= "" then table.insert(genres, label) end
        end
        if #genres == 0 then
          local label = string_trim(valueEl:text())
          if label ~= "" then table.insert(genres, label) end
        end
      end
      break
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

function getBookStatus(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  for _, block in ipairs(doc:select("div.data-ranobe")) do
    if block:selectFirst("span.dashicons-megaphone") then
      local val = block:selectFirst("div.data-value")
      if val then
        local s = string_clean(val:text())
        if s ~= "" then return s end
      end
      break
    end
  end
  return nil
end

function getBookLastUpdate(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local first = doc:selectFirst(".li-ranobe")
  if not first then return nil end
  local dateEl = first:selectFirst(".li-col2-ranobe")
  if not dateEl then return nil end
  return parseBookDate(string_trim(dateEl:text()))
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return {} end

  local chapters = {}
  for _, li in ipairs(doc:select(".li-ranobe")) do
    local a = li:selectFirst(".li-col1-ranobe a")
    if a then
      local chUrl = absUrl(a:attr("href"))
      if chUrl ~= "" then
        table.insert(chapters, {
          title = string_clean(a:text()),
          url   = chUrl
        })
      end
    end
  end

  local reversed = {}
  for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
  return reversed
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local doc = fetchBookDoc(bookUrl)
  if not doc then return nil end
  local el = doc:selectFirst(".data-value")
  if el then return string_clean(el:text()) end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads", ".pc-adv", ".mob-adv")
  local el = html_select_first(cleaned, ".entry-content")
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
  local doc = r:toHtml()
  local items = parseCards(doc)

  return { items = items, hasNext = #items > 0 }
end
