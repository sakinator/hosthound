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
    final excludeCamsChecked = cfg.excludeCams ? 'checked' : '';
    final dedupeChecked = cfg.enableDeduplication ? 'checked' : '';
    final deadLinkChecked = cfg.enableDeadLinkFilter ? 'checked' : '';
    final maxRes = cfg.maxResolution;
    final prefLang = cfg.preferredLanguage;

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
      padding: 24px;
    }
    .container { max-width: 1080px; margin: 0 auto; }
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
      background: var(--accent-grad);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 6px;
      font-weight: 900;
      letter-spacing: -0.5px;
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
      body {
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
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="brand-logo-wrap">
        <img src="/logo.png" alt="Hostreamio" class="brand-logo" />
      </div>
      <h1>Hostreamio</h1>
      <p class="subtitle">Direct Hosters • Streaming Links • TorBox Cloud Debrid • Smart Proxy • Instant Badges</p>
    </header>

    <!-- Architecture & Engine Status Pills -->
    <div class="status-banner">
      <div class="status-chip"><span class="status-dot"></span> <strong>DNS-over-HTTPS:</strong> Cloudflare & Google Fallback (Active)</div>
      <div class="status-chip"><span class="status-dot"></span> <strong>HLS Segment Cache:</strong> 35MB RAM Ring Buffer (Active)</div>
      <div class="status-chip"><span class="status-dot"></span> <strong>DASH to HLS:</strong> Virtual Transmuxer Ready</div>
      <div class="status-chip"><span class="status-dot"></span> <strong>Circuit Breaker:</strong> 56 Providers Monitored</div>
    </div>

    <!-- Main Top Tabs Switcher -->
    <div class="main-tabs-nav">
      <button id="tabBtnServer" class="main-tab-btn active" onclick="switchMainTab('server')">
        🖥️ Server &amp; Addon Setup
      </button>
      <button id="tabBtnStreaming" class="main-tab-btn" onclick="switchMainTab('streaming')">
        🎬 Streaming Theater
      </button>
    </div>

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
        <div id="hostersGrid" class="grid" style="max-height:240px;">
          <div style="color:var(--text-muted); padding:8px;">Click "Refresh Hosters" to view active debrid hosters.</div>
        </div>
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

  <!-- TAB 2: STREAMING & NATIVE THEATER -->
  <div id="tabContentStreaming" style="display:none;">
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

    <!-- Legal & Vibe Coded Disclaimer Footer -->
    <div style="text-align:center; padding:24px 14px 14px; color:var(--text-muted); font-size:0.8rem; border-top:1px solid var(--border); margin-top:24px; line-height:1.6;">
      <div style="margin-bottom:8px;">
        <span style="display:inline-block; background:rgba(255,105,180,0.15); color:#ff69b4; border:1px solid rgba(255,105,180,0.3); border-radius:12px; padding:2px 10px; font-weight:600; font-size:0.75rem; letter-spacing:0.5px;">✨ 100% VIBE CODED WITH AI</span>
      </div>
      <strong>⚖️ GitHub & Legal Disclaimer:</strong> The author does not own, host, upload, or broadcast any media or streams. Hostreamio acts solely as a local search indexer aggregating publicly available hyperlinks from third-party websites on the internet. All media is hosted by independent third-party services. Not affiliated with Stremio, Nuvio, TorBox, or any scraped source.
    </div>
  </div>

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
            <div style="font-size:0.75rem; color:var(--text-muted);">vlc:// scheme &amp; auto-download</div>
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

  <div id="toast" class="toast">Copied to clipboard!</div>

  <script>
    let currentStreams = [];
    let activeFilter = 'all';
    let currentHls = null;

    function switchMainTab(tab) {
      const serverTab = document.getElementById('tabContentServer');
      const streamingTab = document.getElementById('tabContentStreaming');
      const btnServer = document.getElementById('tabBtnServer');
      const btnStreaming = document.getElementById('tabBtnStreaming');

      if (tab === 'streaming') {
        if (serverTab) serverTab.style.display = 'none';
        if (streamingTab) streamingTab.style.display = 'block';
        if (btnServer) btnServer.classList.remove('active');
        if (btnStreaming) btnStreaming.classList.add('active');
        try { localStorage.setItem('hostreamio_active_tab', 'streaming'); } catch (_) {}
        if (typeof _catalogItems !== 'undefined' && _catalogItems.length === 0) {
          initCatalogBrowser();
        }
      } else {
        if (serverTab) serverTab.style.display = 'block';
        if (streamingTab) streamingTab.style.display = 'none';
        if (btnServer) btnServer.classList.add('active');
        if (btnStreaming) btnStreaming.classList.remove('active');
        try { localStorage.setItem('hostreamio_active_tab', 'server'); } catch (_) {}
      }
    }

    // Auto-restore previous tab or hash, then init catalog
    window.addEventListener('DOMContentLoaded', () => {
      const hash = window.location.hash;
      const savedTab = localStorage.getItem('hostreamio_active_tab');
      if (hash === '#streaming' || (savedTab === 'streaming' && hash !== '#server')) {
        switchMainTab('streaming');
      } else {
        switchMainTab('server');
      }
      // Init catalog browser on first load
      initCatalogBrowser();
    });

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

        return '<div class="catalog-card" data-id="' + encodeURIComponent(item.id || '') + '" data-type="' + encodeURIComponent(item.type || 'movie') + '" data-name="' + encodeURIComponent(item.name || '') + '" data-poster="' + encodeURIComponent(item.poster || '') + '" data-series="' + (isSeries ? '1' : '0') + '" onclick="onCatalogCardClick(this)" title="' + safeName + '">'
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

    function onCatalogCardClick(el) {
      const id = decodeURIComponent(el.getAttribute('data-id') || '');
      const type = decodeURIComponent(el.getAttribute('data-type') || 'movie');
      const name = decodeURIComponent(el.getAttribute('data-name') || '');
      const poster = decodeURIComponent(el.getAttribute('data-poster') || '');
      const isSeries = el.getAttribute('data-series') === '1';
      catalogItemClick(id, type, name, poster, isSeries);
    }

    function loadMoreCatalog() {
      loadCatalog(false);
    }

    function catalogItemClick(id, type, name, poster, isSeries) {
      // Scroll to theater
      const theater = document.getElementById('searchTheaterCard');
      if (theater) theater.scrollIntoView({ behavior: 'smooth', block: 'start' });

      // Set type selector
      const typeSelect = document.getElementById('theaterMediaType');
      if (typeSelect) {
        typeSelect.value = type === 'series' ? 'series' : 'movie';
        toggleSeasonEpisodeInputs();
      }

      // Set search query to the id
      const searchInput = document.getElementById('theaterSearchQuery');
      if (searchInput) searchInput.value = id;

      // Small delay for scroll, then kick off scrape
      setTimeout(() => {
        if (isSeries) {
          // For series: show catalog + default to S1E1
          const seasonEl = document.getElementById('theaterSeason');
          const episodeEl = document.getElementById('theaterEpisode');
          if (seasonEl) seasonEl.value = '1';
          if (episodeEl) episodeEl.value = '1';
          // Trigger search
          executeTheaterSearch();
        } else {
          executeTheaterSearch();
        }
      }, 350);
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
            showRatingsInStreams: false,
            omdbApiKey: document.getElementById('omdbApiKey').value.trim(),
            fanartApiKey: document.getElementById('fanartApiKey').value.trim(),
            tvdbApiKey: document.getElementById('tvdbApiKey').value.trim(),
            tmdbApiKey: document.getElementById('tmdbApiKey') ? document.getElementById('tmdbApiKey').value.trim() : '',
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
        if (type === 'series') {
          loadSeriesCatalog(baseId, query, null);
        } else {
          const catalogBox = document.getElementById('seriesCatalogContainer');
          if (catalogBox) catalogBox.style.display = 'none';
          scrapeMediaById(query, type, query, null, null, null);
        }
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
          suggestionsBox.innerHTML = '<div style="color:var(--text-muted); padding:10px;">No exact title matches found in Cinemeta/TMDB. Scraping directly for "' + escapeHtml(query) + '"...</div>';
          scrapeMediaById(query, type, query, null, null, null);
        } else {
          let html = '<div style="font-size:0.85rem; color:var(--text-muted); margin-bottom:8px; font-weight:600;">Found ' + results.length + ' match(es) — click any title to load catalog:</div>';
          html += '<div class="search-suggestions-grid">';
          for (const m of results) {
            const posterUrl = m.poster || ('https://images.metahub.space/poster/medium/' + m.id + '/img');
            const yearStr = m.year ? ' (' + m.year + ')' : '';
            html += `
              <div class="search-suggestion-item" onclick="selectSearchSuggestion('\${escapeHtml(m.id)}', '\${m.type || type}', '\${escapeHtml(m.name)}', '\${escapeHtml(m.year)}', '\${escapeHtml(posterUrl)}', '\${escapeHtml(m.description || '')}')">
                <img src="\${posterUrl}" class="search-suggestion-thumb" onerror="this.src='/logo.png'">
                <div style="overflow:hidden;">
                  <div style="font-weight:600; font-size:0.88rem; color:#fff; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">\${escapeHtml(m.name)}</div>
                  <div style="font-size:0.75rem; color:var(--text-muted);">\${escapeHtml(m.type || type).toUpperCase()}\${yearStr}</div>
                </div>
              </div>
            `;
          }
          html += '</div>';
          suggestionsBox.innerHTML = html;

          // Auto-select the top result
          const top = results[0];
          selectSearchSuggestion(top.id, top.type || type, top.name, top.year, top.poster, top.description || '');
        }
      } catch (err) {
        suggestionsBox.innerHTML = '<div style="color:#f85149; padding:10px;">Search request error: ' + err + '</div>';
        scrapeMediaById(query, type, query, null, null, null);
      } finally {
        btn.disabled = false;
        btn.innerText = '🔍 Search & Scrape';
      }
    }

    function selectSearchSuggestion(id, type, name, year, poster, desc) {
      document.getElementById('theaterSearchQuery').value = id;
      document.getElementById('theaterMediaType').value = type;
      toggleSeasonEpisodeInputs();

      const baseId = id.split(':')[0];

      if (type === 'series') {
        loadSeriesCatalog(baseId, name, poster);
      } else {
        const catalogBox = document.getElementById('seriesCatalogContainer');
        if (catalogBox) catalogBox.style.display = 'none';
        scrapeMediaById(baseId, 'movie', name, poster, desc, year);
      }
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
      const displayYear = year ? ' • ' + year : '';

      activeCard.innerHTML = `
        <div class="media-card-box">
          <img src="\${posterImg}" class="media-card-poster" onerror="this.src='/logo.png'">
          <div style="flex:1;">
            <div style="display:flex; justify-content:space-between; align-items:flex-start; gap:10px;">
              <div>
                <h3 style="font-size:1.15rem; color:#fff; font-weight:700;">\${escapeHtml(displayTitle)}</h3>
                <div style="font-size:0.8rem; color:var(--text-muted); margin-top:2px;">
                  <span class="badge" style="background:#21262d; margin-right:4px;">\${escapeHtml(type).toUpperCase()}</span>
                  <span>\${escapeHtml(id)}\${displayYear}</span>
                </div>
              </div>
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

          // A stream is cachable to TorBox only if it is not HLS/DASH, not already cached, and is either tagged cachable or hosted on a supported hoster
          const isSupportedHoster = !isHlsOrDash && !isTorboxCached && (
            isTorboxCachable ||
            lowerUrl.endsWith('.mp4') || lowerUrl.endsWith('.mkv') || lowerUrl.endsWith('.avi') || lowerUrl.endsWith('.webm') || lowerUrl.endsWith('.ts') ||
            lowerUrl.includes('hubcloud') || lowerUrl.includes('hubdrive') || lowerUrl.includes('driveseed') ||
            lowerUrl.includes('pixeldrain') || lowerUrl.includes('1fichier') || lowerUrl.includes('rapidgator') ||
            lowerUrl.includes('mega.nz') || lowerUrl.includes('mediafire') || lowerUrl.includes('ddownload') ||
            lowerUrl.includes('drive.google.com') || lowerUrl.includes('workers.dev') || lowerUrl.includes('vcloud') || lowerUrl.includes('fastdl')
          );

          return {
            index: idx,
            name: rawName,
            title: rawTitle,
            url: finalUrl,
            underlyingUrl: underlyingUrl,
            mediaTitle: displayTitle,
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

      const modal = document.getElementById('playerModal');
      const title = document.getElementById('playerStreamTitle');
      const video = document.getElementById('previewVideoPlayer');

      title.innerText = (s.mediaTitle ? s.mediaTitle + ' • ' : '') + s.name;
      modal.style.display = 'flex';

      if (currentHls) {
        currentHls.destroy();
        currentHls = null;
      }

      const streamUrl = s.url;
      const isHls = streamUrl.includes('.m3u8') || streamUrl.includes('/proxy');

      if (isHls && Hls.isSupported()) {
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

      const modal = document.getElementById('openWithModal');
      const title = document.getElementById('openWithStreamTitle');
      const sub = document.getElementById('openWithStreamSub');
      const urlPreview = document.getElementById('openWithUrlPreview');

      title.innerText = '🚀 Open With: ' + s.name;
      sub.innerText = (s.mediaTitle ? s.mediaTitle + ' • ' : '') + s.title.replace(/\\n/g, ' • ');
      urlPreview.innerText = s.url;

      const streamUrl = s.url;
      const cleanName = (s.mediaTitle || 'Hostreamio') + ' - ' + s.name;

      // VLC
      const vlcBtn = document.getElementById('openWithVlc');
      vlcBtn.onclick = (e) => {
        e.preventDefault();
        window.location.href = 'vlc://' + streamUrl;
        showToast('🚀 Launching VLC...');
        setTimeout(() => {
          downloadM3u(cleanName, streamUrl);
        }, 1200);
      };

      // PotPlayer
      const potBtn = document.getElementById('openWithPotPlayer');
      potBtn.onclick = (e) => {
        e.preventDefault();
        window.location.href = 'potplayer://' + streamUrl;
        showToast('🚀 Launching PotPlayer...');
      };

      // MPV
      const mpvBtn = document.getElementById('openWithMpv');
      mpvBtn.onclick = (e) => {
        e.preventDefault();
        navigator.clipboard.writeText('mpv "' + streamUrl + '"');
        showToast('📋 MPV command copied! Also launching mpv://...');
        window.location.href = 'mpv://' + streamUrl;
      };

      // IINA
      const iinaBtn = document.getElementById('openWithIina');
      iinaBtn.onclick = (e) => {
        e.preventDefault();
        window.location.href = 'iina://weblink?url=' + encodeURIComponent(streamUrl);
        showToast('🚀 Launching IINA...');
      };

      // Mobile
      const mobileBtn = document.getElementById('openWithMobile');
      mobileBtn.onclick = (e) => {
        e.preventDefault();
        window.location.href = 'intent:' + streamUrl + '#Intent;type=video/*;scheme=https;end';
        showToast('🚀 Launching Android Video Player...');
      };

      modal.style.display = 'flex';
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
