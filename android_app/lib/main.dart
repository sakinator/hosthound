import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'catalog_service.dart';
import 'config.dart';
import 'iptv_service.dart';
import 'key_validator.dart';
import 'metadata_service.dart';
import 'dtdd_service.dart';
import 'scraper_engine.dart';
import 'server_service.dart';
import 'torbox_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'player_screen.dart';
import 'window_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    await WindowService.instance.initialize();
  }
  await ServerService.instance.init();
  // Auto-start server on app launch
  await ServerService.instance.startServer();
  runApp(const HostreamioAddonApp());
}

class HostreamioAddonApp extends StatelessWidget {
  const HostreamioAddonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hostreamio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF08090C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF195FEB),
          secondary: Color(0xFFFF0C82),
          tertiary: Color(0xFFF55014),
          surface: Color(0xFF11141C),
        ),
        fontFamily: 'sans-serif',
      ),
      home: const MainDashboardScreen(),
    );
  }
}

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  static const MethodChannel _playerChannel = MethodChannel('com.playtorrio.nuvio.addon/player');

  // Tab Navigation State
  int _selectedTabIndex = 0; // 0 = Server, 1 = Streaming, 2 = Live IPTV, 3 = Caching, 4 = About
  // Sidebar state (collapsed to icon-only by default for better view on Android and Windows)
  bool _isSidebarExpanded = false;
  final FocusNode _serverTabFocus = FocusNode();
  final FocusNode _streamingTabFocus = FocusNode();
  final FocusNode _iptvTabFocus = FocusNode();
  final FocusNode _cachingTabFocus = FocusNode();
  final FocusNode _aboutTabFocus = FocusNode();

  // TorBox Cloud Caching Queue State
  List<Map<String, dynamic>> _cacheQueueItems = [];
  bool _isLoadingCacheQueue = false;
  Timer? _cacheQueueTimer;

  // Nuvio-style Media Detail View state
  bool _isInDetailView = false;

  // Live IPTV State (iptv-org integration)
  final TextEditingController _iptvSearchController = TextEditingController();
  String _selectedIptvCategory = 'All';
  String _selectedIptvCountry = 'All';
  List<IptvChannel> _iptvChannels = [];
  bool _isLoadingIptv = false;
  int _iptvDisplayLimit = 60;
  Set<String> _iptvFavourites = {};
  bool _showOnlyFavourites = false;

  final FocusNode _startStopFocus = FocusNode();
  final FocusNode _oneClickInstallFocus = FocusNode();
  final FocusNode _copyManifestFocus = FocusNode();
  final FocusNode _openWebFocus = FocusNode();
  final FocusNode _refreshIpFocus = FocusNode();

  final TextEditingController _torboxKeyController = TextEditingController();
  final FocusNode _torboxInputFocus = FocusNode();
  final FocusNode _torboxSaveFocus = FocusNode();
  final FocusNode _torboxKeyLinkFocus = FocusNode();
  bool _obscureTorboxKey = true;
  bool _isValidatingTorbox = false;
  String? _torboxStatusMessage;
  bool _isTorboxValid = false;

  // Metadata & External API Keys State
  final TextEditingController _tmdbKeyController = TextEditingController();
  final TextEditingController _omdbKeyController = TextEditingController();
  final TextEditingController _fanartKeyController = TextEditingController();
  final TextEditingController _tvdbKeyController = TextEditingController();
  final TextEditingController _dtddKeyController = TextEditingController();
  final Map<String, String?> _apiStatusMessages = {};
  final Map<String, bool> _apiValidating = {};
  final Map<String, bool> _apiValid = {};

  // Stream Filtering Profiles & Optimization State
  String _selectedAudioLang = 'any';
  String _selectedMaxRes = 'all';
  bool _excludeCams = true;
  bool _enableDeduplication = true;
  bool _enableDeadLinkFilter = true;
  bool _enableOpenSubtitles = true;
  bool _enableTorboxCachedTorrents = false;
  bool _enableCacheBypass = true;
  final TextEditingController _proxyResolverController = TextEditingController();

  // Streaming View State
  String _selectedMediaType = 'movie'; // 'movie' or 'series'
  final TextEditingController _searchQueryController = TextEditingController(text: 'tt1375666');
  final TextEditingController _seasonController = TextEditingController(text: '1');
  final TextEditingController _episodeController = TextEditingController(text: '1');
  final FocusNode _searchInputFocus = FocusNode();
  final FocusNode _searchButtonFocus = FocusNode();

  bool _isSearching = false;
  List<Map<String, dynamic>> _catalogSuggestions = [];
  Map<String, dynamic>? _selectedMediaMeta;
  Map<String, dynamic>? _seriesDetails;
  int _selectedSeason = 1;
  String? _selectedEpisodeId;
  bool _isDtddExpanded = false;
  bool _isLoadingDtdd = false;

  bool _isScrapingStreams = false;
  List<Map<String, dynamic>> _scrapedStreams = [];
  String _activeStreamFilter = 'all';

  // Watch History — tracks recently played items (max 30, with position_ms)
  List<Map<String, dynamic>> _watchHistory = [];
  // Watchlist — bookmarked items to watch later
  List<Map<String, dynamic>> _watchlist = [];
  bool _showWatchHistory = false;

  // Catalog Browser State
  String _activeCatalogTab = 'trending-movie';
  String _activeCatalogGenre = 'All';
  int _catalogSkip = 0;
  bool _isLoadingCatalog = false;
  List<Map<String, dynamic>> _catalogItems = [];

  static const Map<String, Map<String, dynamic>> _catalogDefs = {
    'trending-movie': {
      'label': '🔥 Trending Movies',
      'type': 'movie',
      'src': 'cinemeta',
      'id': 'top',
    },
    'trending-series': {
      'label': '📺 Trending Series',
      'type': 'series',
      'src': 'cinemeta',
      'id': 'top',
    },
    'yt_indian': {
      'label': '🎬 YouTube Indian',
      'type': 'movie',
      'src': 'local',
      'id': 'yt_indian',
      'genres': [
        'All',
        'Bollywood Full Movies',
        'South Hindi Dubbed',
        'Indian Web Series',
        'Classic Hindi',
        'Comedy Hindi Movies',
      ],
    },
    'yt_international': {
      'label': '🌍 YouTube Intl',
      'type': 'movie',
      'src': 'local',
      'id': 'yt_international',
      'genres': [
        'All',
        'Action Movies',
        'Sci-Fi & Thriller',
        'Documentaries',
        'Indie Cinema',
      ],
    },
    'vimeo_picks': {
      'label': '🎥 Vimeo',
      'type': 'movie',
      'src': 'local',
      'id': 'vimeo_picks',
      'genres': [
        'All',
        'Staff Picks',
        'Short of the Week',
        'Animation',
        'Documentaries',
      ],
    },
    'archive_movies': {
      'label': '🏛️ Archive',
      'type': 'movie',
      'src': 'local',
      'id': 'archive_movies',
      'genres': [
        'All',
        'Indian Classics',
        'Golden Era Hollywood',
        'Film Noir',
        'Sci-Fi & Horror',
        'Silent Era',
      ],
    },
    'dm_movies': {
      'label': '📺 Dailymotion',
      'type': 'movie',
      'src': 'local',
      'id': 'dm_movies',
      'genres': [
        'All',
        'Hindi Movies & Dramas',
        'Pakistani Dramas',
        'International Movies',
      ],
    },
  };

  @override
  void initState() {
    super.initState();
    // Request initial focus on the primary action button for TV remote
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startStopFocus.requestFocus();
    });

    final cfg = AddonConfig.instance;
    final currentKey = cfg.torboxApiKey;
    _torboxKeyController.text = currentKey;
    if (currentKey.isNotEmpty) {
      _validateTorboxKeySilent(currentKey);
    }

    _tmdbKeyController.text = cfg.tmdbApiKey;
    _omdbKeyController.text = cfg.omdbApiKey;
    _fanartKeyController.text = cfg.fanartApiKey;
    _tvdbKeyController.text = cfg.tvdbApiKey;
    _dtddKeyController.text = cfg.dtddApiKey;
    _selectedAudioLang = cfg.preferredLanguage;
    _selectedMaxRes = cfg.maxResolution;
    _excludeCams = cfg.excludeCams;
    _enableDeduplication = cfg.enableDeduplication;
    _enableDeadLinkFilter = cfg.enableDeadLinkFilter;
    _enableOpenSubtitles = cfg.enableOpenSubtitles;
    _enableTorboxCachedTorrents = cfg.enableTorboxCachedTorrents;
    _enableCacheBypass = cfg.enableCacheBypass;
    _proxyResolverController.text = cfg.proxyResolverUrl;

    // Preload default catalog
    _loadCatalog(reset: true);
    _startCacheQueuePolling();
  }

  @override
  void dispose() {
    _serverTabFocus.dispose();
    _streamingTabFocus.dispose();
    _iptvTabFocus.dispose();
    _cachingTabFocus.dispose();
    _aboutTabFocus.dispose();
    _cacheQueueTimer?.cancel();
    _iptvSearchController.dispose();
    _proxyResolverController.dispose();
    _startStopFocus.dispose();
    _oneClickInstallFocus.dispose();
    _copyManifestFocus.dispose();
    _openWebFocus.dispose();
    _refreshIpFocus.dispose();
    _torboxKeyController.dispose();
    _torboxInputFocus.dispose();
    _torboxSaveFocus.dispose();
    _torboxKeyLinkFocus.dispose();
    _tmdbKeyController.dispose();
    _omdbKeyController.dispose();
    _fanartKeyController.dispose();
    _tvdbKeyController.dispose();
    _dtddKeyController.dispose();
    _searchQueryController.dispose();
    _seasonController.dispose();
    _episodeController.dispose();
    _searchInputFocus.dispose();
    _searchButtonFocus.dispose();
    super.dispose();
  }

  Future<void> _validateTorboxKeySilent(String key) async {
    if (key.trim().isEmpty) return;
    final res = await TorboxService.instance.validateAccount(key.trim());
    if (mounted) {
      setState(() {
        _isTorboxValid = res['valid'] == true;
        _torboxStatusMessage = res['message'];
      });
    }
  }

  Future<void> _saveAndValidateTorbox() async {
    final key = _torboxKeyController.text.trim();
    setState(() {
      _isValidatingTorbox = true;
      _torboxStatusMessage = 'Validating key with TorBox API...';
    });

    AddonConfig.instance.torboxApiKey = key;
    await AddonConfig.instance.save();

    if (key.isEmpty) {
      setState(() {
        _isValidatingTorbox = false;
        _isTorboxValid = false;
        _torboxStatusMessage = 'TorBox integration disabled (key removed).';
      });
      return;
    }

    final res = await TorboxService.instance.validateAccount(key);
    if (mounted) {
      setState(() {
        _isValidatingTorbox = false;
        _isTorboxValid = res['valid'] == true;
        _torboxStatusMessage = res['message'] ?? (res['valid'] == true ? 'Connected' : 'Invalid Key');
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF238636),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$label copied to clipboard!',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final server = ServerService.instance;
    final cfg = AddonConfig.instance;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
          WindowService.instance.toggleFullscreen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<bool>(
          valueListenable: server.isRunning,
          builder: (context, running, _) {
            return ValueListenableBuilder<String>(
              valueListenable: server.localIp,
              builder: (context, ip, _) {
                final port = cfg.port;
                final manifestUrl = 'http://$ip:$port/manifest.json';
                final dashboardUrl = 'http://$ip:$port/configure';

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 720;

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Navigation Sidebar
                          _buildSidebarNav(running),
                          // Right Main Content View
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                              children: [
                                if (_selectedTabIndex == 0) ...[
                                  // TAB 0: Server Two-Column Dashboard
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            _buildStatusCard(running, ip, port, manifestUrl),
                                            const SizedBox(height: 18),
                                            _buildActionButtons(running, manifestUrl, dashboardUrl),
                                            const SizedBox(height: 18),
                                            _buildLogsCard(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      Expanded(
                                        flex: 5,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            _buildTorboxCard(),
                                            const SizedBox(height: 18),
                                            _buildOtherApisCard(),
                                            const SizedBox(height: 18),
                                            _buildStreamFilteringCard(),
                                            const SizedBox(height: 18),
                                            _buildInfoRow(isWide: true),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else if (_selectedTabIndex == 1) ...[
                                  // TAB 1: Cinema & Series Streaming Theater
                                  _buildStreamingView(isWide: true),
                                ] else if (_selectedTabIndex == 2) ...[
                                  // TAB 2: Global Live IPTV Broadcasts
                                  _buildIptvView(isWide: true),
                                ] else if (_selectedTabIndex == 3) ...[
                                  // TAB 3: TorBox Cloud Caching Queue
                                  _buildCachingView(isWide: true),
                                ] else ...[
                                  // TAB 4: Dedicated About & System Diagnostics
                                  _buildAboutView(isWide: true),
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    // Mobile Portrait Mode
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          children: [
                            // Mobile Top Tabs Switcher
                            _buildTabSelector(isWide: false),
                            const SizedBox(height: 16),

                            if (_selectedTabIndex == 0) ...[
                              // TAB 0: Server
                              _buildStatusCard(running, ip, port, manifestUrl),
                              const SizedBox(height: 16),
                              _buildActionButtons(running, manifestUrl, dashboardUrl),
                              const SizedBox(height: 16),
                              _buildTorboxCard(),
                              const SizedBox(height: 16),
                              _buildOtherApisCard(),
                              const SizedBox(height: 16),
                              _buildStreamFilteringCard(),
                              const SizedBox(height: 16),
                              _buildInfoRow(isWide: false),
                              const SizedBox(height: 16),
                              _buildLogsCard(),
                            ] else if (_selectedTabIndex == 1) ...[
                              // TAB 1: Cinema
                              _buildStreamingView(isWide: false),
                            ] else if (_selectedTabIndex == 2) ...[
                              // TAB 2: Live IPTV
                              _buildIptvView(isWide: false),
                            ] else if (_selectedTabIndex == 3) ...[
                              // TAB 3: Caching Queue
                              _buildCachingView(isWide: false),
                            ] else ...[
                              // TAB 4: About & Diagnostics
                              _buildAboutView(isWide: false),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    ),
    );
  }

  Widget _buildTabSelector({bool isWide = false}) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F2432)),
      ),
      child: Row(
        children: [
          // Tab 0: Server & Addon
          Expanded(
            child: _TvFocusableButton(
              focusNode: _serverTabFocus,
              onPressed: () {
                setState(() => _selectedTabIndex = 0);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  gradient: _selectedTabIndex == 0
                      ? const LinearGradient(colors: [Color(0xFF195FEB), Color(0xFFFF0C82)])
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.dns_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Server',
                        style: TextStyle(
                          fontSize: isWide ? 14 : 12,
                          fontWeight: FontWeight.bold,
                          color: _selectedTabIndex == 0 ? Colors.white : Colors.grey.shade400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Tab 1: Cinema & Series Streaming
          Expanded(
            child: _TvFocusableButton(
              focusNode: _streamingTabFocus,
              onPressed: () {
                setState(() => _selectedTabIndex = 1);
                if (_catalogItems.isEmpty && !_isLoadingCatalog) {
                  _loadCatalog(reset: true);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  gradient: _selectedTabIndex == 1
                      ? const LinearGradient(colors: [Color(0xFF195FEB), Color(0xFFFF0C82)])
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.movie_filter_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Cinema',
                        style: TextStyle(
                          fontSize: isWide ? 14 : 12,
                          fontWeight: FontWeight.bold,
                          color: _selectedTabIndex == 1 ? Colors.white : Colors.grey.shade400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Tab 2: Free Global Live IPTV
          Expanded(
            child: _TvFocusableButton(
              focusNode: _iptvTabFocus,
              onPressed: () {
                setState(() => _selectedTabIndex = 2);
                if (_iptvChannels.isEmpty && !_isLoadingIptv) {
                  _loadIptvChannels(reset: true);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  gradient: _selectedTabIndex == 2
                      ? const LinearGradient(colors: [Color(0xFF195FEB), Color(0xFFFF0C82)])
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.live_tv_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Live IPTV',
                        style: TextStyle(
                          fontSize: isWide ? 14 : 12,
                          fontWeight: FontWeight.bold,
                          color: _selectedTabIndex == 2 ? Colors.white : Colors.grey.shade400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Tab 3: TorBox Cloud Caching Queue
          Expanded(
            child: _TvFocusableButton(
              focusNode: _cachingTabFocus,
              onPressed: () {
                setState(() => _selectedTabIndex = 3);
                _loadCacheQueue(showFeedback: true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  gradient: _selectedTabIndex == 3
                      ? const LinearGradient(colors: [Color(0xFF195FEB), Color(0xFFFF0C82)])
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Caching',
                        style: TextStyle(
                          fontSize: isWide ? 14 : 12,
                          fontWeight: FontWeight.bold,
                          color: _selectedTabIndex == 3 ? Colors.white : Colors.grey.shade400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Tab 4: Dedicated About & System Diagnostics
          Expanded(
            child: _TvFocusableButton(
              focusNode: _aboutTabFocus,
              onPressed: () {
                setState(() => _selectedTabIndex = 4);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  gradient: _selectedTabIndex == 4
                      ? const LinearGradient(colors: [Color(0xFF195FEB), Color(0xFFFF0C82)])
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'About',
                        style: TextStyle(
                          fontSize: isWide ? 14 : 12,
                          fontWeight: FontWeight.bold,
                          color: _selectedTabIndex == 4 ? Colors.white : Colors.grey.shade400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNav(bool running) {
    final isExpanded = _isSidebarExpanded;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: isExpanded ? 230 : 68,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(right: BorderSide(color: Color(0xFF1F2432))),
      ),
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: isExpanded ? 12 : 8),
      child: Column(
        crossAxisAlignment: isExpanded ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
        children: [
          // Brand Logo & Expand/Collapse Toggle
          InkWell(
            onTap: () => setState(() => _isSidebarExpanded = !_isSidebarExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
              child: isExpanded
                  ? Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF0C82).withOpacity(0.4),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              'assets/images/hostreamio_logo.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFF195FEB),
                                child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Hostreamio', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFFF0C82))),
                              Text('Direct & Debrid', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.menu_open_rounded, color: Colors.grey, size: 20),
                          tooltip: 'Collapse sidebar',
                          onPressed: () => setState(() => _isSidebarExpanded = false),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: 'Hostreamio (Click to expand)',
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF0C82).withOpacity(0.4),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset(
                                'assets/images/hostreamio_logo.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFF195FEB),
                                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 16),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF1F2432), height: 1),
          const SizedBox(height: 14),

          // 5 Menu Buttons on Side Pane
          _buildSidebarNavButton(0, Icons.dns_rounded, 'Server & Addon', _serverTabFocus),
          const SizedBox(height: 8),
          _buildSidebarNavButton(1, Icons.movie_filter_rounded, 'Cinema & Series', _streamingTabFocus),
          const SizedBox(height: 8),
          _buildSidebarNavButton(2, Icons.live_tv_rounded, 'Live IPTV', _iptvTabFocus),
          const SizedBox(height: 8),
          _buildSidebarNavButton(3, Icons.bolt_rounded, 'Caching Queue', _cachingTabFocus),
          const SizedBox(height: 8),
          _buildSidebarNavButton(4, Icons.info_outline_rounded, 'About & Diagnostics', _aboutTabFocus),

          const Spacer(),

          // Fullscreen Toggle Button (Desktop & Mobile)
          ValueListenableBuilder<bool>(
            valueListenable: WindowService.instance.isFullscreenNotifier,
            builder: (context, isFs, _) {
              return _buildSidebarActionButton(
                icon: isFs ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                label: isFs ? 'Exit Fullscreen' : 'Fullscreen (F11)',
                onPressed: () => WindowService.instance.toggleFullscreen(),
              );
            },
          ),
          const SizedBox(height: 8),

          // Running status indicator
          isExpanded
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: running ? const Color(0xFF3FB950) : const Color(0xFFF85149),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: running ? const Color(0xFF3FB950).withOpacity(0.6) : const Color(0xFFF85149).withOpacity(0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        running ? 'Engine Online' : 'Engine Stopped',
                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )
              : Tooltip(
                  message: running ? 'Engine Online (Click to toggle)' : 'Engine Stopped (Click to toggle)',
                  child: InkWell(
                    onTap: () => setState(() => _isSidebarExpanded = true),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF30363D)),
                      ),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: running ? const Color(0xFF3FB950) : const Color(0xFFF85149),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: running ? const Color(0xFF3FB950).withOpacity(0.6) : const Color(0xFFF85149).withOpacity(0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSidebarNavButton(int index, IconData icon, String label, FocusNode focusNode) {
    final isSelected = _selectedTabIndex == index;
    final isExpanded = _isSidebarExpanded;

    return Tooltip(
      message: isExpanded ? '' : label,
      preferBelow: false,
      child: _TvFocusableButton(
        focusNode: focusNode,
        onPressed: () {
          setState(() => _selectedTabIndex = index);
          if (index == 2 && _iptvChannels.isEmpty && !_isLoadingIptv) {
            _loadIptvChannels(reset: true);
          } else if (index == 3) {
            _loadCacheQueue(showFeedback: false);
          }
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isExpanded ? 12 : 8, vertical: 12),
          decoration: BoxDecoration(
            gradient: isSelected ? const LinearGradient(colors: [Color(0xFF195FEB), Color(0xFFFF0C82)]) : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? const Color(0xFFFF0C82).withOpacity(0.5) : Colors.transparent),
          ),
          child: isExpanded
              ? Row(
                  children: [
                    Icon(icon, size: 20, color: isSelected ? Colors.white : Colors.grey.shade400),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.grey.shade300,
                        ),
                      ),
                    ),
                    if (index == 3 && _cacheQueueItems.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0C82),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_cacheQueueItems.length}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                  ],
                )
              : Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(icon, size: 22, color: isSelected ? Colors.white : Colors.grey.shade400),
                      if (index == 3 && _cacheQueueItems.isNotEmpty)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF0C82),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSidebarActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final isExpanded = _isSidebarExpanded;
    return Tooltip(
      message: isExpanded ? '' : label,
      preferBelow: false,
      child: _TvFocusableButton(
        onPressed: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isExpanded ? 12 : 8, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: isExpanded
              ? Row(
                  children: [
                    Icon(icon, size: 20, color: const Color(0xFF58A6FF)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                )
              : Center(child: Icon(icon, size: 20, color: const Color(0xFF58A6FF))),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  TORBOX CLOUD CACHING QUEUE LOGIC & UI (ANDROID)
  // ════════════════════════════════════════════════════════════

  final TextEditingController _cachingUploadInputController = TextEditingController();

  void _startCacheQueuePolling() {
    _cacheQueueTimer?.cancel();
    _cacheQueueTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_selectedTabIndex == 3 && mounted) {
        _loadCacheQueue(showFeedback: false);
      }
    });
  }

  Future<void> _loadCacheQueue({bool showFeedback = false}) async {
    final apiKey = AddonConfig.instance.torboxApiKey.trim();
    if (apiKey.isEmpty) {
      if (mounted) {
        setState(() {
          _cacheQueueItems = [];
          _isLoadingCacheQueue = false;
        });
      }
      return;
    }
    setState(() => _isLoadingCacheQueue = true);
    try {
      final items = await TorboxService.instance.getLiveCacheQueue(apiKey);
      if (mounted) {
        setState(() {
          _cacheQueueItems = items;
          _isLoadingCacheQueue = false;
        });
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚡ Caching queue refreshed!'),
              backgroundColor: Color(0xFF195FEB),
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingCacheQueue = false);
    }
  }

  Future<void> _deleteCacheQueueItem(String id, String type) async {
    final apiKey = AddonConfig.instance.torboxApiKey.trim();
    final ok = await TorboxService.instance.deleteQueueItem(id, type, apiKey);
    if (ok && mounted) {
      _loadCacheQueue(showFeedback: false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🗑️ Removed from TorBox cloud queue'),
          backgroundColor: Color(0xFF238636),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _uploadFromCachingInput() async {
    final url = _cachingUploadInputController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste a valid stream or hoster URL'), backgroundColor: Colors.orange),
      );
      return;
    }
    final apiKey = AddonConfig.instance.torboxApiKey.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please configure your TorBox API key first'), backgroundColor: Colors.red),
      );
      return;
    }
    final res = await TorboxService.instance.uploadToTorbox(url, apiKey);
    if (res['success'] == true && mounted) {
      _cachingUploadInputController.clear();
      _loadCacheQueue(showFeedback: false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('☁️ Link queued to TorBox Caching!'), backgroundColor: Color(0xFF238636)),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Upload failed'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildCachingView({bool isWide = false}) {
    final hasKey = AddonConfig.instance.torboxApiKey.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Color(0xFFFF0C82), size: 26),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'TorBox Cloud Caching Queue',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  if (_isLoadingCacheQueue)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF0C82)),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 22),
                      tooltip: 'Refresh Queue',
                      onPressed: () => _loadCacheQueue(showFeedback: true),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Real-time status of hoster streams & torrents currently downloading to high-speed cloud CDN.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 14),
              // Paste Link Input Box
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF30363D)),
                      ),
                      child: TextField(
                        controller: _cachingUploadInputController,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Paste hoster or magnet link to cache (HubCloud, PixelDrain, GoFile)...',
                          hintStyle: TextStyle(color: Color(0xFF484F58), fontSize: 12),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _uploadFromCachingInput,
                    icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                    label: const Text('Start Caching', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF238636),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // If no TorBox key configured
        if (!hasKey) ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Column(
              children: [
                const Icon(Icons.vpn_key_rounded, size: 42, color: Color(0xFF818CF8)),
                const SizedBox(height: 12),
                const Text(
                  'TorBox API Key Not Configured',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter your TorBox API key in the Server tab to activate cloud caching and track live download progress.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () => setState(() => _selectedTabIndex = 0),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF195FEB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Go to Server Settings'),
                ),
              ],
            ),
          ),
        ] else if (_cacheQueueItems.isEmpty) ...[
          // Empty state
          Container(
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Column(
              children: [
                const Icon(Icons.bolt_rounded, size: 48, color: Color(0xFF484F58)),
                const SizedBox(height: 12),
                const Text(
                  'Cache Queue is Empty',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'When you click "Cache to TorBox" on an uncached stream, or attempt to stream an uncached link, it will appear here with live speed, ETA, and progress.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400, height: 1.4),
                ),
              ],
            ),
          ),
        ] else ...[
          // Active Queue List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _cacheQueueItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final it = _cacheQueueItems[index];
              final isDone = it['status'] == 'completed';
              final isFailed = it['status'] == 'failed';
              final pct = it['progressPercent'] ?? ((it['progress'] ?? 0.0) * 100).round();
              final name = it['name']?.toString() ?? 'Stream Download';
              final size = it['size']?.toString() ?? '--';
              final speed = it['speed']?.toString() ?? '--';
              final eta = it['eta']?.toString() ?? '--';
              final type = it['type'] == 'torrent' ? 'Torrent' : 'WebDL';
              final rawUrl = it['rawUrl']?.toString() ?? '';
              final playUrl = 'http://localhost:7002/torbox/play?url=${Uri.encodeComponent(rawUrl)}';

              Color badgeColor = const Color(0xFF58A6FF);
              String badgeText = '⚡ CACHING ($pct%)';
              if (isDone) {
                badgeColor = const Color(0xFF3FB950);
                badgeText = '✅ READY';
              } else if (isFailed) {
                badgeColor = const Color(0xFFF85149);
                badgeText = '❌ FAILED';
              } else if (it['status'] == 'queued') {
                badgeColor = const Color(0xFFE3B341);
                badgeText = '⏳ QUEUED';
              }

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDone ? const Color(0xFF238636) : const Color(0xFF21262D), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF161B22),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(type, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('📦 $size', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                                  const SizedBox(width: 8),
                                  Text('⚡ $speed', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                                  const SizedBox(width: 8),
                                  Text('⏱️ $eta', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: badgeColor, width: 1),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (it['progress'] is num) ? (it['progress'] as num).toDouble() : 0.0,
                        backgroundColor: const Color(0xFF161B22),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDone ? const Color(0xFF3FB950) : const Color(0xFFFF0C82),
                        ),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isDone ? '✨ Ready to stream from TorBox CDN' : 'Downloading to cloud drive…',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        ),
                        Row(
                          children: [
                            if (isDone && rawUrl.isNotEmpty) ...[
                              ElevatedButton.icon(
                                onPressed: () => _playStream(playUrl),
                                icon: const Icon(Icons.play_arrow_rounded, size: 14),
                                label: const Text('Play', style: TextStyle(fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF238636),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton.icon(
                                onPressed: () => _showPlayWithDialog({'url': playUrl, 'title': name, 'name': name}),
                                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                label: const Text('Play With', style: TextStyle(fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF195FEB),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                              tooltip: 'Remove',
                              onPressed: () => _deleteCacheQueueItem(it['id'].toString(), it['type'].toString()),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildAboutView({bool isWide = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Brand Header (Logo, title, subtitle)
        Center(
          child: Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF0C82).withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: const Color(0xFF195FEB).withOpacity(0.4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/images/hostreamio_logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF195FEB),
                      child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 40),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Hostreamio',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFF0C82),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Direct Hosters • Streaming Links • TorBox Cloud Debrid • Smart Proxy • Instant Badges',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400, height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF238636).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3FB950).withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF3FB950), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      Platform.isWindows ? 'Release v1.0.0 Ready (Native Windows Desktop)' : 'Release v1.0.0 Ready (Native Android TV & Mobile)',
                      style: const TextStyle(color: Color(0xFF7EE787), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Engine Status & Architecture Card
        _buildEngineFeaturesCard(),
        const SizedBox(height: 18),

        // Community Attributions & Open Source Credits Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.stars_rounded, color: Color(0xFFFFD700), size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Community Attributions & Open Source Credits',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Hostreamio stands on the shoulders of giants. We gratefully acknowledge and credit the following pioneering open source developers, communities, and services:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400, height: 1.4),
              ),
              const SizedBox(height: 14),
              _buildCreditItem('PlayTorrio (ayman708-UX)', 'Original base Dart scraper architecture, StreamSource models, Knaben aggregator & TorrentGalaxy scrapers.', const Color(0xFF58A6FF)),
              _buildCreditItem('Cloudstream 3 Community & Extension Authors', 'Pioneering hoster extraction patterns and cloud link bypass techniques (Hexated, Stormunblessed, Hindi Providers).', const Color(0xFF79C0FF)),
              _buildCreditItem('Nuvio Team', 'Next-gen TV and desktop streaming player with beautiful native badge pill rendering and player UX.', const Color(0xFF7EE787)),
              _buildCreditItem('TorBox', 'Exceptional debrid infrastructure, lightning-fast WebDL cloud caching, and high-bandwidth global CDN delivery.', const Color(0xFF0070F3)),
              _buildCreditItem('Nyaa.si & Tokyo Toshokan', 'Global anime, Asian live-action drama & OST community metadata, indexing, and RSS feeds.', const Color(0xFFFF69B4)),
              _buildCreditItem('1TamilMV & TamilBlasters Community', 'Premier regional Indian entertainment trackers for Hindi, Tamil, Telugu, Malayalam, and Kannada releases.', const Color(0xFF3FB950)),
              _buildCreditItem('YTS.mx & EZTV APIs', 'Public community APIs for high-efficiency movie releases and global television series episodes.', const Color(0xFFF55014)),
              _buildCreditItem('IPTV-org Community', 'Public domain worldwide live television broadcasts, logos, categories, and electronic program guides.', const Color(0xFF38BDF8)),
              _buildCreditItem('OpenSubtitles.org v3 API', 'Direct subtitle synchronization across 90+ languages without mandatory VIP registration.', const Color(0xFFE3B341)),
              _buildCreditItem('CNCVerse-Bridge', 'Design inspiration for DNS-over-HTTPS fallback, segment caching, and virtual HLS playlist converter.', const Color(0xFFBC8CFF)),
              _buildCreditItem('Torrentio, MediaFusion, Comet, AIOStreams & EasyTorbox', 'For shaping modern community debrid streaming workflows and Stremio/Nuvio addon conventions.', const Color(0xFFD29922)),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Legal & Vibe Coded Disclaimer Footer
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF21262D)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF69B4).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFF69B4).withOpacity(0.3)),
                  ),
                  child: const Text('✨ 100% VIBE CODED WITH AI', style: TextStyle(color: Color(0xFFFF69B4), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ),
                const SizedBox(height: 8),
                Text(
                  '⚖️ GitHub & Legal Disclaimer: The author does not own, host, upload, or broadcast any media or streams. Hostreamio acts solely as a local search indexer aggregating publicly available hyperlinks from third-party websites on the internet. All media is hosted by independent third-party services. Not affiliated with Stremio, Nuvio, TorBox, or any scraped source.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreditItem(String title, String desc, Color accentColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF21262D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: accentColor)),
          const SizedBox(height: 3),
          Text(desc, style: TextStyle(fontSize: 11, color: Colors.grey.shade400, height: 1.3)),
        ],
      ),
    );
  }


  Widget _buildStepPill(String text, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isHighlight ? const Color(0xFF3FB950) : const Color(0xFF30363D)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
          color: isHighlight ? const Color(0xFF3FB950) : Colors.white,
        ),
      ),
    );
  }

  Widget _buildStatusCard(bool running, String ip, int port, String manifestUrl) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1F2432), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.router_rounded, color: Color(0xFF195FEB), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Nuvio Addon Manifest URL',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _TvFocusableButton(
                focusNode: _refreshIpFocus,
                onPressed: () async {
                  await ServerService.instance.updateLanIp();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, size: 15, color: Color(0xFF195FEB)),
                      SizedBox(width: 4),
                      Text('Detect IP', style: TextStyle(color: Color(0xFF195FEB), fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF08090C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1F2432)),
            ),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, color: Color(0xFFFF0C82), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    manifestUrl,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7EE787),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildStepPill('1. Open Nuvio'),
              const Text('➔', style: TextStyle(color: Colors.grey, fontSize: 11)),
              _buildStepPill('2. Settings ⚙️'),
              const Text('➔', style: TextStyle(color: Colors.grey, fontSize: 11)),
              _buildStepPill('3. General'),
              const Text('➔', style: TextStyle(color: Colors.grey, fontSize: 11)),
              _buildStepPill('4. Addons (+)'),
              const Text('➔', style: TextStyle(color: Colors.grey, fontSize: 11)),
              _buildStepPill('5. Paste & Install', isHighlight: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTorboxCard() {
    final hasKey = _torboxKeyController.text.trim().isNotEmpty;
    Color statusColor;
    String statusBadgeText;
    IconData statusIcon;

    if (!hasKey) {
      statusColor = const Color(0xFF8B949E);
      statusBadgeText = 'OPTIONAL';
      statusIcon = Icons.info_outline_rounded;
    } else if (_isValidatingTorbox) {
      statusColor = const Color(0xFF58A6FF);
      statusBadgeText = 'VALIDATING...';
      statusIcon = Icons.sync_rounded;
    } else if (_isTorboxValid) {
      statusColor = const Color(0xFF3FB950);
      statusBadgeText = 'CONNECTED';
      statusIcon = Icons.check_circle_rounded;
    } else {
      statusColor = const Color(0xFFF85149);
      statusBadgeText = 'INVALID KEY';
      statusIcon = Icons.error_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isTorboxValid ? const Color(0xFF238636) : const Color(0xFF30363D),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_sync_rounded, color: Color(0xFF38BDF8), size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'TorBox Debrid Integration',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      statusBadgeText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Enables 1-click cloud streaming and instant caching for HubCloud, PixelDrain, and direct hosters via TorBox CDNs with high-speed byte seeking in Nuvio.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          // API Key Input
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF21262D)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.vpn_key_rounded, color: Color(0xFF818CF8), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    focusNode: _torboxInputFocus,
                    controller: _torboxKeyController,
                    obscureText: _obscureTorboxKey,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Enter TorBox API Key (manual input only)',
                      hintStyle: TextStyle(color: Color(0xFF484F58), fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    ),
                    onFieldSubmitted: (_) => _saveAndValidateTorbox(),
                  ),
                ),
                IconButton(
                  tooltip: _obscureTorboxKey ? 'Show API Key' : 'Hide API Key',
                  icon: Icon(
                    _obscureTorboxKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureTorboxKey = !_obscureTorboxKey;
                    });
                  },
                ),
                if (_torboxKeyController.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.clear_rounded, color: Colors.grey, size: 18),
                    onPressed: () {
                      _torboxKeyController.clear();
                      _saveAndValidateTorbox();
                    },
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Action Buttons: Save & Validate, Open TorBox Settings
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _TvFocusableButton(
                focusNode: _torboxSaveFocus,
                isPrimary: true,
                primaryColor: const Color(0xFF238636),
                onPressed: _isValidatingTorbox ? () {} : _saveAndValidateTorbox,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isValidatingTorbox)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      else
                        const Icon(Icons.save_rounded, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Save & Validate',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              _TvFocusableButton(
                focusNode: _torboxKeyLinkFocus,
                onPressed: () async {
                  const url = 'https://torbox.app/settings';
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    _copyToClipboard(url, 'TorBox Settings URL');
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.launch_rounded, size: 16, color: Color(0xFF38BDF8)),
                      SizedBox(width: 6),
                      Text(
                        'Get Key (torbox.app)',
                        style: TextStyle(fontSize: 13, color: Color(0xFF38BDF8), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_torboxStatusMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (_isTorboxValid ? const Color(0xFF238636) : const Color(0xFF21262D)).withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isTorboxValid ? const Color(0xFF3FB950).withOpacity(0.4) : const Color(0xFF30363D),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isTorboxValid ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                    color: _isTorboxValid ? const Color(0xFF3FB950) : const Color(0xFF8B949E),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _torboxStatusMessage!,
                      style: TextStyle(
                        fontSize: 13,
                        color: _isTorboxValid ? const Color(0xFF7EE787) : const Color(0xFFC9D1D9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _enableTorboxCachedTorrents ? const Color(0xFFE3B341) : const Color(0xFF21262D)),
            ),
            child: CheckboxListTile(
              title: const Text('⚡ Fetch TorBox Cached Torrents (Default OFF • 0 P2P)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              subtitle: Text('Queries community torrent scrapers (Nyaa Anime, 1TamilMV Desi, Asian Dramas, YTS, EZTV) and streams ONLY 100% cached files via TorBox CDN. Uncached torrents are discarded. Zero P2P upload.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
              value: _enableTorboxCachedTorrents,
              activeColor: const Color(0xFFE3B341),
              contentPadding: EdgeInsets.zero,
              onChanged: (v) {
                setState(() => _enableTorboxCachedTorrents = v ?? false);
                AddonConfig.instance.enableTorboxCachedTorrents = _enableTorboxCachedTorrents;
                AddonConfig.instance.scheduleSave();
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testApiKey(String service, String key) async {
    setState(() {
      _apiValidating[service] = true;
      _apiStatusMessages[service] = 'Validating key...';
    });
    try {
      final res = await KeyValidator.validate(service, key);
      if (mounted) {
        setState(() {
          _apiValidating[service] = false;
          _apiValid[service] = res.valid;
          _apiStatusMessages[service] = res.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _apiValidating[service] = false;
          _apiValid[service] = false;
          _apiStatusMessages[service] = 'Validation error: $e';
        });
      }
    }
  }

  Future<void> _saveOtherApiKeys() async {
    final cfg = AddonConfig.instance;
    cfg.tmdbApiKey = _tmdbKeyController.text.trim();
    cfg.omdbApiKey = _omdbKeyController.text.trim();
    cfg.fanartApiKey = _fanartKeyController.text.trim();
    cfg.tvdbApiKey = _tvdbKeyController.text.trim();
    cfg.dtddApiKey = _dtddKeyController.text.trim();
    await cfg.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Metadata & External API keys saved successfully!'),
          backgroundColor: Color(0xFF238636),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveStreamFiltering() async {
    final cfg = AddonConfig.instance;
    cfg.preferredLanguage = _selectedAudioLang;
    cfg.maxResolution = _selectedMaxRes;
    cfg.excludeCams = _excludeCams;
    cfg.enableDeduplication = _enableDeduplication;
    cfg.enableDeadLinkFilter = _enableDeadLinkFilter;
    cfg.enableOpenSubtitles = _enableOpenSubtitles;
    cfg.enableTorboxCachedTorrents = _enableTorboxCachedTorrents;
    cfg.enableCacheBypass = _enableCacheBypass;
    cfg.proxyResolverUrl = _proxyResolverController.text.trim();
    await cfg.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Stream filtering & resolver profiles saved!'),
          backgroundColor: Color(0xFF238636),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildApiRow({
    required String title,
    required String subtitle,
    required String service,
    required TextEditingController controller,
    required String hintText,
    required String helpUrl,
    required String helpLabel,
  }) {
    final isValidating = _apiValidating[service] == true;
    final statusMsg = _apiStatusMessages[service];
    final isValid = _apiValid[service];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF21262D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              InkWell(
                onTap: () async {
                  final uri = Uri.parse(helpUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  helpLabel,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8), decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: TextFormField(
                    controller: controller,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: const TextStyle(color: Color(0xFF484F58), fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isValidating ? null : () => _testApiKey(service, controller.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF21262D),
                  foregroundColor: const Color(0xFF58A6FF),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  side: const BorderSide(color: Color(0xFF30363D)),
                ),
                child: isValidating
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF58A6FF)))
                    : const Text('🔍 Test Key', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (statusMsg != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isValid == true ? Icons.check_circle_rounded : (isValid == false ? Icons.error_rounded : Icons.info_rounded),
                  size: 14,
                  color: isValid == true ? const Color(0xFF3FB950) : (isValid == false ? const Color(0xFFF85149) : const Color(0xFF8B949E)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    statusMsg,
                    style: TextStyle(
                      fontSize: 11,
                      color: isValid == true ? const Color(0xFF7EE787) : (isValid == false ? const Color(0xFFFFA198) : const Color(0xFF8B949E)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOtherApisCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF30363D), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFF69B4), size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Metadata & Artwork API Integrations',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _saveOtherApiKeys,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save Keys', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF195FEB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Enrich Nuvio & Stremio with crystal-clear ClearLogos, 4K artwork, Rotten Tomatoes / IMDb ratings, and anime absolute episode mappings. All keys 100% optional (zero-key public fallbacks active).',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          _buildApiRow(
            title: '1. OMDb API Key (IMDb & Rotten Tomatoes Ratings)',
            subtitle: 'Live rating badges directly inside Stremio & Nuvio streams.',
            service: 'omdb',
            controller: _omdbKeyController,
            hintText: 'Pre-configured fallback key active',
            helpUrl: 'https://www.omdbapi.com/apikey.aspx',
            helpLabel: 'Get OMDb Key (Free) ↗',
          ),
          _buildApiRow(
            title: '2. Fanart.tv API Key (ClearLogos & HD Artwork)',
            subtitle: 'HD transparent PNG logos and custom title banners.',
            service: 'fanart',
            controller: _fanartKeyController,
            hintText: 'Leave empty for Metahub ClearLogos fallback',
            helpUrl: 'https://fanart.tv/get-an-api-key/',
            helpLabel: 'Get Fanart.tv Key ↗',
          ),
          _buildApiRow(
            title: '3. TheTVDB API Key (Episode Mappings & Seasons)',
            subtitle: 'Precise anime episode mappings, specials & alternate season orders.',
            service: 'tvdb',
            controller: _tvdbKeyController,
            hintText: 'Leave empty for Cinemeta & TVMaze fallback',
            helpUrl: 'https://thetvdb.com/api-information',
            helpLabel: 'Get TVDB Key ↗',
          ),
          _buildApiRow(
            title: '4. TMDB API Key (The Movie Database)',
            subtitle: 'Rich cast, posters, plot descriptions, and recommendations.',
            service: 'tmdb',
            controller: _tmdbKeyController,
            hintText: 'Pre-configured fallback key active',
            helpUrl: 'https://www.themoviedb.org/settings/api',
            helpLabel: 'Get TMDB Key ↗',
          ),
          _buildApiRow(
            title: '5. DoesTheDogDie (DTDD) API Key (Content Warnings & Triggers)',
            subtitle: 'Enables community trigger advisories & content warnings (e.g. animal death, jumpscares) in media details.',
            service: 'dtdd',
            controller: _dtddKeyController,
            hintText: 'Leave empty for zero-key web resolution fallback',
            helpUrl: 'https://www.doesthedogdie.com',
            helpLabel: 'Get DTDD Key (Free) ↗',
          ),
        ],
      ),
    );
  }

  Widget _buildStreamFilteringCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF30363D), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: Color(0xFFF55014), size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Stream Filtering Profiles & Optimization',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _saveStreamFiltering,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save Settings', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF238636),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Fine-tune how streams are filtered, deduplicated, and ranked in your Nuvio drawer.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          // Preferred Audio Language
          Row(
            children: [
              const Expanded(
                child: Text('Preferred Audio Language:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: DropdownButton<String>(
                  value: _selectedAudioLang,
                  dropdownColor: const Color(0xFF161B22),
                  underline: const SizedBox(),
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'any', child: Text('Any / Default Order')),
                    DropdownMenuItem(value: 'hindi', child: Text('🇮🇳 Hindi')),
                    DropdownMenuItem(value: 'english', child: Text('🇬🇧 English')),
                    DropdownMenuItem(value: 'dual', child: Text('🌐 Dual / Multi Audio')),
                    DropdownMenuItem(value: 'tamil', child: Text('🇮🇳 Tamil')),
                    DropdownMenuItem(value: 'telugu', child: Text('🇮🇳 Telugu')),
                    DropdownMenuItem(value: 'malayalam', child: Text('🇮🇳 Malayalam')),
                    DropdownMenuItem(value: 'kannada', child: Text('🇮🇳 Kannada')),
                    DropdownMenuItem(value: 'bengali', child: Text('🇮🇳 Bengali')),
                    DropdownMenuItem(value: 'punjabi', child: Text('🇮🇳 Punjabi')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedAudioLang = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Max Resolution Cap
          Row(
            children: [
              const Expanded(
                child: Text('Max Resolution Cap:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: DropdownButton<String>(
                  value: _selectedMaxRes,
                  dropdownColor: const Color(0xFF161B22),
                  underline: const SizedBox(),
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Unlimited (4K / 2160p)')),
                    DropdownMenuItem(value: '1080p', child: Text('1080p Max')),
                    DropdownMenuItem(value: '720p', child: Text('720p Max')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedMaxRes = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Checkboxes
          CheckboxListTile(
            title: const Text('Clean Drawer Mode (Exclude CAMs & TeleSync)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            subtitle: Text('Automatically strips CAM, TS, PreDVD, and Telesync copies when WEB-DL exists.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            value: _excludeCams,
            activeColor: const Color(0xFF238636),
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _excludeCams = v ?? true),
          ),
          CheckboxListTile(
            title: const Text('Smart Stream Deduplication', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            subtitle: Text('Merges duplicate CDN streams from multiple providers into a single stream card.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            value: _enableDeduplication,
            activeColor: const Color(0xFF238636),
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _enableDeduplication = v ?? true),
          ),
          CheckboxListTile(
            title: const Text('Ultra-Fast Dead-Link Filter', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            subtitle: Text('Runs rapid parallel HEAD probes on stream links to eliminate broken file hosters.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            value: _enableDeadLinkFilter,
            activeColor: const Color(0xFF238636),
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _enableDeadLinkFilter = v ?? true),
          ),
          CheckboxListTile(
            title: const Text('OpenSubtitles v3 Subtitle Fetching', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            subtitle: Text('Automatically fetches multi-language subtitles (.srt) for movies & TV series.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            value: _enableOpenSubtitles,
            activeColor: const Color(0xFF238636),
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _enableOpenSubtitles = v ?? true),
          ),
          const Divider(color: Color(0xFF30363D), height: 24),
          const Text('Anti-Scrape & Captcha Resolver (Prowlarr / FlareSolverr)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 6),
          Text('Solves Cloudflare Turnstile, IUAM challenges, and bypasses ISP stale caching headers.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.security_rounded, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _proxyResolverController,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'FlareSolverr URL (e.g. http://localhost:8191/v1)',
                      hintStyle: TextStyle(color: Color(0xFF484F58), fontSize: 12),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            title: const Text('Prowlarr Origin-Fresh Cache-Bypass', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            subtitle: Text('Injects origin no-cache headers and query nonces to avoid stale or blocked ISP cache hits.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            value: _enableCacheBypass,
            activeColor: const Color(0xFF238636),
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _enableCacheBypass = v ?? true),
          ),
        ],
      ),
    );
  }

  Widget _buildEngineFeaturesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.speed_rounded, color: Color(0xFF818CF8), size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Engine & Network Optimizations',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isTwoColumn = constraints.maxWidth >= 500;
              final itemWidth = isTwoColumn ? (constraints.maxWidth - 12) / 2 : double.infinity;

              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _buildFeatureBadge(
                      icon: Icons.shield_rounded,
                      title: 'DoH DNS Fallback',
                      subtitle: 'Cloudflare & Google (Active)',
                      color: const Color(0xFF238636),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildFeatureBadge(
                      icon: Icons.memory_rounded,
                      title: 'HLS Segment Cache',
                      subtitle: '35 MB Ring Buffer (Active)',
                      color: const Color(0xFF1F6FEB),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildFeatureBadge(
                      icon: Icons.video_settings_rounded,
                      title: 'MPEG-DASH Transmuxer',
                      subtitle: 'Virtual HLS Converter (Ready)',
                      color: const Color(0xFF7928CA),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildFeatureBadge(
                      icon: Icons.electric_bolt_rounded,
                      title: 'Auto Circuit Breaker',
                      subtitle: '56 Providers Monitored',
                      color: const Color(0xFFD29922),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBadge({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF21262D)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8B949E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool running, String manifestUrl, String dashboardUrl) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        // Start / Stop Toggle
        _TvFocusableButton(
          focusNode: _startStopFocus,
          isPrimary: true,
          primaryColor: running ? const Color(0xFFDA3633) : const Color(0xFF238636),
          onPressed: () async {
            if (running) {
              await ServerService.instance.stopServer();
            } else {
              await ServerService.instance.startServer();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 22,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  running ? 'Stop Server' : 'Start Server',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ),

        // 1-Click Install to Stremio / Nuvio
        _TvFocusableButton(
          focusNode: _oneClickInstallFocus,
          isPrimary: true,
          primaryColor: const Color(0xFF195FEB),
          onPressed: () async {
            final port = AddonConfig.instance.port;
            final uri = Uri.parse('stremio://127.0.0.1:$port/manifest.json');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              _copyToClipboard(manifestUrl, 'Addon Manifest URL');
            }
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.download_rounded, size: 22, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  '1-Click Install (Stremio / Nuvio)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ),

        // Copy Manifest URL
        _TvFocusableButton(
          focusNode: _copyManifestFocus,
          onPressed: () {
            _copyToClipboard(manifestUrl, 'Addon Manifest URL');
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.copy_rounded, size: 20, color: Color(0xFFFF0C82)),
                SizedBox(width: 8),
                Text(
                  'Copy Manifest URL',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ),

        // Open Web Dashboard
        _TvFocusableButton(
          focusNode: _openWebFocus,
          onPressed: () async {
            final uri = Uri.parse(dashboardUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              _copyToClipboard(dashboardUrl, 'Web Dashboard URL');
            }
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.open_in_browser_rounded, size: 20, color: Color(0xFFF55014)),
                SizedBox(width: 8),
                Text(
                  'Open Web Dashboard',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({bool isWide = true}) {
    final activeCount = ScraperEngine.instance.activeScrapers.length;
    final totalCount = ScraperEngine.instance.getProviderList().length;

    final providersCard = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.hub_rounded, color: Color(0xFF818CF8), size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$activeCount / $totalCount Active',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Scraper Providers',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final requestsCard = ValueListenableBuilder<int>(
      valueListenable: ServerService.instance.requestCount,
      builder: (context, count, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF238636).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.sync_alt_rounded, color: Color(0xFF3FB950), size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$count Requests',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Handled this session',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (isWide) {
      return Row(
        children: [
          Expanded(child: providersCard),
          const SizedBox(width: 14),
          Expanded(child: requestsCard),
        ],
      );
    } else {
      return Column(
        children: [
          providersCard,
          const SizedBox(height: 12),
          requestsCard,
        ],
      );
    }
  }

  Widget _buildLogsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.terminal_rounded, color: Colors.grey, size: 20),
              SizedBox(width: 8),
              Text(
                'Live Server Activity',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 160,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF21262D)),
            ),
            child: ValueListenableBuilder<List<String>>(
              valueListenable: ServerService.instance.logs,
              builder: (context, logs, _) {
                if (logs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No requests yet. Listening on local network...',
                      style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final item = logs[logs.length - 1 - index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Color(0xFF8B949E),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Native Streaming Theater Implementation ──────────────────────────

  Widget _buildStreamingView({bool isWide = false}) {
    if (_isInDetailView && _selectedMediaMeta != null) {
      return _buildDedicatedMediaDetailView(isWide: isWide);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Dual-Rail Architecture Philosophy Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF195FEB).withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF195FEB).withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.lightbulb_rounded, color: Color(0xFF58A6FF), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Dual-Rail Streaming Philosophy',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF58A6FF)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '• ⚡ TorBox [Cached]: Plays from high-speed TorBox CDN instantly.\n'
                '• 🌐 TorBox [Start Caching]: Queues link in TorBox cloud; stream immediately on direct link without waiting!\n'
                '• 🌐 Direct Play: Direct hoster or HLS stream without requiring a debrid subscription.',
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade300),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Search & Scrape Control Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF11141C),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1F2432), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.search_rounded, color: Color(0xFFFF0C82), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isWide ? 'Native Search & Stream Theater' : 'Stream Theater',
                      style: TextStyle(fontSize: isWide ? 17 : 15, fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Media Type Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF08090C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TvFocusableButton(
                          onPressed: () {
                            setState(() {
                              _selectedMediaType = 'movie';
                              _seriesDetails = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedMediaType == 'movie' ? const Color(0xFF195FEB) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('🎬 Movie', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _TvFocusableButton(
                          onPressed: () {
                            setState(() => _selectedMediaType = 'series');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedMediaType == 'series' ? const Color(0xFF195FEB) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('📺 Series', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Search Input Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchQueryController,
                      focusNode: _searchInputFocus,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF08090C),
                        hintText: 'Search title or IMDb ID...',
                        hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1F2432))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1F2432))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFF0C82))),
                      ),
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                  if (_selectedMediaType == 'series') ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 50,
                      child: TextField(
                        controller: _seasonController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'S',
                          labelStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                          filled: true,
                          fillColor: const Color(0xFF08090C),
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1F2432))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 50,
                      child: TextField(
                        controller: _episodeController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'E',
                          labelStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                          filled: true,
                          fillColor: const Color(0xFF08090C),
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1F2432))),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  _TvFocusableButton(
                    focusNode: _searchButtonFocus,
                    isPrimary: true,
                    primaryColor: const Color(0xFFFF0C82),
                    onPressed: _performSearch,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isSearching)
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          else
                            const Icon(Icons.search_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          const Text('Search', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Search Suggestions Row
        if (_catalogSuggestions.isNotEmpty) ...[
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _catalogSuggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final m = _catalogSuggestions[index];
                final poster = m['poster']?.toString() ?? 'https://images.metahub.space/poster/medium/${m['id']}/img';
                return GestureDetector(
                  onTap: () => _onSelectSuggestion(m),
                  child: Container(
                    width: 220,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11141C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF1F2432)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            poster,
                            width: 50,
                            height: 75,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 50, height: 75, color: Colors.black26, child: const Icon(Icons.movie, size: 20)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                m['name']?.toString() ?? 'Title',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(m['type']?.toString() ?? '').toUpperCase()} • ${m['year'] ?? ''}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 4. Browse & Discover Catalogs (Mobile & TV Adaptable)
        _buildCatalogBrowser(isWide: isWide),
      ],
    );
  }

  /// Asynchronously fetches full metadata details (description, multi-source ratings,
  /// genres, cast) and DoesTheDogDie (DTDD) community trigger warnings.
  Future<void> _fetchRichMediaDetailsAndDtdd(String rawId, String type, String name, {String? yearStr}) async {
    setState(() => _isLoadingDtdd = true);

    // 1. Fetch full metadata (ratings, description, genres, year, cast, etc.)
    try {
      final details = await MetadataService.getMediaDetails(rawId, type: type);
      if (mounted && details != null && _selectedMediaMeta?['id'] == rawId) {
        setState(() {
          _selectedMediaMeta = {
            ...?_selectedMediaMeta,
            ...details,
          };
        });
      }
    } catch (e) {
      debugPrint('[Metadata] Error loading media details: $e');
    }

    // 2. Fetch DoesTheDogDie content warnings
    try {
      final cleanYear = int.tryParse((yearStr ?? _selectedMediaMeta?['year']?.toString() ?? '').split('-').first);
      final dtddData = await DtddService.instance.getContentWarnings(
        rawId,
        title: name,
        year: cleanYear,
      );
      if (mounted && dtddData.isNotEmpty && _selectedMediaMeta?['id'] == rawId) {
        setState(() {
          _selectedMediaMeta = {
            ...?_selectedMediaMeta,
            'dtdd': dtddData,
          };
          _isLoadingDtdd = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('[DTDD] Error fetching content warnings: $e');
    }

    if (mounted) setState(() => _isLoadingDtdd = false);
  }

  /// Builds the DoesTheDogDie Content Advisories card with community triggers and links.
  Widget _buildDtddCard(Map<String, dynamic>? dtdd, String title, String rawId) {
    final triggers = (dtdd?['triggers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final safe = (dtdd?['safe'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final dtddUrl = dtdd?['url']?.toString() ?? 'https://www.doesthedogdie.com/search?q=${Uri.encodeComponent(title)}';
    final hasTriggers = triggers.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasTriggers ? const Color(0xFFF85149).withOpacity(0.5) : const Color(0xFF1F2432),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          InkWell(
            onTap: () => setState(() => _isDtddExpanded = !_isDtddExpanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.pets_rounded, color: Color(0xFFE3B341), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'DoesTheDogDie Advisories',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  if (_isLoadingDtdd)
                    const Text('⏳ Checking...', style: TextStyle(fontSize: 11, color: Colors.grey))
                  else if (dtdd == null)
                    const Text('ℹ️ Community ratings', style: TextStyle(fontSize: 11, color: Colors.grey))
                  else if (hasTriggers)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF85149).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFF85149).withOpacity(0.5)),
                      ),
                      child: Text(
                        '⚠️ ${triggers.length} Triggers',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFF85149)),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF238636).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFF238636).withOpacity(0.5)),
                      ),
                      child: const Text(
                        '✅ No Major Triggers',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF3FB950)),
                      ),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: const Size(60, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () async {
                      try {
                        final uri = Uri.parse(dtddUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 12, color: Color(0xFF58A6FF)),
                    label: const Text('doesthedogdie.com', style: TextStyle(fontSize: 11, color: Color(0xFF58A6FF))),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isDtddExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Expanded Content Panel
          if (_isDtddExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF1F2432))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  if (_isLoadingDtdd)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('Checking community safety triggers...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    )
                  else if (dtdd == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('No advisory data returned yet.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    )
                  else if (triggers.isEmpty && safe.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('No triggers submitted by community members for this title.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    )
                  else ...[
                    if (triggers.isNotEmpty) ...[
                      const Text(
                        'Community Trigger Warnings:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFF85149)),
                      ),
                      const SizedBox(height: 6),
                      ...triggers.take(8).map((t) {
                        final topic = t['topic']?.toString() ?? '';
                        final yes = t['yes'] ?? 0;
                        final no = t['no'] ?? 0;
                        final comment = t['comment']?.toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFF85149)),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    RichText(
                                      text: TextSpan(
                                        text: topic,
                                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                                        children: [
                                          TextSpan(
                                            text: '  (Yes: $yes • No: $no)',
                                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (comment != null && comment.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          comment,
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    if (safe.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Safe Topics: ${safe.take(5).map((s) => s['topic']?.toString() ?? '').where((s) => s.isNotEmpty).join(', ')}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF3FB950)),
                      ),
                    ],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDedicatedMediaDetailView({bool isWide = false}) {
    final meta = _selectedMediaMeta ?? {};
    final id = meta['id']?.toString() ?? '';
    final name = meta['name']?.toString() ?? 'Media Details';
    final poster = meta['poster']?.toString() ?? (id.isNotEmpty ? 'https://images.metahub.space/poster/medium/$id/img' : '');
    final year = meta['year']?.toString() ?? '';
    final rating = meta['rating']?.toString() ?? meta['imdbRating']?.toString() ?? '';
    final desc = meta['description']?.toString() ?? meta['overview']?.toString() ?? '';
    final genres = meta['genres'] is List ? (meta['genres'] as List).map((e) => e.toString()).toList() : <String>[];
    final dtdd = meta['dtdd'] as Map<String, dynamic>?;
    final universalAge = meta['universalAgeRating']?.toString() ?? '';
    final indianAge = meta['indianAgeRating']?.toString() ?? '';
    final ratingsList = (meta['ratings'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Navigation Bar: Back to Catalog
        Row(
          children: [
            _TvFocusableButton(
              onPressed: () {
                setState(() => _isInDetailView = false);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Back to Catalog', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: TextStyle(fontSize: isWide ? 18 : 15, fontWeight: FontWeight.bold, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (id.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.grey),
                tooltip: 'Copy ID',
                onPressed: () => _copyToClipboard(id, 'Media ID'),
              ),
          ],
        ),
        const SizedBox(height: 14),

        // Hero Metadata Card (Nuvio-style)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF11141C),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1F2432), width: 1.5),
          ),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: poster.isNotEmpty
                          ? Image.network(
                              poster,
                              width: 140,
                              height: 210,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 140,
                                height: 210,
                                color: const Color(0xFF090D13),
                                child: const Icon(Icons.movie_rounded, color: Colors.grey, size: 40),
                              ),
                            )
                          : Container(
                              width: 140,
                              height: 210,
                              color: const Color(0xFF090D13),
                              child: const Icon(Icons.movie_rounded, color: Colors.grey, size: 40),
                            ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _selectedMediaType == 'series' ? const Color(0xFF195FEB) : const Color(0xFFFF0C82),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _selectedMediaType.toUpperCase(),
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                              if (year.isNotEmpty)
                                Text(year, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                              // Multi-source ratings
                              if (ratingsList.isNotEmpty)
                                ...ratingsList.map((r) {
                                  final src = r['source']?.toString() ?? '';
                                  final val = r['value']?.toString() ?? '';
                                  final isRotten = src.toLowerCase().contains('rotten');
                                  final isMeta = src.toLowerCase().contains('metacritic');
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(isRotten ? '🍅 ' : (isMeta ? 'Ⓜ️ ' : '★ '), style: const TextStyle(fontSize: 12)),
                                      Text(val, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                                    ],
                                  );
                                })
                              else if (rating.isNotEmpty && rating != '0')
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded, size: 16, color: Color(0xFFE3B341)),
                                    const SizedBox(width: 4),
                                    Text(rating, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              if (universalAge.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade600),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(universalAge, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                                ),
                              if (indianAge.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFFF9933)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(indianAge, style: const TextStyle(fontSize: 10, color: Color(0xFFFF9933), fontWeight: FontWeight.bold)),
                                ),
                              ...genres.map((g) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1F2432),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(g, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                  )),
                            ],
                          ),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              desc,
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade300, height: 1.4),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: poster.isNotEmpty
                              ? Image.network(
                                  poster,
                                  width: 90,
                                  height: 135,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 90,
                                    height: 135,
                                    color: const Color(0xFF090D13),
                                    child: const Icon(Icons.movie_rounded, color: Colors.grey, size: 30),
                                  ),
                                )
                              : Container(
                                  width: 90,
                                  height: 135,
                                  color: const Color(0xFF090D13),
                                  child: const Icon(Icons.movie_rounded, color: Colors.grey, size: 30),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _selectedMediaType == 'series' ? const Color(0xFF195FEB) : const Color(0xFFFF0C82),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      _selectedMediaType.toUpperCase(),
                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  if (year.isNotEmpty)
                                    Text(year, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  if (ratingsList.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, size: 14, color: Color(0xFFE3B341)),
                                        const SizedBox(width: 2),
                                        Text(ratingsList.first['value']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                      ],
                                    )
                                  else if (rating.isNotEmpty && rating != '0')
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, size: 14, color: Color(0xFFE3B341)),
                                        const SizedBox(width: 2),
                                        Text(rating, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  if (universalAge.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade600),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(universalAge, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                              if (genres.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  genres.take(3).join(', '),
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        desc,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400, height: 1.3),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // DoesTheDogDie Content Advisories & Trigger Warnings Card
        _buildDtddCard(dtdd, name, id),
        const SizedBox(height: 16),

        // Series Seasons & Episode browser (if series)
        if (_selectedMediaType == 'series' && _seriesDetails != null) ...[
          _buildSeriesCatalogBrowser(),
          const SizedBox(height: 16),
        ],

        // Scraped Streams Section
        _buildStreamsSection(),
      ],
    );
  }

  Widget _buildCatalogBrowser({bool isWide = false}) {
    final currentDef = _catalogDefs[_activeCatalogTab];
    final genres = currentDef != null && currentDef.containsKey('genres') ? currentDef['genres'] as List<String>? : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1F2432), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.video_library_rounded, color: Color(0xFFFF0C82), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Browse Catalogs',
                  style: TextStyle(
                    fontSize: isWide ? 18 : 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                'Tap any title to stream',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Catalog Tabs Row
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _catalogDefs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final key = _catalogDefs.keys.elementAt(index);
                final def = _catalogDefs[key]!;
                final isActive = (key == _activeCatalogTab);
                final label = def['label'] as String;

                return _TvFocusableButton(
                  onPressed: () {
                    if (_activeCatalogTab != key) {
                      setState(() {
                        _activeCatalogTab = key;
                        _activeCatalogGenre = 'All';
                      });
                      _loadCatalog(reset: true);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF195FEB) : const Color(0xFF090D13),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isActive ? const Color(0xFF195FEB) : const Color(0xFF1F2432)),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.white : Colors.grey.shade400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Genre Filter Chips Row (if applicable)
          if (genres != null && genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: genres.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final g = genres[index];
                  final isActive = (g == _activeCatalogGenre);
                  return GestureDetector(
                    onTap: () {
                      if (_activeCatalogGenre != g) {
                        setState(() => _activeCatalogGenre = g);
                        _loadCatalog(reset: true);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFF238636) : const Color(0xFF090D13),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isActive ? const Color(0xFF238636) : const Color(0xFF1F2432)),
                      ),
                      child: Text(
                        g,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.white : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Catalog Content (Loading, Empty, or Posters Grid)
          if (_isLoadingCatalog && _catalogItems.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFFF0C82)),
                  SizedBox(height: 12),
                  Text('Loading catalog titles...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          ] else if (_catalogItems.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.inbox_rounded, size: 36, color: Colors.grey.shade600),
                  const SizedBox(height: 8),
                  Text('No titles found for this category.', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => _loadCatalog(reset: true),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF195FEB)),
                    child: const Text('Retry', style: TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ] else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final cols = isWide
                    ? (width >= 900 ? 6 : 5)
                    : (width >= 550 ? 4 : (width < 340 ? 2 : 3));

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.58,
                  ),
                  itemCount: _catalogItems.length,
                  itemBuilder: (context, index) {
                    final item = _catalogItems[index];
                    return _buildCatalogCard(item, isWide: isWide);
                  },
                );
              },
            ),

            const SizedBox(height: 16),
            // Load More Button
            Center(
              child: _TvFocusableButton(
                onPressed: _isLoadingCatalog ? () {} : () => _loadCatalog(reset: false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoadingCatalog)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      else
                        const Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Load More Titles',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCatalogCard(Map<String, dynamic> item, {bool isWide = false}) {
    final id = item['id']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Unknown';
    final poster = item['poster']?.toString() ?? '';
    final year = item['year']?.toString() ?? '';
    final rating = item['rating']?.toString() ?? '';
    final type = item['type']?.toString() ?? 'movie';
    final isSelected = (_searchQueryController.text.trim() == id);

    return _TvFocusableButton(
      onPressed: () => _onSelectCatalogItem(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Poster Image
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: poster.isNotEmpty
                      ? Image.network(
                          poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF090D13),
                            child: const Center(
                              child: Icon(Icons.movie_rounded, color: Colors.grey, size: 30),
                            ),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF090D13),
                          child: const Center(
                            child: Icon(Icons.movie_rounded, color: Colors.grey, size: 30),
                          ),
                        ),
                ),
                // Rating or Type Badge
                if (rating.isNotEmpty && rating != '0')
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE3B341).withOpacity(0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 12, color: Color(0xFFE3B341)),
                          const SizedBox(width: 2),
                          Text(
                            rating,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (type == 'series')
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF195FEB).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'SERIES',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                if (isSelected)
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFF0C82), width: 2.5),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                  ),
              ],
            ),
          ),
          // Title & Year Footer
          Padding(
            padding: const EdgeInsets.all(7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isWide ? 12 : 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? const Color(0xFFFF0C82) : Colors.white,
                  ),
                ),
                if (year.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    year,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onSelectCatalogItem(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    final name = item['name']?.toString() ?? '';
    final type = item['type']?.toString() ?? 'movie';
    final poster = item['poster']?.toString();
    final year = item['year']?.toString() ?? item['releaseInfo']?.toString();

    _searchQueryController.text = id;
    setState(() {
      _selectedMediaType = type;
      _selectedMediaMeta = Map<String, dynamic>.from(item);
      _isInDetailView = true;
      _scrapedStreams = [];
    });

    _fetchRichMediaDetailsAndDtdd(id, type, name, yearStr: year);

    if (type == 'series') {
      _loadSeriesCatalog(id, name, poster);
    } else {
      _scrapeStreams(id, 'movie', name);
    }
  }

  Future<void> _loadCatalog({bool reset = false}) async {
    if (_isLoadingCatalog) return;
    setState(() {
      _isLoadingCatalog = true;
      if (reset) {
        _catalogSkip = 0;
        _catalogItems = [];
      }
    });

    try {
      final def = _catalogDefs[_activeCatalogTab];
      if (def == null) return;

      List<Map<String, dynamic>> items = [];
      final isCinemeta = def['src'] == 'cinemeta';
      final mediaType = def['type'] as String;

      if (isCinemeta) {
        final url = Uri.parse('https://v3-cinemeta.strem.io/catalog/$mediaType/top/skip=$_catalogSkip.json');
        final res = await http.get(url, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final metas = (data['metas'] as List?) ?? [];
          items = metas.map((m) {
            final id = m['id']?.toString() ?? '';
            final name = m['name']?.toString() ?? m['title']?.toString() ?? 'Unknown';
            final poster = m['poster']?.toString() ?? 'https://images.metahub.space/poster/medium/$id/img';
            return {
              'id': id,
              'type': mediaType,
              'name': name,
              'poster': poster,
              'year': m['year']?.toString() ?? m['releaseInfo']?.toString() ?? '',
              'rating': m['imdbRating']?.toString() ?? '',
              'description': m['description']?.toString() ?? '',
            };
          }).toList();
        }
      } else {
        final catalogId = def['id'] as String;
        final genreParam = (_activeCatalogGenre != 'All') ? _activeCatalogGenre : null;
        items = await CatalogService.instance.getCatalogItems(
          type: mediaType,
          id: catalogId,
          genre: genreParam,
          skip: _catalogSkip,
        );
      }

      if (mounted) {
        setState(() {
          if (reset) {
            _catalogItems = items;
          } else {
            _catalogItems.addAll(items);
          }
          _catalogSkip += items.length;
        });
      }
    } catch (e) {
      debugPrint('[Catalog] Error loading catalog: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingCatalog = false);
      }
    }
  }

  Widget _buildSeriesCatalogBrowser() {
    final seasons = (_seriesDetails!['seasons'] as List?)?.map((e) => int.tryParse(e.toString()) ?? 1).toList() ?? [1];
    final epsBySeason = (_seriesDetails!['episodesBySeason'] as Map<String, dynamic>?) ?? {};
    final currentEps = (epsBySeason['$_selectedSeason'] as List?) ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F2432)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '📺 Seasons & Episodes (${_seriesDetails!['name'] ?? ''})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
              ),
              Text(
                '${seasons.length} Season(s)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Seasons Horizontal Bar
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: seasons.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final sNum = seasons[index];
                final isActive = (sNum == _selectedSeason);
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedSeason = sNum);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF195FEB) : const Color(0xFF090D13),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isActive ? const Color(0xFF195FEB) : const Color(0xFF1F2432)),
                    ),
                    child: Text(
                      'Season $sNum',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.white : Colors.grey.shade400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // Episodes List
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: currentEps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final ep = currentEps[index] as Map<String, dynamic>;
                final epId = ep['id']?.toString() ?? '';
                final isSelected = (epId == _selectedEpisodeId);
                final thumb = ep['thumbnail']?.toString() ?? _seriesDetails!['poster']?.toString() ?? '';
                final epNum = 'S${ep['season'] < 10 ? '0' : ''}${ep['season']}E${ep['episode'] < 10 ? '0' : ''}${ep['episode']}';

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedEpisodeId = epId;
                      _seasonController.text = ep['season'].toString();
                      _episodeController.text = ep['episode'].toString();
                    });
                    final title = '${_seriesDetails!['name']} $epNum: ${ep['name']}';
                    _scrapeStreams(epId, 'series', title);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF195FEB).withOpacity(0.15) : const Color(0xFF090D13),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF195FEB) : const Color(0xFF1F2432),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (thumb.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              thumb,
                              width: 65,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(width: 65, height: 48, color: Colors.black26),
                            ),
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$epNum: ${ep['name'] ?? ''}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                              ),
                              if (ep['overview'] != null && ep['overview'].toString().isNotEmpty)
                                Text(
                                  ep['overview'].toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.play_circle_outline_rounded, color: Color(0xFFFF0C82), size: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamsSection() {
    if (_isScrapingStreams) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: const Column(
          children: [
            CircularProgressIndicator(color: Color(0xFFFF0C82)),
            SizedBox(height: 12),
            Text('Scraping 56 providers for streams...', style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      );
    }

    if (_scrapedStreams.isEmpty) {
      return const SizedBox.shrink();
    }

    final count4K = _scrapedStreams.where((s) => s['is4K'] == true).length;
    final count1080p = _scrapedStreams.where((s) => s['is1080p'] == true).length;
    final countCached = _scrapedStreams.where((s) => s['isCached'] == true).length;
    final countCachable = _scrapedStreams.where((s) => s['isCache'] == true).length;

    var filtered = _scrapedStreams;
    if (_activeStreamFilter == '4k') filtered = _scrapedStreams.where((s) => s['is4K'] == true).toList();
    else if (_activeStreamFilter == '1080p') filtered = _scrapedStreams.where((s) => s['is1080p'] == true).toList();
    else if (_activeStreamFilter == 'cached') filtered = _scrapedStreams.where((s) => s['isCached'] == true).toList();
    else if (_activeStreamFilter == 'cachable') filtered = _scrapedStreams.where((s) => s['isCache'] == true).toList();
    else if (_activeStreamFilter == 'direct') filtered = _scrapedStreams.where((s) => s['isCached'] != true && s['isCache'] != true).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter Chips Bar
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildStreamFilterChip('all', 'All (${_scrapedStreams.length})'),
            if (count4K > 0) _buildStreamFilterChip('4k', '4K ($count4K)'),
            if (count1080p > 0) _buildStreamFilterChip('1080p', '1080p ($count1080p)'),
            if (countCached > 0) _buildStreamFilterChip('cached', '⚡ Cached ($countCached)'),
            if (countCachable > 0) _buildStreamFilterChip('cachable', '🌐 TorBox Cachable ($countCachable)'),
            _buildStreamFilterChip('direct', 'Direct Play'),
          ],
        ),
        const SizedBox(height: 12),

        // Streams ListView
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final s = filtered[index];
            final name = s['cleanName']?.toString() ?? '';
            final title = s['cleanTitle']?.toString() ?? '';
            final url = s['finalUrl']?.toString() ?? '';
            final underlying = s['underlyingUrl']?.toString() ?? url;
            final isCachable = s['isCachableToTorbox'] == true;
            final isCached = s['isCached'] == true;
            final isCacheTag = s['isCache'] == true;

            // Extract scene filename and extra source/host metadata cleanly
            final rawLines = title.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
            final sceneFilename = rawLines.isNotEmpty
                ? rawLines.first.split(' • ').first.trim()
                : (name.isNotEmpty ? name.split('\n').first.trim() : 'Stream Link');

            final metaItems = <String>[];
            for (final line in rawLines) {
              for (final part in line.split(' • ')) {
                final trimmed = part.trim();
                if (trimmed.isEmpty) continue;
                if (trimmed.contains('Source:') ||
                    trimmed.contains('Host:') ||
                    trimmed.contains('Provider:') ||
                    trimmed.contains('mirrored') ||
                    trimmed.contains('Broadcast')) {
                  if (!metaItems.contains(trimmed)) {
                    metaItems.add(trimmed);
                  }
                }
              }
            }

            // Fallback to stream provider and host if not in title text
            final provider = s['provider']?.toString() ?? '';
            final host = s['hoster']?.toString() ?? s['host']?.toString() ?? '';
            if (!metaItems.any((m) => m.contains('Source:') || m.contains('Provider:')) && provider.isNotEmpty) {
              metaItems.add('🌐 Source: $provider');
            }
            if (!metaItems.any((m) => m.contains('Host:')) && host.isNotEmpty) {
              metaItems.add('📦 Host: $host');
            }

            final metaParts = metaItems.join(' • ');

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF11141C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isCached
                      ? const Color(0xFF238636)
                      : (isCacheTag ? const Color(0xFF195FEB) : const Color(0xFF1F2432)),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Scene Filename Header
                  Text(
                    sceneFilename,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, height: 1.25),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 7),

                  // 2. Built-in Fusion Badges!
                  _buildFusionBadgesRow(s),
                  const SizedBox(height: 7),

                  // 3. Source & Host metadata
                  if (metaParts.isNotEmpty)
                    Text(
                      metaParts,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400, height: 1.2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 10),

                  // 4. Action buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF195FEB),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
                        label: const Text('Play', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                        onPressed: () => _playStream(s),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          side: const BorderSide(color: Color(0xFF388BFD)),
                          backgroundColor: const Color(0xFF161B22),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.playlist_play_rounded, size: 16, color: Color(0xFF58A6FF)),
                        label: const Text('Play With...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF58A6FF))),
                        onPressed: () => _showPlayWithDialog(s),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          side: const BorderSide(color: Color(0xFF30363D)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 14, color: Colors.grey),
                        label: const Text('Copy', style: TextStyle(fontSize: 12, color: Colors.white)),
                        onPressed: () => _copyToClipboard(url, 'Stream URL'),
                      ),
                      if (isCachable)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF238636),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.cloud_upload_rounded, size: 14, color: Colors.white),
                          label: Text(
                            isCacheTag ? '⚡ Start Cache' : 'Cache to TorBox',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          onPressed: () => _startTorboxCache(underlying),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFusionBadge(String text, {required Color bg, required Color border, required Color textColor, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.2),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: border.withOpacity(0.8), width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: textColor),
            const SizedBox(width: 3.5),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFusionBadgesRow(Map<String, dynamic> s) {
    final rawName = s['cleanName']?.toString() ?? '';
    final rawTitle = s['cleanTitle']?.toString() ?? '';
    final isCached = s['isCached'] == true;
    final isCacheTag = s['isCache'] == true;
    final combined = '$rawName $rawTitle'.toUpperCase();
    final badges = <Widget>[];

    // 1. Tier / Source
    if (isCached) {
      badges.add(_buildFusionBadge('⚡ TorBox Cached', bg: const Color(0xFF238636), border: const Color(0xFF3FB950), textColor: const Color(0xFF3FB950)));
    } else if (isCacheTag) {
      badges.add(_buildFusionBadge('☁️ TorBox Cachable', bg: const Color(0xFF195FEB), border: const Color(0xFF58A6FF), textColor: const Color(0xFF58A6FF)));
    } else {
      badges.add(_buildFusionBadge('🌐 Direct Play', bg: const Color(0xFF1F6FEB), border: const Color(0xFF388BFD), textColor: const Color(0xFF79C0FF)));
    }

    // 2. Resolution (Neon purple for 4K, Cyan for 1080p, Amber for 720p)
    if (combined.contains('4K') || combined.contains('2160P') || combined.contains('UHD')) {
      badges.add(_buildFusionBadge('4K UHD', bg: const Color(0xFF8957E5), border: const Color(0xFFD2A8FF), textColor: const Color(0xFFD2A8FF)));
    } else if (combined.contains('1080P') || combined.contains('[FHD]') || combined.contains('FHD')) {
      badges.add(_buildFusionBadge('1080p FHD', bg: const Color(0xFF1F6FEB), border: const Color(0xFF58A6FF), textColor: const Color(0xFF58A6FF)));
    } else if (combined.contains('720P') || combined.contains('HD')) {
      badges.add(_buildFusionBadge('720p HD', bg: const Color(0xFFD29922), border: const Color(0xFFE3B341), textColor: const Color(0xFFE3B341)));
    }

    // 3. Quality / Release
    if (combined.contains('REMUX')) {
      badges.add(_buildFusionBadge('REMUX', bg: const Color(0xFF6366F1), border: const Color(0xFFA5B4FC), textColor: const Color(0xFFA5B4FC)));
    } else if (combined.contains('BLURAY') || combined.contains('BLU-RAY')) {
      badges.add(_buildFusionBadge('BLURAY', bg: const Color(0xFF6366F1), border: const Color(0xFFA5B4FC), textColor: const Color(0xFFA5B4FC)));
    } else if (combined.contains('WEB-DL') || combined.contains('WEBDL')) {
      badges.add(_buildFusionBadge('WEB-DL', bg: const Color(0xFF4F46E5), border: const Color(0xFF818CF8), textColor: const Color(0xFF818CF8)));
    } else if (combined.contains('WEBRIP')) {
      badges.add(_buildFusionBadge('WEBRIP', bg: const Color(0xFF334155), border: const Color(0xFF64748B), textColor: const Color(0xFF94A3B8)));
    } else if (combined.contains('HDRIP')) {
      badges.add(_buildFusionBadge('HDRIP', bg: const Color(0xFF334155), border: const Color(0xFF64748B), textColor: const Color(0xFF94A3B8)));
    }

    // 4. Visual (HDR / Dolby Vision)
    if (combined.contains('DOLBY VISION') || combined.contains('[DV]') || combined.contains('DV')) {
      badges.add(_buildFusionBadge('DOLBY VISION', bg: const Color(0xFFC026D3), border: const Color(0xFFF472B6), textColor: const Color(0xFFF472B6)));
    }
    if (combined.contains('HDR10+')) {
      badges.add(_buildFusionBadge('HDR10+', bg: const Color(0xFFD97706), border: const Color(0xFFFBBF24), textColor: const Color(0xFFFBBF24)));
    } else if (combined.contains('HDR')) {
      badges.add(_buildFusionBadge('HDR', bg: const Color(0xFFD97706), border: const Color(0xFFFBBF24), textColor: const Color(0xFFFBBF24)));
    }
    if (combined.contains('10BIT') || combined.contains('10-BIT')) {
      badges.add(_buildFusionBadge('10-BIT', bg: const Color(0xFF78350F), border: const Color(0xFFF59E0B), textColor: const Color(0xFFF59E0B)));
    }

    // 5. Codec
    if (combined.contains('HEVC') || combined.contains('X265') || combined.contains('H.265') || combined.contains('H265')) {
      badges.add(_buildFusionBadge('HEVC / x265', bg: const Color(0xFF0D9488), border: const Color(0xFF2DD4BF), textColor: const Color(0xFF2DD4BF)));
    } else if (combined.contains('AV1')) {
      badges.add(_buildFusionBadge('AV1', bg: const Color(0xFF0284C7), border: const Color(0xFF38BDF8), textColor: const Color(0xFF38BDF8)));
    } else if (combined.contains('X264') || combined.contains('H.264') || combined.contains('AVC')) {
      badges.add(_buildFusionBadge('x264', bg: const Color(0xFF475569), border: const Color(0xFF94A3B8), textColor: const Color(0xFFCBD5E1)));
    }

    // 6. Audio
    if (combined.contains('ATMOS')) {
      badges.add(_buildFusionBadge('ATMOS', bg: const Color(0xFF059669), border: const Color(0xFF34D399), textColor: const Color(0xFF34D399)));
    } else if (combined.contains('TRUEHD')) {
      badges.add(_buildFusionBadge('TRUEHD', bg: const Color(0xFF059669), border: const Color(0xFF34D399), textColor: const Color(0xFF34D399)));
    } else if (combined.contains('DTS-HD') || combined.contains('DTSHD')) {
      badges.add(_buildFusionBadge('DTS-HD', bg: const Color(0xFF059669), border: const Color(0xFF34D399), textColor: const Color(0xFF34D399)));
    } else if (combined.contains('DD+') || combined.contains('DDP') || combined.contains('E-AC-3') || combined.contains('EAC3')) {
      badges.add(_buildFusionBadge('DD+', bg: const Color(0xFF059669), border: const Color(0xFF34D399), textColor: const Color(0xFF34D399)));
    } else if (combined.contains('5.1')) {
      badges.add(_buildFusionBadge('5.1 CH', bg: const Color(0xFF059669), border: const Color(0xFF34D399), textColor: const Color(0xFF34D399)));
    } else if (combined.contains('AAC')) {
      badges.add(_buildFusionBadge('AAC', bg: const Color(0xFF0D9488), border: const Color(0xFF2DD4BF), textColor: const Color(0xFF2DD4BF)));
    }

    // 7. File Size (Prominent pink/rose pill with disk icon)
    final fileSize = s['fileSize']?.toString() ?? '';
    if (fileSize.isNotEmpty) {
      badges.add(_buildFusionBadge(fileSize, bg: const Color(0xFFE11D48), border: const Color(0xFFFB7185), textColor: const Color(0xFFFB7185), icon: Icons.save_rounded));
    }

    // 8. Stream delivery flags
    if (combined.contains('HLS STREAM') || combined.contains('.M3U8')) {
      badges.add(_buildFusionBadge('HLS', bg: const Color(0xFF1E293B), border: const Color(0xFF475569), textColor: const Color(0xFF94A3B8)));
    }
    if (combined.contains('PROXIED')) {
      badges.add(_buildFusionBadge('Proxied', bg: const Color(0xFF1E293B), border: const Color(0xFF475569), textColor: const Color(0xFF94A3B8)));
    }

    return Wrap(
      spacing: 5,
      runSpacing: 4,
      children: badges,
    );
  }

  Widget _buildStreamFilterChip(String filterKey, String label) {
    final isActive = (_activeStreamFilter == filterKey);
    return GestureDetector(
      onTap: () {
        setState(() => _activeStreamFilter = filterKey);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF195FEB) : const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? const Color(0xFF195FEB) : const Color(0xFF30363D)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }

  Future<void> _performSearch() async {
    final query = _searchQueryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _catalogSuggestions = [];
      _scrapedStreams = [];
    });

    try {
      if (query.startsWith('tt') || query.startsWith('tmdb:')) {
        setState(() {
          _selectedMediaMeta = {
            'id': query,
            'name': query,
            'type': _selectedMediaType,
            'poster': 'https://images.metahub.space/poster/medium/$query/img',
          };
          _isInDetailView = true;
        });
        _fetchRichMediaDetailsAndDtdd(query, _selectedMediaType, query);
        if (_selectedMediaType == 'series') {
          await _loadSeriesCatalog(query, query, null);
        } else {
          await _scrapeStreams(query, 'movie', query);
        }
        return;
      }

      final results = await MetadataService.search(query: query, type: _selectedMediaType);
      if (mounted) {
        setState(() {
          _catalogSuggestions = results;
        });
        if (results.isNotEmpty) {
          final top = results.first;
          _onSelectSuggestion(top);
        } else {
          setState(() {
            _selectedMediaMeta = {
              'id': query,
              'name': query,
              'type': _selectedMediaType,
              'poster': '',
            };
            _isInDetailView = true;
          });
          _fetchRichMediaDetailsAndDtdd(query, _selectedMediaType, query);
          _scrapeStreams(query, _selectedMediaType, query);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _onSelectSuggestion(Map<String, dynamic> m) {
    final id = m['id']?.toString() ?? '';
    final name = m['name']?.toString() ?? '';
    final type = m['type']?.toString() ?? _selectedMediaType;
    final poster = m['poster']?.toString();
    final year = m['year']?.toString();

    _searchQueryController.text = id;
    setState(() {
      _selectedMediaType = type;
      _selectedMediaMeta = Map<String, dynamic>.from(m);
      _isInDetailView = true;
    });

    _fetchRichMediaDetailsAndDtdd(id, type, name, yearStr: year);

    if (type == 'series') {
      _loadSeriesCatalog(id, name, poster);
    } else {
      _scrapeStreams(id, 'movie', name);
    }
  }

  Future<void> _loadSeriesCatalog(String id, String name, String? poster) async {
    setState(() {
      _selectedMediaMeta = {
        ...?_selectedMediaMeta,
        'id': id,
        'name': name,
        if (poster != null) 'poster': poster,
      };
      _seriesDetails = null;
    });

    try {
      final details = await MetadataService.getSeriesDetails(id);
      if (mounted && details != null) {
        setState(() {
          _seriesDetails = details;
          _selectedMediaMeta = {
            ...?_selectedMediaMeta,
            ...details,
          };
          final seasons = (details['seasons'] as List?)?.map((e) => int.tryParse(e.toString()) ?? 1).toList() ?? [1];
          _selectedSeason = seasons.isNotEmpty ? seasons.first : 1;
        });

        // Also fetch community trigger warnings
        _fetchRichMediaDetailsAndDtdd(id, 'series', name, yearStr: details['year']?.toString());

        // Auto scrape episode 1
        final epsBySeason = details['episodesBySeason'] as Map<String, dynamic>? ?? {};
        final firstSeasonEps = (epsBySeason['$_selectedSeason'] as List?) ?? [];
        if (firstSeasonEps.isNotEmpty) {
          final ep1 = firstSeasonEps.first as Map<String, dynamic>;
          _selectedEpisodeId = ep1['id']?.toString();
          final epTitle = '$name S${ep1['season']}E${ep1['episode']}: ${ep1['name']}';
          await _scrapeStreams(ep1['id'].toString(), 'series', epTitle);
        }
      } else {
        final s = int.tryParse(_seasonController.text) ?? 1;
        final e = int.tryParse(_episodeController.text) ?? 1;
        await _scrapeStreams('$id:$s:$e', 'series', name);
      }
    } catch (_) {
      final s = int.tryParse(_seasonController.text) ?? 1;
      final e = int.tryParse(_episodeController.text) ?? 1;
      await _scrapeStreams('$id:$s:$e', 'series', name);
    }
  }

  Future<void> _scrapeStreams(String id, String type, String title) async {
    setState(() {
      _isScrapingStreams = true;
      _scrapedStreams = [];
    });

    try {
      final port = AddonConfig.instance.port;
      final url = Uri.parse('http://127.0.0.1:$port/stream/$type/${Uri.encodeComponent(id)}.json');
      final res = await http.get(url).timeout(const Duration(seconds: 25));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawList = (data is Map && data['streams'] is List) ? data['streams'] as List : [];

        final parsed = rawList.map((s) {
          final m = Map<String, dynamic>.from(s as Map);
          final rawName = (m['name']?.toString() ?? '').replaceAll('\n', ' ');
          final rawTitle = (m['title']?.toString() ?? '').replaceAll('\n', ' • ');
          final rawUrl = m['url']?.toString() ?? '';

          String underlying = rawUrl;
          if (rawUrl.contains('?url=')) {
            try {
              final parsedUri = Uri.parse(rawUrl);
              final inner = parsedUri.queryParameters['url'];
              if (inner != null && inner.isNotEmpty) underlying = inner;
            } catch (_) {}
          }

          final lower = underlying.toLowerCase();
          final isHls = lower.contains('.m3u8') || lower.contains('.mpd');
          final isCached = rawName.contains('[Cached]') || rawTitle.contains('Cached on TorBox');
          final isCachableTag = rawName.toLowerCase().contains('cachable') || rawName.contains('Start Caching') || rawTitle.toLowerCase().contains('cachable');

          final isHosterSupported = !isHls && !isCached && (
            isCachableTag ||
            lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.avi') || lower.endsWith('.webm') || lower.endsWith('.ts') ||
            lower.contains('hubcloud') || lower.contains('hubdrive') || lower.contains('driveseed') ||
            lower.contains('pixeldrain') || lower.contains('gofile') || lower.contains('buzzheavier') || lower.contains('qiwi') || lower.contains('multiup') || lower.contains('1fichier') || lower.contains('rapidgator') ||
            lower.contains('mega.nz') || lower.contains('mediafire') || lower.contains('ddownload') ||
            lower.contains('drive.google.com') || lower.contains('workers.dev') || lower.contains('vcloud')
          );

          m['cleanName'] = rawName;
          m['cleanTitle'] = rawTitle;
          m['finalUrl'] = rawUrl;
          m['underlyingUrl'] = underlying;
          m['isCached'] = isCached;
          m['isCache'] = isCachableTag;
          m['isCachableToTorbox'] = isHosterSupported;
          final is4K = rawName.contains('4K') || rawTitle.contains('[4K]') || rawTitle.contains('2160p');
          final is1080p = rawName.contains('1080p') || rawTitle.contains('[FHD]') || rawTitle.contains('1080p');
          m['is4K'] = is4K;
          m['is1080p'] = is1080p;

          // Extract or estimate fileSize
          String rawFileSize = m['fileSize']?.toString() ?? '';
          if (rawFileSize.isEmpty) {
            final sizeMatch = RegExp(r'💾\s*([0-9\.]+\s*(?:GB|MB|GiB|MiB))', caseSensitive: false).firstMatch(rawTitle) ??
                RegExp(r'\b([0-9\.]+\s*(?:GB|MB|GiB|MiB))\b', caseSensitive: false).firstMatch(rawTitle);
            if (sizeMatch != null) {
              rawFileSize = sizeMatch.group(1) ?? '';
            } else if (is4K) {
              rawFileSize = _selectedMediaType == 'series' ? '1.8 GB' : '4.2 GB';
            } else if (is1080p) {
              rawFileSize = _selectedMediaType == 'series' ? '850 MB' : '1.9 GB';
            } else if (rawName.contains('720') || rawTitle.contains('720p')) {
              rawFileSize = _selectedMediaType == 'series' ? '450 MB' : '950 MB';
            } else {
              rawFileSize = _selectedMediaType == 'series' ? '300 MB' : '650 MB';
            }
          }
          m['fileSize'] = rawFileSize;
          return m;
        }).toList();

        if (mounted) {
          setState(() {
            _scrapedStreams = parsed;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scrape error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isScrapingStreams = false);
    }
  }

  void _addToWatchHistory(Map<String, dynamic> entry) {
    setState(() {
      // Remove existing entry with same URL to avoid duplicates
      _watchHistory.removeWhere((h) => h['url'] == entry['url']);
      // Insert at front (most recent first)
      _watchHistory.insert(0, entry);
      // Cap at 30 entries
      if (_watchHistory.length > 30) {
        _watchHistory = _watchHistory.sublist(0, 30);
      }
    });
  }

  void _toggleWatchlist(Map<String, dynamic> meta) {
    final id = meta['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() {
      final existing = _watchlist.indexWhere((w) => w['id'] == id);
      if (existing >= 0) {
        _watchlist.removeAt(existing);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "${meta['name']}" from Watchlist'),
            duration: const Duration(seconds: 1),
            backgroundColor: const Color(0xFF21262D),
          ),
        );
      } else {
        _watchlist.insert(0, meta);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${meta['name']}" to Watchlist ✓'),
            duration: const Duration(seconds: 1),
            backgroundColor: const Color(0xFF238636),
          ),
        );
      }
    });
  }

  Future<void> _startTorboxCache(String url) async {
    final apiKey = AddonConfig.instance.torboxApiKey.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please configure your TorBox API Key in the Server tab first!'),
          backgroundColor: Color(0xFFF85149),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Submitting link to TorBox cloud cache...'),
        duration: Duration(seconds: 2),
      ),
    );

    final res = await TorboxService.instance.uploadToTorbox(url, apiKey);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? 'Queued to TorBox Cache!'),
          backgroundColor: res['success'] == true ? const Color(0xFF238636) : const Color(0xFFF85149),
        ),
      );
    }
  }

  String _resolvePlayUrl(dynamic streamTarget) {
    if (streamTarget is Map) {
      final rawUrl = streamTarget['finalUrl']?.toString() ?? streamTarget['url']?.toString() ?? '';
      final bh = streamTarget['behaviorHints'] is Map ? streamTarget['behaviorHints'] as Map : null;
      final headersMap = <String, String>{};
      if (bh != null && bh['proxyHeaders'] is Map && bh['proxyHeaders']['request'] is Map) {
        (bh['proxyHeaders']['request'] as Map).forEach((k, v) {
          if (k != null && v != null) headersMap[k.toString()] = v.toString();
        });
      }

      final port = AddonConfig.instance.port;
      if (rawUrl.contains('/proxy') || rawUrl.contains('/torbox/play')) {
        final uri = Uri.tryParse(rawUrl);
        if (uri != null) {
          return 'http://127.0.0.1:$port${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
        }
        return rawUrl;
      } else if (headersMap.isNotEmpty) {
        final headersJson = jsonEncode(headersMap);
        return 'http://127.0.0.1:$port/proxy?url=${Uri.encodeComponent(rawUrl)}&headers=${Uri.encodeComponent(headersJson)}';
      }
      return rawUrl;
    } else if (streamTarget is String) {
      final port = AddonConfig.instance.port;
      if (streamTarget.contains('/proxy') || streamTarget.contains('/torbox/play')) {
        final uri = Uri.tryParse(streamTarget);
        if (uri != null) {
          return 'http://127.0.0.1:$port${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
        }
      }
      return streamTarget;
    }
    return '';
  }

  Future<void> _playStream(
    dynamic streamTarget, {
    String? packageName,
    bool forceChooser = false,
    bool forceExternal = false,
    bool isLive = false,
  }) async {
    final playUrl = _resolvePlayUrl(streamTarget);
    if (playUrl.isEmpty) return;

    String title = '';
    String subtitle = '';
    Map<String, String>? headers;

    if (streamTarget is Map) {
      title = streamTarget['cleanTitle']?.toString() ?? streamTarget['title']?.toString() ?? '';
      subtitle = streamTarget['cleanName']?.toString() ?? streamTarget['name']?.toString() ?? '';
      final bh = streamTarget['behaviorHints'] is Map ? streamTarget['behaviorHints'] as Map : null;
      if (bh != null && bh['proxyHeaders'] is Map && bh['proxyHeaders']['request'] is Map) {
        final headersMap = <String, String>{};
        (bh['proxyHeaders']['request'] as Map).forEach((k, v) {
          if (k != null && v != null) headersMap[k.toString()] = v.toString();
        });
        if (headersMap.isNotEmpty) headers = headersMap;
      }
    } else if (streamTarget is String) {
      title = streamTarget;
    }

    // Default: Open in built-in high-performance libmpv player (for both Android & Windows)
    if (!forceChooser && !forceExternal && packageName == null) {
      if (mounted) {
        // Record to watch history (max 30 entries)
        _addToWatchHistory({
          'title': title.isNotEmpty ? title : 'Hostreamio Stream',
          'subtitle': subtitle,
          'url': playUrl,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'meta': _selectedMediaMeta,
        });

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              streamUrl: playUrl,
              title: title.isNotEmpty ? title : 'Hostreamio Stream',
              subtitle: subtitle.isNotEmpty ? subtitle : null,
              headers: headers,
              onOpenExternal: () => _playStream(streamTarget, forceChooser: true, forceExternal: true, isLive: isLive),
              // Pass IMDb ID + type for auto subtitle fetching via OpenSubtitles (VOD only)
              imdbId: isLive ? null : _selectedMediaMeta?['id']?.toString(),
              mediaType: isLive ? null : _selectedMediaType,
              isLive: isLive,
            ),
          ),
        );
        return;
      }
    }

    // External player fallback (for Android Intent or platform default)
    try {
      if (Platform.isAndroid) {
        final success = await _playerChannel.invokeMethod<bool>('playStream', {
          'url': playUrl,
          'title': title,
          'package': packageName,
          'forceChooser': forceChooser,
        });
        if (success == true) return;
      }
    } on PlatformException catch (e) {
      if (e.code == 'APP_NOT_INSTALLED') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected player is not installed. Opening app chooser instead...'),
              backgroundColor: Color(0xFFF85149),
              duration: Duration(seconds: 2),
            ),
          );
        }
        await _playStream(streamTarget, forceChooser: true, forceExternal: true, isLive: isLive);
        return;
      }
    } catch (_) {}

    try {
      final uri = Uri.parse(playUrl);
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        final fallbackUrl = (streamTarget is Map)
            ? (streamTarget['finalUrl']?.toString() ?? streamTarget['url']?.toString() ?? '')
            : streamTarget.toString();
        _copyToClipboard(fallbackUrl, 'Stream Link');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open external player. Link copied: $e')),
        );
      }
    }
  }

  Future<void> _showPlayWithDialog(Map<String, dynamic> s, {bool isLive = false}) async {
    final playUrl = _resolvePlayUrl(s);
    if (playUrl.isEmpty) return;

    final streamTitle = s['cleanTitle']?.toString() ?? s['title']?.toString() ?? 'Stream';
    final streamName = s['cleanName']?.toString() ?? s['name']?.toString() ?? '';

    List<String> installed = [];
    try {
      if (Platform.isAndroid) {
        final res = await _playerChannel.invokeMethod<List<dynamic>>('checkInstalledPlayers');
        if (res != null) {
          installed = res.map((e) => e.toString()).toList();
        }
      }
    } catch (_) {}

    if (!mounted) return;

    final players = [
      {
        'id': 'internal_libmpv',
        'title': 'Internal Player (libmpv)',
        'subtitle': 'Built-in player • Hardware acceleration & styled subtitles',
        'icon': Icons.smart_display_rounded,
        'package': null,
        'forceChooser': false,
        'color': const Color(0xFFFF0C82),
        'isInstalled': true,
      },
      {
        'id': 'chooser',
        'title': 'App Chooser (Open With...)',
        'subtitle': 'System dialog to select any installed player on device',
        'icon': Icons.apps_rounded,
        'package': null,
        'forceChooser': true,
        'color': const Color(0xFF58A6FF),
        'isInstalled': true,
      },
      {
        'id': 'vlc',
        'title': 'VLC for Android',
        'subtitle': 'org.videolan.vlc',
        'icon': Icons.play_circle_fill_rounded,
        'package': 'org.videolan.vlc',
        'forceChooser': false,
        'color': const Color(0xFFFF8800),
        'isInstalled': installed.contains('org.videolan.vlc'),
      },
      {
        'id': 'just_player',
        'title': 'Just Player',
        'subtitle': 'com.brouken.player • ExoPlayer',
        'icon': Icons.video_collection_rounded,
        'package': 'com.brouken.player',
        'forceChooser': false,
        'color': const Color(0xFF3FB950),
        'isInstalled': installed.contains('com.brouken.player'),
      },
      {
        'id': 'mx_player',
        'title': 'MX Player',
        'subtitle': 'com.mxtech.videoplayer (Free / Pro)',
        'icon': Icons.movie_filter_rounded,
        'package': 'com.mxtech.videoplayer',
        'forceChooser': false,
        'color': const Color(0xFF2196F3),
        'isInstalled': installed.contains('com.mxtech.videoplayer.ad') || installed.contains('com.mxtech.videoplayer.pro'),
      },
      {
        'id': 'mpv',
        'title': 'MPV Player',
        'subtitle': 'is.xyz.mpv • LibMPV core',
        'icon': Icons.play_arrow_rounded,
        'package': 'is.xyz.mpv',
        'forceChooser': false,
        'color': const Color(0xFF9C27B0),
        'isInstalled': installed.contains('is.xyz.mpv'),
      },
      {
        'id': 'nova',
        'title': 'Nova Video Player',
        'subtitle': 'org.courville.nova • Android TV Leanback',
        'icon': Icons.tv_rounded,
        'package': 'org.courville.nova',
        'forceChooser': false,
        'color': const Color(0xFFE91E63),
        'isInstalled': installed.contains('org.courville.nova'),
      },
      {
        'id': 'next_player',
        'title': 'Next Player',
        'subtitle': 'dev.anilbeesetti.nextplayer',
        'icon': Icons.smart_display_rounded,
        'package': 'dev.anilbeesetti.nextplayer',
        'forceChooser': false,
        'color': const Color(0xFF00BCD4),
        'isInstalled': installed.contains('dev.anilbeesetti.nextplayer'),
      },
      {
        'id': 'browser',
        'title': 'Web Browser / Default',
        'subtitle': 'Open via standard platform launcher',
        'icon': Icons.public_rounded,
        'package': null,
        'forceChooser': false,
        'color': Colors.grey,
        'isInstalled': true,
      },
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF0D1117),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF30363D), width: 1.5),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF195FEB).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.playlist_play_rounded, color: Color(0xFF58A6FF), size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Play With External Player',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Choose your preferred video player',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF21262D)),

                // Stream metadata preview
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: const Color(0xFF161B22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        streamName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF58A6FF)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        streamTitle,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF21262D)),

                // Options list
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: players.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF161B22)),
                    itemBuilder: (c, idx) {
                      final p = players[idx];
                      final isInst = p['isInstalled'] == true;
                      final isSystem = p['id'] == 'chooser' || p['id'] == 'browser';
                      final color = p['color'] as Color;

                      return ListTile(
                        autofocus: (idx == 0),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: color.withOpacity(0.3), width: 1),
                          ),
                          child: Icon(p['icon'] as IconData, color: color, size: 20),
                        ),
                        title: Row(
                          children: [
                            Text(
                              p['title'] as String,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            if (!isSystem && isInst)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF238636).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF3FB950), width: 0.8),
                                ),
                                child: const Text(
                                  'INSTALLED',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF3FB950)),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          p['subtitle'] as String,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (p['id'] == 'browser') {
                            _launchBrowserFallback(playUrl);
                          } else if (p['id'] == 'internal_libmpv') {
                            _playStream(s, isLive: isLive);
                          } else {
                            _playStream(
                              s,
                              packageName: p['package'] as String?,
                              forceChooser: p['forceChooser'] as bool,
                              forceExternal: true,
                              isLive: isLive,
                            );
                          }
                        },
                      );
                    },
                  ),
                ),

                const Divider(height: 1, color: Color(0xFF21262D)),

                // Footer action: copy link
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.copy_rounded, size: 14, color: Colors.grey),
                        label: const Text('Copy Stream Link', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _copyToClipboard(playUrl, 'Stream URL');
                        },
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _launchBrowserFallback(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        _copyToClipboard(url, 'Stream Link');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open browser. Link copied: $e')),
        );
      }
    }
  }

  // ── Live IPTV Implementation (iptv-org integration) ───────────────────

  Future<void> _loadIptvChannels({bool reset = false}) async {
    if (_isLoadingIptv) return;
    setState(() => _isLoadingIptv = true);
    try {
      await IptvService.instance.loadChannels(forceRefresh: reset);
      final filtered = IptvService.instance.filterChannels(
        search: _iptvSearchController.text.trim(),
        category: _selectedIptvCategory == 'All' ? null : _selectedIptvCategory,
        country: _selectedIptvCountry == 'All' ? null : _selectedIptvCountry,
      );
      if (mounted) {
        setState(() {
          _iptvChannels = filtered;
        });
      }
    } catch (e) {
      debugPrint('[IPTV] Error loading channels: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingIptv = false);
      }
    }
  }

  void _onFilterIptv() {
    var filtered = IptvService.instance.filterChannels(
      search: _iptvSearchController.text.trim(),
      category: _selectedIptvCategory == 'All' ? null : _selectedIptvCategory,
      country: _selectedIptvCountry == 'All' ? null : _selectedIptvCountry,
    );
    if (_showOnlyFavourites) {
      filtered = filtered.where((ch) => _iptvFavourites.contains(ch.id)).toList();
    }
    setState(() {
      _iptvChannels = filtered;
    });
  }

  void _toggleIptvFavourite(IptvChannel ch) {
    setState(() {
      if (_iptvFavourites.contains(ch.id)) {
        _iptvFavourites.remove(ch.id);
      } else {
        _iptvFavourites.add(ch.id);
      }
      // Update filtered list if showing favourites
      if (_showOnlyFavourites) _onFilterIptv();
    });
  }

  static const Map<String, String> _iptvCategoryLabels = {
    'All': '📺 All Channels',
    'News': '📰 News',
    'Sports': '⚽ Sports',
    'Movies': '🎬 Movies',
    'Animation': '✨ Animation',
    'Music': '🎵 Music',
    'Entertainment': '🎭 Entertainment',
    'Documentary': '📚 Documentary',
    'General': '📡 General',
  };

  static const Map<String, String> _iptvCountryLabels = {
    'All': '🌐 All Countries',
    'Global': '🌍 Global Broadcasts',
    'IN': '🇮🇳 India',
    'US': '🇺🇸 United States',
    'UK': '🇬🇧 United Kingdom',
    'CA': '🇨🇦 Canada',
    'AU': '🇦🇺 Australia',
    'FR': '🇫🇷 France',
    'DE': '🇩🇪 Germany',
    'ES': '🇪🇸 Spain',
    'IT': '🇮🇹 Italy',
    'JP': '🇯🇵 Japan',
    'BR': '🇧🇷 Brazil',
    'KR': '🇰🇷 South Korea',
    'RU': '🇷🇺 Russia',
    'MX': '🇲🇽 Mexico',
    'TR': '🇹🇷 Turkey',
    'AE': '🇦🇪 UAE',
    'PK': '🇵🇰 Pakistan',
    'BD': '🇧🇩 Bangladesh',
    'NL': '🇳🇱 Netherlands',
  };

  static String _getChannelCategoryLabel(String cat) {
    switch (cat.toLowerCase()) {
      case 'news': return '📰 NEWS';
      case 'sports': return '⚽ SPORTS';
      case 'movies': return '🎬 MOVIES';
      case 'animation': return '✨ ANIMATION';
      case 'music': return '🎵 MUSIC';
      case 'entertainment': return '🎭 ENTERTAINMENT';
      case 'documentary': return '📚 DOCUMENTARY';
      default: return '📡 ${cat.toUpperCase()}';
    }
  }

  static String _getChannelCountryLabel(String ctry) {
    switch (ctry.toUpperCase()) {
      case 'IN': return '🇮🇳 INDIA';
      case 'US': return '🇺🇸 USA';
      case 'UK': return '🇬🇧 UK';
      case 'CA': return '🇨🇦 CANADA';
      case 'AU': return '🇦🇺 AUSTRALIA';
      case 'FR': return '🇫🇷 FRANCE';
      case 'DE': return '🇩🇪 GERMANY';
      case 'ES': return '🇪🇸 SPAIN';
      case 'IT': return '🇮🇹 ITALY';
      case 'JP': return '🇯🇵 JAPAN';
      case 'BR': return '🇧🇷 BRAZIL';
      case 'KR': return '🇰🇷 S. KOREA';
      case 'RU': return '🇷🇺 RUSSIA';
      case 'MX': return '🇲🇽 MEXICO';
      case 'TR': return '🇹🇷 TURKEY';
      case 'AE': return '🇦🇪 UAE';
      case 'PK': return '🇵🇰 PAKISTAN';
      case 'BD': return '🇧🇩 BANGLADESH';
      case 'NL': return '🇳🇱 NETHERLANDS';
      case 'GLOBAL': return '🌍 GLOBAL';
      default: return '🌐 $ctry';
    }
  }

  Widget _buildIptvView({bool isWide = false}) {
    const categories = [
      'All',
      'News',
      'Sports',
      'Movies',
      'Animation',
      'Music',
      'Entertainment',
      'Documentary',
      'General'
    ];

    const countries = [
      'All',
      'Global',
      'IN',
      'US',
      'UK',
      'CA',
      'AU',
      'FR',
      'DE',
      'ES',
      'IT',
      'JP',
      'BR',
      'KR',
      'RU',
      'MX',
      'TR',
      'AE',
      'PK',
      'BD',
      'NL',
    ];

    final displayedChannels = _iptvChannels.take(_iptvDisplayLimit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Philosophy Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF195FEB).withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF195FEB).withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.live_tv_rounded, color: Color(0xFF58A6FF), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Free Global Live IPTV Broadcasts',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF58A6FF)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '• 8,000+ free broadcast channels powered by iptv-org open-source index.\n'
                '• Filter by Category, Country, and Search channel names in real time.\n'
                '• Dual-Rail Playback: Stream in app or use "Play With..." to cast to VLC, Just Player, or MPV.',
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade300),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Search & Filters Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF11141C),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1F2432), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Input Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _iptvSearchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF08090C),
                        hintText: 'Search channel name (e.g. Sky, BBC, NDTV, Red Bull)...',
                        hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFFF0C82), size: 20),
                        suffixIcon: _iptvSearchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                                onPressed: () {
                                  _iptvSearchController.clear();
                                  _onFilterIptv();
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1F2432))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1F2432))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFF0C82))),
                      ),
                      onChanged: (_) => _onFilterIptv(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _TvFocusableButton(
                    onPressed: () => _loadIptvChannels(reset: true),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF30363D)),
                      ),
                      child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Categories Row
              const Text('Category:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length + 1, // +1 for Favourites chip
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    // First chip is always Favourites
                    if (index == 0) {
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _showOnlyFavourites = !_showOnlyFavourites;
                            if (_showOnlyFavourites) _selectedIptvCategory = 'All';
                          });
                          _onFilterIptv();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _showOnlyFavourites ? const Color(0xFFE3B341) : const Color(0xFF090D13),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _showOnlyFavourites ? const Color(0xFFE3B341) : const Color(0xFF1F2432)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showOnlyFavourites ? Icons.star_rounded : Icons.star_border_rounded,
                                color: _showOnlyFavourites ? Colors.white : Colors.grey.shade400,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Favourites (${_iptvFavourites.length})',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _showOnlyFavourites ? Colors.white : Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final cat = categories[index - 1];
                    final isActive = (!_showOnlyFavourites && _selectedIptvCategory == cat);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedIptvCategory = cat;
                          _showOnlyFavourites = false;
                        });
                        _onFilterIptv();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFF195FEB) : const Color(0xFF090D13),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isActive ? const Color(0xFF195FEB) : const Color(0xFF1F2432)),
                        ),
                        child: Text(
                          _iptvCategoryLabels[cat] ?? cat,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isActive ? Colors.white : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),

              // Countries Row
              const Text('Country / Region:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: countries.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final ctry = countries[index];
                    final isActive = (_selectedIptvCountry == ctry);
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedIptvCountry = ctry);
                        _onFilterIptv();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFF238636) : const Color(0xFF090D13),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isActive ? const Color(0xFF238636) : const Color(0xFF1F2432)),
                        ),
                        child: Text(
                          _iptvCountryLabels[ctry] ?? ctry,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isActive ? Colors.white : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Channels Grid or Empty / Loading
        if (_isLoadingIptv && _iptvChannels.isEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            alignment: Alignment.center,
            child: const Column(
              children: [
                CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFFF0C82)),
                SizedBox(height: 12),
                Text('Loading global IPTV channels...', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
        ] else if (_iptvChannels.isEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.tv_off_rounded, size: 36, color: Colors.grey.shade600),
                const SizedBox(height: 8),
                Text('No channels found matching current filters.', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => _loadIptvChannels(reset: true),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF195FEB)),
                  child: const Text('Refresh Channels', style: TextStyle(fontSize: 12, color: Colors.white)),
                ),
              ],
            ),
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available Channels (${_iptvChannels.length})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              if (_iptvChannels.length > _iptvDisplayLimit)
                Text(
                  'Showing top $_iptvDisplayLimit',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final cols = isWide
                  ? (width >= 1200 ? 4 : (width >= 800 ? 3 : 2))
                  : (width >= 550 ? 2 : 1);

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: cols == 1 ? 2.5 : 2.35,
                ),
                itemCount: displayedChannels.length,
                itemBuilder: (context, index) {
                  final ch = displayedChannels[index];
                  return _buildIptvChannelCard(ch);
                },
              );
            },
          ),
          if (_iptvChannels.length > _iptvDisplayLimit) ...[
            const SizedBox(height: 16),
            Center(
              child: _TvFocusableButton(
                onPressed: () {
                  setState(() {
                    _iptvDisplayLimit += 60;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Load More Channels', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildIptvChannelCard(IptvChannel ch) {
    final streamData = {
      'url': ch.url,
      'title': ch.name,
      'cleanTitle': ch.name,
      'name': '📺 ${ch.category}',
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2432)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Large Prominent 72x72 Logo container
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: ch.logo.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          ch.logo,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.live_tv_rounded, color: Colors.grey, size: 32),
                        ),
                      )
                    : const Icon(Icons.live_tv_rounded, color: Colors.grey, size: 32),
              ),
              const SizedBox(width: 12),

              // Name, Badges & Live Status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ch.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white, height: 1.2),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF195FEB).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF195FEB), width: 0.8),
                          ),
                          child: Text(
                            _getChannelCategoryLabel(ch.category),
                            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF58A6FF)),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF238636).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF238636), width: 0.8),
                          ),
                          child: Text(
                            _getChannelCountryLabel(ch.country),
                            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF3FB950)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Row(
                      children: [
                        Icon(Icons.circle, color: Color(0xFF3FB950), size: 7),
                        SizedBox(width: 4),
                        Text(
                          'LIVE STREAM',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF3FB950)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _playStream(streamData, isLive: true),
                  icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
                  label: const Text('Play', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF195FEB),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showPlayWithDialog(streamData, isLive: true),
                  icon: const Icon(Icons.launch_rounded, size: 13, color: Color(0xFF58A6FF)),
                  label: const Text('Play With...', style: TextStyle(fontSize: 10.5, color: Color(0xFF58A6FF))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF388BFD), width: 0.8),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Favourite Star Button
              GestureDetector(
                onTap: () => _toggleIptvFavourite(ch),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _iptvFavourites.contains(ch.id)
                        ? const Color(0xFFE3B341).withOpacity(0.2)
                        : const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _iptvFavourites.contains(ch.id)
                          ? const Color(0xFFE3B341)
                          : const Color(0xFF30363D),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    _iptvFavourites.contains(ch.id)
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: _iptvFavourites.contains(ch.id)
                        ? const Color(0xFFE3B341)
                        : Colors.grey.shade500,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// D-Pad and remote-friendly focusable button for Android TV & Mobile
class _TvFocusableButton extends StatefulWidget {
  final FocusNode? focusNode;
  final VoidCallback onPressed;
  final Widget child;
  final bool isPrimary;
  final Color? primaryColor;

  const _TvFocusableButton({
    this.focusNode,
    required this.onPressed,
    required this.child,
    this.isPrimary = false,
    this.primaryColor,
  });

  @override
  State<_TvFocusableButton> createState() => _TvFocusableButtonState();
}

class _TvFocusableButtonState extends State<_TvFocusableButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hasHighlight = _isFocused || _isHovered;
    final bg = widget.isPrimary
        ? (widget.primaryColor ?? const Color(0xFF6366F1))
        : (hasHighlight ? const Color(0xFF21262D) : const Color(0xFF161B22));

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: false,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        }
      },
      onShowHoverHighlight: (hovered) => setState(() => _isHovered = hovered),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onPressed(),
        ),
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: hasHighlight ? Matrix4.diagonal3Values(1.04, 1.04, 1.0) : Matrix4.identity(),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasHighlight ? const Color(0xFF38BDF8) : const Color(0xFF30363D),
              width: hasHighlight ? 2.5 : 1.2,
            ),
            boxShadow: hasHighlight
                ? [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withOpacity(0.4),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
