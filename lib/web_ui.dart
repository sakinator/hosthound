import 'config.dart';
import 'scraper_engine.dart';

class WebUI {
  static String render({
    required String localIp,
    required int port,
    String? updateMessage,
  }) {
    final providers = ScraperEngine.instance.getProviderList();
    final enabledCount = providers.where((p) => p['enabled'] == true).length;
    final manifestLocal = 'http://localhost:$port/manifest.json';
    final manifestLan = 'http://$localIp:$port/manifest.json';
    final cfg = AddonConfig.instance;
    final torboxApiKey = cfg.torboxApiKey;
    final omdbApiKey = cfg.omdbApiKey;
    final fanartApiKey = cfg.fanartApiKey;
    final tvdbApiKey = cfg.tvdbApiKey;
    final tmdbApiKey = cfg.tmdbApiKey;
    final dtddApiKey = cfg.dtddApiKey;
    final excludeCamsChecked = cfg.excludeCams ? 'checked' : '';
    final dedupeChecked = cfg.enableDeduplication ? 'checked' : '';
    final deadLinkChecked = cfg.enableDeadLinkFilter ? 'checked' : '';
    final maxRes = cfg.maxResolution;
    final prefLang = cfg.preferredLanguage;
    final enableTorboxCachedTorrentsChecked = cfg.enableTorboxCachedTorrents ? 'checked' : '';
    final enableCacheBypassChecked = cfg.enableCacheBypass ? 'checked' : '';
    final proxyResolverUrl = cfg.proxyResolverUrl;
    final enableOpenSubtitlesChecked = cfg.enableOpenSubtitles ? 'checked' : '';

    final providerCheckboxes = providers.map((p) {
      final id = p['id'].toString();
      final name = p['name'].toString();
      final checked = p['enabled'] == true ? 'checked' : '';
      final meta = getProviderMeta(id);
      return '''
        <label class="provider-card" data-name="${name.toLowerCase()}" data-id="${id.toLowerCase()}" data-scope="${meta['scope']!.toLowerCase()}" data-quality="${meta['quality']!.toLowerCase()}">
          <input type="checkbox" name="provider" value="$id" $checked onchange="toggleProvider('$id', this.checked)">
          <div class="card-inner">
            <div style="display:flex; justify-content:space-between; align-items:flex-start; gap:8px;">
              <span class="provider-name">$name</span>
              <span class="badge">$id</span>
            </div>
            <div class="provider-tags">
              <span class="tag-pill tag-scope">${meta['scope']}</span>
              <span class="tag-pill tag-quality">${meta['quality']}</span>
              <span class="tag-pill tag-tech">${meta['tech']}</span>
            </div>
            <div class="provider-desc">${meta['desc']}</div>
          </div>
        </label>
      ''';
    }).join('\n');

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Hostreamio Addon</title>
  <link rel="icon" type="image/png" href="/logo.png">
  <!-- HLS.js for embedded web stream player preview -->
  <script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.8/dist/hls.min.js"></script>
  <style>
    :root {
      --bg: #08090c;
      --card-bg: #11141c;
      --card-hover: #151923;
      --border: #1f2533;
      --accent: #ff0c82;
      --brand-blue: #195feb;
      --brand-orange: #f55014;
      --brand-pink: #ff0c82;
      --accent-grad: linear-gradient(135deg, #195feb 0%, #ff0c82 50%, #f55014 100%);
      --text: #f0f6fc;
      --text-muted: #8b949e;
      --green: #238636;
      --green-light: #3fb950;
      --blue: #195feb;
      --orange: #f55014;
      --red: #f85149;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.5;
    }
    .app-layout {
      display: flex;
      min-height: 100vh;
    }
    .sidebar {
      width: 250px;
      background: #0d1117;
      border-right: 1px solid var(--border);
      padding: 20px 14px;
      display: flex;
      flex-direction: column;
      gap: 6px;
      flex-shrink: 0;
      position: sticky;
      top: 0;
      height: 100vh;
      overflow-y: auto;
      box-sizing: border-box;
      z-index: 100;
    }
    .sidebar-brand {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 6px 10px 18px 10px;
      border-bottom: 1px solid var(--border);
      margin-bottom: 12px;
      cursor: pointer;
    }
    .sidebar-brand-logo {
      width: 40px;
      height: 40px;
      filter: drop-shadow(0 0 10px rgba(255, 12, 130, 0.45));
    }
    .sidebar-brand-text {
      display: flex;
      flex-direction: column;
    }
    .sidebar-brand-title {
      font-size: 1.18rem;
      font-weight: 900;
      color: #FF0C82;
      letter-spacing: -0.3px;
      text-shadow: 0 0 12px rgba(255, 12, 130, 0.45);
    }
    .sidebar-brand-sub {
      font-size: 0.72rem;
      color: var(--text-muted);
      font-weight: 500;
    }
    .sidebar-nav-group {
      display: flex;
      flex-direction: column;
      gap: 6px;
      flex: 1;
    }
    .sidebar-nav-btn {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 12px 14px;
      border-radius: 10px;
      color: var(--text-muted);
      background: transparent;
      border: 1px solid transparent;
      font-size: 0.92rem;
      font-weight: 600;
      cursor: pointer;
      text-align: left;
      transition: all 0.2s ease;
      width: 100%;
    }
    .sidebar-nav-btn .nav-icon {
      font-size: 1.15rem;
      flex-shrink: 0;
    }
    .sidebar-nav-btn:hover {
      background: rgba(255, 255, 255, 0.05);
      color: #fff;
    }
    .sidebar-nav-btn.active {
      background: linear-gradient(135deg, rgba(25, 95, 235, 0.35) 0%, rgba(255, 12, 130, 0.3) 100%);
      border-color: rgba(255, 12, 130, 0.45);
      color: #fff;
      box-shadow: 0 0 14px rgba(255, 12, 130, 0.2);
    }
    .sidebar-footer {
      padding: 14px 10px 4px 10px;
      border-top: 1px solid var(--border);
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 0.76rem;
      color: var(--text-muted);
    }
    .sidebar-status-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--green-light);
      box-shadow: 0 0 8px var(--green-light);
    }
    .main-content {
      flex: 1;
      padding: 24px 32px;
      max-width: 1120px;
      margin: 0 auto;
      width: 100%;
      box-sizing: border-box;
      min-width: 0;
    }
    .container { width: 100%; }
    header {
      text-align: center;
      padding: 24px 0 18px;
    }
    .brand-logo-wrap {
      display: flex;
      justify-content: center;
      margin-bottom: 14px;
    }
    .brand-logo {
      width: 78px;
      height: 78px;
      border: none;
      background: transparent;
      filter: drop-shadow(0 0 16px rgba(255, 12, 130, 0.45)) drop-shadow(0 0 8px rgba(25, 95, 235, 0.35));
      transition: transform 0.25s ease, filter 0.25s ease;
    }
    .brand-logo:hover {
      transform: scale(1.06);
      filter: drop-shadow(0 0 24px rgba(255, 12, 130, 0.75)) drop-shadow(0 0 14px rgba(25, 95, 235, 0.55));
    }
    /* Main Top Tabs Switcher */
    .main-tabs-nav {
      display: flex;
      justify-content: center;
      gap: 10px;
      margin: 0 auto 24px auto;
      max-width: 520px;
      padding: 6px;
      background: rgba(17, 20, 28, 0.95);
      border: 1px solid var(--border);
      border-radius: 14px;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4);
    }
    .main-tab-btn {
      flex: 1;
      padding: 12px 20px;
      background: transparent;
      border: 1px solid transparent;
      border-radius: 10px;
      color: var(--text-muted);
      font-size: 0.96rem;
      font-weight: 700;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      transition: all 0.2s ease;
    }
    .main-tab-btn:hover {
      color: var(--text);
      background: rgba(255, 255, 255, 0.04);
    }
    .main-tab-btn.active {
      color: #fff;
      background: linear-gradient(135deg, rgba(25, 95, 235, 0.4) 0%, rgba(255, 12, 130, 0.35) 100%);
      border-color: rgba(255, 12, 130, 0.5);
      box-shadow: 0 0 16px rgba(255, 12, 130, 0.3);
    }
    .quick-install-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 16px;
    }
    @media (max-width: 768px) {
      .quick-install-grid {
        grid-template-columns: 1fr !important;
      }
    }
    /* Breadcrumb Step Pills for Quick Install */
    .breadcrumb-container {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 6px;
      margin-top: 8px;
    }
    .breadcrumb-step {
      display: inline-flex;
      align-items: center;
      background: #161b22;
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 4px 8px;
      font-size: 0.76rem;
      color: var(--text);
      font-weight: 500;
    }
    .breadcrumb-arrow {
      color: var(--text-muted);
      font-size: 0.75rem;
    }
    h1 {
      font-size: 2.2rem;
      color: #FF0C82;
      margin-bottom: 6px;
      font-weight: 900;
      letter-spacing: -0.5px;
      text-shadow: 0 0 16px rgba(255, 12, 130, 0.4);
    }
    p.subtitle { color: var(--text-muted); font-size: 1.02rem; }

    /* Engine Status Banner */
    .status-banner {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      justify-content: center;
      margin-bottom: 24px;
    }
    .status-chip {
      background: rgba(22, 27, 34, 0.9);
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 6px 14px;
      font-size: 0.82rem;
      color: var(--text);
      display: inline-flex;
      align-items: center;
      gap: 8px;
    }
    .status-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--green-light);
      box-shadow: 0 0 8px var(--green-light);
    }

    .card {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 24px;
      margin-bottom: 24px;
      box-shadow: 0 4px 16px rgba(0,0,0,0.3);
    }
    .card h2 {
      font-size: 1.3rem;
      margin-bottom: 16px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .url-box {
      display: flex;
      gap: 12px;
      align-items: center;
      margin-bottom: 12px;
      flex-wrap: wrap;
    }
    .url-input {
      flex: 1;
      padding: 10px 14px;
      background: #090d13;
      border: 1px solid var(--border);
      border-radius: 6px;
      color: var(--blue);
      font-family: monospace;
      font-size: 0.95rem;
    }
    .password-wrapper {
      flex: 1;
      position: relative;
      display: flex;
    }
    .password-wrapper input {
      width: 100%;
      padding-right: 44px;
    }
    .password-toggle-btn {
      position: absolute;
      right: 8px;
      top: 50%;
      transform: translateY(-50%);
      background: none;
      border: none;
      color: var(--text-muted);
      cursor: pointer;
      font-size: 1.1rem;
      padding: 4px;
      border-radius: 4px;
    }
    .password-toggle-btn:hover {
      color: var(--text);
    }
    .btn {
      padding: 8px 14px;
      background: var(--card-bg);
      color: var(--text);
      border: 1px solid var(--border);
      border-radius: 6px;
      cursor: pointer;
      font-size: 0.88rem;
      font-weight: 500;
      transition: all 0.15s ease;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      white-space: nowrap;
    }
    .btn:hover { background: #21262d; border-color: #8b949e; }
    .btn-primary {
      background: var(--accent);
      border-color: var(--accent);
      color: #fff;
    }
    .btn-primary:hover { background: #9139e8; border-color: #9139e8; }
    .btn-success { background: var(--green); border-color: var(--green); color:#fff; }
    .btn-success:hover { background: #2ea043; }
    .btn-play {
      background: #1f6feb;
      border-color: #388bfd;
      color: #fff;
    }
    .btn-play:hover {
      background: #388bfd;
    }
    .instructions {
      background: rgba(88, 166, 255, 0.08);
      border: 1px solid rgba(88, 166, 255, 0.2);
      border-radius: 8px;
      padding: 14px;
      margin-top: 14px;
      font-size: 0.9rem;
    }
    .instructions ol { margin-left: 20px; }
    .instructions li { margin-bottom: 4px; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
      gap: 12px;
      max-height: 480px;
      overflow-y: auto;
      padding: 4px;
    }
    .provider-card {
      position: relative;
      cursor: pointer;
    }
    .provider-card input {
      position: absolute;
      opacity: 0;
    }
    .card-inner {
      background: #0d1117;
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 12px;
      display: flex;
      flex-direction: column;
      gap: 6px;
      transition: all 0.15s ease;
      height: 100%;
    }
    .provider-card input:checked + .card-inner {
      border-color: #7928ca;
      background: rgba(121, 40, 202, 0.12);
    }
    .provider-name { font-weight: 600; font-size: 0.95rem; }
    .badge {
      font-size: 0.72rem;
      color: var(--text-muted);
      font-family: monospace;
      background: #21262d;
      padding: 2px 6px;
      border-radius: 4px;
    }
    .provider-tags {
      display: flex;
      flex-wrap: wrap;
      gap: 4px;
      margin-top: 2px;
    }
    .tag-pill {
      font-size: 0.68rem;
      padding: 2px 6px;
      border-radius: 4px;
      font-weight: 600;
    }
    .tag-scope {
      background: rgba(88, 166, 255, 0.15);
      color: #58a6ff;
      border: 1px solid rgba(88, 166, 255, 0.3);
    }
    .tag-quality {
      background: rgba(63, 185, 80, 0.15);
      color: #3fb950;
      border: 1px solid rgba(63, 185, 80, 0.3);
    }
    .tag-tech {
      background: rgba(210, 153, 34, 0.15);
      color: #d29922;
      border: 1px solid rgba(210, 153, 34, 0.3);
    }
    .provider-desc {
      font-size: 0.76rem;
      color: var(--text-muted);
      line-height: 1.35;
      margin-top: 2px;
    }
    .test-box {
      display: flex;
      gap: 12px;
      margin-bottom: 16px;
    }
    .test-input {
      flex: 1;
      padding: 10px 14px;
      background: #090d13;
      border: 1px solid var(--border);
      border-radius: 6px;
      color: var(--text);
    }
    select {
      padding: 10px 14px;
      background: #090d13;
      border: 1px solid var(--border);
      border-radius: 6px;
      color: var(--text);
    }
    #testResults {
      background: #090d13;
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 14px;
      max-height: 520px;
      overflow-y: auto;
      font-size: 0.88rem;
      display: none;
    }
    .stream-filter-bar {
      display: flex;
      gap: 8px;
      margin-bottom: 14px;
      flex-wrap: wrap;
      align-items: center;
    }
    .stream-filter-chip {
      background: #161b22;
      border: 1px solid var(--border);
      color: var(--text-muted);
      padding: 4px 10px;
      border-radius: 16px;
      cursor: pointer;
      font-size: 0.78rem;
      font-weight: 600;
      transition: all 0.15s;
    }
    .stream-filter-chip:hover, .stream-filter-chip.active {
      background: #21262d;
      color: var(--text);
      border-color: var(--blue);
    }
    .catalog-card {
      background: #0d1117;
      border: 1px solid var(--border);
      border-radius: 10px;
      cursor: pointer;
      transition: transform 0.15s, border-color 0.15s, box-shadow 0.15s;
      overflow: hidden;
      position: relative;
    }
    .catalog-card:hover {
      transform: translateY(-3px) scale(1.02);
      border-color: var(--blue);
      box-shadow: 0 6px 20px rgba(88,166,255,0.18);
    }
    .catalog-card:active { transform: scale(0.98); }

    .stream-item {
      padding: 12px 10px;
      border-bottom: 1px solid var(--border);
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 14px;
    }
    .stream-item:last-child { border-bottom: none; }
    .stream-info { flex: 1; min-width: 0; }
    .stream-title { font-weight: 600; color: var(--blue); font-size: 0.95rem; word-break: break-word; }
    .stream-sub { font-size: 0.82rem; color: var(--text-muted); margin-top: 4px; word-break: break-word; white-space: pre-wrap; }
    .stream-actions { display: flex; gap: 8px; flex-shrink: 0; flex-wrap: wrap; }
    .hoster-card {
      background: #0d1117;
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 10px;
      font-size: 0.85rem;
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    .hoster-name { font-weight: 600; color: #fff; }
    .hoster-domains { color: var(--text-muted); font-size: 0.75rem; word-break: break-all; }
    .hoster-status { display: inline-block; font-size: 0.72rem; padding: 2px 6px; border-radius: 4px; width: fit-content; }
    .status-up { background: rgba(35, 134, 54, 0.2); color: #3fb950; }
    .status-down { background: rgba(248, 81, 73, 0.2); color: #f85149; }
    .update-box {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 14px;
      background: #0d1117;
      border: 1px solid var(--border);
      border-radius: 8px;
    }
    .update-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: 14px;
      margin-bottom: 14px;
    }
    .update-subcard {
      background: #090d13;
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 14px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      gap: 12px;
    }
    .update-subcard-header {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      gap: 10px;
    }
    .update-subcard-title {
      font-weight: 600;
      color: #fff;
      font-size: 0.95rem;
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .update-subcard-desc {
      color: var(--text-muted);
      font-size: 0.8rem;
      margin-top: 4px;
      line-height: 1.4;
    }
    .update-pill {
      font-size: 0.72rem;
      padding: 3px 8px;
      border-radius: 12px;
      font-weight: 600;
      white-space: nowrap;
    }
    .update-downloads-bar {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }
    .btn-sm {
      padding: 5px 10px;
      font-size: 0.8rem;
    }
    .btn-outline {
      background: transparent;
      border-color: var(--border);
      color: var(--blue);
      text-decoration: none;
    }
    .btn-outline:hover {
      background: rgba(88, 166, 255, 0.1);
      border-color: var(--blue);
    }
    .toast {
      position: fixed;
      bottom: 24px;
      right: 24px;
      background: var(--green);
      color: #fff;
      padding: 12px 20px;
      border-radius: 8px;
      box-shadow: 0 4px 16px rgba(0,0,0,0.5);
      display: none;
      z-index: 10000;
      font-weight: 600;
    }

    /* Modal Player Styles */
    .player-modal {
      display: none;
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: rgba(0,0,0,0.85);
      z-index: 99999;
      justify-content: center;
      align-items: center;
      padding: 20px;
    }
    .player-modal-content {
      background: #161b22;
      border: 1px solid var(--border);
      border-radius: 12px;
      width: 100%;
      max-width: 900px;
      overflow: hidden;
      box-shadow: 0 8px 32px rgba(0,0,0,0.8);
      display: flex;
      flex-direction: column;
    }
    .player-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 14px 18px;
      border-bottom: 1px solid var(--border);
      background: #0d1117;
    }
    .player-title {
      font-weight: 600;
      font-size: 1rem;
      color: var(--text);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .player-close-btn {
      background: none;
      border: none;
      color: var(--text-muted);
      font-size: 1.5rem;
      cursor: pointer;
      line-height: 1;
      padding: 0 4px;
    }
    .player-close-btn:hover { color: #fff; }
    .video-wrapper {
      position: relative;
      width: 100%;
      padding-top: 56.25%; /* 16:9 Aspect Ratio */
      background: #000;
    }
    .video-wrapper video {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
    }
    /* Open With Modal */
    .open-with-modal {
      display: none;
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: rgba(0,0,0,0.85);
      z-index: 99999;
      justify-content: center;
      align-items: center;
      padding: 20px;
    }
    .open-with-content {
      background: #161b22;
      border: 1px solid var(--border);
      border-radius: 12px;
      width: 100%;
      max-width: 620px;
      overflow: hidden;
      box-shadow: 0 8px 32px rgba(0,0,0,0.8);
      display: flex;
      flex-direction: column;
    }
    .player-opt-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 12px;
      padding: 20px;
    }
    .player-opt-btn {
      display: flex;
      align-items: center;
      gap: 12px;
      background: #0d1117;
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 12px 16px;
      color: var(--text);
      cursor: pointer;
      text-decoration: none;
      font-weight: 600;
      font-size: 0.92rem;
      transition: all 0.2s ease;
    }
    .player-opt-btn:hover {
      background: #1c2128;
      border-color: var(--accent);
      transform: translateY(-2px);
    }
    .player-opt-icon {
      font-size: 1.6rem;
      flex-shrink: 0;
    }
    .media-card-box {
      background: #0d1117;
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 16px;
      margin-bottom: 16px;
      display: flex;
      gap: 16px;
      align-items: flex-start;
    }
    .media-card-poster {
      width: 90px;
      height: 135px;
      border-radius: 6px;
      object-fit: cover;
      background: #161b22;
      flex-shrink: 0;
    }
    .search-suggestions-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
      gap: 12px;
      margin-top: 14px;
      margin-bottom: 16px;
    }
    .search-suggestion-item {
      background: #090d13;
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 10px;
      cursor: pointer;
      display: flex;
      gap: 10px;
      align-items: center;
      transition: border-color 0.2s, transform 0.2s;
    }
    .search-suggestion-item:hover {
      border-color: var(--accent);
      transform: translateY(-2px);
    }
    .search-suggestion-thumb {
      width: 44px;
      height: 64px;
      border-radius: 4px;
      object-fit: cover;
      background: #161b22;
      flex-shrink: 0;
    }
    .btn-open-with {
      background: #21262d;
      border: 1px solid var(--border);
      color: #58a6ff;
    }
    .btn-open-with:hover {
      background: #30363d;
      border-color: #58a6ff;
    }
    /* Series Catalog & Episode Browser */
    .seasons-bar {
      display: flex;
      gap: 8px;
      overflow-x: auto;
      padding: 6px 0 12px;
      margin-bottom: 12px;
      border-bottom: 1px solid var(--border);
    }
    .season-tab {
      background: #090d13;
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 6px 14px;
      font-size: 0.84rem;
      font-weight: 600;
      color: var(--text-muted);
      cursor: pointer;
      white-space: nowrap;
      transition: all 0.2s;
    }
    .season-tab:hover {
      border-color: var(--blue);
      color: #fff;
    }
    .season-tab.active {
      background: var(--blue);
      border-color: var(--blue);
      color: #fff;
    }
    .episodes-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 12px;
      margin-bottom: 16px;
      max-height: 380px;
      overflow-y: auto;
      padding-right: 4px;
    }
    .episode-card {
      background: #090d13;
      border: 1px solid var(--border);
      border-radius: 8px;
      overflow: hidden;
      display: flex;
      cursor: pointer;
      transition: all 0.2s;
    }
    .episode-card:hover {
      border-color: var(--accent);
      transform: translateY(-2px);
    }
    .episode-card.active {
      border-color: var(--green-light);
      background: #111a14;
    }
    .episode-thumb {
      width: 100px;
      height: 75px;
      object-fit: cover;
      background: #161b22;
      flex-shrink: 0;
    }
    .episode-content {
      padding: 8px 10px;
      flex: 1;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      overflow: hidden;
    }
    .episode-num {
      font-size: 0.72rem;
      font-weight: 700;
      color: var(--blue);
      text-transform: uppercase;
    }
    .episode-title {
      font-size: 0.84rem;
      font-weight: 600;
      color: #fff;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .episode-desc {
      font-size: 0.72rem;
      color: var(--text-muted);
      display: -webkit-box;
      -webkit-line-clamp: 2;
      -webkit-box-orient: vertical;
      overflow: hidden;
      line-height: 1.3;
    }

    /* Mobile & Small Screen Responsive Enhancements */
    @media (max-width: 768px) {
      .app-layout {
        flex-direction: column;
      }
      .sidebar {
        width: 100%;
        height: auto;
        position: relative;
        border-right: none;
        border-bottom: 1px solid var(--border);
        padding: 12px 14px;
        flex-direction: row;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
      }
      .sidebar-brand {
        border-bottom: none;
        padding: 0;
        margin-bottom: 0;
      }
      .sidebar-nav-group {
        flex-direction: row;
        flex-wrap: wrap;
        gap: 6px;
      }
      .sidebar-nav-btn {
        width: auto;
        padding: 8px 12px;
        font-size: 0.82rem;
      }
      .sidebar-footer {
        display: none;
      }
      .main-content {
        padding: 14px 10px;
      }
      .container {
        width: 100%;
      }
      .card {
        padding: 16px 12px;
        margin-bottom: 16px;
      }
      h1 {
        font-size: 1.75rem;
      }
      p.subtitle {
        font-size: 0.86rem;
        word-break: break-word;
      }
      .main-tabs-nav {
        max-width: 100%;
        gap: 6px;
        padding: 4px;
      }
      .main-tab-btn {
        padding: 10px 10px;
        font-size: 0.85rem;
        text-align: center;
        white-space: normal;
        gap: 6px;
      }
      .url-box {
        flex-direction: column;
        align-items: stretch;
        gap: 8px;
      }
      .url-box label {
        min-width: 0 !important;
        width: 100%;
      }
      .url-box .url-input {
        width: 100%;
        min-width: 0;
      }
      .url-box .password-wrapper {
        width: 100%;
      }
      .url-box .btn, .url-box a.btn {
        width: 100%;
        justify-content: center;
      }
      .test-box {
        flex-direction: column;
        align-items: stretch;
      }
      .test-box select, .test-box input, .test-box button {
        width: 100% !important;
        min-width: 0 !important;
      }
      #seriesInputsRow {
        width: 100%;
        justify-content: flex-start;
      }
      .stream-item {
        flex-direction: column;
        align-items: stretch;
        gap: 10px;
      }
      .stream-actions {
        width: 100%;
        justify-content: flex-start;
        gap: 6px;
      }
      .stream-actions .btn {
        flex: 1 1 auto;
        justify-content: center;
        min-width: 90px;
      }
      .player-opt-grid {
        grid-template-columns: 1fr !important;
        padding: 14px;
      }
      .player-header {
        padding: 10px 14px;
      }
      .player-title {
        max-width: 180px;
      }
      .media-card-box {
        flex-direction: column;
        align-items: center;
        text-align: center;
      }
      .media-card-poster {
        width: 110px;
        height: 165px;
      }
      .search-suggestions-grid {
        grid-template-columns: 1fr;
      }
      .catalog-card {
        min-width: 0;
      }
      .update-subcard-header {
        flex-wrap: wrap;
      }
      .breadcrumb-container {
        justify-content: center;
      }
      .breadcrumb-step {
        font-size: 0.72rem;
        padding: 3px 6px;
      }
      .status-chip {
        font-size: 0.74rem;
        padding: 5px 10px;
      }
    }
    @media (max-width: 480px) {
      .main-tabs-nav {
        flex-direction: column;
      }
      .main-tab-btn {
        width: 100%;
        justify-content: center;
      }
      .stream-actions .btn {
        flex: 1 1 100%;
      }
      #catalogGrid {
        grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)) !important;
        gap: 8px !important;
      }
    }

    /* ═════════ Nuvio-like Full Expand Media Modal ═════════ */
    .media-modal-backdrop {
      position: fixed;
      inset: 0;
      z-index: 9999;
      background: rgba(4, 7, 13, 0.88);
      backdrop-filter: blur(14px);
      -webkit-backdrop-filter: blur(14px);
      overflow-y: auto;
      display: flex;
      justify-content: center;
      align-items: flex-start;
      padding: 30px 16px;
      box-sizing: border-box;
    }
    .media-modal-container {
      background: #0b0f17;
      border: 1px solid #30363d;
      border-radius: 16px;
      width: 100%;
      max-width: 980px;
      overflow: hidden;
      position: relative;
      box-shadow: 0 25px 60px rgba(0, 0, 0, 0.85);
      animation: modalScaleIn 0.22s cubic-bezier(0.16, 1, 0.3, 1);
    }
    @keyframes modalScaleIn {
      from { opacity: 0; transform: scale(0.96) translateY(12px); }
      to { opacity: 1; transform: scale(1) translateY(0); }
    }
    .modal-hero {
      position: relative;
      min-height: 280px;
      background-size: cover;
      background-position: center 25%;
      background-color: #161b22;
      display: flex;
      align-items: flex-end;
      padding: 24px;
      box-sizing: border-box;
    }
    .modal-hero-overlay {
      position: absolute;
      inset: 0;
      background: linear-gradient(180deg, rgba(11, 15, 23, 0.2) 0%, rgba(11, 15, 23, 0.8) 65%, #0b0f17 100%),
                  linear-gradient(90deg, rgba(11, 15, 23, 0.85) 0%, rgba(11, 15, 23, 0.4) 60%, rgba(11, 15, 23, 0.85) 100%);
    }
    .modal-hero-content {
      position: relative;
      z-index: 2;
      display: flex;
      gap: 20px;
      align-items: flex-end;
      width: 100%;
    }
    .modal-poster {
      width: 135px;
      height: 200px;
      border-radius: 10px;
      object-fit: cover;
      box-shadow: 0 10px 30px rgba(0,0,0,0.8);
      border: 2px solid rgba(255,255,255,0.12);
      flex-shrink: 0;
      background: #161b22;
    }
    .modal-header-info {
      flex: 1;
      min-width: 0;
    }
    .modal-close-btn {
      position: absolute;
      top: 14px;
      right: 14px;
      z-index: 10;
      background: rgba(0,0,0,0.7);
      border: 1px solid rgba(255,255,255,0.2);
      color: #fff;
      width: 36px;
      height: 36px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      font-size: 1.1rem;
      transition: background 0.2s, transform 0.2s;
    }
    .modal-close-btn:hover {
      background: #ff0c82;
      border-color: #ff0c82;
      transform: scale(1.08);
    }
    .modal-seasons-bar {
      display: flex;
      gap: 8px;
      overflow-x: auto;
      padding-bottom: 6px;
      margin-bottom: 14px;
    }
    .modal-season-tab {
      background: #161b22;
      border: 1px solid var(--border);
      color: var(--text-muted);
      padding: 7px 14px;
      border-radius: 20px;
      font-size: 0.84rem;
      font-weight: 600;
      cursor: pointer;
      white-space: nowrap;
      transition: all 0.2s;
    }
    .modal-season-tab:hover {
      background: #21262d;
      color: #fff;
    }
    .modal-season-tab.active {
      background: var(--blue);
      color: #fff;
      border-color: var(--blue);
      box-shadow: 0 0 10px rgba(88, 166, 255, 0.4);
    }
    .modal-episodes-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 10px;
      max-height: 340px;
      overflow-y: auto;
      padding-right: 4px;
      margin-bottom: 16px;
    }
    .modal-episode-card {
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 8px;
      overflow: hidden;
      cursor: pointer;
      display: flex;
      gap: 10px;
      padding: 8px;
      transition: border-color 0.2s, background 0.2s;
    }
    .modal-episode-card:hover {
      border-color: var(--blue);
      background: #1c2128;
    }
    .modal-episode-card.active {
      border-color: var(--accent);
      background: rgba(255, 12, 130, 0.1);
      box-shadow: 0 0 10px rgba(255, 12, 130, 0.25);
    }
    .modal-episode-thumb {
      width: 86px;
      height: 56px;
      border-radius: 5px;
      object-fit: cover;
      flex-shrink: 0;
      background: #0d1117;
    }
  </style>
</head>
<body>
  <div class="app-layout">
    <!-- Left Navigation Sidebar -->
    <aside class="sidebar">
      <div class="sidebar-brand" onclick="switchMainTab('about')" title="About Hostreamio">
        <img src="/logo.png" alt="Hostreamio" class="sidebar-brand-logo" />
        <div class="sidebar-brand-text">
          <span class="sidebar-brand-title">Hostreamio</span>
          <span class="sidebar-brand-sub">Direct &amp; Debrid Engine</span>
        </div>
      </div>
      <div class="sidebar-nav-group">
        <button id="tabBtnServer" class="sidebar-nav-btn active" onclick="switchMainTab('server')">
          <span class="nav-icon">🖥️</span>
          <span>Server &amp; Addon</span>
        </button>
        <button id="tabBtnSearch" class="sidebar-nav-btn" onclick="switchMainTab('search')">
          <span class="nav-icon">🔍</span>
          <span>Search &amp; Scrape</span>
        </button>
        <button id="tabBtnStreaming" class="sidebar-nav-btn" onclick="switchMainTab('streaming')">
          <span class="nav-icon">🎬</span>
          <span>Cinema &amp; Series</span>
        </button>
        <button id="tabBtnIptv" class="sidebar-nav-btn" onclick="switchMainTab('iptv')">
          <span class="nav-icon">📺</span>
          <span>Live IPTV</span>
        </button>
        <button id="tabBtnCaching" class="sidebar-nav-btn" onclick="switchMainTab('caching')">
          <span class="nav-icon">⚡</span>
          <span>Caching Queue</span>
          <span id="sidebarQueueBadge" class="badge" style="display:none; background:#ff0c82; color:#fff; font-size:0.7rem; padding:2px 6px; border-radius:10px; margin-left:auto; font-weight:bold;">0</span>
        </button>
        <button id="tabBtnAbout" class="sidebar-nav-btn" onclick="switchMainTab('about')">
          <span class="nav-icon">ℹ️</span>
          <span>About &amp; Diagnostics</span>
        </button>
      </div>
      <div class="sidebar-footer">
        <div class="sidebar-status-dot"></div>
        <span>v1.0.0 Ready</span>
      </div>
    </aside>

    <main class="main-content">
      <!-- TAB 1: SERVER & ADDON HUB -->
      <div id="tabContentServer">
      <!-- Quick Install & Manifest Card -->
      <div class="card" style="background: linear-gradient(180deg, rgba(22, 27, 34, 0.95) 0%, rgba(13, 17, 23, 0.95) 100%);">
        <div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; margin-bottom:16px;">
          <h2>🔌 Quick Install in Nuvio &amp; Stremio</h2>
          <span class="badge" style="background:rgba(88, 166, 255, 0.15); color:var(--blue); border:1px solid rgba(88, 166, 255, 0.3); font-size:0.8rem; padding:4px 10px;">
            📡 Wi-Fi IP: $localIp
          </span>
        </div>

        <div class="quick-install-grid">
          <!-- Option 1: This PC -->
          <div style="background:#090d13; border:1px solid rgba(88, 166, 255, 0.3); border-radius:10px; padding:18px; display:flex; flex-direction:column; justify-content:space-between; gap:14px;">
            <div>
              <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:8px;">
                <span style="font-weight:700; font-size:1rem; color:var(--text);">💻 This PC (Local Player)</span>
                <span style="font-size:0.75rem; color:var(--green-light); background:rgba(35, 134, 54, 0.2); border:1px solid rgba(35, 134, 54, 0.4); padding:3px 8px; border-radius:12px; font-weight:600;">1-Click</span>
              </div>
              <p style="font-size:0.84rem; color:var(--text-muted); line-height:1.5; margin:0;">
                If Nuvio or Stremio is installed on this PC, install addon manifest directly:
              </p>
            </div>
            <div>
              <a href="stremio://127.0.0.1:$port/manifest.json" class="btn btn-primary" style="width:100%; justify-content:center; padding:10px 14px; font-size:0.92rem; font-weight:700; text-decoration:none; margin-bottom:10px;">
                🚀 1-Click Install to Stremio / Nuvio
              </a>
              <div style="display:flex; gap:8px; margin-bottom:10px;">
                <input class="url-input" id="localUrl" value="$manifestLocal" readonly style="font-size:0.82rem; padding:8px 10px;">
                <button type="button" class="btn" onclick="copyText('localUrl')" style="padding:8px 14px; font-size:0.82rem; white-space:nowrap;">📋 Copy</button>
              </div>
              <div class="breadcrumb-container" style="justify-content:center;">
                <span class="breadcrumb-step">1. Click Install</span>
                <span class="breadcrumb-arrow">➔</span>
                <span class="breadcrumb-step">2. App Launches</span>
                <span class="breadcrumb-arrow">➔</span>
                <span class="breadcrumb-step" style="color:var(--green-light); border-color:var(--green-light); font-weight:700;">3. Confirm Addon</span>
              </div>
            </div>
          </div>

          <!-- Option 2: Android TV, Fire TV & Mobile -->
          <div style="background:#090d13; border:1px solid rgba(88, 166, 255, 0.3); border-radius:10px; padding:18px; display:flex; flex-direction:column; justify-content:space-between; gap:14px;">
            <div>
              <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:8px;">
                <span style="font-weight:700; font-size:1rem; color:var(--text);">📺 Android TV, Fire TV &amp; Mobile</span>
                <span style="font-size:0.75rem; color:var(--blue); background:rgba(88, 166, 255, 0.2); border:1px solid rgba(88, 166, 255, 0.4); padding:3px 8px; border-radius:12px; font-weight:600;">Wi-Fi LAN</span>
              </div>
              <p style="font-size:0.84rem; color:var(--text-muted); line-height:1.5; margin:0;">
                For Android TV, Fire TV Stick, or Phone connected to the same Wi-Fi network:
              </p>
            </div>
            <div>
              <button type="button" class="btn btn-primary" onclick="copyText('lanUrl')" style="width:100%; justify-content:center; padding:10px 14px; font-size:0.92rem; font-weight:700; margin-bottom:10px;">
                📋 Copy LAN Manifest URL for TV
              </button>
              <div style="display:flex; gap:8px; margin-bottom:10px;">
                <input class="url-input" id="lanUrl" value="$manifestLan" readonly style="font-size:0.82rem; padding:8px 10px; color:var(--green-light);">
                <button type="button" class="btn" onclick="copyText('lanUrl')" style="padding:8px 14px; font-size:0.82rem; white-space:nowrap;">📋 Copy</button>
              </div>
              <div class="breadcrumb-container" style="justify-content:center;">
                <span class="breadcrumb-step">1. Nuvio Settings</span>
                <span class="breadcrumb-arrow">➔</span>
                <span class="breadcrumb-step">2. Addons (+)</span>
                <span class="breadcrumb-arrow">➔</span>
                <span class="breadcrumb-step" style="color:var(--green-light); border-color:var(--green-light); font-weight:700;">3. Paste &amp; Install</span>
              </div>
            </div>
          </div>

          <!-- Option 3: Nuvio Fusion Badges (Quality & OTT Logos) -->
          <div style="background:#090d13; border:1px solid rgba(255, 105, 180, 0.4); border-radius:10px; padding:18px; display:flex; flex-direction:column; justify-content:space-between; gap:14px; grid-column: 1 / -1;">
            <div>
              <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:8px; flex-wrap:wrap; gap:8px;">
                <span style="font-weight:700; font-size:1rem; color:#ff69b4;">🎨 Nuvio Logo Badges (Quality &amp; OTT Logos)</span>
                <span style="font-size:0.75rem; color:#ff69b4; background:rgba(255, 105, 180, 0.15); border:1px solid rgba(255,105,180,0.4); padding:3px 8px; border-radius:12px; font-weight:600;">Required for Logo Badges</span>
              </div>
              <p style="font-size:0.84rem; color:var(--text); line-height:1.5; margin:0;">
                Nuvio renders visual logos &amp; badges (4K, WEB-DL, Hotstar, Netflix, Prime, JioCinema, SonyLIV, Zee5) through <strong>Fusion Badge URLs</strong>:
              </p>
            </div>
            <div>
              <div style="display:flex; gap:8px; margin-bottom:10px;">
                <input class="url-input" id="badgesUrl" value="http://$localIp:$port/badges.json" readonly style="font-size:0.84rem; padding:8px 10px; color:#ff69b4; font-weight:600;">
                <button type="button" class="btn btn-primary" onclick="copyText('badgesUrl')" style="padding:8px 16px; font-size:0.85rem; white-space:nowrap; font-weight:700; background:#ff69b4; border-color:#ff69b4; color:#fff;">📋 Copy Badge URL</button>
              </div>
              <div class="breadcrumb-container" style="justify-content:center;">
                <span class="breadcrumb-step">1. Nuvio Settings</span>
                <span class="breadcrumb-arrow">➔</span>
                <span class="breadcrumb-step">2. Layout &amp; Streams</span>
                <span class="breadcrumb-arrow">➔</span>
                <span class="breadcrumb-step">3. Fusion Badge URLs</span>
                <span class="breadcrumb-arrow">➔</span>
                <span class="breadcrumb-step" style="color:#ff69b4; border-color:#ff69b4; font-weight:700;">4. Paste &amp; Save</span>
              </div>
            </div>
          </div>
        </div>
      </div>

    <!-- TorBox Debrid & Cache Integration -->
    <div class="card">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 14px; flex-wrap:wrap; gap:8px;">
        <h2>⚡ TorBox Debrid & Cloud Cache</h2>
        <span id="torboxStatusBadge" class="badge" style="background:#21262d; padding:4px 8px; border-radius:4px; font-size:0.85rem;">Not Configured</span>
      </div>
      <p style="color:var(--text-muted); margin-bottom:14px; font-size:0.9rem;">
        Integrate your TorBox API key to stream cached cloud links (HubCloud, HubDrive, DriveSeed, Pixeldrain, Mega, 1fichier, Rapidgator, Google Drive) directly through TorBox CDN at unlimited speed with zero buffering.
      </p>
      
      <div class="url-box">
        <label style="min-width: 130px; font-weight:600;">TorBox API Key:</label>
        <div class="password-wrapper">
          <input class="url-input" type="password" id="torboxApiKey" value="$torboxApiKey" placeholder="Enter your TorBox API Key">
          <button type="button" class="password-toggle-btn" onclick="togglePasswordVisibility()" title="Show/Hide Key">👁️</button>
        </div>
        <button class="btn btn-primary" id="btnSaveTorbox" onclick="saveTorboxKey()">💾 Save & Validate</button>
        <a href="https://torbox.app/settings" target="_blank" class="btn" style="text-decoration:none; display:inline-flex; align-items:center; gap:4px;" title="Open TorBox Account Settings">🔗 Get TorBox Key ↗</a>
      </div>
      <div id="torboxAccountInfo" style="font-size:0.88rem; color:var(--text-muted); margin-bottom:14px; display:none;"></div>

      <div style="border-top:1px solid var(--border); padding-top:14px; margin-top:14px;">
        <h3 style="font-size:1rem; margin-bottom:8px;">🚀 Upload & Cache Link to TorBox</h3>
        <p style="color:var(--text-muted); font-size:0.82rem; margin-bottom:10px;">
          Paste any non-cached stream or cloud link below to queue a WebDL job to TorBox:
        </p>
        <div class="url-box">
          <input class="url-input" id="torboxUploadUrl" placeholder="https://hubcloud.cx/drive/... or any supported hoster URL">
          <button class="btn btn-success" id="btnUploadTorbox" onclick="uploadLinkToTorbox()">☁️⬆️ Cache to TorBox</button>
        </div>
        <div id="torboxUploadStatus" style="font-size:0.85rem; margin-top:6px; display:none;"></div>
      </div>

      <div style="border-top:1px solid var(--border); padding-top:14px; margin-top:14px;">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; flex-wrap:wrap; gap:8px;">
          <h3 style="font-size:1rem;">🌐 TorBox Live Supported Hosters (<a href="https://torbox.app/hosters" target="_blank" style="color:var(--blue); text-decoration:none;">torbox.app/hosters</a>)</h3>
          <div style="display:flex; gap:8px;">
            <input type="text" id="hosterSearch" placeholder="Filter hosters (e.g. hubcloud)..." oninput="filterHosters()" style="padding:6px 10px; background:#090d13; border:1px solid var(--border); border-radius:4px; color:var(--text); font-size:0.85rem;">
            <button class="btn" id="btnRefreshHosters" onclick="loadTorboxHosters()">🔄 Refresh Hosters</button>
          </div>
        </div>
        <div id="hostersGrid" class="grid" style="max-height:240px;"></div>
      </div>

      <div style="margin-top:14px; padding:12px 14px; background:#090d13; border:1px solid rgba(255, 12, 130, 0.35); border-radius:8px;">
        <label style="display:flex; align-items:flex-start; gap:12px; cursor:pointer;">
          <input type="checkbox" id="enableTorboxCachedTorrents" style="margin-top:4px;" $enableTorboxCachedTorrentsChecked onchange="saveTorboxCachedToggle(this.checked)">
          <div>
            <strong style="color:var(--text); font-size:0.92rem;">⚡ Fetch TorBox Cached Torrents (Default OFF • Strictly 0 P2P)</strong>
            <p style="margin:4px 0 0 0; font-size:0.8rem; color:var(--text-muted); line-height:1.4;">
              Queries high-speed torrent providers (YTS, EZTV, Nyaa Anime, 1TamilMV Desi, Knaben, TorrentGalaxy) <em>strictly and only</em> if the file is already 100% cached on TorBox Cloud CDN. Uncached torrents are completely discarded with zero P2P seeding, zero peer connections, and instant gigabit cloud playback.
            </p>
          </div>
        </label>
      </div>
    </div>

    <!-- Prowlarr Captcha Resolver & Cache-Bypass -->
    <div class="card">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; flex-wrap:wrap; gap:8px;">
        <h2>🧩 Prowlarr Captcha Resolver &amp; Anti-Cache</h2>
        <span class="badge" style="background:rgba(88, 166, 255, 0.15); color:var(--blue); border:1px solid rgba(88, 166, 255, 0.3); font-size:0.8rem; padding:4px 10px;">FlareSolverr Ready</span>
      </div>
      <p style="color:var(--text-muted); font-size:0.88rem; margin-bottom:14px;">
        Prowlarr-style automated proxy bridge to solve Cloudflare Turnstile, IUAM challenges, and bypass stale ISP/CDN cached pages:
      </p>
      <div class="url-box" style="margin-bottom:12px;">
        <label style="min-width:140px; font-weight:600;">FlareSolverr URL:</label>
        <input class="url-input" id="proxyResolverUrl" value="$proxyResolverUrl" placeholder="http://localhost:8191/v1 (optional)">
        <button class="btn btn-primary" onclick="saveProxyResolverSettings()">💾 Save Proxy</button>
      </div>
      <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:12px 14px;">
        <label style="display:flex; align-items:center; gap:10px; cursor:pointer; font-size:0.86rem; color:var(--text);">
          <input type="checkbox" id="enableCacheBypass" $enableCacheBypassChecked onchange="saveCacheBypassToggle(this.checked)">
          <span><strong>Prowlarr Origin-Fresh Cache-Bypass:</strong> Injects no-cache origin headers &amp; query nonces to avoid stale/broken ISP cache hits.</span>
        </label>
      </div>
    </div>

    <!-- Stream Filtering Profiles & Optimization -->
    <div class="card">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 14px; flex-wrap:wrap; gap:8px;">
        <h2>🎛️ Stream Filtering Profiles & Optimization</h2>
        <button class="btn btn-primary" id="btnSaveSettings" onclick="saveSettings()">💾 Save Settings</button>
      </div>
      <p style="color:var(--text-muted); margin-bottom:16px; font-size:0.9rem;">
        Fine-tune how streams are filtered, deduplicated, and ranked in your Nuvio drawer.
      </p>

      <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(280px, 1fr)); gap:16px; margin-bottom:16px;">
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px;">
          <label style="font-weight:600; display:block; margin-bottom:6px;">Preferred Audio Language:</label>
          <select id="prefLangSelect" style="width:100%; padding:8px; background:#161b22; border:1px solid var(--border); border-radius:6px; color:var(--text); font-size:0.88rem;">
            <option value="any" ${prefLang == 'any' ? 'selected' : ''}>Any / Default Order</option>
            <option value="hindi" ${prefLang == 'hindi' ? 'selected' : ''}>🇮🇳 Hindi</option>
            <option value="english" ${prefLang == 'english' ? 'selected' : ''}>🇬🇧 English</option>
            <option value="dual" ${prefLang == 'dual' ? 'selected' : ''}>🌐 Dual Audio / Multi Audio</option>
            <option value="tamil" ${prefLang == 'tamil' ? 'selected' : ''}>🇮🇳 Tamil</option>
            <option value="telugu" ${prefLang == 'telugu' ? 'selected' : ''}>🇮🇳 Telugu</option>
            <option value="malayalam" ${prefLang == 'malayalam' ? 'selected' : ''}>🇮🇳 Malayalam</option>
            <option value="kannada" ${prefLang == 'kannada' ? 'selected' : ''}>🇮🇳 Kannada</option>
            <option value="bengali" ${prefLang == 'bengali' ? 'selected' : ''}>🇮🇳 Bengali</option>
            <option value="punjabi" ${prefLang == 'punjabi' ? 'selected' : ''}>🇮🇳 Punjabi</option>
            <option value="marathi" ${prefLang == 'marathi' ? 'selected' : ''}>🇮🇳 Marathi</option>
            <option value="gujarati" ${prefLang == 'gujarati' ? 'selected' : ''}>🇮🇳 Gujarati</option>
          </select>
          <div style="color:var(--text-muted); font-size:0.78rem; margin-top:6px;">Boosts matching releases directly to the top of the stream list.</div>
        </div>

        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px;">
          <label style="font-weight:600; display:block; margin-bottom:6px;">Max Resolution Cap:</label>
          <select id="maxResSelect" style="width:100%; padding:8px; background:#161b22; border:1px solid var(--border); border-radius:6px; color:var(--text); font-size:0.88rem;">
            <option value="all" ${maxRes == 'all' ? 'selected' : ''}>Unlimited (4K / 2160p Allowed)</option>
            <option value="1080p" ${maxRes == '1080p' ? 'selected' : ''}>1080p Max (Filters out 4K for lower bandwidth)</option>
            <option value="720p" ${maxRes == '720p' ? 'selected' : ''}>720p Max (Fastest playback & lowest data)</option>
          </select>
          <div style="color:var(--text-muted); font-size:0.78rem; margin-top:6px;">Prevents high-bitrate 4K streams on smaller devices or slow WiFi.</div>
        </div>
      </div>

      <div style="display:flex; flex-direction:column; gap:10px;">
        <label style="display:flex; align-items:center; gap:10px; cursor:pointer;">
          <input type="checkbox" id="chkExcludeCams" $excludeCamsChecked style="width:18px; height:18px;">
          <div>
            <strong style="color:var(--text);">Clean Drawer Mode (Exclude CAMs & TeleSync)</strong>
            <div style="color:var(--text-muted); font-size:0.8rem;">Automatically strips CAM, TS, PreDVD, and Telesync copies when high-grade WEB-DL or BluRay copies exist.</div>
          </div>
        </label>

        <label style="display:flex; align-items:center; gap:10px; cursor:pointer;">
          <input type="checkbox" id="chkDedupe" $dedupeChecked style="width:18px; height:18px;">
          <div>
            <strong style="color:var(--text);">Smart Stream Deduplication</strong>
            <div style="color:var(--text-muted); font-size:0.8rem;">Merges identical CDN streams from multiple providers into a single card with combined tags.</div>
          </div>
        </label>

        <label style="display:flex; align-items:center; gap:10px; cursor:pointer;">
          <input type="checkbox" id="chkDeadLink" $deadLinkChecked style="width:18px; height:18px;">
          <div>
            <strong style="color:var(--text);">Ultra-Fast Dead-Link Filter</strong>
            <div style="color:var(--text-muted); font-size:0.8rem;">Runs a rapid 1200ms parallel HEAD probe on direct stream links to eliminate 404/broken file hosters.</div>
          </div>
        </label>

        <label style="display:flex; align-items:center; gap:10px; cursor:pointer;">
          <input type="checkbox" id="chkOpenSubtitles" $enableOpenSubtitlesChecked style="width:18px; height:18px;">
          <div>
            <strong style="color:var(--text);">Direct OpenSubtitles v3 Subtitles</strong>
            <div style="color:var(--text-muted); font-size:0.8rem;">Injects matched multilingual subtitles directly via OpenSubtitles REST API without registration.</div>
          </div>
        </label>
      </div>
    </div>

    <!-- Metadata & Artwork API Integrations -->
    <div class="card">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 14px; flex-wrap:wrap; gap:8px;">
        <h2>🎨 Metadata & Artwork API Integrations (OMDb, Fanart, TVDB)</h2>
        <button class="btn btn-primary" onclick="saveSettings()">💾 Save API Keys</button>
      </div>
      <p style="color:var(--text-muted); margin-bottom:16px; font-size:0.9rem;">
        Elevate Nuvio and Stremio with crystal-clear transparent ClearLogos, 4K banners, live Rotten Tomatoes/IMDb ratings, and anime absolute episode mappings. <strong>All keys are 100% optional</strong> — built-in zero-key public fallbacks (Cinemeta, Metahub, TVMaze) operate out of the box!
      </p>

      <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(300px, 1fr)); gap:16px;">
        <!-- OMDb API Key -->
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px; display:flex; flex-direction:column; justify-content:space-between; gap:10px;">
          <div>
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
              <label style="font-weight:600;">⭐ OMDb API Key <span style="font-weight:normal; font-size:0.8rem; color:#3fb950;">(Optional)</span>:</label>
              <a href="https://www.omdbapi.com/apikey.aspx" target="_blank" style="color:var(--blue); font-size:0.8rem; text-decoration:none; font-weight:600;">🔗 Get Free Key ↗</a>
            </div>
            <input type="text" id="omdbApiKey" value="$omdbApiKey" placeholder="Pre-configured fallback key active" style="width:100%; padding:8px; background:#161b22; border:1px solid var(--border); border-radius:6px; color:var(--text); font-size:0.88rem;">
            <div style="color:var(--text-muted); font-size:0.78rem; margin-top:6px;">Instant 1-min free signup for live IMDb ratings, RT tomatometer, and Metascores. Falls back to Cinemeta if empty.</div>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center; border-top:1px solid var(--border); padding-top:8px;">
            <button class="btn" style="padding:4px 10px; font-size:0.8rem;" onclick="testKey('omdb', 'omdbApiKey', 'omdbBadge')">🔍 Test Key</button>
            <span id="omdbBadge" class="badge" style="background:#21262d; font-size:0.75rem;">Ready</span>
          </div>
        </div>

        <!-- Fanart.tv API Key -->
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px; display:flex; flex-direction:column; justify-content:space-between; gap:10px;">
          <div>
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
              <label style="font-weight:600;">✨ Fanart.tv Key <span style="font-weight:normal; font-size:0.8rem; color:#3fb950;">(Optional)</span>:</label>
              <a href="https://fanart.tv/get-an-api-key/" target="_blank" style="color:var(--blue); font-size:0.8rem; text-decoration:none; font-weight:600;">🔗 Get Key ↗</a>
            </div>
            <input type="text" id="fanartApiKey" value="$fanartApiKey" placeholder="Leave empty for Metahub ClearLogos" style="width:100%; padding:8px; background:#161b22; border:1px solid var(--border); border-radius:6px; color:var(--text); font-size:0.88rem;">
            <div style="color:var(--text-muted); font-size:0.78rem; margin-top:6px;">Transparent PNG ClearLogos & 4K backdrops for Nuvio. Automatically falls back to Metahub CDN with zero keys.</div>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center; border-top:1px solid var(--border); padding-top:8px;">
            <button class="btn" style="padding:4px 10px; font-size:0.8rem;" onclick="testKey('fanart', 'fanartApiKey', 'fanartBadge')">🔍 Test Key</button>
            <span id="fanartBadge" class="badge" style="background:#21262d; font-size:0.75rem;">Ready</span>
          </div>
        </div>

        <!-- TheTVDB API Key -->
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px; display:flex; flex-direction:column; justify-content:space-between; gap:10px;">
          <div>
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
              <label style="font-weight:600;">📺 TheTVDB Key <span style="font-weight:normal; font-size:0.8rem; color:#3fb950;">(Optional)</span>:</label>
              <a href="https://thetvdb.com/dashboard/account/apikeys" target="_blank" style="color:var(--blue); font-size:0.8rem; text-decoration:none; font-weight:600;">🔗 Get Key ↗</a>
            </div>
            <input type="text" id="tvdbApiKey" value="$tvdbApiKey" placeholder="Leave empty for Cinemeta & TVMaze" style="width:100%; padding:8px; background:#161b22; border:1px solid var(--border); border-radius:6px; color:var(--text); font-size:0.88rem;">
            <div style="color:var(--text-muted); font-size:0.78rem; margin-top:6px;">Maps absolute anime episode numbers & titles. Automatically falls back to Cinemeta & TVMaze with zero keys.</div>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center; border-top:1px solid var(--border); padding-top:8px;">
            <button class="btn" style="padding:4px 10px; font-size:0.8rem;" onclick="testKey('tvdb', 'tvdbApiKey', 'tvdbBadge')">🔍 Test Key</button>
            <span id="tvdbBadge" class="badge" style="background:#21262d; font-size:0.75rem;">Ready</span>
          </div>
        </div>

        <!-- TMDB API Key -->
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px; display:flex; flex-direction:column; justify-content:space-between; gap:10px;">
          <div>
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
              <label style="font-weight:600;">🎬 TMDB Key <span style="font-weight:normal; font-size:0.8rem; color:#3fb950;">(Optional)</span>:</label>
              <a href="https://www.themoviedb.org/settings/api" target="_blank" style="color:var(--blue); font-size:0.8rem; text-decoration:none; font-weight:600;">🔗 Get Key ↗</a>
            </div>
            <input type="text" id="tmdbApiKey" value="$tmdbApiKey" placeholder="Pre-configured fallback key active" style="width:100%; padding:8px; background:#161b22; border:1px solid var(--border); border-radius:6px; color:var(--text); font-size:0.88rem;">
            <div style="color:var(--text-muted); font-size:0.78rem; margin-top:6px;">Custom TMDB searches. Automatically falls back to Speedracelight proxy and Cinemeta with zero keys.</div>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center; border-top:1px solid var(--border); padding-top:8px;">
            <button class="btn" style="padding:4px 10px; font-size:0.8rem;" onclick="testKey('tmdb', 'tmdbApiKey', 'tmdbBadge')">🔍 Test Key</button>
            <span id="tmdbBadge" class="badge" style="background:#21262d; font-size:0.75rem;">Ready</span>
          </div>
        </div>

        <!-- DoesTheDogDie (DTDD) API Key -->
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px; display:flex; flex-direction:column; justify-content:space-between; gap:10px;">
          <div>
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
              <label style="font-weight:600;">🐶 DoesTheDogDie Key <span style="font-weight:normal; font-size:0.8rem; color:#3fb950;">(Optional)</span>:</label>
              <a href="https://www.doesthedogdie.com/profile" target="_blank" style="color:var(--blue); font-size:0.8rem; text-decoration:none; font-weight:600;">🔗 Get Free Key ↗</a>
            </div>
            <input type="text" id="dtddApiKey" value="$dtddApiKey" placeholder="Paste DoesTheDogDie API key (free)" style="width:100%; padding:8px; background:#161b22; border:1px solid var(--border); border-radius:6px; color:var(--text); font-size:0.88rem;">
            <div style="color:var(--text-muted); font-size:0.78rem; margin-top:6px;">Enables community content warnings &amp; trigger advisories (e.g. animal death, jumpscares) in media modal.</div>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center; border-top:1px solid var(--border); padding-top:8px;">
            <button class="btn" style="padding:4px 10px; font-size:0.8rem;" onclick="testKey('dtdd', 'dtddApiKey', 'dtddBadge')">🔍 Test Key</button>
            <span id="dtddBadge" class="badge" style="background:#21262d; font-size:0.75rem;">Ready</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Scraper Providers -->
    <div class="card">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 14px; flex-wrap:wrap; gap:8px;">
        <h2>📦 HTTP Scraper Providers (<span id="enabledCount">$enabledCount</span>/${providers.length} Active)</h2>
        <div style="display:flex; gap:8px;">
          <button class="btn" onclick="bulkToggle(true)">Enable All</button>
          <button class="btn" onclick="bulkToggle(false)">Disable All</button>
          <button class="btn" style="background:#1f6feb; border-color:#388bfd;" onclick="resetScrapers()">🔄 Reset Circuit Breaker</button>
        </div>
      </div>
      <!-- Instant Search Filter & Quick Chips -->
      <div style="display:flex; flex-direction:column; gap:8px; margin-bottom:14px;">
        <div style="display:flex; gap:10px; align-items:center;">
          <input type="text" id="providerSearchInput" placeholder="🔍 Search 56 providers (e.g. hubcloud, 4k, regional, anime, hls, bollyflix)..." oninput="filterProvidersList()" style="flex:1; padding:8px 12px; background:#090d13; border:1px solid var(--border); border-radius:6px; color:var(--text); font-size:0.88rem;">
          <span id="providerFilteredCount" style="font-size:0.82rem; color:var(--text-muted); white-space:nowrap;">Showing ${providers.length} of ${providers.length}</span>
        </div>
        <div style="display:flex; gap:6px; flex-wrap:wrap; align-items:center;" id="providerFilterChips">
          <span style="font-size:0.75rem; color:var(--text-muted); margin-right:4px;">Filter by:</span>
          <button type="button" class="stream-filter-chip active" onclick="setProviderFilter('', this)">All (${providers.length})</button>
          <button type="button" class="stream-filter-chip" onclick="setProviderFilter('regional', this)">🇮🇳 Indian Regional (8)</button>
          <button type="button" class="stream-filter-chip" onclick="setProviderFilter('anime', this)">⛩️ Anime & Asian (6)</button>
          <button type="button" class="stream-filter-chip" onclick="setProviderFilter('global', this)">🌐 Global (42)</button>
          <button type="button" class="stream-filter-chip" onclick="setProviderFilter('4k', this)">💎 4K UHD</button>
          <button type="button" class="stream-filter-chip" onclick="setProviderFilter('extractor', this)">☁️ Cloud Extractors</button>
          <button type="button" class="stream-filter-chip" onclick="setProviderFilter('hls', this)">⚡ Fast HLS</button>
        </div>
      </div>
      <div class="grid" id="providersGrid">
        $providerCheckboxes
      </div>
    </div>

    <!-- Multi-Source Unified Update Hub -->
    <div class="card" id="updateHubCard">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; flex-wrap:wrap; gap:10px;">
        <h2>🔄 Multi-Source Unified Update Hub</h2>
        <span class="update-pill" style="background:#238636; color:#fff; font-size:0.82rem; padding:4px 10px;">${providers.length} Total Active Providers</span>
      </div>
      <p style="color:var(--text-muted); margin-bottom:16px;">
        Manage and synchronize your ${providers.length} aggregated providers across PlayTorrio base framework, Cloudstream community plugins &amp; extractors, Indian regional OTTs, Anime scrapers, and official binary releases.
      </p>

      <div class="update-grid">
        <!-- 1. App Releases & Core Binaries -->
        <div class="update-subcard">
          <div class="update-subcard-header">
            <div>
              <div class="update-subcard-title">📦 Hostreamio Releases</div>
              <div class="update-subcard-desc">Official desktop and Android binaries with all scrapers, extractors &amp; TorBox debrid built-in.</div>
            </div>
            <span class="update-pill" style="background:#238636; color:#fff;" id="appVersionBadge">v2.0.0 Current</span>
          </div>
          <div class="update-downloads-bar">
            <a href="https://github.com/sakinator/hostreamio/releases/latest/download/hostreamio-windows-x64.zip" class="btn btn-sm btn-outline" id="dlWinZip" target="_blank">🪟 Windows (.zip)</a>
            <a href="https://github.com/sakinator/hostreamio/releases/latest/download/hostreamio.apk" class="btn btn-sm btn-outline" id="dlAndroidApk" target="_blank">📱 Android (.apk)</a>
            <a href="https://github.com/sakinator/hostreamio/releases" class="btn btn-sm btn-outline" target="_blank">📜 All Releases</a>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center; margin-top:6px;">
            <span id="releaseCheckInfo" style="font-size:0.8rem; color:var(--text-muted);">Release sync ready</span>
            <button class="btn btn-sm" id="btnCheckRelease" onclick="checkGitHubReleases()">🔍 Check Release</button>
          </div>
        </div>

        <!-- 2. Cloudstream Community Addons -->
        <div class="update-subcard">
          <div class="update-subcard-header">
            <div>
              <div class="update-subcard-title">☁️ Cloudstream Community Addons</div>
              <div class="update-subcard-desc">Extractors &amp; resolvers for HubCloud, Vega, DriveSeed, Pixeldrain, Mega, 1fichier, Rapidgator, and direct hosters.</div>
            </div>
            <span class="update-pill" style="background:#1f6feb; color:#fff;">Plugins &amp; Resolvers</span>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center; margin-top:6px;">
            <div style="font-size:0.8rem; color:var(--text-muted);">Module: <code>services/cloudstream</code></div>
            <button class="btn btn-sm btn-success" id="btnUpdateCloudstream" onclick="triggerUpdateChannel('cloudstream')">⚡ Update Cloudstream</button>
          </div>
        </div>

        <!-- 3. PlayTorrioV3 Base Architecture -->
        <div class="update-subcard">
          <div class="update-subcard-header">
            <div>
              <div class="update-subcard-title">🔄 PlayTorrioV3 Base Architecture</div>
              <div class="update-subcard-desc">Core PlayTorrio scraping pipeline and global providers (Vidsrc, Lookmovie, Vidlink, MultiEmbed, etc.).</div>
            </div>
            <span class="update-pill" style="background:#8957e5; color:#fff;">Base Framework</span>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center; margin-top:6px;">
            <div style="font-size:0.8rem; color:var(--text-muted);">
              Upstream: <a href="https://github.com/ayman708-UX/PlayTorrioV3" target="_blank" style="color:var(--blue); text-decoration:none;">ayman708-UX/PlayTorrioV3</a>
            </div>
            <button class="btn btn-sm btn-success" id="btnUpdatePlayTorrio" onclick="triggerUpdateChannel('playtorrio')">⚡ Sync PlayTorrio Base</button>
          </div>
        </div>

        <!-- 4. Indian OTT & Regional Scrapers -->
        <div class="update-subcard">
          <div class="update-subcard-header">
            <div>
              <div class="update-subcard-title">🇮🇳 Indian OTT &amp; Anime Scrapers</div>
              <div class="update-subcard-desc">Bollyflix, Vegamovies, HDHub4u, HindMoviez, Playdesi, Yomovies, 4kHDHub, AnimePahe, GogoAnime, HiAnime, KissKH, Vadapav.</div>
            </div>
            <span class="update-pill" style="background:#f0883e; color:#000; font-weight:700;">Regional &amp; Anime</span>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center; margin-top:6px;">
            <div style="font-size:0.8rem; color:var(--text-muted);">Directory: <code>scraper/sites/</code></div>
            <button class="btn btn-sm btn-success" id="btnUpdateScrapers" onclick="triggerUpdateChannel('scrapers')">⚡ Sync Regional Scrapers</button>
          </div>
        </div>

        <!-- 5. Badges & Regional OTT Logos -->
        <div class="update-subcard">
          <div class="update-subcard-header">
            <div>
              <div class="update-subcard-title">🏷️ Nuvio Badges &amp; Regional OTT Logos</div>
              <div class="update-subcard-desc">Hot-reloads Netflix, Prime, Hotstar, JioCinema, SonyLIV, Zee5, Aha, SunNXT, Hoichoi, and multi-audio tags.</div>
            </div>
            <span class="update-pill" style="background:#d29922; color:#000;">Hot-Reload</span>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center; margin-top:6px;">
            <div style="font-size:0.8rem; color:var(--text-muted);">Source: <code>data/badges.json</code></div>
            <button class="btn btn-sm btn-success" id="btnUpdateBadges" onclick="triggerUpdateChannel('badges')">⚡ Reload Badges</button>
          </div>
        </div>
      </div>

      <!-- Master Full Update Action -->
      <div style="margin-top:16px; padding-top:14px; border-top:1px solid var(--border); display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:12px;">
        <div style="font-size:0.86rem; color:var(--text-muted);">
          Syncs git repository, Cloudstream resolvers, PlayTorrio base, regional scrapers, regenerates registry, and refreshes memory caches.
        </div>
        <button class="btn btn-success" id="btnMasterUpdate" onclick="triggerUpdateChannel('all')" style="padding:9px 18px; font-weight:600; font-size:0.92rem;">
          ⚡ Run Full Update Pipeline (All 56 Providers &amp; Sources)
        </button>
      </div>

      <!-- Live Terminal Output Console -->
      <div id="pipelineConsoleBox" style="margin-top:16px;">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
          <span style="font-size:0.82rem; color:var(--text); font-weight:700; text-transform:uppercase; letter-spacing:0.5px;">📡 Update Pipeline Console &amp; Status</span>
          <span id="pipelineConsoleBadge" class="update-pill" style="font-size:0.75rem; background:#238636; color:#fff;">Idle (Ready)</span>
        </div>
        <pre id="pipelineConsole" style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:12px 14px; font-family:monospace; font-size:0.82rem; color:#8b949e; max-height:220px; overflow-y:auto; white-space:pre-wrap; margin:0;">[Ready] Multi-Source Unified Update Hub online. Select any channel above or click "Run Full Update Pipeline" to sync providers and binaries.</pre>
      </div>
    </div>
  </div> <!-- End of tabContentServer -->

  <!-- TAB 2: SEARCH & STREAM THEATER -->
  <div id="tabContentSearch" style="display:none;">
    <!-- Cloud Debrid & Cache Philosophy Banner -->
    <div style="background: rgba(25, 95, 235, 0.08); border: 1px solid rgba(88, 166, 255, 0.25); border-radius: 12px; padding: 14px 18px; margin-bottom: 16px; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 12px;">
      <div style="font-size: 0.86rem; color: var(--text); line-height: 1.5;">
        <strong style="color: var(--blue);">💡 Dual-Rail Stream Philosophy:</strong>
        <span style="color: var(--text-muted); margin-left: 6px;">
          <span style="color:#3fb950; font-weight:600;">⚡ TorBox [Cached]</span>: Stream from high-speed TorBox CDN instantly.
          • <span style="color:#58a6ff; font-weight:600;">☁️⬆️ TorBox [Start Caching]</span>: Caches link in cloud; plays direct immediately without waiting!
          • <span style="color:#f0883e; font-weight:600;">🌐 Direct Play</span>: Plays direct hoster/HLS link without TorBox requirement.
        </span>
      </div>
      <button class="btn btn-sm" onclick="switchMainTab('server')" style="font-size: 0.8rem; white-space:nowrap;">⚙️ Configure TorBox</button>
    </div>

    <!-- ═══════════════════ SEARCH & STREAM THEATER ═══════════════════ -->
    <div class="card" id="searchTheaterCard" style="margin-bottom:16px;">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; flex-wrap:wrap; gap:8px;">
        <h2>🎬 Search &amp; Stream Theater</h2>
        <div style="display:flex; gap:6px;">
          <span class="badge" style="background:rgba(255,12,130,0.15); color:var(--accent); border:1px solid rgba(255,12,130,0.3); font-size:0.78rem;">▶ Web Mode</span>
          <span class="badge" style="background:rgba(88,166,255,0.15); color:var(--blue); border:1px solid rgba(88,166,255,0.3); font-size:0.78rem;">🚀 Open With (VLC / PotPlayer / MPV)</span>
        </div>
      </div>
      <p style="color:var(--text-muted); font-size:0.86rem; margin-bottom:14px;">
        Search any movie or TV series across all ${providers.length} scrapers. Select seasons &amp; episodes, play in your browser via Web Mode, or launch directly in VLC, PotPlayer, MPV, or download universal .m3u playlist.
      </p>

      <div class="test-box" style="flex-wrap:wrap; gap:10px;">
        <select id="theaterMediaType" onchange="toggleSeasonEpisodeInputs()" style="padding:10px 14px; background:#090d13; border:1px solid var(--border); border-radius:6px; color:var(--text); font-weight:600;">
          <option value="movie">🎬 Movie</option>
          <option value="series">📺 Series</option>
        </select>
        <input class="test-input" id="theaterSearchQuery" placeholder="Search by title (e.g. Inception, Mirzapur, KGF) or IMDb ID (tt1375666)..." value="tt1375666" style="flex:2; min-width:260px;" onkeydown="if(event.key==='Enter') executeTheaterSearch()">
        <div id="seriesInputsRow" style="display:none; align-items:center; gap:8px;">
          <label style="font-size:0.85rem; color:var(--text-muted);">S:</label>
          <input type="number" id="theaterSeason" value="1" min="1" style="width:55px; padding:10px 8px; background:#090d13; border:1px solid var(--border); border-radius:6px; color:var(--text); text-align:center;">
          <label style="font-size:0.85rem; color:var(--text-muted);">E:</label>
          <input type="number" id="theaterEpisode" value="1" min="1" style="width:55px; padding:10px 8px; background:#090d13; border:1px solid var(--border); border-radius:6px; color:var(--text); text-align:center;">
        </div>
        <button class="btn btn-primary" id="btnTheaterSearch" onclick="executeTheaterSearch()" style="padding:10px 18px; font-weight:700;">🔍 Search &amp; Scrape</button>
      </div>

      <!-- Live Search Suggestions Container -->
      <div id="searchSuggestionsContainer" style="display:none;"></div>

      <!-- Active Media Header Info Card -->
      <div id="activeMediaContainer" style="display:none;"></div>

      <!-- Native Series Catalog & Episode Browser -->
      <div id="seriesCatalogContainer" style="display:none;"></div>

      <!-- Scraped Stream Results -->
      <div id="testResults"></div>
    </div>
  </div> <!-- End of tabContentSearch -->

  <!-- TAB 3: CINEMA & SERIES CATALOGS -->
  <div id="tabContentStreaming" style="display:none;">
    <!-- ═══════════════════ CATALOG BROWSER ═══════════════════ -->
    <div class="card" id="catalogBrowserCard" style="margin-bottom:16px;">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:14px; flex-wrap:wrap; gap:8px;">
        <h2 style="margin:0;">🗂️ Browse Catalogs</h2>
        <span style="font-size:0.78rem; color:var(--text-muted);">Click any title to instantly load streams ↓</span>
      </div>

      <!-- Catalog Sub-Tabs -->
      <div id="catalogTabNav" style="display:flex; flex-wrap:wrap; gap:6px; margin-bottom:14px; padding-bottom:12px; border-bottom:1px solid var(--border);">
        <button class="stream-filter-chip active" id="ctab-trending-movie" onclick="switchCatalogTab('trending-movie')">🔥 Trending Movies</button>
        <button class="stream-filter-chip" id="ctab-trending-series" onclick="switchCatalogTab('trending-series')">📺 Trending Series</button>
        <button class="stream-filter-chip" id="ctab-yt_indian" onclick="switchCatalogTab('yt_indian')">🎬 YouTube Indian</button>
        <button class="stream-filter-chip" id="ctab-yt_international" onclick="switchCatalogTab('yt_international')">🌍 YouTube Intl</button>
        <button class="stream-filter-chip" id="ctab-vimeo_picks" onclick="switchCatalogTab('vimeo_picks')">🎥 Vimeo</button>
        <button class="stream-filter-chip" id="ctab-archive_movies" onclick="switchCatalogTab('archive_movies')">🏛️ Archive</button>
        <button class="stream-filter-chip" id="ctab-dm_movies" onclick="switchCatalogTab('dm_movies')">📺 Dailymotion</button>
      </div>

      <!-- Genre Filter Row (visible for applicable tabs) -->
      <div id="catalogGenreRow" style="display:none; flex-wrap:wrap; gap:6px; margin-bottom:12px;"></div>

      <!-- Catalog Grid -->
      <div id="catalogGrid" style="display:grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap:12px; min-height:180px;">
        <div style="grid-column:1/-1; color:var(--text-muted); text-align:center; padding:40px 0; font-size:0.9rem;">⏳ Loading catalog…</div>
      </div>

      <!-- Load More -->
      <div style="text-align:center; margin-top:14px;">
        <button class="btn btn-sm" id="btnCatalogLoadMore" onclick="loadMoreCatalog()" style="display:none;">⬇️ Load More</button>
      </div>
    </div>
  </div> <!-- End of tabContentStreaming -->

  <!-- TAB 3: LIVE IPTV BROADCASTS -->
  <div id="tabContentIptv" style="display:none;">
    <div class="card" style="margin-bottom:16px;">
      <div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; margin-bottom:14px;">
        <div>
          <h2 style="margin:0;">📺 Global Live IPTV &amp; Electronic Program Guide (EPG)</h2>
          <p style="margin:4px 0 0 0; font-size:0.85rem; color:var(--text-muted);">
            Over 8,000+ free live television channels aggregated from IPTV-org. Zero peer dependency, 100% direct HTTP/HLS streaming.
          </p>
        </div>
        <span class="badge" id="iptvChannelCountBadge" style="background:rgba(63, 185, 80, 0.15); color:#3fb950; border:1px solid rgba(63, 185, 80, 0.3); font-size:0.8rem; padding:4px 10px;">
          8,000+ Channels Ready
        </span>
      </div>

      <!-- IPTV Filter Bar -->
      <div style="display:flex; gap:10px; flex-wrap:wrap; align-items:center; margin-bottom:14px;">
        <input type="text" id="iptvSearchInput" placeholder="🔍 Search channels by name or language (e.g. BBC, NASA, Aaj Tak, Bloomberg)..." oninput="filterIptvChannels()" style="flex:1; min-width:240px; padding:10px 14px; background:#090d13; border:1px solid var(--border); border-radius:6px; color:var(--text); font-size:0.88rem;">
        <select id="iptvCountryFilter" onchange="filterIptvChannels()" style="padding:10px 14px; background:#090d13; border:1px solid var(--border); border-radius:6px; color:var(--text); font-size:0.88rem;">
          <option value="All">🌍 All Countries</option>
          <option value="US">🇺🇸 United States</option>
          <option value="IN">🇮🇳 India</option>
          <option value="UK">🇬🇧 United Kingdom</option>
          <option value="CA">🇨🇦 Canada</option>
          <option value="DE">🇩🇪 Germany</option>
          <option value="FR">🇫🇷 France</option>
          <option value="JP">🇯🇵 Japan</option>
          <option value="AU">🇦🇺 Australia</option>
          <option value="IT">🇮🇹 Italy</option>
          <option value="ES">🇪🇸 Spain</option>
          <option value="BR">🇧🇷 Brazil</option>
        </select>
      </div>

      <!-- Category Filter Chips -->
      <div style="display:flex; gap:6px; flex-wrap:wrap; margin-bottom:16px;">
        <button class="stream-filter-chip active" id="iptv-cat-all" onclick="selectIptvCategory('All')">🌐 All</button>
        <button class="stream-filter-chip" id="iptv-cat-news" onclick="selectIptvCategory('News')">📰 News</button>
        <button class="stream-filter-chip" id="iptv-cat-general" onclick="selectIptvCategory('General')">📺 General</button>
        <button class="stream-filter-chip" id="iptv-cat-movies" onclick="selectIptvCategory('Movies')">🎬 Movies</button>
        <button class="stream-filter-chip" id="iptv-cat-series" onclick="selectIptvCategory('Series')">🍿 Series</button>
        <button class="stream-filter-chip" id="iptv-cat-sports" onclick="selectIptvCategory('Sports')">⚽ Sports</button>
        <button class="stream-filter-chip" id="iptv-cat-music" onclick="selectIptvCategory('Music')">🎵 Music</button>
        <button class="stream-filter-chip" id="iptv-cat-animation" onclick="selectIptvCategory('Animation')">✨ Animation</button>
        <button class="stream-filter-chip" id="iptv-cat-documentary" onclick="selectIptvCategory('Documentary')">🌿 Documentary</button>
        <button class="stream-filter-chip" id="iptv-cat-kids" onclick="selectIptvCategory('Kids')">👶 Kids</button>
      </div>

      <!-- Channels Grid -->
      <div id="iptvGrid" style="display:grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap:12px; min-height:200px;">
        <div style="grid-column:1/-1; color:var(--text-muted); text-align:center; padding:40px 0; font-size:0.9rem;">⏳ Loading live IPTV broadcasts…</div>
      </div>

      <!-- Load More IPTV -->
      <div style="text-align:center; margin-top:16px;">
        <button class="btn btn-sm" id="btnIptvLoadMore" onclick="loadMoreIptv()" style="display:none;">⬇️ Load More Channels</button>
      </div>
    </div>
  </div> <!-- End of tabContentIptv -->

  <!-- TAB 4: TORBOX CLOUD CACHING QUEUE -->
  <div id="tabContentCaching" style="display:none;">
    <div class="card" style="margin-bottom:16px;">
      <div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; margin-bottom:16px;">
        <div>
          <h2 style="margin:0; display:flex; align-items:center; gap:8px;">
            <span>⚡ TorBox Cloud Caching Queue</span>
            <span id="queueItemsCountBadge" class="badge" style="background:rgba(255, 12, 130, 0.15); color:#ff0c82; border:1px solid rgba(255, 12, 130, 0.3); font-size:0.8rem; padding:3px 8px;">0 Downloads</span>
          </h2>
          <p style="margin:4px 0 0 0; font-size:0.85rem; color:var(--text-muted);">
            Real-time status of hoster streams &amp; torrents currently downloading to high-speed cloud CDN. Stream instantly once completed.
          </p>
        </div>
        <div style="display:flex; align-items:center; gap:10px;">
          <label style="display:flex; align-items:center; gap:6px; font-size:0.82rem; color:var(--text); cursor:pointer;">
            <input type="checkbox" id="queueAutoPoll" checked onchange="toggleQueueAutoPoll(this.checked)">
            <span>Live Polling (3s)</span>
          </label>
          <button class="btn btn-sm" onclick="loadCacheQueue(true)" title="Force Refresh Queue">🔄 Refresh</button>
        </div>
      </div>

      <!-- Quick Upload Input inside Caching Tab -->
      <div class="url-box" style="margin-bottom:14px;">
        <input class="url-input" id="cachingTabUploadUrl" placeholder="Paste any stream or cloud link (HubCloud, PixelDrain, GoFile, etc.) to start caching...">
        <button class="btn btn-success" onclick="uploadLinkFromCachingTab()">☁️⬆️ Start Caching</button>
      </div>

      <!-- Queue Filter Toggle Bar -->
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:14px; flex-wrap:wrap; gap:10px;">
        <div style="display:flex; gap:6px; background:#161b22; padding:3px; border-radius:8px; border:1px solid var(--border);">
          <button id="btnFilterHostreamio" class="btn btn-sm btn-primary" onclick="setCacheQueueFilter('hostreamio')">⚡ Hostreamio Caches (<span id="queueHostreamioCount">0</span>)</button>
          <button id="btnFilterAll" class="btn btn-sm" style="background:transparent; border:none; color:var(--text-muted);" onclick="setCacheQueueFilter('all')">🌐 All TorBox Cloud (<span id="queueAllCount">0</span>)</button>
        </div>
        <div style="font-size:0.8rem; color:var(--text-muted);">
          <span>Showing: <strong id="queueCurrentFilterLabel" style="color:#58a6ff;">Hostreamio Initiated</strong></span>
        </div>
      </div>

      <!-- Queue Items Container -->
      <div id="cacheQueueContainer" style="display:flex; flex-direction:column; gap:12px; min-height:160px;">
        <div style="text-align:center; padding:40px 20px; color:var(--text-muted);">
          <div style="font-size:2.5rem; margin-bottom:10px;">⚡</div>
          <strong style="color:var(--text); font-size:1.05rem;">Cache Queue is Empty</strong>
          <p style="font-size:0.85rem; max-width:480px; margin:8px auto 0 auto; line-height:1.5;">
            When you click <strong>"Cache to TorBox"</strong> on an uncached stream, or attempt to stream an uncached link, it will appear here with live progress, speed, ETA, and 1-tap playback controls.
          </p>
        </div>
      </div>
    </div>
  </div> <!-- End of tabContentCaching -->

  <!-- TAB 5: ABOUT & SYSTEM DIAGNOSTICS -->
  <div id="tabContentAbout" style="display:none;">
    <header>
      <div class="brand-logo-wrap">
        <img src="/logo.png" alt="Hostreamio" class="brand-logo" />
      </div>
      <h1>Hostreamio</h1>
      <p class="subtitle">Direct Hosters • Streaming Links • TorBox Cloud Debrid • Smart Proxy • Instant Badges</p>
    </header>

    <!-- Architecture & Engine Status Pills -->
    <div class="status-banner">
      <div class="status-chip"><span class="status-dot"></span> <strong>DNS-over-HTTPS:</strong> Cloudflare &amp; Google Fallback (Active)</div>
      <div class="status-chip"><span class="status-dot"></span> <strong>HLS Segment Cache:</strong> 35MB RAM Ring Buffer (Active)</div>
      <div class="status-chip"><span class="status-dot"></span> <strong>DASH to HLS:</strong> Virtual Transmuxer Ready</div>
      <div class="status-chip"><span class="status-dot"></span> <strong>Circuit Breaker:</strong> Monitored Scrapers Active</div>
      <div class="status-chip"><span class="status-dot"></span> <strong>Prowlarr Captcha:</strong> FlareSolverr Ready</div>
    </div>

    <!-- Community Attributions & Open Source Credits Card -->
    <div class="card" style="margin-top: 20px;">
      <h2>🌟 Community Attributions &amp; Open Source Credits</h2>
      <p style="color:var(--text-muted); font-size:0.88rem; margin-bottom:16px; line-height:1.5;">
        Hostreamio stands on the shoulders of giants. We gratefully acknowledge and credit the following pioneering open source developers, communities, and services:
      </p>
      <div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap:12px;">
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px;">
          <strong style="color:#79c0ff; font-size:0.95rem;">Nuvio Streaming App</strong>
          <div style="font-size:0.8rem; color:var(--text-muted); margin-top:4px;">Next-generation streaming client whose native badge system, sleek layout, and debrid philosophy inspired Hostreamio&apos;s UI &amp; stream architecture.</div>
        </div>
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px;">
          <strong style="color:#a371f7; font-size:0.95rem;">Cloudstream (recloudstream)</strong>
          <div style="font-size:0.8rem; color:var(--text-muted); margin-top:4px;">Pioneering open modular scraping framework and multi-provider cloud resolvers that inspired Hostreamio&apos;s direct hoster extractors.</div>
        </div>
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px;">
          <strong style="color:var(--blue); font-size:0.95rem;">PlayTorrio (ayman708-UX)</strong>
          <div style="font-size:0.8rem; color:var(--text-muted); margin-top:4px;">Original base Dart scraper architecture, StreamSource models, Knaben aggregator &amp; TorrentGalaxy scrapers.</div>
        </div>
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px;">
          <strong style="color:#ff69b4; font-size:0.95rem;">Nyaa.si &amp; Tokyo Toshokan</strong>
          <div style="font-size:0.8rem; color:var(--text-muted); margin-top:4px;">Global anime, Asian live-action drama &amp; OST community metadata, indexing, and RSS feeds.</div>
        </div>
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px;">
          <strong style="color:#3fb950; font-size:0.95rem;">1TamilMV &amp; TamilBlasters Community</strong>
          <div style="font-size:0.8rem; color:var(--text-muted); margin-top:4px;">Premier regional Indian entertainment trackers for Hindi, Tamil, Telugu, Malayalam, and Kannada releases.</div>
        </div>
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px;">
          <strong style="color:#f55014; font-size:0.95rem;">YTS.mx &amp; EZTV APIs</strong>
          <div style="font-size:0.8rem; color:var(--text-muted); margin-top:4px;">Public community APIs for high-efficiency movie releases and global television series episodes.</div>
        </div>
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px;">
          <strong style="color:#58a6ff; font-size:0.95rem;">IPTV-org Community</strong>
          <div style="font-size:0.8rem; color:var(--text-muted); margin-top:4px;">Public domain worldwide live television broadcasts, logos, categories, and electronic program guides.</div>
        </div>
        <div style="background:#090d13; border:1px solid var(--border); border-radius:8px; padding:14px;">
          <strong style="color:#e3b341; font-size:0.95rem;">OpenSubtitles.org v3 API</strong>
          <div style="font-size:0.8rem; color:var(--text-muted); margin-top:4px;">Direct subtitle synchronization across 50+ languages without mandatory VIP registration.</div>
        </div>
      </div>
    </div>

    <!-- Legal & Vibe Coded Disclaimer Footer -->
    <div style="text-align:center; padding:24px 14px 14px; color:var(--text-muted); font-size:0.8rem; border-top:1px solid var(--border); margin-top:24px; line-height:1.6;">
      <div style="margin-bottom:8px;">
        <span style="display:inline-block; background:rgba(255,105,180,0.15); color:#ff69b4; border:1px solid rgba(255,105,180,0.3); border-radius:12px; padding:2px 10px; font-weight:600; font-size:0.75rem; letter-spacing:0.5px;">✨ 100% VIBE CODED WITH AI</span>
      </div>
      <strong>⚖️ GitHub &amp; Legal Disclaimer:</strong> The author does not own, host, upload, or broadcast any media or streams. Hostreamio acts solely as a local search indexer aggregating publicly available hyperlinks from third-party websites on the internet. All media is hosted by independent third-party services. Not affiliated with Stremio, Nuvio, TorBox, or any scraped source.
    </div>
  </div> <!-- End of tabContentAbout -->
  </main>
  </div> <!-- End of app-layout -->

  <!-- Inline Stream Player Modal -->
  <div id="playerModal" class="player-modal" onclick="closePlayerModal(event)">
    <div class="player-modal-content" onclick="event.stopPropagation()">
      <div class="player-header">
        <div style="display:flex; align-items:center; gap:10px; max-width:65%;">
          <span style="font-size:1.1rem;">▶️</span>
          <div class="player-title" id="playerStreamTitle">Stream Preview</div>
        </div>
        <div style="display:flex; align-items:center; gap:8px;">
          <select onchange="changePlayerSpeed(this.value)" style="background:#090d13; border:1px solid var(--border); border-radius:4px; color:var(--text); padding:3px 6px; font-size:0.75rem;">
            <option value="1">1x Speed</option>
            <option value="1.25">1.25x</option>
            <option value="1.5">1.5x</option>
            <option value="2">2x</option>
            <option value="0.75">0.75x</option>
          </select>
          <button class="btn btn-sm btn-open-with" onclick="openWithFromPlayer()" style="font-size:0.75rem; padding:3px 8px;">🚀 Open With...</button>
          <button class="player-close-btn" onclick="closePlayerModal()">✕</button>
        </div>
      </div>
      <div class="video-wrapper">
        <video id="previewVideoPlayer" controls playsinline></video>
      </div>
    </div>
  </div>

  <!-- Open With External Player Modal -->
  <div id="openWithModal" class="open-with-modal" onclick="closeOpenWithModal(event)">
    <div class="open-with-content" onclick="event.stopPropagation()">
      <div class="player-header">
        <div>
          <div class="player-title" id="openWithStreamTitle">🚀 Open Stream With...</div>
          <div style="font-size:0.78rem; color:var(--text-muted); margin-top:2px;" id="openWithStreamSub">Select your external media player</div>
        </div>
        <button class="player-close-btn" onclick="closeOpenWithModal()">✕</button>
      </div>
      <div class="player-opt-grid">
        <a class="player-opt-btn" id="openWithVlc" href="#">
          <span class="player-opt-icon">🟧</span>
          <div>
            <div>VLC Media Player</div>
            <div style="font-size:0.75rem; color:var(--text-muted);">Direct vlc:// protocol launch</div>
          </div>
        </a>
        <a class="player-opt-btn" id="openWithPotPlayer" href="#">
          <span class="player-opt-icon">🟨</span>
          <div>
            <div>PotPlayer</div>
            <div style="font-size:0.75rem; color:var(--text-muted);">potplayer:// direct protocol</div>
          </div>
        </a>
        <a class="player-opt-btn" id="openWithMpv" href="#">
          <span class="player-opt-icon">⬛</span>
          <div>
            <div>MPV Player</div>
            <div style="font-size:0.75rem; color:var(--text-muted);">mpv:// &amp; CLI copy command</div>
          </div>
        </a>
        <a class="player-opt-btn" id="openWithIina" href="#">
          <span class="player-opt-icon">🟦</span>
          <div>
            <div>IINA (macOS)</div>
            <div style="font-size:0.75rem; color:var(--text-muted);">iina://weblink protocol</div>
          </div>
        </a>
        <a class="player-opt-btn" id="openWithMobile" href="#">
          <span class="player-opt-icon">📱</span>
          <div>
            <div>Android / Mobile</div>
            <div style="font-size:0.75rem; color:var(--text-muted);">MX Player, Just Player, VLC Android</div>
          </div>
        </a>
        <div class="player-opt-btn" onclick="downloadM3uCurrentStream()">
          <span class="player-opt-icon">📥</span>
          <div>
            <div>Download .m3u Playlist</div>
            <div style="font-size:0.75rem; color:var(--text-muted);">Universal 1-click desktop launch</div>
          </div>
        </div>
        <div class="player-opt-btn" onclick="copyCurrentStreamUrl()">
          <span class="player-opt-icon">📋</span>
          <div>
            <div>Copy Stream Link</div>
            <div style="font-size:0.75rem; color:var(--text-muted);">Paste into any network player</div>
          </div>
        </div>
      </div>
      <div style="padding:12px 20px; background:#0d1117; border-top:1px solid var(--border); font-size:0.8rem; color:var(--text-muted); display:flex; justify-content:space-between; align-items:center;">
        <span id="openWithUrlPreview" style="font-family:monospace; max-width:400px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;"></span>
        <button class="btn btn-sm" onclick="closeOpenWithModal()">Cancel</button>
      </div>
    </div>
  </div>

  <!-- ═══════════════════ NUVIO-LIKE FULL EXPAND MEDIA MODAL ═══════════════════ -->
  <div id="mediaDetailModal" class="media-modal-backdrop" style="display:none;" onclick="handleModalBackdropClick(event)">
    <div class="media-modal-container" id="mediaDetailModalContainer" onclick="event.stopPropagation()">
      <button class="modal-close-btn" onclick="closeMediaDetailModal()" title="Close (Esc)">✕</button>

      <!-- Hero Backdrop Header -->
      <div class="modal-hero" id="modalHero">
        <div class="modal-hero-overlay"></div>
        <div class="modal-hero-content">
          <img id="modalPoster" class="modal-poster" src="/logo.png" alt="Poster" onerror="this.src='/logo.png'">
          <div class="modal-header-info">
            <div style="display:flex; gap:6px; align-items:center; flex-wrap:wrap; margin-bottom:6px;">
              <span id="modalTypeBadge" class="badge" style="background:#ff0c82; color:#fff; font-weight:700; font-size:0.75rem;">MOVIE</span>
              <span id="modalYearBadge" class="badge" style="background:#161b22; color:var(--text); font-size:0.75rem;"></span>
              <div id="modalRatingsContainer" style="display:inline-flex; gap:6px; flex-wrap:wrap; align-items:center;">
                <span id="modalRatingBadge" class="badge" style="background:rgba(227, 179, 65, 0.2); color:#e3b341; border:1px solid rgba(227, 179, 65, 0.4); font-size:0.75rem; font-weight:700;"></span>
              </div>
            </div>
            <h1 id="modalTitle" style="font-size:1.6rem; font-weight:800; color:#fff; line-height:1.2; margin:0 0 6px 0; text-shadow:0 2px 10px rgba(0,0,0,0.8);"></h1>
            <div id="modalGenres" style="display:flex; gap:6px; flex-wrap:wrap; margin-bottom:8px;"></div>
          </div>
        </div>
      </div>

      <!-- Modal Body -->
      <div style="padding:20px; display:flex; flex-direction:column; gap:16px;">
        <!-- Synopsis -->
        <div>
          <div style="font-size:0.8rem; font-weight:700; color:var(--text-muted); text-transform:uppercase; letter-spacing:0.5px; margin-bottom:4px;">Overview</div>
          <p id="modalOverview" style="font-size:0.88rem; color:var(--text); line-height:1.55; margin:0;"></p>
        </div>

        <!-- DoesTheDogDie Content Advisories & Trigger Warnings Card (Just after Overview) -->
        <div id="modalDtddCard" style="background:#0d1117; border:1px solid #30363d; border-radius:10px; overflow:hidden;">
          <div style="padding:10px 14px; display:flex; justify-content:space-between; align-items:center; cursor:pointer; background:#161b22; transition:background 0.2s;" onclick="toggleDtddExpand()">
            <div style="display:flex; align-items:center; gap:8px;">
              <span style="font-size:1.15rem;">🐶</span>
              <strong style="color:#fff; font-size:0.88rem;">DoesTheDogDie Content Advisories</strong>
              <span id="modalDtddSummaryBadge" class="badge" style="background:rgba(248,81,73,0.15); color:#f85149; border:1px solid rgba(248,81,73,0.3); font-size:0.72rem; display:none;"></span>
            </div>
            <div style="display:flex; align-items:center; gap:8px;">
              <a id="modalDtddLink" href="https://www.doesthedogdie.com" target="_blank" rel="noopener" onclick="event.stopPropagation()" style="font-size:0.78rem; color:#58a6ff; text-decoration:none; padding:3px 8px; background:rgba(88,166,255,0.1); border:1px solid rgba(88,166,255,0.25); border-radius:4px;">Visit doesthedogdie.com ↗</a>
              <button type="button" id="btnToggleDtdd" class="btn btn-sm" style="padding:3px 10px; font-size:0.75rem; background:#21262d;">▼ Expand</button>
            </div>
          </div>
          <!-- Expandable Panel -->
          <div id="modalDtddExpandable" style="display:none; padding:12px 14px; border-top:1px solid #21262d;">
            <div id="modalDtddLoading" style="font-size:0.8rem; color:var(--text-muted);">⏳ Checking community trigger warnings…</div>
            <div id="modalDtddContent" style="display:none;"></div>
          </div>
        </div>

        <!-- TV Series Seasons & Episodes Explorer (Hidden for movies) -->
        <div id="modalSeriesBrowser" style="display:none;">
          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px; flex-wrap:wrap; gap:8px;">
            <div style="font-weight:700; font-size:0.95rem; color:#fff;">📺 Seasons &amp; Episodes</div>
            <span id="modalSeasonsCount" style="font-size:0.8rem; color:var(--text-muted);"></span>
          </div>
          <!-- Season switcher pills -->
          <div class="modal-seasons-bar" id="modalSeasonTabs"></div>
          <!-- Episode Cards Grid -->
          <div class="modal-episodes-grid" id="modalEpisodesGrid"></div>
        </div>

        <!-- Action / Scraper Bar -->
        <div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; padding:12px 16px; background:#161b22; border:1px solid #30363d; border-radius:10px;">
          <div style="display:flex; align-items:center; gap:8px;">
            <span style="font-size:0.85rem; color:var(--text-muted);">Selection:</span>
            <strong id="modalSelectedMediaLabel" style="color:#58a6ff; font-size:0.9rem;"></strong>
          </div>
          <div style="display:flex; gap:8px;">
            <button class="btn btn-primary" id="btnModalScrape" onclick="triggerModalScrape()" style="padding:8px 16px; font-weight:700;">⚡ Scrape Sources</button>
            <button class="btn btn-sm" onclick="openCurrentInSearchTab()" style="font-size:0.82rem;">🔍 Open in Search Tab</button>
          </div>
        </div>

        <!-- Scraped Stream Results inside Modal -->
        <div>
          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px; flex-wrap:wrap; gap:8px;">
            <div style="font-weight:700; font-size:0.95rem; color:#fff;">🎬 Available Streams (<span id="modalStreamsCount">0</span>)</div>
            <div id="modalStreamFilterChips" style="display:flex; gap:6px; flex-wrap:wrap;">
              <button class="stream-filter-chip active" onclick="filterModalStreams('all', this)">All</button>
              <button class="stream-filter-chip" onclick="filterModalStreams('torbox', this)">⚡ TorBox Cached</button>
              <button class="stream-filter-chip" onclick="filterModalStreams('direct', this)">🌐 Direct Play</button>
              <button class="stream-filter-chip" onclick="filterModalStreams('1080p', this)">1080p+</button>
            </div>
          </div>
          <div id="modalStreamsList" style="display:flex; flex-direction:column; gap:10px; min-height:80px;">
            <div style="color:var(--text-muted); text-align:center; padding:20px; font-size:0.88rem;">Click &quot;⚡ Scrape Sources&quot; above or select an episode to discover streams.</div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <div id="toast" class="toast">Copied to clipboard!</div>

  <script>
    let currentStreams = [];
    let activeFilter = 'all';
    let currentHls = null;
    let activeMainTab = 'server';

    function switchMainTab(tab) {
      activeMainTab = tab;
      window.activeMainTab = tab;
      const tabs = ['server', 'search', 'streaming', 'iptv', 'caching', 'about'];
      tabs.forEach(t => {
        const content = document.getElementById('tabContent' + t.charAt(0).toUpperCase() + t.slice(1));
        const btn = document.getElementById('tabBtn' + t.charAt(0).toUpperCase() + t.slice(1));
        if (content) content.style.display = (t === tab) ? 'block' : 'none';
        if (btn) {
          if (t === tab) btn.classList.add('active');
          else btn.classList.remove('active');
        }
      });
      try { localStorage.setItem('hostreamio_active_tab', tab); } catch (_) {}
      if (tab === 'streaming') {
        if (typeof _catalogItems !== 'undefined' && _catalogItems.length === 0) {
          initCatalogBrowser();
        }
      } else if (tab === 'iptv') {
        loadIptvChannels();
      } else if (tab === 'caching') {
        loadCacheQueue(true);
      }
    }

    // Auto-restore previous tab or hash, then init catalog
    window.addEventListener('DOMContentLoaded', () => {
      const hash = window.location.hash.replace('#', '');
      const savedTab = localStorage.getItem('hostreamio_active_tab');
      if (hash && ['server', 'search', 'streaming', 'iptv', 'caching', 'about'].includes(hash)) {
        switchMainTab(hash);
      } else if (savedTab && ['server', 'search', 'streaming', 'iptv', 'caching', 'about'].includes(savedTab)) {
        switchMainTab(savedTab);
      } else {
        switchMainTab('server');
      }

      // Start background polling for caching queue badge & queue status
      startQueueBackgroundPolling();
    });

    // ════════════════════════════════════════════════════════════
    //  GLOBAL VIDEO PLAYER & EXTERNAL APP LAUNCHER
    // ════════════════════════════════════════════════════════════
    function playStream(url, titleText) {
      if (!url) return;
      const modal = document.getElementById('playerModal');
      const title = document.getElementById('playerStreamTitle');
      const video = document.getElementById('previewVideoPlayer');

      if (title) title.innerText = titleText || 'Hostreamio Stream';
      if (modal) modal.style.display = 'flex';

      if (currentHls) {
        currentHls.destroy();
        currentHls = null;
      }

      const streamUrl = url;
      const isHls = streamUrl.includes('.m3u8') || streamUrl.includes('/proxy');

      if (isHls && typeof Hls !== 'undefined' && Hls.isSupported()) {
        currentHls = new Hls({
          enableWorker: true,
          lowLatencyMode: true,
        });
        currentHls.loadSource(streamUrl);
        currentHls.attachMedia(video);
        currentHls.on(Hls.Events.MANIFEST_PARSED, function() {
          video.play().catch(() => {});
        });
        currentHls.on(Hls.Events.ERROR, function(event, data) {
          if (data.fatal) {
            video.src = streamUrl;
            video.play().catch(() => {});
          }
        });
      } else {
        video.src = streamUrl;
        video.play().catch(() => {});
      }
    }

    function openWithModal(url, titleText) {
      if (!url) return;
      const modal = document.getElementById('openWithModal');
      const title = document.getElementById('openWithStreamTitle');
      const sub = document.getElementById('openWithStreamSub');
      const urlPreview = document.getElementById('openWithUrlPreview');

      if (title) title.innerText = '🚀 Open With: ' + (titleText || 'Stream');
      if (sub) sub.innerText = titleText || 'Hostreamio Media Stream';
      if (urlPreview) urlPreview.innerText = url;

      const streamUrl = url;
      const cleanName = titleText || 'Hostreamio Stream';

      // VLC (1-Click Desktop Launcher)
      const vlcBtn = document.getElementById('openWithVlc');
      if (vlcBtn) {
        vlcBtn.onclick = async (e) => {
          e.preventDefault();
          showToast('🚀 Launching VLC Media Player...');
          try {
            const res = await fetch('/api/player/launch', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ player: 'vlc', url: streamUrl })
            });
            const json = await res.json();
            if (json.success) {
              showToast('✅ ' + json.message);
              closeOpenWithModal();
              return;
            }
          } catch (_) {}
          window.location.href = 'vlc://' + streamUrl;
        };
      }

      // PotPlayer (1-Click Desktop Launcher)
      const potBtn = document.getElementById('openWithPotPlayer');
      if (potBtn) {
        potBtn.onclick = async (e) => {
          e.preventDefault();
          showToast('🚀 Launching PotPlayer...');
          try {
            const res = await fetch('/api/player/launch', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ player: 'potplayer', url: streamUrl })
            });
            const json = await res.json();
            if (json.success) {
              showToast('✅ ' + json.message);
              closeOpenWithModal();
              return;
            }
          } catch (_) {}
          window.location.href = 'potplayer://' + streamUrl;
        };
      }

      // MPV (1-Click Desktop Launcher)
      const mpvBtn = document.getElementById('openWithMpv');
      if (mpvBtn) {
        mpvBtn.onclick = async (e) => {
          e.preventDefault();
          showToast('🚀 Launching MPV Player...');
          try {
            const res = await fetch('/api/player/launch', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ player: 'mpv', url: streamUrl })
            });
            const json = await res.json();
            if (json.success) {
              showToast('✅ ' + json.message);
              closeOpenWithModal();
              return;
            }
          } catch (_) {}
          navigator.clipboard.writeText('mpv "' + streamUrl + '"');
          showToast('📋 MPV command copied! Launching mpv://...');
          window.location.href = 'mpv://' + streamUrl;
        };
      }

      // IINA
      const iinaBtn = document.getElementById('openWithIina');
      if (iinaBtn) {
        iinaBtn.onclick = (e) => {
          e.preventDefault();
          window.location.href = 'iina://weblink?url=' + encodeURIComponent(streamUrl);
          showToast('🚀 Launching IINA...');
        };
      }

      // Mobile
      const mobileBtn = document.getElementById('openWithMobile');
      if (mobileBtn) {
        mobileBtn.onclick = (e) => {
          e.preventDefault();
          window.location.href = 'intent:' + streamUrl + '#Intent;type=video/*;scheme=https;end';
          showToast('🚀 Launching Android Video Player...');
        };
      }

      if (modal) modal.style.display = 'flex';
    }

    // ════════════════════════════════════════════════════════════
    //  LIVE IPTV (IPTV-ORG)
    // ════════════════════════════════════════════════════════════
    let allIptvChannels = [];
    let displayedIptvCount = 48;
    let selectedIptvCategory = 'All';
    let iptvFetchPromise = null;
    let _currentFilteredIptv = [];

    async function loadIptvChannels(force = false) {
      if (allIptvChannels.length > 0 && !force) {
        renderIptvGrid();
        return;
      }
      if (iptvFetchPromise) return iptvFetchPromise;

      const grid = document.getElementById('iptvGrid');
      grid.innerHTML = '<div style="grid-column:1/-1; text-align:center; padding:50px 0; color:var(--text-muted);"><div style="font-size:2rem; margin-bottom:12px;">⏳</div>Fetching live global broadcast directory from IPTV-org (8,000+ streams & 730+ Indian regional channels)...</div>';

      iptvFetchPromise = (async () => {
        try {
          const res = await fetch('/api/iptv/channels?limit=10000');
          if (res.ok) {
            const data = await res.json();
            allIptvChannels = data.channels || [];
            const countBadge = document.getElementById('iptvChannelCountBadge');
            if (countBadge) {
              const inCount = allIptvChannels.filter(c => c.country === 'IN').length;
              countBadge.textContent = allIptvChannels.length.toLocaleString() + ' Channels Online (' + inCount + ' India)';
            }
            renderIptvGrid();
          } else {
            grid.innerHTML = '<div style="grid-column:1/-1; text-align:center; color:#f85149; padding:40px 0;">Failed to load IPTV catalog from server.</div>';
          }
        } catch (e) {
          grid.innerHTML = '<div style="grid-column:1/-1; text-align:center; color:#f85149; padding:40px 0;">Error connecting to IPTV: ' + escapeHtml(String(e)) + '</div>';
        } finally {
          iptvFetchPromise = null;
        }
      })();

      return iptvFetchPromise;
    }

    function selectIptvCategory(cat) {
      selectedIptvCategory = cat;
      document.querySelectorAll('[id^="iptv-cat-"]').forEach(btn => {
        btn.classList.toggle('active', btn.id === 'iptv-cat-' + cat.toLowerCase());
      });
      displayedIptvCount = 48;
      renderIptvGrid();
    }

    function filterIptvChannels() {
      displayedIptvCount = 48;
      renderIptvGrid();
    }

    function renderIptvGrid() {
      const grid = document.getElementById('iptvGrid');
      const query = (document.getElementById('iptvSearchInput').value || '').toLowerCase().trim();
      const country = (document.getElementById('iptvCountryFilter').value || 'All').toUpperCase();

      _currentFilteredIptv = allIptvChannels.filter(ch => {
        if (country !== 'ALL' && (ch.country || '').toUpperCase() !== country) return false;
        if (selectedIptvCategory !== 'All' && !(ch.category || '').toLowerCase().includes(selectedIptvCategory.toLowerCase())) return false;
        if (query) {
          const matchName = (ch.name || '').toLowerCase().includes(query);
          const matchCat = (ch.category || '').toLowerCase().includes(query);
          const matchCtry = (ch.country || '').toLowerCase().includes(query);
          if (!matchName && !matchCat && !matchCtry) return false;
        }
        return true;
      });

      if (_currentFilteredIptv.length === 0) {
        grid.innerHTML = '<div style="grid-column:1/-1; text-align:center; padding:60px 20px; color:var(--text-muted);">' +
          '<div style="font-size:2.5rem; margin-bottom:10px;">📡</div>' +
          '<strong style="font-size:1.1rem; color:var(--text);">No Broadcast Channels Found</strong>' +
          '<p style="font-size:0.85rem; margin-top:6px;">Try adjusting your search query, country dropdown, or category filters.</p>' +
          '</div>';
        document.getElementById('btnIptvLoadMore').style.display = 'none';
        return;
      }

      const visible = _currentFilteredIptv.slice(0, displayedIptvCount);
      let html = '';

      visible.forEach((ch, idx) => {
        const logo = ch.logo || '';
        const name = ch.name || 'Live Channel';
        const cat = ch.category || 'General';
        const ctry = ch.country || 'Global';
        const flag = ctry === 'IN' ? '🇮🇳' : ctry === 'US' ? '🇺🇸' : ctry === 'UK' ? '🇬🇧' : ctry === 'CA' ? '🇨🇦' : ctry === 'DE' ? '🇩🇪' : ctry === 'FR' ? '🇫🇷' : ctry === 'JP' ? '🇯🇵' : ctry === 'AU' ? '🇦🇺' : ctry === 'IT' ? '🇮🇹' : ctry === 'ES' ? '🇪🇸' : ctry === 'BR' ? '🇧🇷' : '🌐';

        html += '<div style="background:#0d1117; border:1px solid var(--border); border-radius:12px; padding:14px; display:flex; flex-direction:column; justify-content:space-between; gap:12px; box-shadow:0 4px 12px rgba(0,0,0,0.25); transition:transform 0.15s ease, border-color 0.15s ease;" onmouseenter="this.style.borderColor=&apos;#38bdf8&apos;" onmouseleave="this.style.borderColor=&apos;var(--border)&apos;">' +
          // Header with Prominent 72x72px Logo
          '<div style="display:flex; align-items:center; gap:14px;">' +
            '<div style="width:72px; height:72px; min-width:72px; min-height:72px; border-radius:10px; background:#161b22; border:1px solid #30363d; display:flex; align-items:center; justify-content:center; overflow:hidden; padding:6px; box-sizing:border-box;">' +
              (logo ? '<img src="' + escapeHtml(logo) + '" alt="' + escapeHtml(name) + '" style="width:100%; height:100%; object-fit:contain;" onerror="this.onerror=null; this.parentElement.innerHTML=&apos;📺&apos;; this.parentElement.style.fontSize=&apos;2rem&apos;;">' : '<span style="font-size:2rem;">📺</span>') +
            '</div>' +
            '<div style="overflow:hidden; flex:1; min-width:0;">' +
              '<div style="font-weight:700; font-size:0.95rem; color:#fff; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;" title="' + escapeHtml(name) + '">' + escapeHtml(name) + '</div>' +
              '<div style="display:flex; align-items:center; gap:6px; margin-top:4px; flex-wrap:wrap;">' +
                '<span class="badge" style="background:rgba(56, 189, 248, 0.15); color:#38bdf8; border:1px solid rgba(56, 189, 248, 0.3); font-size:0.7rem; padding:1px 6px;">' + flag + ' ' + escapeHtml(ctry) + '</span>' +
                '<span class="badge" style="background:#161b22; color:var(--text-muted); font-size:0.7rem; padding:1px 6px;">' + escapeHtml(cat) + '</span>' +
              '</div>' +
              '<div style="display:flex; align-items:center; gap:5px; margin-top:5px; font-size:0.72rem; color:#3fb950; font-weight:600;">' +
                '<span style="display:inline-block; width:6px; height:6px; background:#3fb950; border-radius:50%; box-shadow:0 0 6px #3fb950;"></span> LIVE STREAM' +
              '</div>' +
            '</div>' +
          '</div>' +
          // Action Buttons
          '<div style="display:flex; gap:6px; margin-top:auto;">' +
            '<button class="btn btn-sm btn-primary" style="flex:1; justify-content:center; padding:7px 10px; font-size:0.8rem; font-weight:600;" onclick="playIptvIndex(' + idx + ')">▶ Play</button>' +
            '<button class="btn btn-sm btn-open-with" style="padding:7px 10px; font-size:0.8rem;" onclick="openWithIptvIndex(' + idx + ')">🚀 With...</button>' +
            '<button class="btn btn-sm" style="padding:7px 10px; font-size:0.8rem; background:#161b22; color:var(--text-muted);" onclick="copyIptvUrl(' + idx + ')" title="Copy Direct Stream URL">📋</button>' +
          '</div>' +
        '</div>';
      });

      grid.innerHTML = html;
      document.getElementById('btnIptvLoadMore').style.display = (_currentFilteredIptv.length > displayedIptvCount) ? 'inline-block' : 'none';
    }

    function loadMoreIptv() {
      displayedIptvCount += 48;
      renderIptvGrid();
    }

    function playIptvIndex(idx) {
      const ch = (_currentFilteredIptv || [])[idx];
      if (!ch || !ch.url) return;
      playStream(ch.url, ch.name);
    }

    function openWithIptvIndex(idx) {
      const ch = (_currentFilteredIptv || [])[idx];
      if (!ch || !ch.url) return;
      openWithModal(ch.url, ch.name);
    }

    function copyIptvUrl(idx) {
      const ch = (_currentFilteredIptv || [])[idx];
      if (!ch || !ch.url) return;
      navigator.clipboard.writeText(ch.url).then(() => {
        showToast('📋 Stream URL for "' + ch.name + '" copied to clipboard!');
      });
    }

    // ════════════════════════════════════════════════════════════
    //  LIVE TORBOX CLOUD CACHING QUEUE
    // ════════════════════════════════════════════════════════════
    let queuePollTimer = null;
    let isQueuePollingActive = true;
    let cacheQueueFilter = 'hostreamio'; // 'hostreamio' or 'all'
    let _queueReqSeq = 0;
    let _isLoadingQueue = false;

    function startQueueBackgroundPolling() {
      loadCacheQueue(false);
      if (queuePollTimer) clearInterval(queuePollTimer);
      queuePollTimer = setInterval(() => {
        if (isQueuePollingActive) {
          loadCacheQueue(false);
        }
      }, 5000);
    }

    function toggleQueueAutoPoll(enabled) {
      isQueuePollingActive = !!enabled;
      if (enabled) loadCacheQueue(false);
    }

    function setCacheQueueFilter(filter) {
      cacheQueueFilter = filter;
      const btnHostreamio = document.getElementById('btnFilterHostreamio');
      const btnAll = document.getElementById('btnFilterAll');
      const label = document.getElementById('queueCurrentFilterLabel');

      if (filter === 'hostreamio') {
        if (btnHostreamio) {
          btnHostreamio.className = 'btn btn-sm btn-primary';
          btnHostreamio.style.background = '';
          btnHostreamio.style.color = '';
        }
        if (btnAll) {
          btnAll.className = 'btn btn-sm';
          btnAll.style.background = 'transparent';
          btnAll.style.border = 'none';
          btnAll.style.color = 'var(--text-muted)';
        }
        if (label) label.textContent = 'Hostreamio Initiated';
      } else {
        if (btnHostreamio) {
          btnHostreamio.className = 'btn btn-sm';
          btnHostreamio.style.background = 'transparent';
          btnHostreamio.style.border = 'none';
          btnHostreamio.style.color = 'var(--text-muted)';
        }
        if (btnAll) {
          btnAll.className = 'btn btn-sm btn-primary';
          btnAll.style.background = '';
          btnAll.style.color = '';
        }
        if (label) label.textContent = 'All TorBox Cloud';
      }
      loadCacheQueue(false);
    }

    async function loadCacheQueue(showToastNotice = false) {
      if (_isLoadingQueue) return;
      _isLoadingQueue = true;
      const currentSeq = ++_queueReqSeq;
      const requestedFilter = cacheQueueFilter;

      try {
        const res = await fetch('/api/torbox/queue?filter=' + encodeURIComponent(requestedFilter));
        if (!res.ok) return;
        const data = await res.json();
        // Guard against race conditions and stale responses
        if (currentSeq !== _queueReqSeq || data.filter !== cacheQueueFilter) return;

        const items = data.items || [];

        // Update counts
        const hostreamioCount = data.hostreamioCount != null ? data.hostreamioCount : items.length;
        const totalCount = data.totalCount != null ? data.totalCount : items.length;

        const elH = document.getElementById('queueHostreamioCount');
        const elA = document.getElementById('queueAllCount');
        if (elH) elH.textContent = hostreamioCount;
        if (elA) elA.textContent = totalCount;

        // Update badges
        const badge = document.getElementById('sidebarQueueBadge');
        const countBadge = document.getElementById('queueItemsCountBadge');
        const activeCount = items.filter(it => it.status === 'caching' || it.status === 'queued').length;

        if (badge) {
          badge.textContent = hostreamioCount;
          badge.style.display = hostreamioCount > 0 ? 'inline-block' : 'none';
        }
        if (countBadge) {
          countBadge.textContent = items.length + ' Item' + (items.length === 1 ? '' : 's') + (activeCount > 0 ? ' (' + activeCount + ' Caching)' : '');
        }

        // Only reconcile/render DOM if currently on caching tab
        if (!window.activeMainTab || window.activeMainTab === 'caching') {
          renderCacheQueue(items, data.hasKey);
        }
        if (showToastNotice) showToast('Caching queue refreshed');
      } catch (err) {
        console.error('Error fetching cache queue:', err);
      } finally {
        _isLoadingQueue = false;
      }
    }

    function renderCacheQueue(items, hasKey) {
      const container = document.getElementById('cacheQueueContainer');
      if (!container) return;

      if (!hasKey) {
        container.innerHTML = '<div style="background:#161b22; border:1px solid #30363d; border-radius:10px; padding:24px; text-align:center;">' +
          '<div style="font-size:2rem; margin-bottom:8px;">🔑</div>' +
          '<strong style="color:var(--text); font-size:1rem;">TorBox API Key Not Configured</strong>' +
          '<p style="color:var(--text-muted); font-size:0.85rem; margin:8px 0 16px 0;">Configure your TorBox API key in Server &amp; Addon tab to activate cloud caching &amp; instant CDN streaming.</p>' +
          '<button class="btn btn-primary btn-sm" onclick="switchMainTab(&apos;server&apos;)">⚙️ Configure TorBox</button>' +
          '</div>';
        return;
      }

      if (!items || items.length === 0) {
        const isHFilter = cacheQueueFilter === 'hostreamio';
        container.innerHTML = '<div style="text-align:center; padding:40px 20px; color:var(--text-muted);">' +
          '<div style="font-size:2.5rem; margin-bottom:10px;">⚡</div>' +
          '<strong style="color:var(--text); font-size:1.05rem;">' + (isHFilter ? 'No Hostreamio Caches Active' : 'Cache Queue is Empty') + '</strong>' +
          '<p style="font-size:0.85rem; max-width:480px; margin:8px auto 0 auto; line-height:1.5;">' +
          (isHFilter ? 'When you stream uncached links or click "Cache to TorBox" in Hostreamio, they will track here. Switch to <strong>"All TorBox Cloud"</strong> to see downloads started elsewhere.' : 'When you start caching a torrent or web stream, it will appear here with live progress, speed, ETA, and 1-tap playback controls.') +
          '</p>' +
          '</div>';
        return;
      }

      window._cacheQueueItems = items;

      // Smooth DOM reconciliation: check if existing card IDs match new items
      const existingCards = container.querySelectorAll('.cache-queue-card');
      const existingIds = Array.from(existingCards).map(c => c.getAttribute('data-id'));
      const newIds = items.map(it => String(it.id));

      const isSameList = existingIds.length === newIds.length && existingIds.every((id, idx) => id === newIds[idx]);

      if (isSameList) {
        // Update in-place smoothly without layout thrashing or image reload!
        items.forEach((it, idx) => {
          const card = existingCards[idx];
          if (!card) return;
          const isDone = it.status === 'completed';
          const isFailed = it.status === 'failed';
          const pct = it.progressPercent || Math.round((it.progress || 0) * 100);

          let badgeBg = 'rgba(88, 166, 255, 0.15)';
          let badgeColor = '#58a6ff';
          let badgeBorder = 'rgba(88, 166, 255, 0.3)';
          let badgeText = '⚡ CACHING (' + pct + '%)';

          if (isDone) {
            badgeBg = 'rgba(63, 185, 80, 0.15)';
            badgeColor = '#3fb950';
            badgeBorder = 'rgba(63, 185, 80, 0.3)';
            badgeText = '✅ READY TO STREAM';
          } else if (isFailed) {
            badgeBg = 'rgba(248, 81, 73, 0.15)';
            badgeColor = '#f85149';
            badgeBorder = 'rgba(248, 81, 73, 0.3)';
            badgeText = '❌ FAILED';
          } else if (it.status === 'queued') {
            badgeBg = 'rgba(227, 179, 65, 0.15)';
            badgeColor = '#e3b341';
            badgeBorder = 'rgba(227, 179, 65, 0.3)';
            badgeText = '⏳ QUEUED';
          }

          const statusBadge = card.querySelector('.queue-status-badge');
          if (statusBadge) {
            statusBadge.textContent = badgeText;
            statusBadge.style.background = badgeBg;
            statusBadge.style.color = badgeColor;
            statusBadge.style.borderColor = badgeBorder;
          }

          const progressBar = card.querySelector('.queue-progress-bar');
          if (progressBar) {
            progressBar.style.width = pct + '%';
            progressBar.style.background = isDone ? '#3fb950' : 'linear-gradient(90deg, #195feb, #ff0c82)';
          }

          const statsSpeed = card.querySelector('.queue-stat-speed');
          if (statsSpeed) statsSpeed.textContent = '⚡ ' + (it.speed || '--');
          const statsEta = card.querySelector('.queue-stat-eta');
          if (statsEta) statsEta.textContent = '⏱️ ' + (it.eta || '--');

          card.style.borderColor = isDone ? '#238636' : '#21262d';
        });
        return;
      }

      // Rebuild HTML only when items were added/removed/switched
      let html = '';
      items.forEach((it, idx) => {
        const isDone = it.status === 'completed';
        const isFailed = it.status === 'failed';
        const pct = it.progressPercent || Math.round((it.progress || 0) * 100);

        let badgeBg = 'rgba(88, 166, 255, 0.15)';
        let badgeColor = '#58a6ff';
        let badgeBorder = 'rgba(88, 166, 255, 0.3)';
        let badgeText = '⚡ CACHING (' + pct + '%)';

        if (isDone) {
          badgeBg = 'rgba(63, 185, 80, 0.15)';
          badgeColor = '#3fb950';
          badgeBorder = 'rgba(63, 185, 80, 0.3)';
          badgeText = '✅ READY TO STREAM';
        } else if (isFailed) {
          badgeBg = 'rgba(248, 81, 73, 0.15)';
          badgeColor = '#f85149';
          badgeBorder = 'rgba(248, 81, 73, 0.3)';
          badgeText = '❌ FAILED';
        } else if (it.status === 'queued') {
          badgeBg = 'rgba(227, 179, 65, 0.15)';
          badgeColor = '#e3b341';
          badgeBorder = 'rgba(227, 179, 65, 0.3)';
          badgeText = '⏳ QUEUED';
        }

        const playUrl = it.rawUrl ? ('/torbox/play?url=' + encodeURIComponent(it.rawUrl)) : '';
        const poster = it.poster || '';
        const cleanTitle = it.cleanTitle || it.movieTitle || it.name;
        const showRawName = cleanTitle !== it.name && it.name.length > 0;
        const badges = (it.qualityBadges || []).map(b => '<span class="badge" style="background:rgba(56, 189, 248, 0.15); color:#38bdf8; font-size:0.7rem; padding:1px 6px;">' + escapeHtml(b) + '</span>').join('');

        html += '<div class="cache-queue-card" data-id="' + escapeHtml(String(it.id)) + '" style="background:#0d1117; border:1px solid ' + (isDone ? '#238636' : '#21262d') + '; border-radius:12px; padding:14px 16px; display:flex; gap:16px; align-items:flex-start; box-shadow:0 4px 16px rgba(0,0,0,0.25);">' +
          // Vertical Poster Thumbnail
          '<div style="width:52px; height:74px; min-width:52px; min-height:74px; border-radius:8px; background:#161b22; border:1px solid #30363d; overflow:hidden; display:flex; align-items:center; justify-content:center; flex-shrink:0;">' +
            (poster ? '<img src="' + escapeHtml(poster) + '" style="width:100%; height:100%; object-fit:cover;" onerror="this.onerror=null; this.parentElement.innerHTML=&apos;🎬&apos;;">' : '<span style="font-size:1.6rem;">🎬</span>') +
          '</div>' +

          // Main Information
          '<div style="flex:1; min-width:0; display:flex; flex-direction:column; gap:8px;">' +
            '<div style="display:flex; justify-content:space-between; align-items:flex-start; gap:10px; flex-wrap:wrap;">' +
              '<div style="flex:1; min-width:180px;">' +
                '<div style="font-weight:700; font-size:1.02rem; color:#fff; line-height:1.3;">' + escapeHtml(cleanTitle) + '</div>' +
                (showRawName ? ('<div style="font-size:0.75rem; color:var(--text-muted); font-family:monospace; margin-top:2px; word-break:break-all;">📁 ' + escapeHtml(it.name) + '</div>') : '') +
                '<div style="display:flex; gap:8px; align-items:center; margin-top:6px; flex-wrap:wrap;">' +
                  badges +
                  '<span class="badge" style="background:#161b22; color:var(--text-muted); padding:1px 6px; font-size:0.7rem;">' + (it.type === 'torrent' ? 'Torrent' : 'WebDL') + '</span>' +
                  (it.isHostreamio ? '<span class="badge" style="background:rgba(255, 12, 130, 0.15); color:#ff0c82; padding:1px 6px; font-size:0.7rem;">⚡ Hostreamio</span>' : '') +
                  '<span style="font-size:0.75rem; color:var(--text-muted);">📦 ' + escapeHtml(it.size || '--') + '</span>' +
                  '<span class="queue-stat-speed" style="font-size:0.75rem; color:var(--text-muted);">⚡ ' + escapeHtml(it.speed || '--') + '</span>' +
                  '<span class="queue-stat-eta" style="font-size:0.75rem; color:var(--text-muted);">⏱️ ' + escapeHtml(it.eta || '--') + '</span>' +
                '</div>' +
              '</div>' +
              '<span class="badge queue-status-badge" style="background:' + badgeBg + '; color:' + badgeColor + '; border:1px solid ' + badgeBorder + '; font-size:0.78rem; font-weight:700; padding:4px 10px; border-radius:6px; white-space:nowrap;">' + badgeText + '</span>' +
            '</div>' +

            // Progress Bar
            '<div style="background:#161b22; border-radius:6px; height:7px; width:100%; overflow:hidden; margin-top:2px;">' +
              '<div class="queue-progress-bar" style="background:' + (isDone ? '#3fb950' : 'linear-gradient(90deg, #195feb, #ff0c82)') + '; height:100%; width:' + pct + '%; transition:width 0.4s ease;"></div>' +
            '</div>' +

            // Actions Row
            '<div style="display:flex; justify-content:space-between; align-items:center; gap:8px; margin-top:4px;">' +
              '<div style="font-size:0.75rem; color:var(--text-muted);">' + (isDone ? '✨ Stream ready at unlimited speed on TorBox CDN' : 'Downloading to cloud CDN…') + '</div>' +
              '<div style="display:flex; gap:8px;">' +
                (isDone && playUrl ? (
                  '<button class="btn btn-sm btn-success" style="padding:6px 12px; font-size:0.8rem; font-weight:600;" onclick="playQueueIndex(' + idx + ')">▶ Stream</button>' +
                  '<button class="btn btn-sm" style="padding:6px 12px; font-size:0.8rem;" onclick="openWithQueueIndex(' + idx + ')">🚀 Play With</button>'
                ) : '') +
                '<button class="btn btn-sm btn-danger" style="padding:6px 10px; font-size:0.8rem;" onclick="deleteQueueIndex(' + idx + ')" title="Remove from TorBox Cloud">🗑️</button>' +
              '</div>' +
            '</div>' +
          '</div>' +
        '</div>';
      });

      container.innerHTML = html;
    }


    function playQueueIndex(idx) {
      const it = (window._cacheQueueItems || [])[idx];
      if (!it) return;
      const playUrl = it.rawUrl ? ('/torbox/play?url=' + encodeURIComponent(it.rawUrl)) : '';
      if (playUrl) playStream(playUrl, it.cleanTitle || it.name);
    }

    function openWithQueueIndex(idx) {
      const it = (window._cacheQueueItems || [])[idx];
      if (!it) return;
      const playUrl = it.rawUrl ? ('/torbox/play?url=' + encodeURIComponent(it.rawUrl)) : '';
      if (playUrl) openWithModal(playUrl, it.cleanTitle || it.name);
    }

    function deleteQueueIndex(idx) {
      const it = (window._cacheQueueItems || [])[idx];
      if (!it) return;
      deleteQueueDownload(it.id, it.type);
    }

    async function deleteQueueDownload(id, type) {
      if (!confirm('Remove this download from your TorBox cloud queue?')) return;
      try {
        const res = await fetch('/api/torbox/queue/delete', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ id: id, type: type })
        });
        if (res.ok) {
          showToast('Item removed from queue');
          loadCacheQueue(false);
        }
      } catch (e) {
        alert('Failed to delete item: ' + e);
      }
    }

    async function uploadLinkFromCachingTab() {
      const input = document.getElementById('cachingTabUploadUrl');
      const url = input ? input.value.trim() : '';
      if (!url) {
        alert('Please enter or paste a valid stream URL.');
        return;
      }
      try {
        const res = await fetch('/api/torbox/upload', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ url: url })
        });
        const data = await res.json();
        if (data.success) {
          showToast('☁️ Link queued to TorBox Caching!');
          if (input) input.value = '';
          loadCacheQueue(false);
        } else {
          alert('Upload failed: ' + (data.message || 'Could not queue link'));
        }
      } catch (e) {
        alert('Error queuing link: ' + e);
      }
    }

    async function saveTorboxCachedToggle(checked) {
      try {
        const res = await fetch('/api/settings', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({ enableTorboxCachedTorrents: checked })
        });
        if (res.ok) {
          showToast(checked ? 'TorBox Cached Torrents Enabled (0 P2P)' : 'TorBox Cached Torrents Disabled');
        }
      } catch (e) {
        showToast('Error saving setting: ' + e);
      }
    }

    async function saveCacheBypassToggle(checked) {
      try {
        const res = await fetch('/api/settings', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({ enableCacheBypass: checked })
        });
        if (res.ok) {
          showToast(checked ? 'Prowlarr Cache-Bypass Enabled' : 'Prowlarr Cache-Bypass Disabled');
        }
      } catch (e) {
        showToast('Error saving setting: ' + e);
      }
    }

    async function saveProxyResolverSettings() {
      const url = document.getElementById('proxyResolverUrl').value.trim();
      try {
        const res = await fetch('/api/settings', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({ proxyResolverUrl: url })
        });
        if (res.ok) {
          showToast('FlareSolverr Proxy URL Saved');
        }
      } catch (e) {
        showToast('Error saving proxy setting: ' + e);
      }
    }

    // ════════════════════════════════════════════════════════════
    //  CATALOG BROWSER
    // ════════════════════════════════════════════════════════════
    let _activeCatalogTab = 'trending-movie';
    let _catalogSkip = 0;
    let _catalogItems = [];
    let _catalogActiveGenre = 'All';

    const _catalogMeta = {
      'trending-movie':    { label:'🔥 Trending Movies',    type:'movie',  src:'cinemeta', id:'top' },
      'trending-series':   { label:'📺 Trending Series',    type:'series', src:'cinemeta', id:'top' },
      'yt_indian':         { label:'🎬 YouTube Indian',      type:'movie',  src:'local',    id:'yt_indian',
        genres:['All','Bollywood Full Movies','South Hindi Dubbed','Indian Web Series','Classic Hindi','Comedy Hindi Movies'] },
      'yt_international':  { label:'🌍 YouTube Intl',        type:'movie',  src:'local',    id:'yt_international',
        genres:['All','Action Movies','Sci-Fi & Thriller','Documentaries','Indie Cinema'] },
      'vimeo_picks':       { label:'🎥 Vimeo',               type:'movie',  src:'local',    id:'vimeo_picks',
        genres:['All','Staff Picks','Short of the Week','Animation','Documentaries'] },
      'archive_movies':    { label:'🏛️ Archive',             type:'movie',  src:'local',    id:'archive_movies',
        genres:['All','Indian Classics','Golden Era Hollywood','Film Noir','Sci-Fi & Horror','Silent Era'] },
      'dm_movies':         { label:'📺 Dailymotion',          type:'movie',  src:'local',    id:'dm_movies',
        genres:['All','Hindi Movies & Dramas','Pakistani Dramas','International Movies'] },
    };

    function initCatalogBrowser() {
      switchCatalogTab('trending-movie');
    }

    function switchCatalogTab(tabKey) {
      _activeCatalogTab = tabKey;
      _catalogSkip = 0;
      _catalogItems = [];
      _catalogActiveGenre = 'All';

      // Update tab button styles
      document.querySelectorAll('#catalogTabNav .stream-filter-chip').forEach(b => b.classList.remove('active'));
      const activeBtn = document.getElementById('ctab-' + tabKey);
      if (activeBtn) activeBtn.classList.add('active');

      // Show genre row if applicable
      const meta = _catalogMeta[tabKey];
      const genreRow = document.getElementById('catalogGenreRow');
      if (meta && meta.genres) {
        genreRow.style.display = 'flex';
        genreRow.innerHTML = meta.genres.map(g => {
          const activeCls = g === 'All' ? ' active' : '';
          return '<button class="stream-filter-chip' + activeCls + '" data-genre="' + encodeURIComponent(g) + '" onclick="onGenreChipClick(this)">' + g + '</button>';
        }).join('');
      } else {
        genreRow.style.display = 'none';
        genreRow.innerHTML = '';
      }

      loadCatalog(true);
    }

    function onGenreChipClick(btn) {
      const genre = decodeURIComponent(btn.getAttribute('data-genre') || 'All');
      setCatalogGenre(genre, btn);
    }

    function setCatalogGenre(genre, btn) {
      _catalogActiveGenre = genre;
      _catalogSkip = 0;
      _catalogItems = [];
      document.querySelectorAll('#catalogGenreRow .stream-filter-chip').forEach(b => b.classList.remove('active'));
      if (btn) btn.classList.add('active');
      loadCatalog(true);
    }

    async function loadCatalog(reset = false) {
      const grid = document.getElementById('catalogGrid');
      if (!grid) return;
      const meta = _catalogMeta[_activeCatalogTab];
      if (!meta) return;

      if (reset) {
        grid.innerHTML = '<div style="grid-column:1/-1;color:var(--text-muted);text-align:center;padding:40px 0;">⏳ Loading catalog…</div>';
        const loadMoreBtn = document.getElementById('btnCatalogLoadMore');
        if (loadMoreBtn) loadMoreBtn.style.display = 'none';
      }

      try {
        let items = [];
        if (meta.src === 'cinemeta') {
          const cinemetaType = meta.type === 'series' ? 'series' : 'movie';
          const skip = _catalogSkip;
          const url = 'https://v3-cinemeta.strem.io/catalog/' + cinemetaType + '/' + meta.id + '/skip=' + skip + '.json';
          const res = await fetch(url);
          if (!res.ok) throw new Error('Cinemeta HTTP ' + res.status);
          const data = await res.json();
          items = (data.metas || []).map(m => ({
            id: m.id,
            type: cinemetaType,
            name: m.name || m.title || 'Unknown',
            poster: m.poster || m.background || '',
            nativePoster: m.nativePoster || m.poster || '',
            year: m.year || m.releaseInfo || '',
            rating: m.imdbRating || m.rating || '',
            genres: m.genres || [],
            description: m.description || '',
          }));
        } else {
          const genre = (_catalogActiveGenre && _catalogActiveGenre !== 'All') ? '&genre=' + encodeURIComponent(_catalogActiveGenre) : '';
          const url = '/catalog/' + meta.type + '/' + meta.id + '/skip=' + _catalogSkip + genre + '.json';
          const res = await fetch(url);
          if (!res.ok) throw new Error('Local catalog HTTP ' + res.status);
          const data = await res.json();
          items = (data.metas || []).map(m => ({
            id: m.id,
            type: meta.type,
            name: m.name || m.title || 'Unknown',
            poster: m.poster || m.background || '',
            nativePoster: m.nativePoster || m.poster || '',
            year: m.releaseInfo || m.year || '',
            rating: m.imdbRating || m.rating || '',
            genres: m.genres || [],
            description: m.description || '',
          }));
        }

        _catalogItems = reset ? items : [..._catalogItems, ...items];
        _catalogSkip += items.length || 20;
        renderCatalogGrid(reset);
        const loadMoreBtn = document.getElementById('btnCatalogLoadMore');
        if (loadMoreBtn) loadMoreBtn.style.display = items.length >= 10 ? 'inline-block' : 'none';
      } catch (e) {
        if (reset) {
          grid.innerHTML = '<div style="grid-column:1/-1;color:#f85149;text-align:center;padding:30px 0;">⚠️ Failed to load catalog: ' + (e.message || e) + '. <button class="btn btn-sm" onclick="loadCatalog(true)" style="margin-left:8px;">↺ Retry</button></div>';
        }
        const loadMoreBtn = document.getElementById('btnCatalogLoadMore');
        if (loadMoreBtn) loadMoreBtn.style.display = 'none';
      }
    }

    function onPosterError(img) {
      const fallback = img.getAttribute('data-fallback');
      const curSrc = img.getAttribute('src') || '';
      if (fallback && curSrc !== fallback) {
        img.removeAttribute('data-fallback');
        img.src = fallback;
        return;
      }
      if ((curSrc.includes('maxresdefault.jpg') || curSrc.includes('hq720.jpg')) && !curSrc.includes('hqdefault.jpg')) {
        img.src = curSrc.replace('maxresdefault.jpg', 'hqdefault.jpg').replace('hq720.jpg', 'hqdefault.jpg');
        return;
      }
      if (curSrc.includes('/__ia_thumb.jpg')) {
        img.src = curSrc.replace('/download/', '/services/img/').replace('/__ia_thumb.jpg', '');
        return;
      }
      img.style.display = 'none';
      if (img.nextElementSibling) img.nextElementSibling.style.display = 'flex';
    }

    function renderCatalogGrid(reset = false) {
      const grid = document.getElementById('catalogGrid');
      if (!grid) return;

      grid.style.gridTemplateColumns = 'repeat(auto-fill, minmax(145px, 1fr))';
      const imgHeight = '215px';

      if (_catalogItems.length === 0) {
        grid.innerHTML = '<div style="grid-column:1/-1;color:var(--text-muted);text-align:center;padding:30px 0;">No results found.</div>';
        return;
      }

      const cards = _catalogItems.map(item => {
        const safeName = escapeHtml(item.name || 'Unknown');
        const isSeries = item.type === 'series';
        const typeIcon = isSeries ? '📺' : '🎬';
        const yearBadge = item.year ? '<span style="font-size:0.72rem;color:var(--text-muted);">' + escapeHtml(item.year) + '</span>' : '';
        const ratingBadge = item.rating
          ? '<span style="background:rgba(227,179,65,0.2);color:#e3b341;border:1px solid rgba(227,179,65,0.35);font-size:0.7rem;padding:1px 5px;border-radius:4px;font-weight:700;">⭐ ' + escapeHtml(item.rating) + '</span>'
          : '';
        const metaRow = '<div style="display:flex;justify-content:space-between;align-items:center;margin-top:6px;">'
          + (yearBadge || '<span></span>')
          + ratingBadge
          + '</div>';

        const fallbackAttr = item.nativePoster ? ' data-fallback="' + encodeURI(item.nativePoster) + '"' : '';
        const posterHtml = item.poster
          ? '<img src="' + encodeURI(item.poster) + '"' + fallbackAttr + ' alt="' + safeName + '" style="width:100%;height:' + imgHeight + ';object-fit:cover;border-radius:8px 8px 0 0;display:block;" onerror="onPosterError(this)">'
          : '<div style="width:100%;height:' + imgHeight + ';background:linear-gradient(135deg,#1a1f2e,#0d1117);display:flex;align-items:center;justify-content:center;font-size:2.5rem;border-radius:8px 8px 0 0;">🎬</div>';

        return '<div class="catalog-card" data-id="' + encodeURIComponent(item.id || '') + '" data-type="' + encodeURIComponent(item.type || 'movie') + '" data-name="' + encodeURIComponent(item.name || '') + '" data-poster="' + encodeURIComponent(item.poster || '') + '" data-rating="' + encodeURIComponent(item.rating || '') + '" data-series="' + (isSeries ? '1' : '0') + '" onclick="onCatalogCardClick(this)" title="' + safeName + '">'
          + posterHtml
          + '<div style="padding:8px 8px 10px;">'
          + '<div style="font-size:0.82rem;font-weight:700;color:var(--text);line-height:1.3;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;">' + typeIcon + ' ' + safeName + '</div>'
          + metaRow
          + '</div>'
          + '</div>';
      }).join('');

      if (reset) {
        grid.innerHTML = cards;
      } else {
        grid.innerHTML = grid.innerHTML + cards;
      }
    }

    let modalCurrentMedia = null;
    let modalScrapedStreams = [];
    let modalSeriesDetails = null;
    let modalSelectedSeason = 1;
    let modalSelectedEpisode = 1;
    let modalSelectedEpId = null;

    function handleModalBackdropClick(event) {
      if (event.target && event.target.id === 'mediaDetailModal') {
        closeMediaDetailModal();
      }
    }

    function closeMediaDetailModal() {
      const modal = document.getElementById('mediaDetailModal');
      if (modal) modal.style.display = 'none';
    }

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closeMediaDetailModal();
      }
    });

    async function openMediaDetailModal(id, type, name, poster, isSeries, initialRating) {
      const modal = document.getElementById('mediaDetailModal');
      if (!modal) return;

      const cleanType = (isSeries || type === 'series' || type === 'tv') ? 'series' : 'movie';
      modalCurrentMedia = {
        id: id,
        baseId: id.includes(':') ? id.split(':')[0] : id,
        type: cleanType,
        name: name || id,
        poster: poster || ('https://images.metahub.space/poster/medium/' + (id.split(':')[0]) + '/img'),
        isSeries: cleanType === 'series',
        rating: initialRating || '',
        season: 1,
        episode: 1,
        epTitle: ''
      };
      modalScrapedStreams = [];
      modalSeriesDetails = null;

      // Reset Modal UI
      modal.style.display = 'flex';
      const posterEl = document.getElementById('modalPoster');
      if (posterEl) posterEl.src = modalCurrentMedia.poster;

      const titleEl = document.getElementById('modalTitle');
      if (titleEl) titleEl.textContent = modalCurrentMedia.name;

      const typeBadge = document.getElementById('modalTypeBadge');
      if (typeBadge) {
        typeBadge.textContent = cleanType === 'series' ? '📺 TV SERIES' : '🎬 MOVIE';
        typeBadge.style.background = cleanType === 'series' ? '#a371f7' : '#ff0c82';
      }

      const yearBadge = document.getElementById('modalYearBadge');
      if (yearBadge) yearBadge.textContent = '';

      const ratingsContainer = document.getElementById('modalRatingsContainer');
      if (ratingsContainer) {
        if (initialRating && initialRating !== 'N/A' && initialRating !== '0' && initialRating !== '0.0') {
          ratingsContainer.innerHTML = '<span class="badge" style="background:rgba(227, 179, 65, 0.2); color:#e3b341; border:1px solid rgba(227, 179, 65, 0.4); font-size:0.75rem; font-weight:700;">⭐ ' + escapeHtml(initialRating) + '</span>';
        } else {
          ratingsContainer.innerHTML = '';
        }
      }

      const genresEl = document.getElementById('modalGenres');
      if (genresEl) genresEl.innerHTML = '';

      const overviewEl = document.getElementById('modalOverview');
      if (overviewEl) overviewEl.textContent = 'Fetching rich metadata from Cinemeta & TMDb…';

      const hero = document.getElementById('modalHero');
      if (hero) hero.style.backgroundImage = 'url(' + modalCurrentMedia.poster + ')';

      const seriesBox = document.getElementById('modalSeriesBrowser');
      if (seriesBox) seriesBox.style.display = 'none';

      // Reset DoesTheDogDie Card
      const dtddCard = document.getElementById('modalDtddCard');
      const dtddBadge = document.getElementById('modalDtddSummaryBadge');
      const dtddLink = document.getElementById('modalDtddLink');
      const dtddExpandable = document.getElementById('modalDtddExpandable');
      const dtddBtn = document.getElementById('btnToggleDtdd');
      const dtddLoading = document.getElementById('modalDtddLoading');
      const dtddContent = document.getElementById('modalDtddContent');

      if (dtddCard) dtddCard.style.display = 'block';
      if (dtddBadge) { dtddBadge.style.display = 'none'; dtddBadge.textContent = ''; }
      if (dtddLink) dtddLink.href = 'https://www.doesthedogdie.com';
      if (dtddExpandable) dtddExpandable.style.display = 'none';
      if (dtddBtn) dtddBtn.textContent = '▼ Expand';
      if (dtddLoading) dtddLoading.style.display = 'block';
      if (dtddContent) { dtddContent.style.display = 'none'; dtddContent.innerHTML = ''; }

      const selLabel = document.getElementById('modalSelectedMediaLabel');
      if (selLabel) selLabel.textContent = modalCurrentMedia.name;

      const streamsList = document.getElementById('modalStreamsList');
      if (streamsList) streamsList.innerHTML = '<div style="color:var(--text-muted); text-align:center; padding:20px; font-size:0.88rem;"><div style="font-size:1.6rem; margin-bottom:8px;">⏳</div>Loading details and media streams…</div>';

      const streamsCount = document.getElementById('modalStreamsCount');
      if (streamsCount) streamsCount.textContent = '0';

      // Load DoesTheDogDie Content Advisories asynchronously
      loadModalDtddAdvisories(modalCurrentMedia.baseId, modalCurrentMedia.name);

      // Fetch comprehensive metadata (background, rating, synopsis, episodes)
      try {
        const res = await fetch('/api/media/details?id=' + encodeURIComponent(modalCurrentMedia.baseId) + '&type=' + cleanType);
        if (res.ok) {
          const data = await res.json();
          if (data && data.success && data.media) {
            const m = data.media;
            modalCurrentMedia.name = m.name || modalCurrentMedia.name;
            if (titleEl) titleEl.textContent = modalCurrentMedia.name;

            if (m.poster && posterEl) posterEl.src = m.poster;
            if (m.background && hero) hero.style.backgroundImage = 'url(' + m.background + ')';

            if (m.year && yearBadge) {
              yearBadge.textContent = m.year;
              yearBadge.style.display = 'inline-block';
            }

            // Render all rating sources side-by-side (IMDb, Rotten Tomatoes, Metacritic, TMDb)
            if (ratingsContainer) {
              if (m.ratings && Array.isArray(m.ratings) && m.ratings.length > 0) {
                ratingsContainer.innerHTML = m.ratings.map(r => {
                  const icon = r.icon || '⭐';
                  const src = r.source || '';
                  const val = r.value || '';
                  let bg = 'rgba(227, 179, 65, 0.15)';
                  let col = '#e3b341';
                  let bdr = 'rgba(227, 179, 65, 0.35)';

                  if (src.toLowerCase().includes('rotten')) {
                    bg = 'rgba(250, 50, 10, 0.15)';
                    col = '#fa320a';
                    bdr = 'rgba(250, 50, 10, 0.35)';
                  } else if (src.toLowerCase().includes('meta')) {
                    bg = 'rgba(0, 206, 56, 0.15)';
                    col = '#00ce38';
                    bdr = 'rgba(0, 206, 56, 0.35)';
                  } else if (src.toLowerCase().includes('tmdb')) {
                    bg = 'rgba(1, 180, 228, 0.15)';
                    col = '#01b4e4';
                    bdr = 'rgba(1, 180, 228, 0.35)';
                  }

                  return '<span class="badge" title="' + escapeHtml(src) + '" style="background:' + bg + '; color:' + col + '; border:1px solid ' + bdr + '; font-size:0.75rem; font-weight:700; display:inline-flex; align-items:center; gap:4px; padding:3px 7px;">'
                    + '<span>' + icon + '</span><span>' + escapeHtml(val) + '</span>'
                    + '<small style="opacity:0.85; font-size:0.68rem; font-weight:600; margin-left:1px;">' + escapeHtml(src) + '</small>'
                    + '</span>';
                }).join('');
              } else {
                const rawRating = m.imdbRating || m.rating;
                if (rawRating && rawRating !== 'N/A' && rawRating !== '0' && rawRating !== '0.0') {
                  ratingsContainer.innerHTML = '<span class="badge" style="background:rgba(227, 179, 65, 0.2); color:#e3b341; border:1px solid rgba(227, 179, 65, 0.4); font-size:0.75rem; font-weight:700;">⭐ ' + escapeHtml(rawRating) + '</span>';
                } else {
                  ratingsContainer.innerHTML = '';
                }
              }
            }

            if (m.genres && Array.isArray(m.genres) && genresEl) {
              genresEl.innerHTML = m.genres.map(g => '<span class="badge" style="background:#161b22; color:var(--text-muted); font-size:0.75rem;">' + escapeHtml(g) + '</span>').join('');
            }
            if (overviewEl) {
              overviewEl.textContent = m.description || m.overview || 'No synopsis available.';
            }

            if (cleanType === 'series') {
              modalSeriesDetails = m;
              renderModalSeriesBrowser(m);
              return; // renderModalSeriesBrowser will trigger scrape for S1E1
            }
          }
        }
      } catch (e) {
        console.error('Error fetching media details:', e);
      }

      // If movie or series without Cinemeta episodes: scrape directly!
      triggerModalScrape();
    }

    function toggleDtddExpand() {
      const panel = document.getElementById('modalDtddExpandable');
      const btn = document.getElementById('btnToggleDtdd');
      if (!panel) return;
      const isHidden = panel.style.display === 'none' || panel.style.display === '';
      panel.style.display = isHidden ? 'block' : 'none';
      if (btn) btn.textContent = isHidden ? '▲ Collapse' : '▼ Expand';
    }

    async function loadModalDtddAdvisories(id, title, year) {
      const card = document.getElementById('modalDtddCard');
      const badge = document.getElementById('modalDtddSummaryBadge');
      const link = document.getElementById('modalDtddLink');
      const loading = document.getElementById('modalDtddLoading');
      const content = document.getElementById('modalDtddContent');
      if (!card) return;

      try {
        const u = '/api/media/dtdd?id=' + encodeURIComponent(id) + (title ? '&title=' + encodeURIComponent(title) : '') + (year ? '&year=' + encodeURIComponent(year) : '');
        const res = await fetch(u);
        const data = await res.json();

        if (loading) loading.style.display = 'none';
        if (content) content.style.display = 'block';

        const targetUrl = (data && data.url) ? data.url : ('https://www.doesthedogdie.com/search?q=' + encodeURIComponent(title || id));
        if (link) {
          link.href = targetUrl;
        }

        if (data && data.matched && data.triggers && data.triggers.length > 0) {
          const triggers = data.triggers;
          const count = triggers.length;

          if (badge) {
            badge.textContent = '⚠️ ' + count + ' Advisory' + (count === 1 ? '' : 's');
            badge.style.background = 'rgba(248,81,73,0.18)';
            badge.style.color = '#f85149';
            badge.style.borderColor = 'rgba(248,81,73,0.35)';
            badge.style.display = 'inline-block';
          }

          let pillsHtml = triggers.map(t => {
            const commentTip = t.comment ? ' title="' + escapeHtml(t.comment) + '"' : '';
            const countTxt = (t.yes !== undefined && t.yes > 0) ? ' <small style="opacity:0.75;">(' + t.yes + ')</small>' : '';
            return '<span class="badge" style="background:rgba(248,81,73,0.15); color:#f85149; border:1px solid rgba(248,81,73,0.3); font-size:0.75rem; padding:4px 9px; margin-right:5px; margin-bottom:6px; display:inline-block;"' + commentTip + '>⚠️ ' + escapeHtml(t.topic) + countTxt + '</span>';
          }).join('');

          let safeHtml = '';
          if (data.safe && Array.isArray(data.safe) && data.safe.length > 0) {
            safeHtml = '<div style="margin-top:10px; padding-top:8px; border-top:1px solid #21262d;">'
              + '<div style="font-size:0.75rem; font-weight:700; color:#3fb950; margin-bottom:6px; text-transform:uppercase; letter-spacing:0.5px;">✓ Safe / Not Reported:</div>'
              + '<div style="display:flex; flex-wrap:wrap; gap:4px;">'
              + data.safe.slice(0, 10).map(s => '<span class="badge" style="background:rgba(63,185,80,0.12); color:#3fb950; border:1px solid rgba(63,185,80,0.25); font-size:0.72rem; padding:2px 7px;">✓ ' + escapeHtml(s.topic) + '</span>').join('')
              + '</div></div>';
          }

          if (content) {
            content.innerHTML = '<div style="font-size:0.78rem; color:var(--text-muted); margin-bottom:8px;">Crowdsourced advisory warnings confirmed for this title:</div>'
              + '<div style="display:flex; flex-wrap:wrap;">' + pillsHtml + '</div>'
              + safeHtml;
          }
        } else if (data && data.matched) {
          if (badge) {
            badge.textContent = '✓ No Major Triggers';
            badge.style.background = 'rgba(63,185,80,0.15)';
            badge.style.color = '#3fb950';
            badge.style.borderColor = 'rgba(63,185,80,0.35)';
            badge.style.display = 'inline-block';
          }
          if (content) {
            content.innerHTML = '<div style="font-size:0.82rem; color:#3fb950; display:flex; align-items:center; gap:8px;">'
              + '<span>✓ DoesTheDogDie: No major triggers confirmed by community.</span>'
              + '</div>';
          }
        } else {
          if (badge) {
            badge.textContent = 'ℹ️ Check on DTDD';
            badge.style.background = 'rgba(139,148,158,0.15)';
            badge.style.color = '#8b949e';
            badge.style.borderColor = 'rgba(139,148,158,0.3)';
            badge.style.display = 'inline-block';
          }
          if (content) {
            content.innerHTML = '<div style="font-size:0.82rem; color:var(--text-muted);">'
              + 'No community advisory reports cached yet. <a href="' + escapeHtml(targetUrl) + '" target="_blank" rel="noopener" style="color:#58a6ff; text-decoration:none;">Search and view advisories directly on DoesTheDogDie.com ↗</a>'
              + '</div>';
          }
        }
      } catch (e) {
        if (loading) loading.style.display = 'none';
        if (content) {
          content.style.display = 'block';
          content.innerHTML = '<div style="font-size:0.8rem; color:var(--text-muted);">Failed to load DoesTheDogDie advisories.</div>';
        }
      }
    }

    function renderModalSeriesBrowser(series) {
      const seriesBox = document.getElementById('modalSeriesBrowser');
      if (!seriesBox) return;
      seriesBox.style.display = 'block';

      const seasons = series.seasons || [1];
      const countEl = document.getElementById('modalSeasonsCount');
      if (countEl) countEl.textContent = seasons.length + ' Season' + (seasons.length === 1 ? '' : 's') + ' Available';

      // Render Seasons tabs
      const tabsBar = document.getElementById('modalSeasonTabs');
      if (tabsBar) {
        modalSelectedSeason = seasons.length > 0 ? seasons[0] : 1;
        tabsBar.innerHTML = seasons.map(s => {
          const isActive = s === modalSelectedSeason;
          return '<button type="button" class="modal-season-tab ' + (isActive ? 'active' : '') + '" onclick="switchModalSeason(' + s + ')">Season ' + s + '</button>';
        }).join('');
      }

      renderModalEpisodesGrid();

      // Auto-scrape Episode 1
      const eps = (series.episodesBySeason && series.episodesBySeason[String(modalSelectedSeason)]) || [];
      if (eps.length > 0) {
        const ep1 = eps[0];
        selectModalEpisode(ep1.id, ep1.season, ep1.episode, ep1.name, ep1.thumbnail, ep1.overview, false);
      }
      triggerModalScrape();
    }

    function switchModalSeason(sNum) {
      modalSelectedSeason = sNum;
      document.querySelectorAll('#modalSeasonTabs .modal-season-tab').forEach(b => {
        b.classList.toggle('active', b.textContent === 'Season ' + sNum);
      });
      renderModalEpisodesGrid();
    }

    function renderModalEpisodesGrid() {
      const grid = document.getElementById('modalEpisodesGrid');
      if (!grid || !modalSeriesDetails) return;

      const eps = (modalSeriesDetails.episodesBySeason && modalSeriesDetails.episodesBySeason[String(modalSelectedSeason)]) || [];
      if (eps.length === 0) {
        grid.innerHTML = '<div style="color:var(--text-muted); padding:16px; font-size:0.85rem;">No episodes found for Season ' + modalSelectedSeason + '.</div>';
        return;
      }

      grid.innerHTML = eps.map((ep, idx) => {
        const isActive = ep.id === modalSelectedEpId;
        const epThumb = ep.thumbnail || modalCurrentMedia.poster || '/logo.png';
        const epNumStr = 'S' + (ep.season < 10 ? '0' : '') + ep.season + 'E' + (ep.episode < 10 ? '0' : '') + ep.episode;
        const safeTitle = escapeHtml(ep.name || ('Episode ' + ep.episode));
        const safeOverview = escapeHtml(ep.overview || 'Click to scrape and stream this episode');

        return '<div class="modal-episode-card ' + (isActive ? 'active' : '') + '" data-idx="' + idx + '" onclick="onModalEpisodeCardClick(this)">' +
          '<img src="' + escapeHtml(epThumb) + '" class="modal-episode-thumb" onerror="this.src=&apos;/logo.png&apos;">' +
          '<div style="flex:1; min-width:0; display:flex; flex-direction:column; justify-content:center;">' +
            '<div style="font-size:0.75rem; color:#58a6ff; font-weight:700;">' + epNumStr + (ep.released ? ' • ' + escapeHtml(ep.released.substring(0, 10)) : '') + '</div>' +
            '<div style="font-size:0.88rem; font-weight:700; color:#fff; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; margin-top:2px;">' + safeTitle + '</div>' +
            '<div style="font-size:0.76rem; color:var(--text-muted); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; margin-top:2px;">' + safeOverview + '</div>' +
          '</div>' +
        '</div>';
      }).join('');
    }

    function onModalEpisodeCardClick(el) {
      const idx = parseInt(el.getAttribute('data-idx') || '0', 10);
      const eps = (modalSeriesDetails && modalSeriesDetails.episodesBySeason && modalSeriesDetails.episodesBySeason[String(modalSelectedSeason)]) || [];
      const ep = eps[idx];
      if (ep) {
        selectModalEpisode(ep.id, ep.season, ep.episode, ep.name, ep.thumbnail, ep.overview, true);
      }
    }

    function selectModalEpisode(epId, season, episode, title, thumb, overview, autoScrape = true) {
      modalSelectedEpId = epId;
      modalSelectedSeason = season;
      modalSelectedEpisode = episode;
      modalCurrentMedia.season = season;
      modalCurrentMedia.episode = episode;
      modalCurrentMedia.epTitle = title;

      // Update active card styling
      const grid = document.getElementById('modalEpisodesGrid');
      if (grid) {
        grid.querySelectorAll('.modal-episode-card').forEach(c => {
          c.classList.remove('active');
        });
      }

      const selLabel = document.getElementById('modalSelectedMediaLabel');
      if (selLabel) {
        selLabel.textContent = modalCurrentMedia.name + ' S' + season + 'E' + episode + (title ? ' (' + title + ')' : '');
      }

      if (autoScrape) {
        triggerModalScrape();
      }
    }

    async function triggerModalScrape() {
      if (!modalCurrentMedia) return;
      const streamsList = document.getElementById('modalStreamsList');
      const streamsCount = document.getElementById('modalStreamsCount');
      const btn = document.getElementById('btnModalScrape');

      if (btn) {
        btn.disabled = true;
        btn.textContent = 'Scraping…';
      }

      let targetId = modalCurrentMedia.baseId;
      if (modalCurrentMedia.isSeries) {
        targetId = modalSelectedEpId || (modalCurrentMedia.baseId + ':' + modalCurrentMedia.season + ':' + modalCurrentMedia.episode);
      }

      const displayTitle = modalCurrentMedia.name + (modalCurrentMedia.isSeries ? ' S' + modalCurrentMedia.season + 'E' + modalCurrentMedia.episode : '');

      if (streamsList) {
        streamsList.innerHTML = '<div style="color:var(--text-muted); text-align:center; padding:24px 16px; font-size:0.88rem;">' +
          '<div style="font-size:1.8rem; margin-bottom:8px;">📡</div>' +
          'Scraping all scrapers for <strong>"' + escapeHtml(displayTitle) + '"</strong>…' +
          '</div>';
      }

      try {
        const res = await fetch('/stream/' + modalCurrentMedia.type + '/' + encodeURIComponent(targetId) + '.json');
        const data = await res.json();
        const rawStreams = data.streams || [];

        modalScrapedStreams = rawStreams.map((s, idx) => {
          const finalUrl = normalizeStreamUrl(s.url);
          const rawName = (s.name || '').replace(/\\n/g, ' ');
          const rawTitle = (s.title || '').replace(/\\n/g, '\\n');

          let underlyingUrl = finalUrl;
          try {
            if (finalUrl.includes('?url=')) {
              const u = new URL(finalUrl);
              underlyingUrl = decodeURIComponent(u.searchParams.get('url') || finalUrl);
            }
          } catch (_) {}

          const hosterInfo = checkUrlHosterStatus(underlyingUrl);
          const isHosterOffline = (hosterInfo.isSupported && !hosterInfo.isOnline) || rawName.includes('Offline') || rawTitle.includes('Offline');

          return {
            idx: idx,
            name: rawName,
            title: rawTitle,
            url: finalUrl,
            underlyingUrl: underlyingUrl,
            hosterName: hosterInfo.name,
            isHosterOffline: isHosterOffline,
            isTorboxCached: rawName.includes('Cached') || rawTitle.includes('Cached') || rawName.includes('⚡') || rawTitle.includes('⚡'),
            isTorboxCaching: !isHosterOffline && (rawName.includes('Start Caching') || rawTitle.includes('Start Caching') || rawName.includes('☁️')),
            isDirect: !rawName.includes('TorBox') && !rawTitle.includes('TorBox'),
            is1080p: /1080p|2160p|4k/i.test(rawName + ' ' + rawTitle),
            is4k: /2160p|4k/i.test(rawName + ' ' + rawTitle)
          };
        });

        if (streamsCount) streamsCount.textContent = modalScrapedStreams.length;
        renderModalStreams(modalScrapedStreams);
      } catch (err) {
        if (streamsList) {
          streamsList.innerHTML = '<div style="color:#f85149; text-align:center; padding:20px;">Scraping failed: ' + escapeHtml(String(err)) + '</div>';
        }
      } finally {
        if (btn) {
          btn.disabled = false;
          btn.textContent = '⚡ Scrape Sources';
        }
      }
    }

    function filterModalStreams(filter, btn) {
      document.querySelectorAll('#modalStreamFilterChips .stream-filter-chip').forEach(b => b.classList.remove('active'));
      if (btn) btn.classList.add('active');

      let filtered = modalScrapedStreams;
      if (filter === 'torbox') {
        filtered = modalScrapedStreams.filter(s => s.isTorboxCached);
      } else if (filter === 'direct') {
        filtered = modalScrapedStreams.filter(s => s.isDirect);
      } else if (filter === '1080p') {
        filtered = modalScrapedStreams.filter(s => s.is1080p);
      }
      renderModalStreams(filtered);
    }

    function renderModalStreams(streams) {
      const container = document.getElementById('modalStreamsList');
      if (!container) return;

      if (!streams || streams.length === 0) {
        container.innerHTML = '<div style="background:#161b22; border:1px solid #30363d; border-radius:10px; padding:24px; text-align:center; color:var(--text-muted);">' +
          '<div style="font-size:1.8rem; margin-bottom:8px;">🔍</div>' +
          'No streams found for this selection with active filter.' +
          '</div>';
        return;
      }

      container.innerHTML = streams.map((s, idx) => {
        let badgeHtml = '';
        if (s.isTorboxCached) {
          badgeHtml = '<span class="badge" style="background:rgba(63, 185, 80, 0.15); color:#3fb950; border:1px solid rgba(63, 185, 80, 0.3); font-weight:700;">⚡ TorBox [Cached]</span>';
        } else if (s.isHosterOffline) {
          const hName = s.hosterName || 'Hoster';
          badgeHtml = '<span class="badge" style="background:rgba(248, 81, 73, 0.15); color:#f85149; border:1px solid rgba(248, 81, 73, 0.3); font-weight:700;">⚠️ TorBox: ' + escapeHtml(hName) + ' Offline</span>';
        } else if (s.isTorboxCaching) {
          badgeHtml = '<span class="badge" style="background:rgba(88, 166, 255, 0.15); color:#58a6ff; border:1px solid rgba(88, 166, 255, 0.3); font-weight:700;">☁️ TorBox [Start Caching]</span>';
        } else {
          badgeHtml = '<span class="badge" style="background:rgba(240, 136, 62, 0.15); color:#f0883e; border:1px solid rgba(240, 136, 62, 0.3); font-weight:700;">🌐 Direct Play</span>';
        }

        const rawTitle = (s.title || s.name || '');
        const nlIdx = rawTitle.indexOf('\\n');
        const mainTitle = nlIdx !== -1 ? rawTitle.substring(0, nlIdx) : rawTitle;
        const subDetails = nlIdx !== -1 ? rawTitle.substring(nlIdx + 1).split('\\n').join(' • ') : '';

        return '<div class="modal-stream-card" style="background:#161b22; border:1px solid #30363d; border-radius:10px; padding:12px 14px; display:flex; justify-content:space-between; align-items:center; gap:12px; flex-wrap:wrap;">' +
          '<div style="flex:1; min-width:200px;">' +
            '<div style="display:flex; gap:6px; align-items:center; flex-wrap:wrap; margin-bottom:4px;">' +
              badgeHtml +
              '<span class="badge" style="background:#090d13; color:var(--text-muted); font-size:0.75rem;">' + escapeHtml(s.name) + '</span>' +
            '</div>' +
            '<div style="font-size:0.92rem; font-weight:700; color:#fff; word-break:break-all;">' + escapeHtml(mainTitle) + '</div>' +
            (subDetails ? '<div style="font-size:0.78rem; color:var(--text-muted); margin-top:2px;">' + escapeHtml(subDetails) + '</div>' : '') +
          '</div>' +
          '<div style="display:flex; gap:6px; align-items:center; flex-wrap:wrap;">' +
            '<button class="btn btn-sm btn-success" style="padding:6px 12px; font-weight:700;" onclick="playModalStreamIdx(' + idx + ')">▶ Play</button>' +
            '<button class="btn btn-sm" style="padding:6px 10px;" onclick="openWithModalStreamIdx(' + idx + ')">🚀 External</button>' +
            '<button class="btn btn-sm" style="padding:6px 8px;" onclick="copyModalStreamIdx(' + idx + ')" title="Copy Stream URL">📋</button>' +
            (s.isTorboxCaching ? '<button class="btn btn-sm" style="padding:6px 8px; background:rgba(88,166,255,0.15); color:#58a6ff;" onclick="cacheModalStreamIdx(' + idx + ')" title="Send to TorBox Cache">☁️ Cache</button>' : '') +
          '</div>' +
        '</div>';
      }).join('');
    }

    function playModalStreamIdx(idx) {
      const s = modalScrapedStreams[idx];
      if (!s || !s.url) return;
      playStream(s.url, s.title || s.name);
    }

    function openWithModalStreamIdx(idx) {
      const s = modalScrapedStreams[idx];
      if (!s || !s.url) return;
      openWithModal(s.url, s.title || s.name);
    }

    function copyModalStreamIdx(idx) {
      const s = modalScrapedStreams[idx];
      if (!s || !s.url) return;
      navigator.clipboard.writeText(s.url).then(() => {
        showToast('📋 Link copied to clipboard!');
      });
    }

    function cacheModalStreamIdx(idx) {
      const s = modalScrapedStreams[idx];
      if (!s || !s.underlyingUrl) return;
      cacheStreamToTorbox(s.underlyingUrl);
    }


    function openCurrentInSearchTab() {
      if (!modalCurrentMedia) return;
      closeMediaDetailModal();
      switchMainTab('search');

      const typeSelect = document.getElementById('theaterMediaType');
      if (typeSelect) {
        typeSelect.value = modalCurrentMedia.type === 'series' ? 'series' : 'movie';
        toggleSeasonEpisodeInputs();
      }

      const searchInput = document.getElementById('theaterSearchQuery');
      if (searchInput) searchInput.value = modalCurrentMedia.baseId;

      if (modalCurrentMedia.isSeries) {
        const seasonEl = document.getElementById('theaterSeason');
        const episodeEl = document.getElementById('theaterEpisode');
        if (seasonEl) seasonEl.value = modalCurrentMedia.season;
        if (episodeEl) episodeEl.value = modalCurrentMedia.episode;
      }

      setTimeout(() => {
        executeTheaterSearch();
      }, 250);
    }

    function openActiveMediaInModal() {
      if (!window._activeMediaData) return;
      const m = window._activeMediaData;
      openMediaDetailModal(m.id, m.type, m.name, m.poster, m.isSeries, m.rating || m.imdbRating || '');
    }

    function onCatalogCardClick(el) {
      const id = decodeURIComponent(el.getAttribute('data-id') || '');
      const type = decodeURIComponent(el.getAttribute('data-type') || 'movie');
      const name = decodeURIComponent(el.getAttribute('data-name') || '');
      const poster = decodeURIComponent(el.getAttribute('data-poster') || '');
      const isSeries = el.getAttribute('data-series') === '1';
      const rating = decodeURIComponent(el.getAttribute('data-rating') || '');
      openMediaDetailModal(id, type, name, poster, isSeries, rating);
    }

    function loadMoreCatalog() {
      loadCatalog(false);
    }

    function catalogItemClick(id, type, name, poster, isSeries, rating) {
      openMediaDetailModal(id, type, name, poster, isSeries, rating || '');
    }


    function showToast(msg) {
      const toast = document.getElementById('toast');
      toast.innerText = msg;
      toast.style.display = 'block';
      setTimeout(() => { toast.style.display = 'none'; }, 3000);
    }

    function copyText(id) {
      const copyText = document.getElementById(id);
      copyText.select();
      copyText.setSelectionRange(0, 99999);
      navigator.clipboard.writeText(copyText.value);
      showToast('📋 Copied: ' + copyText.value);
    }

    function togglePasswordVisibility() {
      const input = document.getElementById('torboxApiKey');
      input.type = input.type === 'password' ? 'text' : 'password';
    }

    function setProviderFilter(term, btn) {
      document.querySelectorAll('#providerFilterChips .stream-filter-chip').forEach(c => c.classList.remove('active'));
      if (btn) btn.classList.add('active');
      const input = document.getElementById('providerSearchInput');
      input.value = term;
      filterProvidersList();
    }

    function filterProvidersList() {
      const query = document.getElementById('providerSearchInput').value.trim().toLowerCase();
      const cards = document.querySelectorAll('#providersGrid .provider-card');
      let visible = 0;
      cards.forEach(c => {
        const text = c.innerText.toLowerCase();
        const name = c.getAttribute('data-name') || '';
        const id = c.getAttribute('data-id') || '';
        const scope = c.getAttribute('data-scope') || '';
        const quality = c.getAttribute('data-quality') || '';
        if (!query || text.includes(query) || name.includes(query) || id.includes(query) || scope.includes(query) || quality.includes(query)) {
          c.style.display = '';
          visible++;
        } else {
          c.style.display = 'none';
        }
      });
      document.getElementById('providerFilteredCount').innerText = 'Showing ' + visible + ' of ' + cards.length;
    }

    async function toggleProvider(id, enabled) {
      try {
        const res = await fetch('/api/provider/' + id, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ enabled: enabled })
        });
        const data = await res.json();
        if (data.success) {
          const countSpan = document.getElementById('enabledCount');
          let current = parseInt(countSpan.innerText);
          countSpan.innerText = enabled ? current + 1 : current - 1;
          showToast((enabled ? 'Enabled ' : 'Disabled ') + id);
        }
      } catch (err) {
        showToast('Error updating provider');
      }
    }

    async function bulkToggle(enable) {
      const checkboxes = document.querySelectorAll('input[name="provider"]');
      const ids = Array.from(checkboxes).map(c => c.value);
      try {
        const res = await fetch('/api/providers/bulk', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ids: ids, enabled: enable })
        });
        const data = await res.json();
        if (data.success) {
          checkboxes.forEach(c => c.checked = enable);
          document.getElementById('enabledCount').innerText = enable ? checkboxes.length : 0;
          showToast(enable ? 'All providers enabled' : 'All providers disabled');
        }
      } catch (err) {
        showToast('Error updating providers');
      }
    }

    async function resetScrapers() {
      try {
        const res = await fetch('/api/scrapers/reset', { method: 'POST' });
        const data = await res.json();
        showToast('✅ ' + (data.message || 'Circuit breaker and scrapers reset!'));
      } catch (e) {
        showToast('❌ Error resetting scrapers: ' + e);
      }
    }

    async function saveTorboxKey() {
      const key = document.getElementById('torboxApiKey').value.trim();
      const btn = document.getElementById('btnSaveTorbox');
      const badge = document.getElementById('torboxStatusBadge');
      const info = document.getElementById('torboxAccountInfo');

      btn.disabled = true;
      btn.innerText = 'Validating...';

      try {
        const res = await fetch('/api/torbox/config', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ apiKey: key })
        });
        const data = await res.json();
        const acc = (data.account && data.account.valid !== undefined) ? data.account : data;
        if (data.success && acc.valid) {
          badge.innerText = '✅ ' + (acc.plan ? acc.plan.toUpperCase() : 'Connected');
          badge.style.background = 'rgba(35, 134, 54, 0.3)';
          badge.style.color = '#3fb950';
          info.style.display = 'block';
          info.innerHTML = '<strong>Account:</strong> ' + escapeHtml(acc.email || 'Active User') + ' | <strong>Plan:</strong> ' + escapeHtml(acc.plan || 'Standard') + (acc.expires ? ' (Expires: ' + escapeHtml(acc.expires) + ')' : '');
          showToast('✅ TorBox Connected: ' + (acc.plan || 'Active'));
        } else {
          badge.innerText = '❌ Invalid Key';
          badge.style.background = 'rgba(248, 81, 73, 0.3)';
          badge.style.color = '#f85149';
          info.style.display = 'block';
          info.innerHTML = '<span style="color:#f85149;">' + escapeHtml(acc.message || data.message || 'Invalid API Key') + '</span>';
          showToast('❌ Invalid TorBox API Key' + (acc.message ? ': ' + acc.message : ''));
        }
      } catch (e) {
        showToast('Error validating TorBox key: ' + e);
      } finally {
        btn.disabled = false;
        btn.innerText = '💾 Save & Validate';
      }
    }

    async function saveSettings() {
      const btn = document.getElementById('btnSaveSettings');
      btn.disabled = true;
      btn.innerText = 'Saving...';
      try {
        const res = await fetch('/api/settings', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            excludeCams: document.getElementById('chkExcludeCams').checked,
            maxResolution: document.getElementById('maxResSelect').value,
            preferredLanguage: document.getElementById('prefLangSelect').value,
            enableDeduplication: document.getElementById('chkDedupe').checked,
            enableDeadLinkFilter: document.getElementById('chkDeadLink').checked,
            enableOpenSubtitles: document.getElementById('chkOpenSubtitles') ? document.getElementById('chkOpenSubtitles').checked : true,
            showRatingsInStreams: false,
            omdbApiKey: document.getElementById('omdbApiKey').value.trim(),
            fanartApiKey: document.getElementById('fanartApiKey').value.trim(),
            tvdbApiKey: document.getElementById('tvdbApiKey').value.trim(),
            tmdbApiKey: document.getElementById('tmdbApiKey') ? document.getElementById('tmdbApiKey').value.trim() : '',
            dtddApiKey: document.getElementById('dtddApiKey') ? document.getElementById('dtddApiKey').value.trim() : '',
          })
        });
        const data = await res.json();
        if (data.success) {
          showToast('✅ Playback & API Settings Saved!');
        } else {
          showToast('❌ Error saving settings');
        }
      } catch (e) {
        showToast('Error saving settings: ' + e);
      } finally {
        btn.disabled = false;
        btn.innerText = '💾 Save Settings';
      }
    }

    async function testKey(service, inputId, badgeId) {
      const input = document.getElementById(inputId);
      const badge = document.getElementById(badgeId);
      const key = input ? input.value.trim() : '';

      badge.innerText = 'Testing...';
      badge.style.background = '#21262d';
      badge.style.color = '#fff';

      try {
        const res = await fetch('/api/keys/validate', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ service: service, key: key })
        });
        const data = await res.json();
        if (data.valid) {
          badge.innerText = '✅ Valid';
          badge.style.background = 'rgba(35, 134, 54, 0.3)';
          badge.style.color = '#3fb950';
          showToast('✅ ' + data.message);
        } else {
          badge.innerText = '❌ Invalid';
          badge.style.background = 'rgba(248, 81, 73, 0.3)';
          badge.style.color = '#f85149';
          showToast('❌ ' + data.message);
        }
      } catch (err) {
        badge.innerText = '⚠️ Error';
        badge.style.background = 'rgba(210, 153, 34, 0.3)';
        badge.style.color = '#d29922';
        showToast('Validation request failed: ' + err);
      }
    }

    async function uploadLinkToTorbox(targetUrl, btnElement) {
      const url = targetUrl || (document.getElementById('torboxUploadUrl') ? document.getElementById('torboxUploadUrl').value.trim() : '');
      const status = document.getElementById('torboxUploadStatus');
      if (!url) {
        showToast('Please enter a link to cache');
        return;
      }

      if (btnElement) {
        btnElement.disabled = true;
        btnElement.innerText = '⏳ Caching...';
      }

      if (status) {
        status.style.display = 'block';
        status.innerHTML = '<span style="color:var(--blue);">Submitting link to TorBox cloud cache...</span>';
      }

      try {
        const res = await fetch('/api/torbox/upload', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ url: url })
        });
        const data = await res.json();
        if (data.success) {
          if (status) status.innerHTML = '<span style="color:var(--green);">✅ ' + escapeHtml(data.message) + '</span>';
          showToast('✅ ' + (data.message || 'Queued to TorBox Cache!'));
          if (btnElement) {
            btnElement.innerText = '✅ Caching Started';
          }
        } else {
          if (status) status.innerHTML = '<span style="color:#f85149;">❌ ' + escapeHtml(data.message) + '</span>';
          showToast('❌ ' + (data.message || 'Cache failed'));
          if (btnElement) {
            btnElement.disabled = false;
            btnElement.innerText = '☁️⬆️ Cache to TorBox';
          }
        }
      } catch (e) {
        if (status) status.innerHTML = '<span style="color:#f85149;">Upload error: ' + e + '</span>';
        showToast('❌ Upload error: ' + e);
        if (btnElement) {
          btnElement.disabled = false;
          btnElement.innerText = '☁️⬆️ Cache to TorBox';
        }
      }
    }

    function checkUrlHosterStatus(url) {
      if (!url) return { isSupported: false, isOnline: false, name: '' };
      const clean = url.toLowerCase().split('?')[0];
      if (clean.endsWith('.mp4') || clean.endsWith('.mkv') || clean.endsWith('.avi') || clean.endsWith('.webm') || clean.endsWith('.ts')) {
        return { isSupported: true, isOnline: true, name: 'Direct Video' };
      }
      if (window.torboxHosters && Array.isArray(window.torboxHosters)) {
        for (const h of window.torboxHosters) {
          const isUp = h.status === 'online' || h.status === true || h.status === 'up' || h.status === 1;
          const domains = Array.isArray(h.domains) ? h.domains : (typeof h.domains === 'string' ? h.domains.split(/[\s,]+/) : []);
          for (const d of domains) {
            if (d && clean.includes(d.toLowerCase())) {
              return { isSupported: true, isOnline: isUp, name: h.name || d };
            }
          }
        }
      }
      return { isSupported: false, isOnline: false, name: '' };
    }

    async function loadTorboxHosters() {
      const grid = document.getElementById('hostersGrid');
      const btn = document.getElementById('btnRefreshHosters');
      if (btn) { btn.disabled = true; btn.innerText = '🔄 Loading...'; }
      grid.innerHTML = '<div style="color:var(--text-muted); padding:10px;">Fetching active hosters from TorBox...</div>';

      try {
        const res = await fetch('/api/torbox/hosters');
        const data = await res.json();
        if (data && data.success && Array.isArray(data.hosters)) {
          window.torboxHosters = data.hosters;
          renderHosters(data.hosters);
          showToast('✅ Loaded ' + data.hosters.length + ' TorBox hosters');
        } else {
          grid.innerHTML = '<div style="color:#f85149; padding:10px;">Failed to load hosters from TorBox.</div>';
        }
      } catch (e) {
        console.error('loadTorboxHosters error:', e);
        grid.innerHTML = '<div style="color:#f85149; padding:10px;">Error loading hosters: ' + escapeHtml(e) + '</div>';
      } finally {
        if (btn) { btn.disabled = false; btn.innerText = '🔄 Refresh Hosters'; }
      }
    }

    function renderHosters(hosters) {
      const grid = document.getElementById('hostersGrid');
      if (!grid) return;
      if (!hosters || !Array.isArray(hosters) || hosters.length === 0) {
        grid.innerHTML = '<div style="color:var(--text-muted); padding:10px;">No hosters found.</div>';
        return;
      }
      grid.innerHTML = hosters.map(h => {
        const isUp = h.status === 'online' || h.status === true || h.status === 'up';
        const hosterName = escapeHtml(h.name || h.id || 'Hoster');
        let domainList = [];
        if (Array.isArray(h.domains)) {
          domainList = h.domains;
        } else if (typeof h.domains === 'string') {
          domainList = h.domains.split(/[\s,]+/);
        }
        const domains = escapeHtml(domainList.filter(Boolean).slice(0, 3).join(', '));
        const statusClass = isUp ? 'status-up' : 'status-down';
        const statusText = isUp ? 'ONLINE' : 'DOWN';
        return '<div class="hoster-card">'
          + '<div style="display:flex; justify-content:space-between; align-items:center;">'
          + '<span class="hoster-name">' + hosterName + '</span>'
          + '<span class="hoster-status ' + statusClass + '">' + statusText + '</span>'
          + '</div>'
          + '<div class="hoster-domains">' + domains + '</div>'
          + '</div>';
      }).join('');
    }

    function filterHosters() {
      const q = document.getElementById('hosterSearch').value.toLowerCase().trim();
      if (!window.torboxHosters) return;
      const filtered = window.torboxHosters.filter(h => {
        const name = (h.name || h.id || '').toLowerCase();
        const domains = (Array.isArray(h.domains) ? h.domains.join(' ') : String(h.domains || '')).toLowerCase();
        return name.includes(q) || domains.includes(q);
      });
      renderHosters(filtered);
    }

    function normalizeStreamUrl(url) {
      if (!url) return '';
      if (url.startsWith('/')) {
        return window.location.origin + url;
      }
      return url;
    }

    function toggleSeasonEpisodeInputs() {
      const type = document.getElementById('theaterMediaType').value;
      const row = document.getElementById('seriesInputsRow');
      if (row) {
        row.style.display = (type === 'series') ? 'inline-flex' : 'none';
      }
    }

    let currentSeriesMeta = null;
    let selectedSeasonNum = 1;
    let activeEpisodeId = null;

    async function executeTheaterSearch() {
      const type = document.getElementById('theaterMediaType').value;
      const query = document.getElementById('theaterSearchQuery').value.trim();
      const suggestionsBox = document.getElementById('searchSuggestionsContainer');
      const resultsDiv = document.getElementById('testResults');
      const btn = document.getElementById('btnTheaterSearch');

      if (!query) return;

      // If user entered direct IMDb ID or TMDB ID
      if (query.startsWith('tt') || query.startsWith('tmdb:')) {
        suggestionsBox.style.display = 'none';
        const baseId = query.split(':')[0];
        const isSeries = (type === 'series');
        openMediaDetailModal(baseId, type, query, null, isSeries, '');
        return;
      }

      // Title Search via /api/search?q=...&type=...
      btn.disabled = true;
      btn.innerText = 'Searching...';
      suggestionsBox.style.display = 'block';
      suggestionsBox.innerHTML = '<div style="color:var(--text-muted); padding:10px;">Searching catalog for "' + escapeHtml(query) + '"...</div>';

      try {
        const res = await fetch('/api/search?q=' + encodeURIComponent(query) + '&type=' + type);
        const data = await res.json();
        const results = (data && data.results) ? data.results : [];

        if (results.length === 0) {
          suggestionsBox.innerHTML = '<div style="color:var(--text-muted); padding:10px;">No exact title matches found in Cinemeta/TMDB. Opening scraper modal for "' + escapeHtml(query) + '"...</div>';
          openMediaDetailModal(query, type, query, null, type === 'series', '');
        } else {
          window._searchResults = results;
          let html = '<div style="font-size:0.85rem; color:var(--text-muted); margin-bottom:8px; font-weight:600;">Found ' + results.length + ' match(es) — click any title to expand details &amp; discover streams:</div>';
          html += '<div class="search-suggestions-grid">';
          for (let i = 0; i < results.length; i++) {
            const m = results[i];
            const posterUrl = m.poster || ('https://images.metahub.space/poster/medium/' + m.id + '/img');
            const yearStr = m.year ? ' (' + m.year + ')' : '';
            const ratingVal = m.rating || m.imdbRating || '';
            const ratingBadge = ratingVal ? ' <span style="background:rgba(227,179,65,0.2);color:#e3b341;border:1px solid rgba(227,179,65,0.35);font-size:0.7rem;padding:1px 5px;border-radius:4px;font-weight:700;">⭐ ' + escapeHtml(ratingVal) + '</span>' : '';
            html += '<div class="search-suggestion-item" data-idx="' + i + '" onclick="onSearchSuggestionCardClick(this)">'
              + '<img src="' + encodeURI(posterUrl) + '" class="search-suggestion-thumb" onerror="this.src=&apos;/logo.png&apos;">'
              + '<div style="overflow:hidden; flex:1;">'
              + '<div style="font-weight:600; font-size:0.88rem; color:#fff; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">' + escapeHtml(m.name || m.title || 'Unknown') + '</div>'
              + '<div style="font-size:0.75rem; color:var(--text-muted); display:flex; align-items:center; gap:6px; margin-top:3px;">'
              + '<span>' + escapeHtml(m.type || type).toUpperCase() + yearStr + '</span>'
              + ratingBadge
              + '</div>'
              + '</div>'
              + '</div>';
          }
          html += '</div>';
          suggestionsBox.innerHTML = html;
        }
      } catch (err) {
        suggestionsBox.innerHTML = '<div style="color:#f85149; padding:10px;">Search request error: ' + err + '</div>';
        openMediaDetailModal(query, type, query, null, type === 'series', '');
      } finally {
        btn.disabled = false;
        btn.innerText = '🔍 Search & Scrape';
      }
    }

    function onSearchSuggestionCardClick(el) {
      const idx = parseInt(el.getAttribute('data-idx') || '0', 10);
      if (!window._searchResults || !window._searchResults[idx]) return;
      const m = window._searchResults[idx];
      const isSeries = (m.type === 'series' || m.type === 'tv');
      const poster = m.poster || ('https://images.metahub.space/poster/medium/' + m.id + '/img');
      const rating = m.rating || m.imdbRating || '';
      openMediaDetailModal(m.id, m.type || (isSeries ? 'series' : 'movie'), m.name, poster, isSeries, rating);
    }

    function selectSearchSuggestion(id, type, name, year, poster, desc, rating) {
      const isSeries = (type === 'series' || type === 'tv');
      openMediaDetailModal(id, type, name, poster, isSeries, rating || '');
    }

    async function loadSeriesCatalog(seriesId, initialName, poster) {
      const catalogBox = document.getElementById('seriesCatalogContainer');
      catalogBox.style.display = 'block';
      catalogBox.innerHTML = '<div style="color:var(--text-muted); padding:14px; background:#0d1117; border:1px solid var(--border); border-radius:10px; margin-bottom:14px;">Loading seasons and episodes catalog for ' + escapeHtml(initialName || seriesId) + '...</div>';

      try {
        const res = await fetch('/api/series/episodes?id=' + encodeURIComponent(seriesId));
        const data = await res.json();
        if (data && data.success && data.series) {
          currentSeriesMeta = data.series;
          const seasons = data.series.seasons || [1];
          selectedSeasonNum = seasons.length > 0 ? seasons[0] : 1;
          renderSeriesCatalog();

          // Auto scrape Episode 1 of first season
          const firstSeasonEps = (data.series.episodesBySeason && data.series.episodesBySeason[String(selectedSeasonNum)]) || [];
          if (firstSeasonEps.length > 0) {
            const ep1 = firstSeasonEps[0];
            activeEpisodeId = ep1.id;
            scrapeMediaById(ep1.id, 'series', currentSeriesMeta.name + ' S' + ep1.season + 'E' + ep1.episode + ': ' + ep1.name, ep1.thumbnail || currentSeriesMeta.poster, ep1.overview, currentSeriesMeta.year);
          }
        } else {
          catalogBox.innerHTML = '<div style="color:var(--text-muted); padding:10px; background:#0d1117; border:1px solid var(--border); border-radius:10px; margin-bottom:14px;">Episode catalog not available via Cinemeta. Using manual S/E inputs above.</div>';
          const s = document.getElementById('theaterSeason').value || '1';
          const e = document.getElementById('theaterEpisode').value || '1';
          scrapeMediaById(seriesId + ':' + s + ':' + e, 'series', initialName || seriesId, poster, null, null);
        }
      } catch (err) {
        catalogBox.innerHTML = '<div style="color:#f85149; padding:10px; background:#0d1117; border:1px solid var(--border); border-radius:10px; margin-bottom:14px;">Error loading episode catalog: ' + err + '</div>';
        const s = document.getElementById('theaterSeason').value || '1';
        const e = document.getElementById('theaterEpisode').value || '1';
        scrapeMediaById(seriesId + ':' + s + ':' + e, 'series', initialName || seriesId, poster, null, null);
      }
    }

    function renderSeriesCatalog() {
      const catalogBox = document.getElementById('seriesCatalogContainer');
      if (!currentSeriesMeta) return;

      const seasons = currentSeriesMeta.seasons || [1];
      const epsBySeason = currentSeriesMeta.episodesBySeason || {};
      const currentEps = epsBySeason[String(selectedSeasonNum)] || [];

      let html = '<div style="margin-top:6px; margin-bottom:14px; background:#0d1117; border:1px solid var(--border); border-radius:10px; padding:16px;">';
      html += '<div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px; flex-wrap:wrap; gap:8px;">';
      html += '<div style="font-weight:700; font-size:0.95rem; color:#fff;">📺 Seasons &amp; Episodes Catalog (' + escapeHtml(currentSeriesMeta.name) + ')</div>';
      html += '<span style="font-size:0.8rem; color:var(--text-muted);">' + seasons.length + ' Season(s) Available</span>';
      html += '</div>';

      // Seasons Tab Bar
      html += '<div class="seasons-bar">';
      for (const sNum of seasons) {
        const isActive = (sNum === selectedSeasonNum);
        html += '<button type="button" class="season-tab ' + (isActive ? 'active' : '') + '" onclick="switchSeason(' + sNum + ')">Season ' + sNum + '</button>';
      }
      html += '</div>';

      // Episodes Grid
      html += '<div class="episodes-grid">';
      for (const ep of currentEps) {
        const isActiveEp = (ep.id === activeEpisodeId);
        const epThumb = ep.thumbnail || currentSeriesMeta.poster || '/logo.png';
        const epNumStr = 'S' + (ep.season < 10 ? '0' : '') + ep.season + 'E' + (ep.episode < 10 ? '0' : '') + ep.episode;
        html += `
          <div class="episode-card \${isActiveEp ? 'active' : ''}" onclick="selectEpisodeCard('\${escapeHtml(ep.id)}', \${ep.season}, \${ep.episode}, '\${escapeHtml(ep.name)}', '\${escapeHtml(epThumb)}', '\${escapeHtml(ep.overview)}')">
            <img src="\${epThumb}" class="episode-thumb" onerror="this.src='/logo.png'">
            <div class="episode-content">
              <div>
                <div class="episode-num">\${epNumStr} \${ep.released ? '• ' + escapeHtml(ep.released.substring(0, 10)) : ''}</div>
                <div class="episode-title">\${escapeHtml(ep.name)}</div>
              </div>
              <div class="episode-desc">\${escapeHtml(ep.overview || 'Click to scrape and stream this episode')}</div>
            </div>
          </div>
        `;
      }
      html += '</div>';
      html += '</div>';

      catalogBox.innerHTML = html;
    }

    function switchSeason(sNum) {
      selectedSeasonNum = sNum;
      renderSeriesCatalog();
    }

    function selectEpisodeCard(epId, season, episode, epTitle, thumb, overview) {
      activeEpisodeId = epId;
      document.getElementById('theaterSeason').value = season;
      document.getElementById('theaterEpisode').value = episode;
      renderSeriesCatalog();

      const fullTitle = currentSeriesMeta ? (currentSeriesMeta.name + ' S' + season + 'E' + episode + ': ' + epTitle) : epTitle;
      scrapeMediaById(epId, 'series', fullTitle, thumb, overview, currentSeriesMeta ? currentSeriesMeta.year : null);
    }

    async function scrapeMediaById(id, type, name, poster, desc, year) {
      const activeCard = document.getElementById('activeMediaContainer');
      const resultsDiv = document.getElementById('testResults');
      const btn = document.getElementById('btnTheaterSearch');

      activeCard.style.display = 'block';
      const posterImg = poster || ('https://images.metahub.space/poster/medium/' + (id.split(':')[0]) + '/img');
      const displayTitle = name || id;
      window._activeMediaData = {
        id: id.split(':')[0],
        type: type,
        name: displayTitle,
        poster: posterImg,
        isSeries: type === 'series'
      };

      activeCard.innerHTML = `
        <div class="media-card-box">
          <img src="\${posterImg}" class="media-card-poster" onerror="this.src='/logo.png'">
          <div style="flex:1;">
            <div style="display:flex; justify-content:space-between; align-items:flex-start; gap:10px; flex-wrap:wrap;">
              <div>
                <h3 style="font-size:1.15rem; color:#fff; font-weight:700;">\${escapeHtml(displayTitle)}</h3>
                <div style="font-size:0.8rem; color:var(--text-muted); margin-top:2px;">
                  <span class="badge" style="background:#21262d; margin-right:4px;">\${escapeHtml(type).toUpperCase()}</span>
                  <span>\${escapeHtml(id)}\${displayYear}</span>
                </div>
              </div>
              <button class="btn btn-sm" onclick="openActiveMediaInModal()" style="font-size:0.78rem; padding:4px 10px; white-space:nowrap; background:#161b22; border:1px solid #30363d;">
                ⛶ Full Expand (Nuvio View)
              </button>
            </div>
            \${desc ? '<p style="font-size:0.82rem; color:var(--text-muted); margin-top:8px; line-height:1.4; max-height:48px; overflow:hidden;">' + escapeHtml(desc) + '</p>' : ''}
          </div>
        </div>
      `;

      btn.disabled = true;
      btn.innerText = 'Scraping...';
      resultsDiv.style.display = 'block';
      resultsDiv.innerHTML = '<div style="color:var(--text-muted); padding:10px;">Scraping all enabled providers for "<strong>' + escapeHtml(displayTitle) + '</strong>" (' + escapeHtml(id) + ')...</div>';

      try {
        const res = await fetch('/stream/' + type + '/' + encodeURIComponent(id) + '.json');
        const data = await res.json();
        const rawStreams = data.streams || [];

        currentStreams = rawStreams.map((s, idx) => {
          const finalUrl = normalizeStreamUrl(s.url);
          const rawName = (s.name || '').replace(/\\n/g, ' ');
          const rawTitle = (s.title || '').replace(/\\n/g, '\\n');

          // Extract underlying target URL if wrapped in /torbox/play?url=... or /proxy?url=...
          let underlyingUrl = finalUrl;
          try {
            if (finalUrl.includes('?url=')) {
              const u = new URL(finalUrl);
              underlyingUrl = decodeURIComponent(u.searchParams.get('url') || finalUrl);
            }
          } catch (_) {}

          const lowerUrl = underlyingUrl.toLowerCase();
          const isHlsOrDash = lowerUrl.includes('.m3u8') || lowerUrl.includes('.mpd');

          const isTorboxCached = rawName.includes('[Cached]') || rawTitle.includes('Cached on TorBox');
          const isTorboxCachable = rawName.toLowerCase().includes('cachable') || rawName.includes('Start Caching') || rawName.includes('[Cache]') || rawTitle.toLowerCase().includes('cachable') || rawTitle.toLowerCase().includes('start caching');

          const hosterInfo = checkUrlHosterStatus(underlyingUrl);
          const isHosterOffline = (hosterInfo.isSupported && !hosterInfo.isOnline) || rawName.includes('Offline') || rawTitle.includes('Offline');

          // A stream is cachable to TorBox only if it is not HLS/DASH, not already cached, and the hoster is NOT offline!
          const isSupportedHoster = !isHlsOrDash && !isTorboxCached && !isHosterOffline && (
            isTorboxCachable ||
            hosterInfo.isOnline ||
            lowerUrl.endsWith('.mp4') || lowerUrl.endsWith('.mkv') || lowerUrl.endsWith('.avi') || lowerUrl.endsWith('.webm') || lowerUrl.endsWith('.ts')
          );

          return {
            index: idx,
            name: rawName,
            title: rawTitle,
            url: finalUrl,
            underlyingUrl: underlyingUrl,
            mediaTitle: displayTitle,
            hosterName: hosterInfo.name,
            isHosterOffline: isHosterOffline,
            isCached: isTorboxCached,
            isCache: isTorboxCachable,
            isCachableToTorbox: isSupportedHoster,
            is4K: rawName.includes('4K') || rawTitle.includes('[4K]'),
            is1080p: rawName.includes('1080p') || rawTitle.includes('[FHD]') || rawTitle.includes('1080p'),
          };
        });

        if (currentStreams.length === 0) {
          resultsDiv.innerHTML = '<div style="color:#f85149; padding:10px;">No streams found for ' + escapeHtml(displayTitle) + '. Check that your scrapers are enabled above.</div>';
        } else {
          renderFilteredStreams('all');
        }
      } catch (err) {
        const isNetErr = String(err).includes('NetworkError') || String(err).includes('Failed to fetch');
        const msg = isNetErr
          ? 'Network connection interrupted (server may be restarting or busy). Please click "Search & Scrape" again.'
          : String(err);
        resultsDiv.innerHTML = '<div style="color:#f85149; padding:10px;">⚠️ ' + escapeHtml(msg) + '</div>';
      } finally {
        btn.disabled = false;
        btn.innerText = '🔍 Search & Scrape';
      }
    }

    function runTest() {
      executeTheaterSearch();
    }

    function renderFilteredStreams(filter) {
      activeFilter = filter;
      const resultsDiv = document.getElementById('testResults');

      const count4K = currentStreams.filter(s => s.is4K).length;
      const count1080p = currentStreams.filter(s => s.is1080p).length;
      const countCached = currentStreams.filter(s => s.isCached).length;
      const countCachable = currentStreams.filter(s => s.isCache).length;
      const countDirect = currentStreams.filter(s => !s.isCached && !s.isCache).length;

      let filtered = currentStreams;
      if (filter === '4k') filtered = currentStreams.filter(s => s.is4K);
      else if (filter === '1080p') filtered = currentStreams.filter(s => s.is1080p);
      else if (filter === 'cached') filtered = currentStreams.filter(s => s.isCached);
      else if (filter === 'cachable' || filter === 'cache') filtered = currentStreams.filter(s => s.isCache);
      else if (filter === 'direct') filtered = currentStreams.filter(s => !s.isCached && !s.isCache);

      let html = `
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px; flex-wrap:wrap; gap:8px;">
          <div style="font-weight:600; color:var(--green); font-size:1rem;">Found \${currentStreams.length} stream(s):</div>
          <div class="stream-filter-bar">
            <span class="stream-filter-chip \${filter === 'all' ? 'active' : ''}" onclick="renderFilteredStreams('all')">All (\${currentStreams.length})</span>
            <span class="stream-filter-chip \${filter === '4k' ? 'active' : ''}" onclick="renderFilteredStreams('4k')">4K UHD (\${count4K})</span>
            <span class="stream-filter-chip \${filter === '1080p' ? 'active' : ''}" onclick="renderFilteredStreams('1080p')">1080p FHD (\${count1080p})</span>
            <span class="stream-filter-chip \${filter === 'cached' ? 'active' : ''}" onclick="renderFilteredStreams('cached')">⚡ Cached (\${countCached})</span>
            <span class="stream-filter-chip \${filter === 'cachable' || filter === 'cache' ? 'active' : ''}" onclick="renderFilteredStreams('cachable')">🌐 TorBox Cachable (\${countCachable})</span>
            <span class="stream-filter-chip \${filter === 'direct' ? 'active' : ''}" onclick="renderFilteredStreams('direct')">🌐 Direct Play (\${countDirect})</span>
          </div>
        </div>
      `;

      for (let i = 0; i < filtered.length; i++) {
        const s = filtered[i];
        html += '<div class="stream-item">';
        html += '  <div class="stream-info">';
        html += '    <div class="stream-title">' + escapeHtml(s.name) + '</div>';
        html += '    <div class="stream-sub">' + escapeHtml(s.title) + '</div>';
        html += '  </div>';
        html += '  <div class="stream-actions">';
        html += '    <button class="btn btn-play" onclick="openPlayerModal(' + s.index + ')">▶️ Web Mode</button>';
        html += '    <button class="btn btn-open-with" onclick="showOpenWithModal(' + s.index + ')">🚀 Open With...</button>';
        html += '    <button class="btn" onclick="downloadM3uCurrent(' + s.index + ')">📥 .m3u</button>';
        html += '    <button class="btn" onclick="copyStreamUrl(' + s.index + ')">📋 URL</button>';
        if (s.isCachableToTorbox) {
          const btnLabel = s.isCache ? '☁️⬆️ Start TorBox Cache' : '☁️⬆️ Cache to TorBox';
          html += '    <button class="btn btn-success" onclick="uploadStreamToTorbox(' + s.index + ', this)">' + btnLabel + '</button>';
        } else if (s.isHosterOffline) {
          html += '    <span class="badge" style="background:rgba(248,81,73,0.15); color:#f85149; border:1px solid rgba(248,81,73,0.3); font-size:0.75rem; padding:6px 9px; display:inline-flex; align-items:center;" title="TorBox debrider for this hoster is currently offline">⚠️ ' + escapeHtml(s.hosterName || 'Hoster') + ' Offline on TorBox</span>';
        }
        html += '  </div>';
        html += '</div>';
      }

      resultsDiv.innerHTML = html;
    }

    function uploadStreamToTorbox(idx, btn) {
      const s = currentStreams[idx];
      if (s) {
        const target = s.underlyingUrl || s.url;
        uploadLinkToTorbox(target, btn);
      }
    }

    function openPlayerModal(idx) {
      const s = currentStreams[idx];
      if (!s || !s.url) return;
      currentPlayingIndex = idx;
      playStream(s.url, (s.mediaTitle ? s.mediaTitle + ' • ' : '') + s.name);
    }

    function openWithFromPlayer() {
      if (currentPlayingIndex !== null) {
        showOpenWithModal(currentPlayingIndex);
      }
    }

    function changePlayerSpeed(speed) {
      const video = document.getElementById('previewVideoPlayer');
      if (video) {
        video.playbackRate = parseFloat(speed) || 1.0;
        showToast('Playback speed: ' + speed + 'x');
      }
    }

    function showOpenWithModal(idx) {
      const s = currentStreams[idx];
      if (!s || !s.url) return;
      selectedStreamForOpenWith = s;
      openWithModal(s.url, (s.mediaTitle ? s.mediaTitle + ' • ' : '') + s.name);
    }

    function closeOpenWithModal(e) {
      const modal = document.getElementById('openWithModal');
      if (modal) modal.style.display = 'none';
    }

    function downloadM3u(title, streamUrl) {
      const cleanTitle = (title || 'Hostreamio_Stream').split(String.fromCharCode(10)).join(' ').split(String.fromCharCode(13)).join('');
      const m3uContent = '#EXTM3U\\n#EXTINF:-1,' + cleanTitle + '\\n' + streamUrl + '\\n';
      const blob = new Blob([m3uContent], { type: 'application/x-mpegurl' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = (cleanTitle.replace(/[^a-zA-Z0-9_-]/g, '_')) + '.m3u';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      showToast('📥 Downloaded .m3u playlist! Double-click to play');
    }

    function downloadM3uCurrent(idx) {
      const s = currentStreams[idx];
      if (s && s.url) {
        downloadM3u((s.mediaTitle || 'Hostreamio') + ' - ' + s.name, s.url);
      }
    }

    function downloadM3uCurrentStream() {
      if (selectedStreamForOpenWith && selectedStreamForOpenWith.url) {
        downloadM3u((selectedStreamForOpenWith.mediaTitle || 'Hostreamio') + ' - ' + selectedStreamForOpenWith.name, selectedStreamForOpenWith.url);
      }
    }

    function copyCurrentStreamUrl() {
      if (selectedStreamForOpenWith && selectedStreamForOpenWith.url) {
        navigator.clipboard.writeText(selectedStreamForOpenWith.url);
        showToast('📋 Stream URL copied to clipboard!');
      }
    }

    function closePlayerModal(e) {
      const modal = document.getElementById('playerModal');
      const video = document.getElementById('previewVideoPlayer');
      video.pause();
      if (currentHls) {
        currentHls.destroy();
        currentHls = null;
      }
      video.removeAttribute('src');
      video.load();
      modal.style.display = 'none';
    }

    function escapeHtml(str) {
      return String(str == null ? '' : str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
    }

    function copyStreamUrl(idx) {
      const s = currentStreams[idx];
      if (s && s.url) {
        navigator.clipboard.writeText(s.url);
        showToast('✅ Stream URL copied to clipboard!');
      }
    }

    async function triggerUpdateChannel(channel) {
      const consoleBox = document.getElementById('pipelineConsoleBox');
      const consoleEl = document.getElementById('pipelineConsole');
      const badge = document.getElementById('pipelineConsoleBadge');
      const masterBtn = document.getElementById('btnMasterUpdate');

      consoleBox.style.display = 'block';
      consoleBox.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      badge.style.background = '#d29922';
      badge.style.color = '#000';
      badge.innerText = 'Running (' + channel + ')...';
      
      const timeStr = new Date().toLocaleTimeString();
      consoleEl.textContent = '[' + timeStr + '] Starting update pipeline for channel: ' + channel + '...\\n';

      if (masterBtn) masterBtn.disabled = true;

      try {
        const res = await fetch('/api/pipeline/update', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ channel: channel })
        });
        const data = await res.json();
        
        consoleEl.textContent += (data.output ? data.output + '\\n' : '');
        consoleEl.textContent += '[' + new Date().toLocaleTimeString() + '] ' + (data.message || 'Done.\\n');
        consoleEl.scrollTop = consoleEl.scrollHeight;

        if (data.success) {
          badge.style.background = '#238636';
          badge.style.color = '#fff';
          badge.innerText = 'Completed';
          showToast('✅ ' + (data.message || 'Updated successfully!'));
        } else {
          badge.style.background = '#f85149';
          badge.style.color = '#fff';
          badge.innerText = 'Failed';
          showToast('❌ Update failed: ' + (data.message || 'Unknown error'));
        }
      } catch (e) {
        consoleEl.textContent += '\\n[ERROR] Pipeline execution error: ' + e + '\\n';
        badge.style.background = '#f85149';
        badge.style.color = '#fff';
        badge.innerText = 'Error';
        showToast('❌ Update request error: ' + e);
      } finally {
        if (masterBtn) masterBtn.disabled = false;
      }
    }

    async function checkGitHubReleases() {
      const infoSpan = document.getElementById('releaseCheckInfo');
      const btn = document.getElementById('btnCheckRelease');
      const versionBadge = document.getElementById('appVersionBadge');
      const dlWin = document.getElementById('dlWinZip');
      const dlApk = document.getElementById('dlAndroidApk');

      if (btn) btn.disabled = true;
      if (infoSpan) infoSpan.innerText = 'Checking GitHub...';

      try {
        const res = await fetch('/api/updates/check');
        const data = await res.json();
        const cur = data.currentVersion || 'v2.0.0';
        const rel = data.release;
        
        if (rel && rel.version) {
          if (dlWin && rel.zipUrl) dlWin.href = rel.zipUrl;
          if (dlApk && rel.apkUrl) dlApk.href = rel.apkUrl;

          if (rel.version === cur) {
            if (infoSpan) infoSpan.innerText = 'You are on the latest release (' + cur + ')';
            if (versionBadge) {
              versionBadge.style.background = '#238636';
              versionBadge.innerText = cur + ' Latest';
            }
          } else {
            if (infoSpan) {
              infoSpan.innerHTML = 'New version <strong style="color:var(--green);">' + rel.version + '</strong> available!';
            }
            if (versionBadge) {
              versionBadge.style.background = '#d29922';
              versionBadge.style.color = '#000';
              versionBadge.innerText = rel.version + ' Available';
            }
          }
        } else {
          if (infoSpan) infoSpan.innerText = 'Release data refreshed.';
        }
      } catch (e) {
        if (infoSpan) infoSpan.innerText = 'Release check: ' + cur + ' active';
      } finally {
        if (btn) btn.disabled = false;
      }
    }

    // Auto-check TorBox key, hosters & GitHub releases on load
    function initOnLoad() {
      const keyInput = document.getElementById('torboxApiKey');
      const key = keyInput ? keyInput.value.trim() : '';
      if (key) {
        saveTorboxKey();
      }
      loadTorboxHosters();
      checkGitHubReleases();
    }

    if (document.readyState === 'loading') {
      window.addEventListener('DOMContentLoaded', initOnLoad);
    } else {
      initOnLoad();
    }

    // Handle ESC key to close player modal
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closePlayerModal();
      }
    });
  </script>
</body>
</html>
    ''';
  }

  static Map<String, String> getProviderMeta(String id) {
    switch (id.toLowerCase()) {
      // 🇮🇳 Indian Regional Special
      case 'vegamovies':
        return {'scope': '🇮🇳 Regional', 'quality': '4K UHD', 'tech': '☁️ Cloud Extractors', 'desc': 'High-bitrate V-Cloud, HubCloud 4K/1080p HEVC Multi-Audio'};
      case 'moviesdrive':
        return {'scope': '🇮🇳 Regional', 'quality': '4K UHD', 'tech': '☁️ Cloud Extractors', 'desc': 'Typesense JSON indexer, HubCloud 10Gbps & PixelDrain 4K/1080p multi-audio'};
      case 'moviesmod':
        return {'scope': '🇮🇳 Regional', 'quality': '1080p FHD', 'tech': '☁️ Cloud Extractors', 'desc': 'Extensive Netflix, Prime, Hotstar, SonyLIV, Zee5 OTT web series & dual audio'};
      case 'uhdmovies':
        return {'scope': '🇮🇳 Regional', 'quality': '4K UHD', 'tech': '☁️ Cloud Extractors', 'desc': 'Pure 4K UHD, HDR, Dolby Vision, 10-Bit HEVC, and REMUX cloud streams'};
      case 'multimovies':
        return {'scope': '🇮🇳 Regional', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Multi-Audio streaming server (Hindi, Tamil, Telugu, English)'};
      case 'toonstream':
        return {'scope': '🇮🇳 Regional', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Dedicated Hindi Dubbed Anime, Cartoons, and Animated Series'};
      case 'bollyflix':
        return {'scope': '🇮🇳 Regional', 'quality': '4K UHD', 'tech': '☁️ Cloud Extractors', 'desc': 'Bollywood, South Hindi Dubbed, 4K/1080p multi-audio releases'};
      case 'hdhub4u':
        return {'scope': '🇮🇳 Regional', 'quality': '4K UHD', 'tech': '☁️ Cloud Extractors', 'desc': 'Latest Hindi cinema, South dubs, HubCloud & DriveSeed direct mirrors'};
      case 'fourkhdhub':
        return {'scope': '🇮🇳 Regional', 'quality': '4K UHD', 'tech': '☁️ Cloud Extractors', 'desc': 'Pure 2160p 4K UHD Remux, HDR10 & multi-audio regional mirrors'};
      case 'hindmoviez':
        return {'scope': '🇮🇳 Regional', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Bollywood, South Hindi dubs & regional streams'};
      case 'playdesi':
        return {'scope': '🇮🇳 Regional', 'quality': '1080p FHD', 'tech': '🎬 Direct MP4', 'desc': 'Indian TV shows, daily serials & Desi web series'};
      case 'yomovies':
        return {'scope': '🇮🇳 Regional', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Hindi, Tamil, Telugu, Punjabi & regional cinema'};
      case 'vadapav':
        return {'scope': '🇮🇳 Regional', 'quality': '1080p FHD', 'tech': '🌐 Direct HTTP', 'desc': 'Zero-lag Indian high-speed direct CDN file storage'};

      // ⛩️ Anime & Asian Special
      case 'animepahe':
        return {'scope': '⛩️ Anime', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Sub/Dub anime with multi-bitrate streams & soft subtitles'};
      case 'gogoanime':
        return {'scope': '⛩️ Anime', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Simulcast anime episodes, massive archive with dual audio'};
      case 'hianime':
        return {'scope': '⛩️ Anime', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'HiAnime CDN, multi-quality streams & soft subs'};
      case 'kisskh':
        return {'scope': '⛩️ Asian', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'K-Drama, C-Drama & Asian series with multi-language subtitles'};
      case 'kissasian':
        return {'scope': '⛩️ Asian', 'quality': '720p/1080p', 'tech': '⚡ Fast HLS', 'desc': 'Korean & Asian drama catalog with high-speed playback'};
      case 'dramacool':
        return {'scope': '⛩️ Asian', 'quality': '720p/1080p', 'tech': '🎬 Direct MP4', 'desc': 'Asian dramas, variety shows & East Asian cinema'};

      // 🌐 International / Global
      case 'vidsrc':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Flagship multi-server global streaming cluster with adaptive HLS'};
      case 'lookmovie':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Premium global cinema & television series with soft subtitles'};
      case 'vidlink':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Ultra-fast global CDN streaming network with multi-language subs'};
      case 'multiembed':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Aggregated multi-source embed fallback player and resolver'};
      case 'rivestream':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Multi-server high-bitrate streaming network with 4K/1080p streams'};
      case 'hexa':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Multi-server mirror cluster with adaptive bitrate streaming'};
      case 'megasource':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '☁️ Cloud Extractors', 'desc': 'Multi-cloud direct stream aggregator and link resolver'};
      case 'movy':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Encrypted HLS & MP4 direct streams for movies and series'};
      case 'videasy':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'One-click fast buffer global streams across multi-CDN mirrors'};
      case 'cinejoy':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'International entertainment streams & reliable mirror sources'};
      case 'flystream':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Low-latency adaptive bitrate streaming network'};
      case 'xdownloader':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '🌐 Direct HTTP', 'desc': 'Direct file hoster link generator & stream extractor'};
      case 'vuflix':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Fast cloud HLS stream resolver for international catalog'};
      case 'movienight':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '🎬 Direct MP4', 'desc': 'Nightly movie archive & high-speed direct streams'};
      case 'fsonline':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Worldwide movie & webseries provider with multi-quality mirrors'};
      case 'cinesrc':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '🎬 Direct MP4', 'desc': 'Direct master HLS & web embeds for movies and series'};
      case 'cinesu':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'International film releases and episodic television streams'};
      case 'vidfast':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Optimized low-latency streaming endpoints'};
      case 'vidgod':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Resilient global streaming fallback with fast seek times'};
      case 'vidrock':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Rock-solid CDN streams with multiple quality options'};
      case 'vidup':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Direct video upload player scraper & mirror resolver'};
      case 'vidvault':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '🎬 Direct MP4', 'desc': 'Archived movies & television vault with high retention'};
      case 'vidzee':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Lightning-fast multi-server global player'};
      case 'vixsrc':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'High-performance Vix stream mirror with fast buffering'};
      case 'purstream':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Clean uninterrupted international streams'};
      case 'nova':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Global release cluster with multiple server mirrors'};
      case 'flaxmovies':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Global movie releases & web streaming endpoints'};
      case 'bcine':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '🎬 Direct MP4', 'desc': 'Direct international cinema catalog with MP4 streams'};
      case 'frame':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'High-efficiency adaptive video streams'};
      case 'fsharetv':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Global TV network episodes & television serials'};
      case 'fsonic':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '🎬 Direct MP4', 'desc': 'Ultra-fast international CDN streams'};
      case 'lmscript':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Script-based lookmovie alternative mirror'};
      case 'mapple':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Fresh global box office & TV episodes'};
      case 'meowtv':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Curated television shows & movies'};
      case 'peestream':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '🎬 Direct MP4', 'desc': 'Direct streaming hoster scraper'};
      case 'vidapi':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'API-driven media scraper endpoint'};
      case 'vidcore':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Core video streaming cluster for global releases'};
      case 'xpass':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Bypass scraper for premium media mirrors'};
      case 'zxcstream':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Low-latency global stream mirrors'};
      case 'a111477':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '🎬 Direct MP4', 'desc': 'Alternative direct stream hoster'};
      case 'downloadeverything':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '🌐 Direct HTTP', 'desc': 'Direct media download & stream extractor'};
      case 'dulo':
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'High-speed direct stream network'};
      default:
        return {'scope': '🌐 Global', 'quality': '1080p FHD', 'tech': '⚡ Fast HLS', 'desc': 'Direct cloud media stream scraper'};
    }
  }
}
