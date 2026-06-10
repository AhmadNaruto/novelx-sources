# Lua Plugin Writing Guide

> Based on analysis of actual code: `LuaSourceAdapter.kt`, `LuaSourceLoader.kt`, `LuaFilterSupport.kt`, `LuaSettingsSupport.kt`, and 27 existing plugins.

---

## Table of Contents

1. [Plugin Structure](#plugin-structure)
2. [Metadata](#metadata)
3. [Mandatory Functions](#mandatory-functions)
4. [Working with HTTP](#working-with-http)
5. [Working with HTML and CSS Selectors](#working-with-html-and-css-selectors)
6. [Text Cleaning](#text-cleaning)
7. [Working with JSON API](#working-with-json-api)
8. [Catalog and Pagination](#catalog-and-pagination)
9. [Chapter List](#chapter-list)
10. [Chapter Text](#chapter-text)
11. [Catalog Filters](#catalog-filters)
12. [Plugin Settings](#plugin-settings)
13. [Helpers and Utilities](#helpers-and-utilities)
14. [Full API Reference](#full-api-reference)
15. [Full Plugin Template](#full-plugin-template)
16. [Common Mistakes](#common-mistakes)

---

## Plugin Structure

A plugin is a single `.lua` file. The engine (`LuaEngine`) loads it via `JsePlatform.standardGlobals()`, executes it, and passes the `globals` to the `LuaSourceAdapter`. All functions and variables declared in the global scope are accessible by the adapter.

Minimal file structure:

```lua
-- 1. METADATA (global variables)
id       = "my_source"
name     = "My Source"
version  = "1.0.0"
baseUrl  = "https://example.com"
language = "en"

-- 2. LOCAL HELPERS
local function absUrl(href) ... end

-- 3. MANDATORY FUNCTIONS
function getCatalogList(index) ... end
function getCatalogSearch(index, query) ... end
function getBookTitle(bookUrl) ... end
function getBookCoverImageUrl(bookUrl) ... end
function getBookDescription(bookUrl) ... end
function getChapterList(bookUrl) ... end
function getChapterText(html, url) ... end

-- 4. OPTIONAL FUNCTIONS
function getBookGenres(bookUrl) ... end
function getChapterListHash(bookUrl) ... end
function getFilterList() ... end
function getCatalogFiltered(index, filters) ... end
function getSettingsSchema() ... end
```

The adapter automatically determines the subclass based on the presence of functions:

| Functions Present | Adapter Subclass |
|---|---|
| Only mandatory | `LuaSourceAdapter` |
| + `getSettingsSchema` | `LuaSourceAdapterConfigurable` |
| + `getFilterList` | `LuaSourceAdapterFilterable` |
| + both | `LuaSourceAdapterFull` |

---

## Metadata

All fields are global Lua variables.

```lua
id       = "source_id"        -- unique ID, used as filename: source_id.lua
name     = "Source Name"      -- display name
version  = "1.0.0"            -- version
baseUrl  = "https://..."      -- base URL (mandatory)
language = "en"               -- ISO 639-1: "en", "ru", "ja", "zh", "id"
                              -- or "MTL" for machine translation
icon     = "https://..."      -- icon URL (optional)
charset  = "UTF-8"            -- response encoding (optional, default UTF-8)
```

**Important regarding `id`:** must match the `.lua` filename without the extension. If `id = "royal_road"`, the file must be named `royal_road.lua`.

---

## Mandatory Functions

### getCatalogList(index)

Paginated catalog. `index` starts at 0.

```lua
function getCatalogList(index)
    local page = index + 1  -- most sites start counting from 1
    local r = http_get(baseUrl .. "/novels?page=" .. page)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, card in ipairs(html_select(r.body, ".novel-item")) do
        local titleEl = html_select_first(card.html, "h3 a")
        if titleEl then
            table.insert(items, {
                title = string_clean(titleEl.text),
                url   = absUrl(titleEl.href),
                cover = absUrl(html_attr(card.html, "img", "src"))
            })
        end
    end

    return { items = items, hasNext = #items > 0 }
end
```

Returned table:
- `items` — array of `{ title, url, cover }`, where `cover` is optional
- `hasNext` — `true` if there is a next page

### getCatalogSearch(index, query)

Search. If the site returns everything on one page — return `hasNext = false` when `index > 0`.

```lua
function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local url = baseUrl .. "/search?q=" .. url_encode(query)
    -- ... same as getCatalogList
end
```

### getBookTitle(bookUrl)

```lua
function getBookTitle(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "h1.title")
    return el and string_clean(el.text) or nil
end
```

### getBookCoverImageUrl(bookUrl)

```lua
function getBookCoverImageUrl(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local cover = html_attr(r.body, ".cover img", "src")
    return cover ~= "" and absUrl(cover) or nil
end
```

### getBookDescription(bookUrl)

```lua
function getBookDescription(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".description")
    return el and string_trim(el.text) or nil
end
```

### getChapterList(bookUrl)

Returns an array of `{ title, url, volume? }` in chronological order (from first to last).

```lua
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local chapters = {}
    for _, a in ipairs(html_select(r.body, ".chapter-list a[href]")) do
        table.insert(chapters, {
            title = string_clean(a.text),
            url   = absUrl(a.href)
        })
    end
    return chapters
end
```

### getChapterText(html, url)

Gets full HTML of the chapter page and the URL. Must return a string with the text.

```lua
function getChapterText(html, url)
    local cleaned = html_remove(html, "script", "style", ".ads", ".nav-links")
    local el = html_select_first(cleaned, ".chapter-content")
    if not el then return "" end
    return applyStandardContentTransforms(html_text(el.html))
end
```

---

## Working with HTTP

### http_get(url [, config])

```lua
-- Simple GET
local r = http_get("https://example.com/page")

-- With headers
local r = http_get(url, {
    headers = {
        ["Referer"]          = baseUrl,
        ["X-Requested-With"] = "XMLHttpRequest",
        ["Accept"]           = "application/json",
    },
    charset = "UTF-8"  -- response encoding (default UTF-8)
})

-- Checking result
if not r.success then
    log_error("Request failed: code=" .. tostring(r.code))
    return { items = {}, hasNext = false }
end
-- r.body  — response body string
-- r.code  — HTTP code (200, 404, ...)
```

### http_post(url, body [, config])

```lua
-- Form-encoded POST
local r = http_post(
    baseUrl .. "/ajax",
    "action=loadChapters&id=" .. novelId,
    {
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Referer"]      = baseUrl
        }
    }
)

-- JSON POST
local r = http_post(
    baseUrl .. "/api/reader",
    json_stringify({ novel_id = 123, chapter = 1 }),
    {
        headers = {
            ["Content-Type"] = "application/json",
            ["Origin"]       = baseUrl
        }
    }
)
```

### http_get_batch(urls_table)

Parallel loading of multiple URLs. Response order matches request order.

```lua
local urls = {}
for p = 2, maxPage do
    table.insert(urls, baseUrl .. "/chapters?page=" .. p)
end

local results = http_get_batch(urls)
for i, res in ipairs(results) do
    if res.success then
        -- process res.body
    end
end
```

### Working with cookies

```lua
-- Get cookies for a domain
local cookies = get_cookies("https://example.com")
local token = cookies["session_token"]

-- Set cookies
set_cookies("https://example.com", {
    ["session_id"] = "abc123",
    ["token"]      = "xyz"
})
```

### Delays (rate limiting)

```lua
sleep(300)                        -- 300 ms
sleep(math.random(150, 350))      -- random delay 150-350 ms
```

Use `sleep` between requests in `getChapterList` if the site aggressively blocks parsers (example: jaomix).

---

## Working with HTML and CSS Selectors

### Basic Functions

```lua
-- Parses HTML, returns { text, html, title, body }
local doc = html_parse(htmlString)

-- Returns array of elements
local cards = html_select(htmlString, ".novel-card")

-- Returns first element or nil
local el = html_select_first(htmlString, "h1.title")

-- Quickly get attribute of first match
local src = html_attr(htmlString, ".cover img", "src")

-- Extract text preserving newline structure (<p>, <br>)
local text = html_text(innerHtml)

-- Remove elements from HTML
local cleanHtml = html_remove(html, "script", "style", ".ads", "#popup")
```

### Element Object

`html_select` and `html_select_first` return tables with the following fields:

```lua
el.text   -- text content (analog to element.innerText)
el.html   -- innerHTML
el.href   -- href attribute (already absolute if abs:href is available)
el.src    -- src attribute
el.title  -- title attribute
el.class  -- class attribute
el.id     -- id attribute

-- Methods:
el:attr("data-id")        -- any attribute
el:select(".child")       -- find child elements
el:get_text()             -- same as el.text
el:get_html()             -- same as el.html
el:remove()               -- remove element from DOM
```

### Typical Patterns with Selectors

```lua
-- Iterate over catalog cards
for _, card in ipairs(html_select(r.body, ".book-item")) do
    local titleEl = html_select_first(card.html, "h3 a")
    local cover   = html_attr(card.html, "img", "src")
    -- ...
end

-- Get href with validation
local a = html_select_first(r.body, ".read-btn a")
if a and a.href ~= "" then
    chapterUrl = absUrl(a.href)
end

-- Get data-attribute
local postId = html_attr(r.body, "#novel-report", "data-post-id")
-- or via select:
local el = html_select_first(r.body, "#novel-report")
if el then
    local postId = el:attr("data-post-id")
end

-- Remove trash before text parsing
local cleaned = html_remove(html,
    "script", "style",
    ".advertisement", ".popup",
    ".chapter-nav", "#comments"
)
```

### Working with Nested Structures

```lua
-- Nested search
for _, row in ipairs(html_select(r.body, "table tr")) do
    local cells = html_select(row.html, "td")
    if #cells >= 2 then
        local label = string_trim(cells[1].text)
        local value = string_trim(cells[2].text)
        if label == "Genre" then
            -- process value
        end
    end
end
```

---

## Text Cleaning

### Standard Content Cleaning Function

Use in every plugin — this is a template from real plugins:

```lua
local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end

    -- 1. Unicode normalization (NFKC)
    text = string_normalize(text)

    -- 2. Remove source site links
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?
", "")

    -- 3. Remove chapter title at start (it is duplicated in the name)
    text = regex_replace(text, "(?i)\A[\s\p{Z}\uFEFF]*((Chapter\s+\d+)[^
]*[
\s]*)+", "")

    -- 4. Remove translator/editor lines
    text = regex_replace(text, "(?im)^\s*(Translator|Editor|Proofreader|Read\s+(at|on|latest))[:\s][^
]{0,70}(?
|$)", "")

    -- 5. Trim whitespace
    text = string_trim(text)
    return text
end
```

### string_clean vs string_trim

```lua
-- string_clean: normalize Unicode + collapse whitespace + trim
-- Use for: title, author, genre — any short fields
string_clean("  Chapter  title  ") --> "Chapter title"

-- string_trim: just trim whitespace
-- Use for: description, where newlines matter
string_trim("  text  ") --> "text"
```

**Rule:** `string_clean` for short metadata, `string_trim` for long description texts.

### html_text — correct text extraction

`html_text` uses `TextExtractor`, which understands HTML structure:
- `<p>` → paragraph + double newline
- `<br>` → single newline
- `<hr>` → double newline

### Regular Expressions

The engine uses Java regex with support for:
- `(?i)` — case-insensitive
- `(?m)` — multiline (`^` and `$` on each line)
- `\p{Z}` — Unicode spaces
- `\uFEFF` — BOM character
- `\A` — start of string (absolute)

---

## Working with JSON API

```lua
function getCatalogList(index)
    local r = http_get(apiBase .. "novels?page=" .. (index + 1))
    if not r.success then return { items = {}, hasNext = false } end

    -- Parsing JSON
    local data = json_parse(r.body)
    if not data then
        log_error("json_parse failed for getCatalogList")
        return { items = {}, hasNext = false }
    end

    local items = {}
    -- data can be an array or an object with a data/items/results field
    local novelList = data.data or data.items or data.results or data
    if type(novelList) ~= "table" then return { items = {}, hasNext = false } end

    for _, novel in ipairs(novelList) do
        local title = novel.title or novel.name or ""
        local id    = tostring(novel.id or "")
        if title ~= "" and id ~= "" then
            table.insert(items, {
                title = string_clean(title),
                url   = baseUrl .. "/novel/" .. id,
                cover = absUrl(novel.cover or novel.image or "")
            })
        end
    end

    -- Determining hasNext
    local hasNext = data.hasNext
        or (data.pagination and data.pagination.hasMore)
        or (#items > 0 and data.total and data.total > (index + 1) * 40)
        or (#items >= 20)

    return { items = items, hasNext = hasNext == true or hasNext ~= false and #items > 0 }
end
```

---

## Catalog and Pagination

### Standard Pagination Schemes

**Scheme 1: `?page=N` parameter**

```lua
function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/catalog?page=" .. page
    -- ...
    return { items = items, hasNext = #items > 0 }
end
```

**Scheme 2: Cursor / offset**

```lua
local ITEMS_PER_PAGE = 20
function getCatalogList(index)
    local offset = index * ITEMS_PER_PAGE
    local url = apiBase .. "novels?offset=" .. offset .. "&limit=" .. ITEMS_PER_PAGE
    -- ...
end
```

**Scheme 3: Single page (whole list at once)**

```lua
function getCatalogList(index)
    if index > 0 then return { items = {}, hasNext = false } end
    -- load everything
end
```

---

## Chapter List

### Pattern 1: All chapters on one page

```lua
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local chapters = {}
    for _, a in ipairs(html_select(r.body, ".chapters-list a[href]")) do
        local title = string_trim(a.title)
        if title == "" then title = string_trim(a.text) end
        table.insert(chapters, {
            title = string_clean(title),
            url   = absUrl(a.href)
        })
    end
    return chapters
end
```

---

## Chapter Text

`getChapterText(html, url)` receives the full HTML of the page and the URL. The engine loads the page itself — the plugin only parses.

### Standard Pattern

```lua
function getChapterText(html, url)
    -- Step 1: Remove unwanted elements
    local cleaned = html_remove(html,
        "script", "style",
        ".ads", ".advertisement",
        ".chapter-nav", ".nav-links",
        "#comments", ".disqus"
    )

    -- Step 2: Find container with text
    local el = html_select_first(cleaned, ".chapter-content")
    if not el then
        -- Fallbacks
        el = html_select_first(cleaned, "#content, .entry-content, .text-content")
    end
    if not el then return "" end

    -- Step 3: Extract text preserving paragraph structure
    local text = html_text(el.html)

    -- Step 4: Standard transforms
    return applyStandardContentTransforms(text)
end
```

---

## Catalog Filters

To support filters, you must declare two functions: `getFilterList()` and `getCatalogFiltered(index, filters)`.

### getFilterList()

Returns an array of filter descriptions. The list always originates from Lua — no hardcoding in Kotlin.

```lua
function getFilterList()
    return {
        {
            type         = "select",
            key          = "sort",
            label        = "Sort By",
            defaultValue = "latest",
            options = {
                { value = "latest",  label = "Latest Update" },
                { value = "popular", label = "Most Popular"  },
            }
        },
        {
            type  = "checkbox",
            key   = "genres",
            label = "Genres",
            options = {
                { value = "action",  label = "Action"  },
                { value = "fantasy", label = "Fantasy" },
            }
        },
    }
end
```

---

## Plugin Settings

For permanent settings saved between sessions.

```lua
-- Constant — setting key
local PREF_LANG = "my_source_language"

local function getLang()
    local v = get_preference(PREF_LANG)
    return (v ~= "" and v) or "en"
end

function getSettingsSchema()
    return {
        {
            key     = PREF_LANG,
            type    = "select",
            label   = "Language",
            current = getLang(),
            options = {
                { value = "en", label = "English" },
                { value = "id", label = "Indonesian" },
            }
        }
    }
end
```

---

## Common Mistakes

1. **Incorrect `nil` handling:** Always check `if el then` before accessing properties.
2. **Using `el.text` instead of `html_text` for chapter text:** `el.text` strips newlines. Use `html_text(el.html)`.
3. **Ignoring encoding:** If the site uses non-UTF-8 encoding (e.g., GBK), you must specify it.
4. **Relative URLs without `absUrl`:** Always use `absUrl()` to convert `/novel/1` to `https://site.com/novel/1`.
5. **Wrong chapter order:** The plugin must return chapters in chronological order (Chapter 1 -> Chapter 2 -> ...). If the site shows the latest chapter first, you must reverse the list.
6. **Forgetting to check `r.success`:** Always check if the request succeeded before processing `r.body`.
