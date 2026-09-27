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
      width: 74px;
      height: 74px;
      border-radius: 20px;
      border: 1.5px solid rgba(255, 12, 130, 0.5);
      box-shadow: 0 0 24px rgba(255, 12, 130, 0.4), 0 0 10px rgba(25, 95, 235, 0.3);
      background: #000;
      transition: transform 0.25s ease, box-shadow 0.25s ease;
    }
    .brand-logo:hover {
      transform: scale(1.06);
      box-shadow: 0 0 32px rgba(255, 12, 130, 0.6), 0 0 14px rgba(25, 95, 235, 0.45);
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

    <!-- Quick Install & Manifest Card -->
    <div class="card" style="background: linear-gradient(180deg, rgba(22, 27, 34, 0.95) 0%, rgba(13, 17, 23, 0.95) 100%);">
      <div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; margin-bottom:14px;">
        <h2>🔌 Quick Install in Nuvio & Stremio</h2>
        <span class="badge" style="background:rgba(88, 166, 255, 0.15); color:var(--blue); border:1px solid rgba(88, 166, 255, 0.3); font-size:0.8rem; padding:4px 10px;">
          📡 Wi-Fi IP: $localIp
        </span>
      </div>

      <div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap:14px;">
        <!-- Option 1: This PC -->
        <div style="background:#090d13; border:1px solid var(--border); border-radius:10px; padding:16px; display:flex; flex-direction:column; justify-content:space-between; gap:12px;">
          <div>
            <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:6px;">
              <span style="font-weight:700; font-size:0.95rem; color:var(--text);">💻 This PC (Local Player)</span>
              <span style="font-size:0.7rem; color:var(--green-light); background:rgba(35, 134, 54, 0.2); padding:2px 8px; border-radius:12px; font-weight:600;">1-Click</span>
            </div>
            <p style="font-size:0.82rem; color:var(--text-muted); line-height:1.4;">
              If Nuvio or Stremio is installed on this PC, launch and add the addon directly:
            </p>
          </div>
          <div>
            <a href="stremio://127.0.0.1:$port/manifest.json" class="btn btn-primary" style="width:100%; justify-content:center; padding:10px 14px; font-size:0.92rem; font-weight:700; text-decoration:none;">
              🚀 1-Click Install to Stremio / Nuvio
            </a>
            <div style="display:flex; gap:8px; margin-top:8px;">
              <input class="url-input" id="localUrl" value="$manifestLocal" readonly style="font-size:0.82rem; padding:6px 10px;">
              <button type="button" class="btn" onclick="copyText('localUrl')" style="padding:6px 12px; font-size:0.8rem; white-space:nowrap;">📋 Copy</button>
            </div>
          </div>
        </div>

        <!-- Option 2: Android TV & Mobile -->
        <div style="background:#090d13; border:1px solid var(--border); border-radius:10px; padding:16px; display:flex; flex-direction:column; justify-content:space-between; gap:12px;">
          <div>
            <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:6px;">
              <span style="font-weight:700; font-size:0.95rem; color:var(--text);">📺 Android TV & Mobile (Wi-Fi)</span>
              <span style="font-size:0.7rem; color:var(--blue); background:rgba(88, 166, 255, 0.2); padding:2px 8px; border-radius:12px; font-weight:600;">Same Network</span>
            </div>
            <p style="font-size:0.82rem; color:var(--text-muted); line-height:1.4;">
              For Android TV, FireStick, or Mobile connected to the same Wi-Fi:
            </p>
          </div>
          <div>
            <div style="display:flex; gap:8px; margin-bottom:8px;">
              <input class="url-input" id="lanUrl" value="$manifestLan" readonly style="font-size:0.82rem; padding:8px 10px; color:var(--green-light);">
              <button type="button" class="btn btn-primary" onclick="copyText('lanUrl')" style="padding:8px 14px; font-size:0.85rem; white-space:nowrap; font-weight:600;">📋 Copy LAN URL</button>
            </div>
            <div style="font-size:0.76rem; color:var(--text-muted); display:flex; align-items:center; gap:6px;">
              <span>💡</span> Open <strong>Nuvio</strong> ➔ <strong>Settings (⚙️)</strong> ➔ <strong>General</strong> ➔ <strong>Content & Discovery</strong> ➔ <strong>Addons (+)</strong> ➔ Paste URL ➔ <strong>Install</strong>
            </div>
          </div>
        </div>

        <!-- Option 3: Nuvio Fusion Badges (Quality & OTT Logos) -->
        <div style="background:#090d13; border:1px solid #ff69b4; border-radius:10px; padding:16px; display:flex; flex-direction:column; justify-content:space-between; gap:12px; grid-column: 1 / -1;">
          <div>
            <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:6px; flex-wrap:wrap; gap:8px;">
              <span style="font-weight:700; font-size:0.95rem; color:#ff69b4;">🎨 Nuvio Logo Badges (Quality & OTT Logos)</span>
              <span style="font-size:0.75rem; color:#ff69b4; background:rgba(255, 105, 180, 0.15); border:1px solid rgba(255,105,180,0.4); padding:2px 8px; border-radius:12px; font-weight:600;">Required for Logo Badges</span>
            </div>
            <p style="font-size:0.84rem; color:var(--text); line-height:1.5; margin:0;">
              Nuvio renders visual logos & badges (4K, WEB-DL, Hotstar, Netflix, Prime, JioCinema, SonyLIV, Zee5) through <strong>Fusion Badge URLs</strong>. To enable badges in Nuvio, copy this URL:
            </p>
          </div>
          <div>
            <div style="display:flex; gap:8px; margin-bottom:8px;">
              <input class="url-input" id="badgesUrl" value="http://$localIp:$port/badges.json" readonly style="font-size:0.84rem; padding:8px 10px; color:#ff69b4; font-weight:600;">
              <button type="button" class="btn btn-primary" onclick="copyText('badgesUrl')" style="padding:8px 16px; font-size:0.85rem; white-space:nowrap; font-weight:700; background:#ff69b4; border-color:#ff69b4; color:#fff;">📋 Copy Badge URL</button>
            </div>
            <div style="font-size:0.8rem; color:var(--text-muted); display:flex; align-items:center; gap:6px;">
              <span>👉</span> In Nuvio app: <strong>Settings (⚙️)</strong> ➔ <strong>General</strong> ➔ <strong>Layout</strong> ➔ <strong>Streams</strong> ➔ <strong>Fusion Badge URLs</strong> ➔ Paste & Add!
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
          <button class="btn btn-success" id="btnUploadTorbox" onclick="uploadLinkToTorbox()">🌐 Cache to TorBox</button>
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

    <!-- Live Stream Tester -->
    <div class="card">
      <h2>🔍 Live Stream Tester & Preview Player</h2>
      <div class="test-box">
        <select id="testType">
          <option value="movie">Movie</option>
          <option value="series">Series</option>
        </select>
        <input class="test-input" id="testId" placeholder="IMDb ID or Title (e.g. tt1375666 or Inception)" value="tt1375666">
        <button class="btn btn-primary" id="btnTest" onclick="runTest()">🚀 Test Scrape</button>
      </div>
      <div id="testResults"></div>
    </div>

    <!-- Multi-Source Unified Update Hub -->
    <div class="card" id="updateHubCard">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; flex-wrap:wrap; gap:10px;">
        <h2>🔄 Multi-Source Unified Update Hub</h2>
        <span class="update-pill" style="background:#238636; color:#fff; font-size:0.82rem; padding:4px 10px;">56 Total Active Providers</span>
      </div>
      <p style="color:var(--text-muted); margin-bottom:16px;">
        Manage and synchronize your 56 aggregated providers across PlayTorrio base framework, Cloudstream community plugins & extractors, Indian regional OTTs, Anime scrapers, and official binary releases.
      </p>

      <div class="update-grid">
        <!-- 1. App Releases & Core Binaries -->
        <div class="update-subcard">
          <div class="update-subcard-header">
            <div>
              <div class="update-subcard-title">📦 Hostreamio Releases</div>
              <div class="update-subcard-desc">Official desktop and Android binaries with all scrapers, extractors & TorBox debrid built-in.</div>
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
              <div class="update-subcard-desc">Extractors & resolvers for HubCloud, Vega, DriveSeed, Pixeldrain, Mega, 1fichier, Rapidgator, and direct hosters.</div>
            </div>
            <span class="update-pill" style="background:#1f6feb; color:#fff;">Plugins & Resolvers</span>
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
              <div class="update-subcard-title">🇮🇳 Indian OTT & Anime Scrapers</div>
              <div class="update-subcard-desc">Bollyflix, Vegamovies, HDHub4u, HindMoviez, Playdesi, Yomovies, 4kHDHub, AnimePahe, GogoAnime, HiAnime, KissKH, Vadapav.</div>
            </div>
            <span class="update-pill" style="background:#f0883e; color:#000; font-weight:700;">Regional & Anime</span>
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
              <div class="update-subcard-title">🏷️ Nuvio Badges & Regional OTT Logos</div>
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
          ⚡ Run Full Update Pipeline (All 56 Providers & Sources)
        </button>
      </div>

      <!-- Live Terminal Output Console -->
      <div id="pipelineConsoleBox" style="display:none; margin-top:14px;">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
          <span style="font-size:0.8rem; color:var(--text-muted); font-weight:600; text-transform:uppercase; letter-spacing:0.5px;">Update Pipeline Console</span>
          <span id="pipelineConsoleBadge" class="update-pill" style="font-size:0.75rem; background:#d29922; color:#000;">Running...</span>
        </div>
        <pre id="pipelineConsole" style="background:#090d13; border:1px solid var(--border); border-radius:6px; padding:12px; font-family:monospace; font-size:0.82rem; color:#e6edf3; max-height:220px; overflow-y:auto; white-space:pre-wrap; margin:0;"></pre>
      </div>
    </div>

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
        <div class="player-title" id="playerStreamTitle">Stream Preview</div>
        <button class="player-close-btn" onclick="closePlayerModal()">✕</button>
      </div>
      <div class="video-wrapper">
        <video id="previewVideoPlayer" controls playsinline></video>
      </div>
    </div>
  </div>

  <div id="toast" class="toast">Copied to clipboard!</div>

  <script>
    let currentStreams = [];
    let activeFilter = 'all';
    let currentHls = null;

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
            btnElement.innerText = '🌐 Cache to TorBox';
          }
        }
      } catch (e) {
        if (status) status.innerHTML = '<span style="color:#f85149;">Upload error: ' + e + '</span>';
        showToast('❌ Upload error: ' + e);
        if (btnElement) {
          btnElement.disabled = false;
          btnElement.innerText = '🌐 Cache to TorBox';
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
        const domains = domainList.filter(Boolean).slice(0, 3).join(', ');
        return `
          <div class="hoster-card">
            <div style="display:flex; justify-content:space-between; align-items:center;">
              <span class="hoster-name">\${hosterName}</span>
              <span class="hoster-status \${isUp ? 'status-up' : 'status-down'}">\${isUp ? 'ONLINE' : 'DOWN'}</span>
            </div>
            <div class="hoster-domains">\${escapeHtml(domains)}</div>
          </div>
        `;
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

    async function runTest() {
      const type = document.getElementById('testType').value;
      const id = document.getElementById('testId').value.trim();
      const resultsDiv = document.getElementById('testResults');
      const btn = document.getElementById('btnTest');

      if (!id) return;

      btn.disabled = true;
      btn.innerText = 'Scraping...';
      resultsDiv.style.display = 'block';
      resultsDiv.innerHTML = '<div style="color:var(--text-muted); padding:10px;">Scraping 56 providers for "' + escapeHtml(id) + '"...</div>';

      try {
        const res = await fetch('/stream/' + type + '/' + encodeURIComponent(id) + '.json');
        const data = await res.json();
        const rawStreams = data.streams || [];

        currentStreams = rawStreams.map((s, idx) => {
          const finalUrl = normalizeStreamUrl(s.url);
          const rawName = (s.name || '').replace(/\\n/g, ' ');
          const rawTitle = (s.title || '').replace(/\\n/g, '\\n');
          return {
            index: idx,
            name: rawName,
            title: rawTitle,
            url: finalUrl,
            isCached: rawName.includes('[Cached]') || rawTitle.includes('Cached on TorBox'),
            isCache: rawName.toLowerCase().includes('cachable') || rawName.includes('Start Caching') || rawName.includes('[Cache]') || rawTitle.toLowerCase().includes('cachable') || rawTitle.toLowerCase().includes('start caching'),
            is4K: rawName.includes('4K') || rawTitle.includes('[4K]'),
            is1080p: rawName.includes('1080p') || rawTitle.includes('[FHD]') || rawTitle.includes('1080p'),
          };
        });

        if (currentStreams.length === 0) {
          resultsDiv.innerHTML = '<div style="color:#f85149; padding:10px;">No streams found. Try another title or check your enabled providers.</div>';
        } else {
          renderFilteredStreams('all');
        }
      } catch (err) {
        resultsDiv.innerHTML = '<div style="color:#f85149; padding:10px;">Error testing scrape: ' + err + '</div>';
      } finally {
        btn.disabled = false;
        btn.innerText = '🚀 Test Scrape';
      }
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
        const isTorbox = s.url.includes('/torbox/play') || s.title.includes('Torbox') || s.title.includes('Cached');
        html += '<div class="stream-item">';
        html += '  <div class="stream-info">';
        html += '    <div class="stream-title">' + escapeHtml(s.name) + '</div>';
        html += '    <div class="stream-sub">' + escapeHtml(s.title) + '</div>';
        html += '  </div>';
        html += '  <div class="stream-actions">';
        html += '    <button class="btn btn-play" onclick="openPlayerModal(' + s.index + ')">▶️ Play Stream</button>';
        html += '    <a class="btn" href="' + escapeHtml(s.url) + '" target="_blank" rel="noreferrer">🔗 Open URL</a>';
        if (!isTorbox) {
          html += '    <button class="btn btn-success" onclick="uploadStreamToTorbox(' + s.index + ', this)">🌐 Cache to TorBox</button>';
        }
        html += '  </div>';
        html += '</div>';
      }

      resultsDiv.innerHTML = html;
    }

    function uploadStreamToTorbox(idx, btn) {
      const s = currentStreams[idx];
      if (s && s.url) {
        uploadLinkToTorbox(s.url, btn);
      }
    }

    function openPlayerModal(idx) {
      const s = currentStreams[idx];
      if (!s || !s.url) return;

      const modal = document.getElementById('playerModal');
      const title = document.getElementById('playerStreamTitle');
      const video = document.getElementById('previewVideoPlayer');

      title.innerText = s.name + ' - ' + s.title.split('\\n')[0];
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
      return String(str == null ? '' : str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
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
        const cur = data.currentVersion || 'v1.5.0';
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
