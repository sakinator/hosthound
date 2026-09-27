<div align="center">
  <a href="https://github.com/sakinator/hostreamio">
    <img src="https://raw.githubusercontent.com/sakinator/hostreamio/main/hostreamio_logo.png?v=3" alt="Hostreamio Logo" width="180" />
  </a>
  <h1 align="center" style="font-size: 2.4rem; font-weight: 900; letter-spacing: -0.5px; margin-top: 12px; margin-bottom: 4px;">▶️ Hostreamio Addon</h1>
  <p align="center"><b>Direct Hosters • Streaming Links • TorBox Cloud Debrid • Smart Proxy • Instant Badges</b></p>
  <p align="center"><i>High-Performance Stream Engine for Nuvio & Stremio (Windows & Android TV / Mobile)</i></p>

  [![Vibe Coded](https://img.shields.io/badge/Vibe%20Coded-100%25%20with%20AI-ff0c82?style=for-the-badge&logo=visualstudiocode&logoColor=white)](https://github.com/sakinator/hostreamio)
  [![Scrapers](https://img.shields.io/badge/Scrapers-58%20Cloud%20Extractors-195feb?style=for-the-badge)](https://github.com/sakinator/hostreamio)
  [![Platforms](https://img.shields.io/badge/Platforms-Windows%20%7C%20Android%20TV%20%26%20Mobile-f55014?style=for-the-badge)](https://github.com/sakinator/hostreamio)
  [![Debrid](https://img.shields.io/badge/TorBox-Cloud%20WebDL%20Caching-0070f3?style=for-the-badge)](https://torbox.app)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
</div>

> [!NOTE]
> **✨ 100% Vibe Coded with AI:** This entire project is vibe-coded through continuous human-AI agentic collaboration, real-time feedback loops, automated regression test suites, and live self-healing pipelines. High velocity, zero bloat, pure vibes.

A high-performance local Stremio & Nuvio-compatible addon server featuring **56 Direct HTTP/HLS Cloud Scrapers**, **TorBox Debrid Integration**, **Live Hoster Cloud Caching**, and rich public catalogs (**YouTube, Vimeo, Internet Archive & Dailymotion**) with automatic badge tagging, native 16:9 widescreen video posters, and embedded streaming proxy.

---

## 🌟 Features

- **100% Non-Torrent (Zero P2P):** No seeders, no torrent clients, and no IP seeding exposure. Streams directly from fast cloud storage and HTTP/HLS CDNs.
- **56 Cloud Scraper Providers:** Extracts streams across 56 scrapers including *4KHDHub, Vadapav, HindMoviez, RiveStream, LookMovie, VidLink, Movy, Videasy, Cinejoy, FlyStream, X-Downloader, Vuflix, FSOnline, KissKH, Megasource, Nova, Purstream*, and more.
- **TorBox Debrid Integration:**
  - **Batch Cache Checking:** Instantly checks up to 100 links in a single API query (`/webdl/checkcached`), cutting scraper turnaround by 2-3 seconds.
  - **1-Click Cloud Caching:** Direct "⚡ Cache to TorBox" links in Nuvio and the Web Dashboard. Submits uncached links to TorBox's WebDL downloader in 1 click.
  - **High-Speed CDN Playback:** Streams cached hoster files through TorBox's ultra-fast Indian and global CDN nodes with full byte-range HTTP 206 seeking in Nuvio (MPV player).
- **Strict Multi-Key Privacy Guarantee:** All API credentials (**TorBox, OMDb, Fanart.tv, TheTVDB, TMDB**) are strictly saved in your local gitignored `data/config.json`. They are **never** shared, never uploaded to third parties, never tracked, and never committed to GitHub.
- **Short-Term Scrape Cache (12m TTL):** In-memory LRU ring buffer that caches scraped streams for 12 minutes. Repeated playback, switching streams, or backing out in Nuvio is instantaneous (0ms).
- **Fast Dead-Link Filter:** Rapid 1200ms parallel HEAD probe on direct stream links to purge 404/broken file hoster links before they hit Nuvio.
- **Live Ratings & Tomatometer (OMDb API):** Live IMDb ratings (`⭐ 8.8 IMDb`), Rotten Tomatoes tomatometer (`🍅 86% RT`), and Metacritic scores (`Ⓜ️ 74 Metascore`) stamped directly onto stream cards and `/meta` detail responses.
- **Fanart.tv ClearLogos & 4K Artwork:** Transparent ClearLogo PNGs (`hdmovielogo`/`clearlogo`) and crystal-clear 4K backdrops for Nuvio's hero title banner, with automatic fallback to Metahub CDN.
- **TheTVDB Episode Mappings:** Episode mapping for anime, cartoons, and Indian serials. Resolves absolute episode numbers (e.g. `Episode 1089` instead of `S21E72`) and episode titles so scrapers never miss anime releases.
- **Stream Filtering Profiles:**
  - **Clean Drawer Mode:** Automatically strips low-grade CAM, TS, PreDVD, and Telesync releases when high-quality WEB-DL or BluRay copies exist.
  - **Max Resolution Cap:** Configurable resolution limits (`4K`, `1080p Max`, `720p Max`) for bandwidth-constrained or TV devices.
  - **Audio Language Prioritization:** Select your preferred audio language (`Hindi`, `English`, `Tamil`, `Telugu`, `Malayalam`, `Kannada`, `Bengali`, `Punjabi`, `Dual Audio`) to boost matching releases to the very top.
- **Smart Stream Deduplication:** Merges identical CDN streams from multiple providers into a single card with combined tags (e.g. `HubCloud [Direct] (MoviesDrive + Vega)`).
- **Inbuilt Native Badges & Indian Regional OTT Logos:** Native bracketed headers (`[4K] [Remux] [HDR] [Hindi]`) rendered directly as colored badge pills in Nuvio, with logos for **JioHotstar, SonyLIV, Zee5, JioCinema, SunNXT, Aha, Hoichoi, ManoramaMAX, Chaupal, Planet Marathi, MX Player, Lionsgate, Shemaroo, and Voot**.
- **5 Rich Media Catalogs with 16:9 Landscape Posters:**
  - 🎬 **YouTube Indian Cinema:** Bollywood classics, South Indian Hindi dubbed movies, comedy, and web series.
  - 🌍 **YouTube International:** Curated action, sci-fi, thriller, documentaries, and indie films.
  - 🎥 **Vimeo Staff Picks & Shorts:** Award-winning short films, Staff Picks, animations, and documentaries in native master HLS.
  - 🏛️ **Internet Archive Classics:** Golden Era Hollywood, film noir, silent cinema, classic horror, and vintage Indian cinema.
  - 📺 **Dailymotion Indian & Global:** Hindi movies, dramas, Pakistani serials, and international titles.
- **Embedded Streaming Proxy (`/proxy`):** Transparently forwards protected HLS (`.m3u8`) playlists and injects required `Referer`, `Origin`, and `User-Agent` headers so that Nuvio's internal player plays restricted streams without HTTP 403 errors.
- **Interactive Web Dashboard (`/configure`):** Dark-mode web interface to test scrape titles, toggle scrapers, manage your TorBox key, configure filtering profiles, inspect live supported hosters, and check for updates.
- **Android TV & Mobile APK:** Native Flutter client for NVIDIA Shield, Fire TV, Google TV, and Android phones with full D-pad remote navigation and 24/7 background foreground service.

---

## 🔑 Optional API Keys & Built-In Public Fallbacks (Zero-Key Operation)

**Hostreamio works 100% out of the box with zero required API keys.** All external keys are strictly optional personal enhancements:

| Integration | Key Requirement | 1-Click Signup Link | Zero-Key Public Fallback | What You Get |
|---|---|---|---|---|
| **Direct Cloud Scrapers** | ❌ **No Key Needed** | *Built-in* | 56 Direct HTTP/HLS Hosters | High-speed cloud streaming from HubCloud, Vadapav, VidLink, Movy, etc. |
| **ClearLogos & 4K Artwork** | 🟢 **Optional** (`fanartApiKey`) | [Get Fanart Key ↗](https://fanart.tv/get-an-api-key/) | **Metahub CDN** (`images.metahub.space`) | Transparent PNG ClearLogos & 4K hero backgrounds without any account. |
| **Live Ratings & Tomatometer** | 🟢 **Optional** (`omdbApiKey`) | [Get Free OMDb Key ↗](https://www.omdbapi.com/apikey.aspx) | **Cinemeta Ratings** (`v3-cinemeta.strem.io`) | Pre-configured key + Cinemeta fallback for ⭐ IMDb, 🍅 RT%, and Ⓜ️ Metascore. |
| **Anime & Episode Mappings** | 🟢 **Optional** (`tvdbApiKey`) | [Get TheTVDB Key ↗](https://thetvdb.com/dashboard/account/apikeys) | **Cinemeta & TVMaze** (`api.tvmaze.com`) | Absolute episode counting (`EP 1089`) and episode title aliases. |
| **TorBox Debrid** | 🟢 **Optional** (`torboxApiKey`) | [Get TorBox Key ↗](https://torbox.app/settings) | **Direct Cloud Stream Playback** | If blank, direct cloud links play immediately with zero warnings. |
| **TMDB Metadata** | 🟢 **Optional** (`tmdbApiKey`) | [Get TMDB Key ↗](https://www.themoviedb.org/settings/api) | **TMDB Proxy & Cinemeta** | Speedracelight proxy & Cinemeta ensure queries succeed worldwide. |

### 🔒 Universal Multi-Key Privacy & Security Guarantee
> [!IMPORTANT]
> **Zero Telemetry & 100% Local Storage:**
> - **All your API credentials** (`torboxApiKey`, `omdbApiKey`, `fanartApiKey`, `tvdbApiKey`, `tmdbApiKey`) are stored **strictly and exclusively inside your local `data/config.json`**.
> - The `data/config.json` file is permanently gitignored. Keys are **never** committed to Git, **never** transmitted to telemetry or tracking servers, and **never** exposed in stream titles or public addon manifests.
> - When you test a key in the Web Dashboard, requests are sent directly from your local machine to the official upstream API (TorBox, OMDb, TMDB, TVDB) — no intermediary servers ever see your keys.

---

## 🔗 Stream & Link Tiers Explained

Hostreamio unifies direct file hosters, adaptive HLS web streams, and cloud debrid caching into a clear, prioritized stream hierarchy in Nuvio and Stremio:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                           HOSTREAMIO STREAM TIERS                           │
├───────────────────────┬─────────────────────────────────────────────────────┤
│ ⚡ TorBox [Cached]     │ • Pre-cached on TorBox global cloud CDN             │
│                       │ • Instant 0-second playback, no buffering           │
│                       │ • Full byte-range HTTP 206 seeking in MPV / Nuvio   │
├───────────────────────┼─────────────────────────────────────────────────────┤
│ 🌐 TorBox [Cachable]  │ • Link from supported hoster (HubCloud, Pixeldrain) │
│                       │ • Not cached in TorBox cloud yet                    │
│                       │ • Click to send 1-click WebDL cache request & stream│
├───────────────────────┼─────────────────────────────────────────────────────┤
│ 🌐 Direct Play        │ • Original file hoster or cloud storage link        │
│                       │ • Proxied through Hostreamio smart header engine    │
│                       │ • Plays directly without needing a debrid account   │
├───────────────────────┼─────────────────────────────────────────────────────┤
│ ⚡ Adaptive HLS Stream │ • Multi-bitrate master .m3u8 playlists              │
│                       │ • On-the-fly header injection (Referer / Origin)    │
│                       │ • Zero 403 Forbidden player playback errors         │
├───────────────────────┼─────────────────────────────────────────────────────┤
│ 🔄 Smart Deduplication│ • Merges duplicate CDN links across scrapers        │
│                       │ • Example: "HubCloud [Direct] (MoviesDrive + Vega)" │
└───────────────────────┴─────────────────────────────────────────────────────┘
```

### 1. ⚡ `TorBox [Cached]`
* **What it means:** The file hoster link has already been downloaded and cached on TorBox's high-speed cloud servers.
* **Experience:** Instant playback (0ms start delay) streaming directly from TorBox's global and Indian CDN edge nodes with full byte-range seeking (`HTTP 206`).
* **Audio & Badges:** Features complete audio, codec, and resolution badges (e.g. `[4K] [Remux] [HDR] [Hindi]`).

### 2. 🌐 `TorBox [Start Caching]` / `[Cachable]`
* **What it means:** The link is on a hoster supported by TorBox's WebDL engine (HubCloud, PixelDrain, DriveSeed, GDrive, 1fichier, Rapidgator, etc.), but nobody has cached it yet.
* **Experience:** Selecting this link immediately submits the URL to your TorBox account's WebDL downloader in 1 click and begins streaming as soon as caching completes.

### 3. 🌐 `Direct Play [Hoster / Provider]`
* **What it means:** The original hoster download URL or direct cloud stream.
* **Experience:** Completely independent of debrid. Plays directly using Hostreamio's embedded smart proxy (`/proxy`) to inject required browser headers (`Referer`, `Origin`, `User-Agent`) so that Nuvio's internal MPV player plays without CORS or 403 blocks.

### 4. ⚡ `Adaptive HLS (.m3u8)`
* **What it means:** Adaptive bitrate web streams from providers like VidLink, LookMovie, Movy, Vimeo, and Dailymotion.
* **Experience:** Smooth playback that automatically scales resolution based on your internet connection speed.

---

## 🚀 Quick Start (Windows PC)

### Method 1: Double-Click the Executable
Run `hostreamio.exe` (or `start.bat`) inside this directory:
```powershell
.\hostreamio.exe 7002
```

Console output:
```text
===============================================================
              ▶️ Hostreamio Addon for Nuvio ▶️         
===============================================================
 Status: RUNNING
 Port:   7002
 Local:  http://localhost:7002
 LAN IP: http://192.168.0.127:7002
---------------------------------------------------------------
 🔌 Nuvio Addon Manifest URLs:
    Localhost: http://localhost:7002/manifest.json
    LAN (TV):  http://192.168.0.127:7002/manifest.json
---------------------------------------------------------------
 🌐 Web Dashboard: http://localhost:7002/configure
===============================================================
```

### Method 2: PowerShell Script
```powershell
.\start.ps1
```

---

## 📱 Android TV (NVIDIA Shield, Fire TV) & Mobile APK

The `android_app` directory contains the complete cross-platform Flutter application tailored for Android TV and mobile devices:

- **D-Pad Remote Friendly:** TV remote focus borders, smooth scale animations, and intuitive D-pad navigation.
- **Background Foreground Service:** Keeps the addon server running 24/7 in the background with wake-lock support.
- **TorBox Debrid Settings Card:** Input and validate your TorBox API key directly on your TV or phone with show/hide password toggle.
- **Automatic IP Detection:** Detects local Wi-Fi IP and displays the ready-to-copy Addon Manifest URL.

### 🔨 GitHub Actions Automated Build
The included CI workflow (`.github/workflows/build-apk.yml`) compiles the release APK on every push to `main`:
1. Go to the **Actions** tab on GitHub.
2. Select **Build Android APK (TV & Mobile)** ➔ Click the latest workflow run.
3. Download the artifact `hostreamio-apk`.
4. Sideload the APK onto your Android TV or phone.

---

## 📺 Step-by-Step Installation in Nuvio & Stremio

### Scenario A: Running on PC & Streaming on Android TV / Fire TV / Phone (Same Wi-Fi)
1. **Launch Hostreamio on your PC:**
   - Run `hostreamio.exe` or `.\start.bat`.
   - Note your PC's local Wi-Fi IP address printed in the console (e.g., `http://192.168.0.127:7002`).
   *(Ensure Windows Firewall allows inbound TCP traffic on port 7002 on your local home network).*
2. **Install Addon Manifest in Nuvio:**
   - Open **Nuvio** on your Android TV, Fire TV, PC, or mobile device.
   - Navigate to: **Settings (⚙️)** ➔ **General** ➔ **Content & Discovery** ➔ **Addons** (under Sources).
   - Click the **`+`** button (or **Install from URL / Custom Addon**).
   - Type or paste your LAN URL:
     ```text
     http://<YOUR_PC_LAN_IP>:7002/manifest.json
     ```
     *(Example: `http://192.168.0.127:7002/manifest.json`)*
   - Click **Install**. Hostreamio will appear under Installed Addons with version `2.0.0`.
3. **Enable OTT & Quality Badges (Fusion Badges in Nuvio):**
   - In Nuvio, go to **Settings (⚙️)** ➔ **General** ➔ **Layout** ➔ **Streams**.
   - Under **Fusion Badge URLs** (or **Badges URL**), enter:
     ```text
     http://<YOUR_PC_LAN_IP>:7002/badges.json
     ```
   - Click **Add / Save**. All stream cards will now render visual quality pills (`[4K]`, `[1080p]`, `[Remux]`) and regional OTT logos (JioHotstar, SonyLIV, Zee5, JioCinema, SunNXT, Netflix, Prime).

---

### Scenario B: Running Standalone on Android TV / Fire TV / Phone (via `hostreamio.apk`)
1. **Install the APK:**
   - Sideload [`hostreamio.apk`](https://github.com/sakinator/hostreamio/releases/latest/download/hostreamio.apk) onto your Android TV or phone (via *Send Files to TV*, *Downloader*, or *ADB*).
   - Open **Hostreamio**. The engine starts automatically in the background on port `7002` with wake-lock support.
   - *(Optional)* Enter your TorBox API key and click **Save & Validate**.
2. **Install into Nuvio (on the Same Device):**
   - Switch to **Nuvio** on your TV or phone.
   - Go to: **Settings (⚙️)** ➔ **General** ➔ **Content & Discovery** ➔ **Addons** ➔ Click **`+`**.
   - Enter the localhost address:
     ```text
     http://127.0.0.1:7002/manifest.json
     ```
     *(Or click the `1-Click Install (Stremio / Nuvio)` button directly inside the Hostreamio Android app).*
   - Click **Install**.
3. **Enable Badges in Nuvio:**
   - In Nuvio: **Settings (⚙️)** ➔ **General** ➔ **Layout** ➔ **Streams** ➔ **Fusion Badge URLs**.
   - Paste: `http://127.0.0.1:7002/badges.json` and save.

---

### Scenario C: Running Nuvio / Stremio on the Same Windows PC
1. **Launch Hostreamio:** Double-click `hostreamio.exe`.
2. **1-Click Install:**
   - Open your browser to `http://localhost:7002/configure`.
   - Click **`🚀 1-Click Install to Stremio / Nuvio`** (or open `stremio://127.0.0.1:7002/manifest.json`).
   - Or in Nuvio Desktop: **Settings (⚙️)** ➔ **General** ➔ **Content & Discovery** ➔ **Addons** ➔ **`+`** ➔ `http://localhost:7002/manifest.json`.
3. **Badges:** Set Fusion Badges URL in Nuvio (**Settings ➔ General ➔ Layout ➔ Streams**) to `http://localhost:7002/badges.json`.

---

### 🛠️ Troubleshooting & Verification
* **Test Manifest in Browser:** Open `http://localhost:7002/manifest.json` (or `http://<LAN_IP>:7002/manifest.json`). It should return valid JSON with `"id": "org.sakinator.hostreamio"`.
* **Windows Firewall Rule (if TV cannot connect):** Run in PowerShell as Administrator:
  ```powershell
  New-NetFirewallRule -DisplayName "Hostreamio Addon Server" -Direction Inbound -LocalPort 7002 -Protocol TCP -Action Allow
  ```
* **Recommended Player in Nuvio:** For the best buffering and seeking experience with TorBox and HLS streams, go to Nuvio **Settings** ➔ **Player** and ensure **ExoPlayer** (default) or **MPV** is selected.

---

## 🔑 TorBox & Metadata Configuration

All external API integrations are 100% optional:
1. Open the Web Dashboard at `http://localhost:7002/configure` (or the Android APK settings screen).
2. Enter any optional keys (TorBox, OMDb, Fanart, TheTVDB, TMDB).
3. Click **Save & Validate**.
4. The dashboard will verify your credentials in real time against upstream APIs.

> [!IMPORTANT]
> **Strict Privacy Guarantee:** None of your API keys are ever shared, committed to Git, or uploaded to third parties. They are stored exclusively in your local `data/config.json`.

---

## 📂 Project Structure

```text
hostreamio/
├── hostreamio.exe            # Compiled standalone Windows binary
├── hostreamio_icon.svg       # Flat vector app icon
├── start.bat                 # Windows one-click starter
├── start.ps1                 # PowerShell launcher
├── start.sh                  # Linux / Android (Termux) launcher
├── bin/
│   └── server.dart           # Standalone HTTP Addon Server
├── lib/
│   ├── badge_service.dart    # NardBadges stream badge matching engine
│   ├── catalog_service.dart  # YouTube, Vimeo, Archive.org & Dailymotion catalogs
│   ├── config.dart           # Port, timeouts, provider toggles & settings
│   ├── metadata_service.dart # IMDB/TMDB/Cinemeta metadata resolver
│   ├── proxy.dart            # HLS .m3u8 proxy & header injection engine
│   ├── scraper_engine.dart   # Parallel scraper dispatcher & sanitizer
│   ├── scraper_registry.dart # Auto-generated registry of 56 scrapers
│   ├── torbox_service.dart   # TorBox WebDL, cache verification & CDN streaming
│   └── web_ui.dart           # Dark-mode Web Configuration Dashboard
├── android_app/              # Android TV & Mobile Flutter application
│   ├── lib/main.dart         # TV/Mobile UI with TorBox settings card
│   └── lib/server_service.dart # Background server service
└── .github/workflows/
    └── build-apk.yml         # Automated GitHub Actions APK builder
```

---

## 🛠️ List of Active Scrapers (56 Total)

The unified scraper engine integrates 56 non-torrent cloud providers across Indian Regional, Anime/Asian, and Global networks:

### 🇮🇳 Indian OTT & Regional Scrapers (8 Providers)
| Scraper Provider | ID | Stream Quality | Technology / Hosters | Focus / Description |
| :--- | :--- | :--- | :--- | :--- |
| **Vegamovies** | `vegamovies` | 💎 4K UHD / 1080p | ☁️ Cloud Extractors (HubCloud, V-Cloud) | Bollywood, South Hindi Dubs, HEVC multi-audio releases |
| **Bollyflix** | `bollyflix` | 💎 4K UHD / 1080p | ☁️ Cloud Extractors (DriveSeed, HubCloud) | High-bitrate Bollywood, Hollywood dubbed, multi-audio |
| **HDHub4u** | `hdhub4u` | 💎 4K UHD / 1080p | ☁️ Cloud Extractors (HubCloud, DriveBot) | Latest Hindi cinema, South dubs, direct mirrors |
| **4KHDHub** | `fourkhdhub` | 💎 Pure 4K UHD / Remux | ☁️ Cloud Extractors (HubCloud, Pixeldrain) | Dedicated 2160p 4K UHD Remux, HDR10+ regional copies |
| **HindMoviez** | `hindmoviez` | 📺 1080p FHD | ⚡ Fast HLS / Direct CDN | Bollywood, South Indian dubbed & regional cinema |
| **PlayDesi** | `playdesi` | 📺 1080p FHD | 🎬 Direct MP4 / Cloud Player | Indian TV serials, daily soaps, reality shows & Desi web series |
| **YoMovies** | `yomovies` | 📺 1080p FHD | ⚡ Fast HLS Streams | Hindi, Punjabi, Tamil, Telugu, and Bengali cinema |
| **Vadapav** | `vadapav` | 📺 1080p FHD | 🌐 Direct HTTP CDN | Zero-lag Indian high-speed direct CDN file storage |

### ⛩️ Anime & Asian Drama Scrapers (6 Providers)
| Scraper Provider | ID | Stream Quality | Technology / Hosters | Focus / Description |
| :--- | :--- | :--- | :--- | :--- |
| **AnimePahe** | `animepahe` | 📺 1080p / 720p | ⚡ Fast HLS / Kwk CDN | Sub/Dub anime with multi-bitrate streams & soft subtitles |
| **Gogoanime** | `gogoanime` | 📺 1080p FHD | ⚡ Fast HLS Streams | Simulcast seasonal anime, massive catalog & dual audio |
| **HiAnime** | `hianime` | 📺 1080p FHD | ⚡ Fast HLS / Megacloud | HiAnime CDN, multi-quality streams & soft subtitles |
| **KissKH** | `kisskh` | 📺 1080p FHD | ⚡ Fast HLS Streams | K-Drama, C-Drama & Asian series with multi-language subs |
| **KissAsian** | `kissasian` | 📺 720p / 1080p | ⚡ Fast HLS Streams | Korean & Asian drama catalog with high-speed playback |
| **DramaCool** | `dramacool` | 📺 720p / 1080p | 🎬 Direct MP4 / HLS | Asian dramas, variety shows & East Asian television |

### 🌐 Global & International Scrapers (42 Providers)
| Scraper Provider | ID | Stream Quality | Technology / Hosters | Focus / Description |
| :--- | :--- | :--- | :--- | :--- |
| **VidSrc** | `vidsrc` | 📺 1080p FHD | ⚡ Fast HLS / Multi-Server | Flagship global streaming cluster with adaptive HLS |
| **LookMovie** | `lookmovie` | 📺 1080p FHD | ⚡ Fast HLS Streams | Premium global cinema & television series with soft subs |
| **VidLink** | `vidlink` | 📺 1080p FHD | ⚡ Fast HLS / Cloud CDN | Ultra-fast global CDN streaming network with multi-language subs |
| **MultiEmbed** | `multiembed` | 📺 1080p FHD | ⚡ Fast HLS Aggregator | Aggregated multi-source embed fallback player and resolver |
| **RiveStream** | `rivestream` | 💎 4K / 1080p FHD | ⚡ Fast HLS / Multi-CDN | Multi-server high-bitrate streaming network |
| **Hexa** | `hexa` | 📺 1080p FHD | ⚡ Fast HLS Streams | Multi-server mirror cluster with adaptive bitrate streaming |
| **MegaSource** | `megasource` | 📺 1080p FHD | ☁️ Cloud Extractors | Multi-cloud direct stream aggregator and link resolver |
| **Movy** | `movy` | 📺 1080p FHD | ⚡ Fast HLS / MP4 | Encrypted HLS & MP4 direct streams for movies and series |
| **Videasy** | `videasy` | 📺 1080p FHD | ⚡ Fast HLS Streams | One-click fast buffer global streams across multi-CDN mirrors |
| **Cinejoy** | `cinejoy` | 📺 1080p FHD | ⚡ Fast HLS Streams | International entertainment streams & reliable mirror sources |
| **FlyStream** | `flystream` | 📺 1080p FHD | ⚡ Fast HLS Streams | Low-latency adaptive bitrate streaming network |
| **XDownloader** | `xdownloader` | 📺 1080p FHD | 🌐 Direct HTTP Extractor | Direct file hoster link generator & stream extractor |
| **Vuflix** | `vuflix` | 📺 1080p FHD | ⚡ Fast HLS Streams | Fast cloud HLS stream resolver for international catalog |
| **MovieNight** | `movienight` | 📺 1080p FHD | 🎬 Direct MP4 Streams | Nightly movie archive & high-speed direct streams |
| **FSOnline** | `fsonline` | 📺 1080p FHD | ⚡ Fast HLS Streams | Worldwide movie & webseries provider with multi-quality mirrors |
| **CineSrc** | `cinesrc` | 📺 1080p FHD | 🎬 Direct MP4 / HLS | Direct master HLS & web embeds for movies and series |
| **CineSu** | `cinesu` | 📺 1080p FHD | ⚡ Fast HLS Streams | International film releases and episodic television streams |
| **VidFast** | `vidfast` | 📺 1080p FHD | ⚡ Fast HLS Streams | Optimized low-latency streaming endpoints |
| **VidGod** | `vidgod` | 📺 1080p FHD | ⚡ Fast HLS Streams | Resilient global streaming fallback with fast seek times |
| **VidRock** | `vidrock` | 📺 1080p FHD | ⚡ Fast HLS Streams | Rock-solid CDN streams with multiple quality options |
| **VidUp** | `vidup` | 📺 1080p FHD | ⚡ Fast HLS Streams | Direct video upload player scraper & mirror resolver |
| **VidVault** | `vidvault` | 📺 1080p FHD | 🎬 Direct MP4 Streams | Archived movies & television vault with high retention |
| **VidZee** | `vidzee` | 📺 1080p FHD | ⚡ Fast HLS Streams | Lightning-fast multi-server global player |
| **VixSrc** | `vixsrc` | 📺 1080p FHD | ⚡ Fast HLS Streams | High-performance Vix stream mirror with fast buffering |
| **Purstream** | `purstream` | 📺 1080p FHD | ⚡ Fast HLS Streams | Clean uninterrupted international streams |
| **Nova** | `nova` | 📺 1080p FHD | ⚡ Fast HLS Streams | Global release cluster with multiple server mirrors |
| **FlaxMovies** | `flaxmovies` | 📺 1080p FHD | ⚡ Fast HLS Streams | Global movie releases & web streaming endpoints |
| **Bcine** | `bcine` | 📺 1080p FHD | 🎬 Direct MP4 Streams | Direct international cinema catalog with MP4 streams |
| **Frame** | `frame` | 📺 1080p FHD | ⚡ Fast HLS Streams | High-efficiency adaptive video streams |
| **FshareTV** | `fsharetv` | 📺 1080p FHD | ⚡ Fast HLS Streams | Global TV network episodes & television serials |
| **FSonic** | `fsonic` | 📺 1080p FHD | 🎬 Direct MP4 Streams | Ultra-fast international CDN streams |
| **LMScript** | `lmscript` | 📺 1080p FHD | ⚡ Fast HLS Streams | Script-based lookmovie alternative mirror |
| **Mapple** | `mapple` | 📺 1080p FHD | ⚡ Fast HLS Streams | Fresh global box office & TV episodes |
| **MeowTV** | `meowtv` | 📺 1080p FHD | ⚡ Fast HLS Streams | Curated television shows & movies |
| **PeeStream** | `peestream` | 📺 1080p FHD | 🎬 Direct MP4 Streams | Direct streaming hoster scraper |
| **VidApi** | `vidapi` | 📺 1080p FHD | ⚡ Fast HLS Streams | API-driven media scraper endpoint |
| **VidCore** | `vidcore` | 📺 1080p FHD | ⚡ Fast HLS Streams | Core video streaming cluster for global releases |
| **XPass** | `xpass` | 📺 1080p FHD | ⚡ Fast HLS Streams | Bypass scraper for premium media mirrors |
| **ZxcStream** | `zxcstream` | 📺 1080p FHD | ⚡ Fast HLS Streams | Low-latency global stream mirrors |
| **A111477** | `a111477` | 📺 1080p FHD | 🎬 Direct MP4 Streams | Alternative direct stream hoster |
| **DownloadEverything** | `downloadeverything` | 📺 1080p FHD | 🌐 Direct HTTP Extractor | Direct media download & stream extractor |
| **Dulo** | `dulo` | 📺 1080p FHD | ⚡ Fast HLS Streams | High-speed direct stream network |

---

## 🔄 Upstream & Cloudstream Extension Sync

### 1. PlayTorrioV3 Native Scrapers
`Hostreamio` is integrated directly with upstream [ayman708-UX/PlayTorrioV3](https://github.com/ayman708-UX/PlayTorrioV3).
- To sync latest providers and fixes:
  - Click **🔄 Check Upstream Updates** in the Web Dashboard (`/configure`), or trigger `POST /api/pipeline/update`.
  - The server clones upstream, scans `lib/upstream/services/scraper/sites/`, regenerates `scraper_registry.dart`, and hot-reloads all active scrapers without restarting.

### 2. Cloudstream Scrapers & Plugins
- Native Dart ports of top Cloudstream extractors (*HubCloud, Vega, DriveSeed, Pixeldrain, Mega, 1fichier*) are maintained directly inside `lib/upstream/services/cloudstream/`.
- In-memory plugin repos can be browsed and refreshed via the embedded `CloudStreamMarketplaceService`.

---

## 🏆 Credits & Acknowledgements

`Hostreamio` builds upon incredible open-source innovations across the streaming community:

- **[ayman708-UX / PlayTorrioV3](https://github.com/ayman708-UX/PlayTorrioV3)**: Core Dart scraper models, site extractors, and multi-source scraping architecture.
- **[Cloudstream 3 Community](https://github.com/recloudstream/cloudstream)** & Extension Authors (*Hexated, Stormunblessed, Hindi Providers*): Pioneering hoster extraction patterns and cloud link bypass techniques.
- **[Nuvio Team](https://nuvio.app)**: Next-gen TV and desktop streaming player with beautiful native badge pill rendering.
- **[TorBox](https://torbox.app)**: Exceptional debrid infrastructure, lightning-fast WebDL cloud caching, and high-bandwidth global CDN delivery.
- **[CNCVerse-Bridge](https://github.com/CNCVerse/Bridge)**: Design inspiration for DNS-over-HTTPS fallback, segment caching, and on-the-fly virtual HLS playlist converter.
- **[Torrentio](https://torrentio.strem.fun)**, **[MediaFusion](https://github.com/mhdzumair/MediaFusion)**, **[Comet](https://github.com/g0ldy/comet)**, **[AIOStreams](https://github.com/Viren070/AIOStreams)** & **[EasyTorbox](https://github.com/sagetendo/EasyTorbox)**: For shaping modern community debrid streaming workflows and Stremio/Nuvio addon conventions.

---

## ✨ Vibe Coded Philosophy & Manifesto

> *"Code at the speed of thought. Guided by vibes, verified by automated test suites."*

This entire codebase — spanning 56 stream scrapers, dynamic HLS proxying, TorBox cloud debrid caching, cross-platform Android TV / mobile interfaces, and live update pipelines — is **100% Vibe Coded**.

### What does "Vibe Coded" mean here?
- **AI-Native Architecture**: Conceived, architected, debugged, and refined through symbiotic interaction between human vision and autonomous AI coding agents (DeepMind Antigravity / Gemini / Claude).
- **Rapid Self-Healing**: Automated QA loops, subagent audits, real-time JavaScript validation (`node -c`), and endpoint stress-testing catch edge cases before they ship.
- **Vibe Velocity**: Shipped iteratively at extreme velocity without bureaucratic technical debt — continuously evolving as streaming protocols, hosters, and community conventions update.
- **As-Is Provision**: As with all vibe-coded software, it is offered purely as open-source research and experimental tooling. Enjoy the vibes responsibly!

---

## ⚖️ GitHub Disclaimer & Legal DMCA Policy

> [!IMPORTANT]
> **GitHub Repository Disclaimer:**
> 1. **No Content Hosted:** This GitHub repository contains **only open-source Dart and Flutter application code**. It does NOT contain, host, store, mirror, link to, or distribute any media files, copyrighted videos, torrents, or pirated content of any kind.
> 2. **Independent Open-Source Utility:** This project is an independent, non-commercial open-source utility developed for educational, interoperability, and personal research purposes.
> 3. **No Affiliation:** This project is NOT affiliated with, sponsored by, endorsed by, or in any way officially connected with GitHub, Stremio, Nuvio, TorBox, Google, YouTube, Internet Archive, Dailymotion, or any of the third-party websites or services indexed by the scraping engines. All product names, trademarks, and registered trademarks belong to their respective owners.
> 4. **Pure Web Indexer:** The software acts solely as an automated search indexer querying publicly accessible search endpoints on the open internet, identical to a standard web browser or search engine query.
> 5. **Zero Media Ownership**: The authors, developers, and maintainers of this project do not own, control, maintain, or manage any of the scraped websites, hosters, content delivery networks (CDNs), or debrid providers indexed by this tool.
> 6. **User Responsibility:** Users are solely responsible for ensuring that their use of this software complies with all applicable local, national, and international laws, regulations, and third-party terms of service.
> 7. **DMCA Takedown Compliance:** Because no media or infringing content is stored in this repository or on any servers operated by the authors, DMCA notices regarding scraped content should be directed to the third-party web host or file storage provider actually hosting the files. For concerns regarding repository source code, please open an Issue or contact the repository owner.

