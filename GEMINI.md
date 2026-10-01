# Hostreamio Development & Architecture Rules

This document defines the mandatory development, UI/UX, release, and synchronization rules for the Hostreamio project. These rules apply to all sessions and modifications.

---

## 1. Strict Local and GitHub Two-Way Sync
- **Local → GitHub:** Whenever files are created, modified, or refactored locally, they must be committed and pushed to `origin main`.
- **GitHub → Local:** When GitHub Actions compiles release artifacts (`hostreamio.apk`, `hostreamio.exe`, `hostreamio-windows-x64.zip`), immediately synchronize the local repository copies in `D:\hostreamio` so local files match the latest artifacts from GitHub Release `v1.0.0`.
- **Post-Update Invariant:** After every update cycle, verify that:
  1. `git status` is clean with no uncommitted or untracked changes.
  2. Local `hostreamio.apk`, `hostreamio.exe`, and `hostreamio-windows-x64.zip` match the latest build.
  3. GitHub Release `v1.0.0` has all 3 updated assets attached.

---

## 2. Fixed Release 1 Policy ("Readiness Rule")
- **Fixed Version:** The release version must ALWAYS remain **`v1.0.0`** (`Release v1.0.0`) until the user explicitly requests otherwise.
- **No Premature Version Bumps:** Do not create experimental tags or releases like `v1.0.1`, `v1.5.0`, `v2.0.0`, etc.
- **Single Release Cleanliness:** All pipeline builds and asset updates overwrite or update assets directly under `Release v1.0.0`. Never leave obsolete or orphaned release tags on GitHub.

---

## 3. Desktop & Android Code Parity (`tool/sync_android.ps1`)
- The project maintains two runtimes:
  - **Desktop / Server:** `bin/server.dart` and `lib/`
  - **Android TV & Mobile App:** `android_app/` (Flutter)
- **Mandatory Sync:** Whenever editing shared components (`badge_service.dart`, `catalog_service.dart`, `config.dart`, `doh_resolver.dart`, `metadata_service.dart`, `proxy.dart`, `scraper_engine.dart`, `scraper_registry.dart`, `torbox_service.dart`, `tvdb_service.dart`, `web_ui.dart`), **always run `tool/sync_android.ps1` immediately**. Both platforms must have 100% feature and logic parity.

---

## 4. Stream Playability & Anti-HTML Guard
- **Strict Media Stream Definition:** `Direct Play` streams must strictly be playable video streams (`.m3u8` HLS, `.mpd` DASH, or direct `.mp4`/`.mkv` containers).
- **Anti-HTML Rule:** Scrapers must never emit HTML landing pages, redirect chains, or human-interactive web pages under `Direct Play`.
- **TorBox Debrid Separation:**
  - `⚡ TorBox [Cached]`: Instant playback from high-speed TorBox CDN.
  - `☁️⬆️ TorBox [Start Caching]`: Queues hoster links in TorBox cloud without blocking direct play.
  - Non-direct hoster links can only be presented if they match TorBox debrid supported hosters (`HubCloud`, `PixelDrain`, `1Fichier`, etc.).

---

## 5. Stream Badge & Presentation Standards
- **Top Badge (Name):** Keep focused strictly on the stream source or caching tier:
  - `🌐 Direct Play [$SourceName]`
  - `⚡ TorBox [Cached]`
  - `☁️⬆️ TorBox [Start Caching]`
- **Host Line (📦 Host:):**
  - Legitimate filehosters and known CDNs display their recognized brand name (`HubCloud`, `Fast-DL`, `PixelDrain`, etc.).
  - Disposable, rotating, or obfuscated domains must be displayed cleanly as `📦 Host: Stealth Edge ($cleanDomain)`.
- **Deduplication Mirror Line:**
  - Merged mirror streams must use `🔗 Also mirrored on: $SourceName` (never repeat the `🌐 Source:` label).

---

## 6. Android TV & Mobile Responsive UI Invariant
- **Mobile First Defensiveness:**
  - Never place long unconstrained text with action buttons in a bare `Row`.
  - Always wrap title texts in `Expanded` or `Flexible` with `TextOverflow.ellipsis`.
  - Use `Wrap(spacing: ..., runSpacing: ...)` for action button rows (e.g. Play, Copy, Cache) to ensure they never trigger yellow-and-black overflow bars on 360px–400px mobile screens.
- **Android TV D-Pad Remote Navigation:**
  - Every interactive button, tab, and catalogue poster card must be wrapped in `_TvFocusableButton` or focus nodes with visible scale/glow focus highlights.
  - Support `LogicalKeyboardKey.select`, `enter`, `space`, and gamepad A for all actions.

---

## 7. Catalogue Browser Integrity (All 7 Categories)
- The Streaming Theater tab in both Flutter (`android_app`) and Web UI (`web_ui.dart`) must provide the full, active **Browse Catalogs** browser with all 7 categories:
  1. 🔥 **Trending Movies** (Cinemeta)
  2. 📺 **Trending Series** (Cinemeta)
  3. 🎬 **YouTube Indian Cinema** (`yt_indian` with genre chips)
  4. 🌍 **YouTube International** (`yt_international` with genre chips)
  5. 🎥 **Vimeo Staff Picks** (`vimeo_picks`)
  6. 🏛️ **Internet Archive Movies** (`archive_movies`)
  7. 📺 **Dailymotion** (`dm_movies`)
- Tapping any catalogue item must automatically populate the search box, load series seasons/episodes (if series), and trigger live scraping.

---

## 8. Windows Process & Lock Safety
- On Windows, a running `hostreamio.exe` process will lock the binary and prevent recompilation or archive packaging (`Access is denied` / `Unable to commit changes`).
- Before compiling `bin/server.dart` or updating `hostreamio-windows-x64.zip`, always stop the background process (`Stop-Process -Name hostreamio -Force`), compile, package, and restart the daemon.

---

## 9. Zero Localhost DNS Interception (DoH Rule)
- The DNS-over-HTTPS fallback engine (`DohResolver`) must strictly bypass `localhost`, `127.0.0.1`, and private RFC1918 subnets (`192.168.*`, `10.*`, `172.16-31.*`).
- Local proxy requests and LAN manifest endpoints must never be routed through external DNS resolvers.

---

## 10. Free Global Live IPTV Integration (`iptv-org`)
- **Dual-Surface Availability:** IPTV channels must be available both in the Android app (dedicated `Live IPTV` tab) and via the Stremio addon catalog (`iptv_global` catalog).
- **Filtering & Search Invariant:** The IPTV view must provide instantaneous in-memory multi-attribute filtering by:
  1. Category (`News`, `Sports`, `Movies`, `Animation`, `Music`, `Entertainment`, `Documentary`, `General`).
  2. Country / Region (`All`, `Global`, `US`, `UK`, `IN`, `CA`, `FR`, `DE`, `ES`, `IT`, `AU`, `JP`, `BR`).
  3. Live channel search field.
- **Local Caching:** Channels must be cached locally in `data/iptv_cache.json` with a 12-hour background refresh cycle and fallback channels for zero-offline resilience.

---

## 11. Dedicated Anime Engine Policy
- **No Torrent Bloat:** Anime scraping must strictly use direct HTTP/HLS sources: **HiAnime / Zoro** (#1 best) with **Gogoanime** (#2 fallback).
- **Clean Labeling:** Anime streams must feature distinct `[SUB]` and `[DUB]` indicators with episode number mapping.

---

## 12. Direct Subtitles Engine (OpenSubtitles v3)
- **Zero Rate Limits:** Hostreamio integrates the official OpenSubtitles v3 REST API (`https://opensubtitles-v3.strem.io/subtitles/{type}/{id}.json`) delivering 90+ languages in <2 seconds with direct `.srt` download links.
- **User Control:** Must feature a user-facing toggle (`enableOpenSubtitles`) in Settings / Config (defaults to `true`) allowing users to disable external subtitles on demand.

---

## 13. Expanded Supported DDL Hosters
- **Supported Providers:** Direct streaming and TorBox cloud debrid caching are supported across: `HubCloud`, `PixelDrain`, `GoFile`, `Buzzheavier`, `Qiwi`, `MultiUp`, `Krakenfiles`, `Mixdrop`, `Voe`, `Filemoon`, `Doodstream`, `Streamtape`, and `1Fichier`.

---

## 14. Nuvio-Style Dedicated Media Detail View
- **Dedicated Viewport:** Selecting any movie, TV series, or suggestion must open a dedicated Hero Detail screen (`_isInDetailView = true`) instead of stacking episodes and streams on the catalog browse page.
- **Hero Metadata:** Detail view must render Hero backdrop / poster, Title, Year, IMDb rating ⭐, Genres, and Overview.
- **Series Seasons & Episodes Browser:** For series, provide an interactive Season selector tab bar and Episode cards with 1-tap stream scraping.
- **Instant Back Navigation:** Provide a prominent "← Back to Catalog" button that returns to the previous catalog scroll position without re-loading.

---

## 15. External Player Integration ("Play With...")
- **Dual Playback Modes:** Every stream card and IPTV channel card must offer both:
  1. **▶ Play:** Launches default internal player or primary player.
  2. **🚀 Play With...:** Displays a native Android app chooser dialog with 1-tap launching for **VLC for Android**, **Just Player**, **MPV**, **MX Player**, and system App Chooser.

---

## 16. In-App Video Player (`media_kit` / `libmpv`) & Super Audio Gain Invariant
- **Cross-Platform In-App Engine:** Both Android and Windows native apps feature an embedded, high-performance in-app video player (`PlayerScreen`) powered by `media_kit` and `libmpv`.
- **Stream Capabilities:**
  - VOD playback (seekable, buffered, position tracking) for high-bitrate 4K Remuxes with hardware decoding and 32MB readahead buffer.
  - Live Stream IPTV detection (`.m3u8` / `.ts`): automatically disables VOD seek controls, displays live latency badge, and enables automatic reconnection on network drops.
  - Strongly-typed `AudioTrack` and `SubtitleTrack` track selection (`SubtitleTrack.no()`).
- **Classic VLC Audio Gain (0% to 200%):**
  - Configured with `volume-max: 200` on the underlying `NativePlayer`.
  - Floating volume HUD pill at the top of the viewport when adjusting volume.
  - Dialogue normalization toggle (`lavfi=[dynaudnorm=f=75:g=15:p=0.95:m=10]`) to bring quiet dialogue forward while taming loud explosions.
  - Quick-jump preset pills: `100%`, `125%`, `150%`, `200%` Super Gain.

---

## 17. Collapsible Sidebar & Screen Real Estate Invariant
- **Default State:** In both native Flutter apps (Windows & Android) and the Web UI (`web_ui.dart`), the navigation sidebar menu must collapse to **icon-only (68px width)** by default.
- **Toggle Control:** Provide a prominent animated expand/collapse toggle button allowing users to expand the full sidebar labels on demand without losing screen space for posters and stream cards.

---

## 18. Windows Desktop Native Runner & Brand Icon Invariant
- **Permanent Git Tracking:** The Windows native runner (`android_app/windows`) is permanently tracked in Git. Never rely on dynamic `flutter create` in CI builds.
- **Embedded Brand Icon:** The official Hostreamio icon (`hostreamio.ico`) must be embedded directly at `android_app/windows/runner/resources/app_icon.ico` so MSVC natively builds `hostreamio.exe` with the brand icon.
- **Dual Binaries in Release:** Windows releases must bundle both:
  - `hostreamio.exe`: Native Flutter desktop GUI application.
  - `hostreamio-cli.exe`: Standalone headless HTTP server daemon.
- **Icon Stamping:** `tool/rcedit.exe` is executed in the packaging pipeline to stamp the brand icon onto all `.exe` binaries.

---

## 19. CI/CD Build & Toolchain Invariants
- **Flutter SDK:** Must use `channel: 'stable'` (do NOT pin to versions older than `3.27.0`, as older Flutter SDKs lack the `android.flutter` extension, causing modern Flutter plugins to fail project evaluation).
- **Gradle & AGP Alignment:**
  - Gradle Wrapper: `gradle-8.14-all.zip`.
  - Android Gradle Plugin (AGP): `8.11.1`.
  - Kotlin Android: `2.2.20`.
- **Android SDK & NDK:**
  - `compileSdk` must be set to `36` (Android API 36) in `android_app/android/app/build.gradle` to satisfy modern AndroidX AAR metadata requirements (`androidx.browser:1.9.0`, `androidx.core:1.17.0`).
  - `ndkVersion` must be `"27.0.12077973"`.
- **DSL Compatibility Flags:** `android_app/android/gradle.properties` must always include:
  ```properties
  android.builtInKotlin=false
  android.newDsl=false
  ```
- **Post-Build Local Sync:** Immediately after every successful GitHub Actions release run, download and overwrite local copies of `hostreamio.apk`, `hostreamio.exe`, and `hostreamio-windows-x64.zip` in `D:\hostreamio` so local files match release artifacts.


