# Panduan Penulisan Plugin Lua

> Didasarkan pada analisis kode aktual: `LuaSourceAdapter.kt`, `LuaSourceLoader.kt`, `LuaFilterSupport.kt`, `LuaSettingsSupport.kt`, dan 27 plugin yang ada.

---

## Daftar Isi

1. [Struktur Plugin](#struktur-plugin)
2. [Metadata](#metadata)
3. [Fungsi Wajib](#fungsi-wajib)
4. [Bekerja dengan HTTP](#bekerja-dengan-http)
5. [Bekerja dengan HTML dan Selektor CSS](#bekerja-dengan-html-dan-selektor-css)
6. [Pembersihan Teks](#pembersihan-teks)
7. [Bekerja dengan JSON API](#bekerja-dengan-json-api)
8. [Katalog dan Penomoran Halaman (Pagination)](#katalog-dan-penomoran-halaman-pagination)
9. [Daftar Bab](#daftar-bab)
10. [Teks Bab](#teks-bab)
11. [Filter Katalog](#filter-katalog)
12. [Pengaturan Plugin](#pengaturan-plugin)
13. [Helper dan Utilitas](#helper-dan-utilitas)
14. [Referensi API Lengkap](#referensi-api-lengkap)
15. [Template Plugin Lengkap](#template-plugin-lengkap)
16. [Kesalahan Umum](#kesalahan-umum)

---

## Struktur Plugin

Sebuah plugin adalah satu file `.lua`. *Engine* (`LuaEngine`) memuatnya melalui `JsePlatform.standardGlobals()`, mengeksekusinya, dan meneruskan `globals` ke `LuaSourceAdapter`. Semua fungsi dan variabel yang dideklarasikan dalam ruang lingkup global dapat diakses oleh adaptor.

Struktur file minimal:

```lua
-- 1. METADATA (variabel global)
id       = "sumber_saya"
name     = "Sumber Saya"
version  = "1.0.0"
baseUrl  = "https://contoh.com"
language = "id"

-- 2. HELPER LOKAL
local function absUrl(href) ... end

-- 3. FUNGSI WAJIB
function getCatalogList(index) ... end
function getCatalogSearch(index, query) ... end
function getBookTitle(bookUrl) ... end
function getBookCoverImageUrl(bookUrl) ... end
function getBookDescription(bookUrl) ... end
function getChapterList(bookUrl) ... end
function getChapterText(html, url) ... end

-- 4. FUNGSI OPSIONAL
function getBookGenres(bookUrl) ... end
function getChapterListHash(bookUrl) ... end
function getFilterList() ... end
function getCatalogFiltered(index, filters) ... end
function getSettingsSchema() ... end
```

Adaptor secara otomatis menentukan subkelas berdasarkan keberadaan fungsi:

| Fungsi yang ada | Subkelas Adaptor |
|---|---|
| Hanya dasar | `LuaSourceAdapter` |
| + `getSettingsSchema` | `LuaSourceAdapterConfigurable` |
| + `getFilterList` | `LuaSourceAdapterFilterable` |
| + keduanya | `LuaSourceAdapterFull` |

---

## Metadata

Semua bidang adalah variabel global Lua.

```lua
id       = "source_id"        -- ID unik, digunakan sebagai nama file: source_id.lua
name     = "Nama Sumber"      -- Nama yang ditampilkan
version  = "1.0.0"            -- Versi
baseUrl  = "https://..."      -- URL dasar (wajib)
language = "en"               -- ISO 639-1: "en", "ru", "ja", "zh", "id"
                              -- atau "MTL" untuk terjemahan mesin
icon     = "https://..."      -- URL ikon (opsional)
charset  = "UTF-8"            -- pengodean respons (opsional, default UTF-8)
```

**Penting tentang `id`:** harus sama dengan nama file `.lua` tanpa ekstensi. Jika `id = "royal_road"`, nama file harus `royal_road.lua`.

---

## Fungsi Wajib

### getCatalogList(index)

Katalog per halaman. `index` dimulai dari 0.

```lua
function getCatalogList(index)
    local page = index + 1  -- kebanyakan situs menghitung dari 1
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

Tabel yang dikembalikan:
- `items` — array `{ title, url, cover }`, di mana `cover` bersifat opsional
- `hasNext` — `true` jika ada halaman berikutnya

### getCatalogSearch(index, query)

Pencarian. Jika situs mengembalikan semuanya di satu halaman — kembalikan `hasNext = false` saat `index > 0`.

```lua
function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local url = baseUrl .. "/search?q=" .. url_encode(query)
    -- ... sama seperti getCatalogList
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

Mengembalikan array `{ title, url, volume? }` dalam urutan kronologis (dari bab pertama ke yang terakhir).

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

Mendapatkan HTML lengkap dari halaman bab dan URL. Harus mengembalikan string teks.

```lua
function getChapterText(html, url)
    local cleaned = html_remove(html, "script", "style", ".ads", ".nav-links")
    local el = html_select_first(cleaned, ".chapter-content")
    if not el then return "" end
    return applyStandardContentTransforms(html_text(el.html))
end
```

---

## Bekerja dengan HTTP

### http_get(url [, config])

```lua
-- GET sederhana
local r = http_get("https://contoh.com/halaman")

-- Dengan header
local r = http_get(url, {
    headers = {
        ["Referer"]          = baseUrl,
        ["X-Requested-With"] = "XMLHttpRequest",
        ["Accept"]           = "application/json",
    },
    charset = "UTF-8"  -- pengodean respons (default UTF-8)
})

-- Memeriksa hasil
if not r.success then
    log_error("Request gagal: kode=" .. tostring(r.code))
    return { items = {}, hasNext = false }
end
-- r.body  — string dengan badan respons
-- r.code  — kode HTTP (200, 404, ...)
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

Pengunduhan paralel beberapa URL. Urutan respons sesuai dengan urutan permintaan.

```lua
local urls = {}
for p = 2, maxPage do
    table.insert(urls, baseUrl .. "/chapters?page=" .. p)
end

local results = http_get_batch(urls)
for i, res in ipairs(results) do
    if res.success then
        -- memproses res.body
    end
end
```

### Bekerja dengan cookie

```lua
-- Mendapatkan cookie untuk domain
local cookies = get_cookies("https://contoh.com")
local token = cookies["session_token"]

-- Mengatur cookie
set_cookies("https://contoh.com", {
    ["session_id"] = "abc123",
    ["token"]      = "xyz"
})
```

### Penundaan (rate limiting)

```lua
sleep(300)                        -- 300 ms
sleep(math.random(150, 350))      -- penundaan acak 150-350 ms
```

Gunakan `sleep` antar permintaan di `getChapterList` jika situs secara agresif memblokir parser (contoh: jaomix).

---

## Bekerja dengan HTML dan Selektor CSS

### Fungsi Dasar

```lua
-- Mengurai HTML, mengembalikan { text, html, title, body }
local doc = html_parse(htmlString)

-- Mengembalikan array elemen
local cards = html_select(htmlString, ".novel-card")

-- Mengembalikan elemen pertama atau nil
local el = html_select_first(htmlString, "h1.title")

-- Mendapatkan atribut kecocokan pertama dengan cepat
local src = html_attr(htmlString, ".cover img", "src")

-- Mengekstrak teks dengan mempertahankan pemisah baris (<p>, <br>)
local text = html_text(innerHtml)

-- Menghapus elemen dari HTML
local cleanHtml = html_remove(html, "script", "style", ".ads", "#popup")
```

### Objek Elemen

`html_select` dan `html_select_first` mengembalikan tabel dengan bidang berikut:

```lua
el.text   -- konten teks (analog dengan element.innerText)
el.html   -- innerHTML
el.href   -- atribut href (sudah absolut jika abs:href tersedia)
el.src    -- atribut src
el.title  -- atribut title
el.class  -- atribut class
el.id     -- atribut id

-- Metode:
el:attr("data-id")        -- atribut apa pun
el:select(".child")       -- menemukan elemen turunan
el:get_text()             -- sama seperti el.text
el:get_html()             -- sama seperti el.html
el:remove()               -- menghapus elemen dari DOM
```

### Pola Tipikal dengan Selektor

```lua
-- Iterasi melalui kartu katalog
for _, card in ipairs(html_select(r.body, ".book-item")) do
    local titleEl = html_select_first(card.html, "h3 a")
    local cover   = html_attr(card.html, "img", "src")
    -- ...
end

-- Mendapatkan href dengan validasi
local a = html_select_first(r.body, ".read-btn a")
if a and a.href ~= "" then
    chapterUrl = absUrl(a.href)
end

-- Mendapatkan data-atribut
local postId = html_attr(r.body, "#novel-report", "data-post-id")
-- atau melalui select:
local el = html_select_first(r.body, "#novel-report")
if el then
    local postId = el:attr("data-post-id")
end

-- Menghapus sampah sebelum mengurai teks
local cleaned = html_remove(html,
    "script", "style",
    ".advertisement", ".popup",
    ".chapter-nav", "#comments"
)
```

### Bekerja dengan Struktur Bersarang

```lua
-- Pencarian bertingkat
for _, row in ipairs(html_select(r.body, "table tr")) do
    local cells = html_select(row.html, "td")
    if #cells >= 2 then
        local label = string_trim(cells[1].text)
        local value = string_trim(cells[2].text)
        if label == "Genre" then
            -- memproses value
        end
    end
end
```

---

## Pembersihan Teks

### Fungsi Pembersihan Konten Standar

Gunakan di setiap plugin — ini adalah template dari plugin nyata:

```lua
local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end

    -- 1. Normalisasi Unicode (NFKC)
    text = string_normalize(text)

    -- 2. Menghapus tautan ke situs sumber
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?
", "")

    -- 3. Menghapus judul bab di awal (karena sudah ada di nama)
    text = regex_replace(text, "(?i)\A[\s\p{Z}\uFEFF]*((Bab\s+\d+|Chapter\s+\d+)[^
]*[
\s]*)+", "")

    -- 4. Menghapus baris penerjemah/editor
    text = regex_replace(text, "(?im)^\s*(Translator|Editor|Proofreader|Read\s+(at|on|latest))[:\s][^
]{0,70}(?
|$)", "")

    -- 5. Memotong spasi
    text = string_trim(text)
    return text
end
```

Untuk situs Indonesia/umum, Anda bisa menyesuaikan regex:

```lua
text = regex_replace(text, "(?im)^\s*(Terjemahan|Penerjemah|Editor|Revisi|Catatan|Situs|Sumber)[:\s][^
]{0,70}(?
|$)", "")
```

### string_clean vs string_trim

```lua
-- string_clean: normalisasi Unicode + merapatkan spasi + trim
-- Gunakan untuk: title, author, genre — bidang pendek apa pun
string_clean("  Judul  bab  ") --> "Judul bab"

-- string_trim: hanya trim spasi
-- Gunakan untuk: description, di mana pemisah baris penting
string_trim("  teks  ") --> "teks"
```

**Aturan:** `string_clean` untuk metadata pendek, `string_trim` untuk teks deskripsi panjang.

### html_text — ekstraksi teks yang benar

`html_text` menggunakan `TextExtractor`, yang memahami struktur HTML:
- `<p>` → paragraf + pemisah baris ganda
- `<br>` → pemisah baris tunggal
- `<hr>` → pemisah baris ganda

```lua
-- BENAR: mempertahankan struktur paragraf
local text = html_text(el.html)

-- SALAH untuk teks bab: kehilangan pemisah baris
local text = el.text
```

### Ekspresi Reguler (Regex)

Engine menggunakan regex Java dengan dukungan:
- `(?i)` — tidak peka huruf besar/kecil (case-insensitive)
- `(?m)` — multiline (`^` dan `$` di setiap baris)
- `\p{Z}` — spasi Unicode
- `\uFEFF` — karakter BOM
- `\A` — awal string (absolut)

```lua
-- Menghapus tag HTML
text = regex_replace(text, "<[^>]*>", "")

-- Menemukan ID numerik
local id = regex_match(url, "/novel/(\d+)/")[1]

-- Menghapus spasi ganda
text = regex_replace(text, "\s+", " ")
```

---

## Bekerja dengan JSON API

```lua
function getCatalogList(index)
    local r = http_get(apiBase .. "novels?page=" .. (index + 1))
    if not r.success then return { items = {}, hasNext = false } end

    -- Mengurai JSON
    local data = json_parse(r.body)
    if not data then
        log_error("json_parse gagal untuk getCatalogList")
        return { items = {}, hasNext = false }
    end

    local items = {}
    -- data bisa berupa array atau objek dengan bidang data/items/results
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

    -- Menentukan hasNext
    local hasNext = data.hasNext                       -- bidang boolean
        or (data.pagination and data.pagination.hasMore)
        or (#items > 0 and data.total and data.total > (index + 1) * 40)
        or (#items >= 20)  -- heuristik: jika kembali >= 20, mungkin masih ada

    return { items = items, hasNext = hasNext == true or hasNext ~= false and #items > 0 }
end
```

### Akses Mendalam ke Bidang

```lua
-- Akses aman ke bidang bertingkat
local cover = (novel.poster and novel.poster.medium) or ""
local title = (novel.names and (novel.names.ind or novel.names.eng)) or novel.name or ""

-- Serialisasi kembali ke JSON (untuk dikirim dalam POST)
local body = json_stringify({
    page = 1,
    filters = { status = "ongoing" }
})
```

---

## Katalog dan Penomoran Halaman (Pagination)

### Skema Penomoran Halaman Standar

**Skema 1: Parameter `?page=N`**

```lua
function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/catalog?page=" .. page
    -- ...
    return { items = items, hasNext = #items > 0 }
end
```

**Skema 2: Kursor / offset**

```lua
local ITEMS_PER_PAGE = 20
function getCatalogList(index)
    local offset = index * ITEMS_PER_PAGE
    local url = apiBase .. "novels?offset=" .. offset .. "&limit=" .. ITEMS_PER_PAGE
    -- ...
end
```

**Skema 3: Satu halaman (seluruh daftar sekaligus)**

```lua
function getCatalogList(index)
    if index > 0 then return { items = {}, hasNext = false } end
    -- memuat semuanya
end
```

**Skema 4: Deteksi otomatis melalui detect_pagination**

```lua
local pagination = detect_pagination(r.body)
return { items = items, hasNext = pagination.hasNext }
```

### Pola Membangun URL Filter

```lua
local url = baseUrl .. "/search?page=" .. page

-- Parameter sederhana
if sort ~= "" then url = url .. "&sort=" .. url_encode(sort) end
if status ~= "all" then url = url .. "&status=" .. status end

-- Array (beberapa parameter yang sama)
for _, v in ipairs(genres_included) do
    url = url .. "&genre[]=" .. url_encode(v)
end

-- Array dengan koma
if #tags_included > 0 then
    url = url .. "&tags=" .. table.concat(tags_included, ",")
end
```

---

## Daftar Bab

### Pola 1: Semua bab di satu halaman

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

### Pola 2: AJAX dengan penomoran halaman

```lua
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    -- Menentukan jumlah halaman
    local pages = html_select(r.body, ".pagination a[href]")
    local maxPage = 1
    for _, a in ipairs(pages) do
        local p = tonumber(a.text)
        if p and p > maxPage then maxPage = p end
    end

    local allChapters = {}
    for page = 1, maxPage do
        local pr = http_post(baseUrl .. "/ajax", "action=chapters&page=" .. page, {
            headers = { ["X-Requested-With"] = "XMLHttpRequest" }
        })
        if not pr.success then break end

        for _, a in ipairs(html_select(pr.body, "a[href]")) do
            table.insert(allChapters, {
                title = string_clean(a.text),
                url   = absUrl(a.href)
            })
        end

        sleep(200)
    end

    return allChapters
end
```

### Pola 3: JSON API dengan Volume

```lua
function getChapterList(bookUrl)
    local novelId = bookUrl:match("/novel/(%d+)")
    if not novelId then return {} end

    local r = http_get(apiBase .. "novels/" .. novelId .. "/chapters")
    if not r.success then return {} end

    local data = json_parse(r.body)
    if not data or not data.volumes then return {} end

    local chapters = {}
    for _, volume in ipairs(data.volumes) do
        local volTitle = "Volume " .. tostring(volume.num or "")
        for _, ch in ipairs(volume.chapters or {}) do
            table.insert(chapters, {
                title  = string_clean(ch.title or "Bab " .. tostring(ch.num)),
                url    = baseUrl .. "/read/" .. novelId .. "/" .. ch.id,
                volume = volTitle
            })
        end
    end
    return chapters
end
```

### Pemuatan paralel melalui http_get_batch

```lua
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    -- Mengumpulkan URL semua halaman
    local slug = bookUrl:match("/([^/]+)$")
    local maxPage = 1
    for _, a in ipairs(html_select(r.body, ".pagination a")) do
        local p = tonumber(a.text)
        if p and p > maxPage then maxPage = p end
    end

    -- Memuat semua halaman secara paralel
    local urls = {}
    for p = 2, maxPage do
        table.insert(urls, baseUrl .. "/novel/" .. slug .. "/chapters?page=" .. p)
    end

    local firstPageChapters = parseChaptersFromHtml(r.body)
    local allChapters = firstPageChapters

    if #urls > 0 then
        local results = http_get_batch(urls)
        for _, res in ipairs(results) do
            if res.success then
                for _, ch in ipairs(parseChaptersFromHtml(res.body)) do
                    table.insert(allChapters, ch)
                end
            end
        end
    end

    return allChapters
end
```

### getChapterListHash

Fungsi opsional. Jika mengembalikan string — digunakan untuk menentukan apakah daftar bab telah berubah (agar tidak memuat ulang seluruh daftar).

```lua
function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    -- Mengembalikan sesuatu yang secara unik mengidentifikasi status saat ini:
    -- URL bab terakhir, jumlah bab, tanggal pembaruan terakhir
    local lastChapter = html_select_first(r.body, ".chapter-list a:last-child")
    return lastChapter and lastChapter.href or nil
end
```

---

## Teks Bab

`getChapterText(html, url)` mendapatkan HTML lengkap halaman dan URL. Engine memuat halaman itu sendiri — plugin hanya mengurai.

### Pola Standar

```lua
function getChapterText(html, url)
    -- Langkah 1: Hapus elemen yang tidak diinginkan
    local cleaned = html_remove(html,
        "script", "style",              -- selalu
        ".ads", ".advertisement",       -- iklan
        ".chapter-nav", ".nav-links",   -- navigasi
        "#comments", ".disqus"          -- komentar
    )

    -- Langkah 2: Temukan kontainer dengan teks
    local el = html_select_first(cleaned, ".chapter-content")
    if not el then
        -- Opsi cadangan
        el = html_select_first(cleaned, "#content, .entry-content, .text-content")
    end
    if not el then return "" end

    -- Langkah 3: Ekstrak teks dengan mempertahankan struktur paragraf
    local text = html_text(el.html)

    -- Langkah 4: Transformasi standar
    return applyStandardContentTransforms(text)
end
```

---

## Filter Katalog

Agar plugin mendukung filter, Anda perlu mendeklarasikan dua fungsi: `getFilterList()` dan `getCatalogFiltered(index, filters)`.

### getFilterList()

Mengembalikan array deskripsi filter. Daftar selalu berasal dari Lua — tidak ada *hardcode* di Kotlin.

```lua
function getFilterList()
    return {
        -- Memilih satu nilai dari daftar
        {
            type         = "select",
            key          = "sort",
            label        = "Urutkan Berdasarkan",
            defaultValue = "latest",
            options = {
                { value = "latest",  label = "Pembaruan Terbaru" },
                { value = "popular", label = "Paling Populer"    },
            }
        },

        -- Pilihan ganda (centang)
        {
            type  = "checkbox",
            key   = "genres",
            label = "Genre",
            options = {
                { value = "action",  label = "Action"  },
                { value = "fantasy", label = "Fantasy" },
            }
        },
        
        -- ... jenis lainnya (switch, text, tristate, sort)
    }
end
```

### getCatalogFiltered(index, filters)

Cara Kotlin meneruskan filter ke `filters` (LuaTable):

| Tipe Filter | Kunci di filters | Nilai |
|---|---|---|
| `select` | `filters["key"]` | string |
| `checkbox` | `filters["key_included"]` | tabel-array string |
| `switch` | `filters["key"]` | `"true"` atau `"false"` |
| `text` | `filters["key"]` | string |
| `sort` | `filters["key"]` | string (nilai yang dipilih) |

---

## Pengaturan Plugin

Untuk pengaturan permanen yang disimpan antar sesi.

```lua
-- Konstanta — kunci pengaturan
local PREF_LANG = "my_source_language"

local function getLang()
    local v = get_preference(PREF_LANG)
    return (v ~= "" and v) or "en"  -- default "en"
end

function getSettingsSchema()
    return {
        {
            key     = PREF_LANG,
            type    = "select",
            label   = "Bahasa",
            current = getLang(),       -- nilai saat ini untuk UI
            options = {
                { value = "en", label = "English" },
                { value = "id", label = "Indonesian" },
            }
        }
    }
end
```

---

## Kesalahan Umum

1. **Bekerja dengan nil secara salah:** Selalu periksa `if el then` sebelum mengakses properti.
2. **Menggunakan el.text alih-alih html_text:** `el.text` akan menghapus semua pemisah baris (`<br>`, `<p>`). Gunakan `html_text(el.html)`.
3. **Mengabaikan pengodean:** Jika situs menggunakan pengodean selain UTF-8 (misalnya GBK), Anda harus menentukannya.
4. **URL relatif tanpa absUrl:** Selalu gunakan `absUrl()` untuk mengubah `/novel/1` menjadi `https://situs.com/novel/1`.
5. **Urutan bab yang salah:** Plugin harus mengembalikan bab dalam urutan kronologis (Bab 1 -> Bab 2 -> ...). Jika situs menampilkan Bab Terbaru di atas, Anda harus membalik urutan daftar tersebut.
6. **Lupa memeriksa r.success:** Selalu periksa apakah permintaan berhasil sebelum memproses `r.body`.
