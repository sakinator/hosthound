import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'metadata_service.dart';
import 'scraper_engine.dart';
import 'server_service.dart';
import 'torbox_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  // Tab Navigation State
  int _selectedTabIndex = 0; // 0 = Server, 1 = Streaming
  final FocusNode _serverTabFocus = FocusNode();
  final FocusNode _streamingTabFocus = FocusNode();

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

  bool _isScrapingStreams = false;
  List<Map<String, dynamic>> _scrapedStreams = [];
  String _activeStreamFilter = 'all';

  @override
  void initState() {
    super.initState();
    // Request initial focus on the primary action button for TV remote
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startStopFocus.requestFocus();
    });

    final currentKey = AddonConfig.instance.torboxApiKey;
    _torboxKeyController.text = currentKey;
    if (currentKey.isNotEmpty) {
      _validateTorboxKeySilent(currentKey);
    }
  }

  @override
  void dispose() {
    _serverTabFocus.dispose();
    _streamingTabFocus.dispose();
    _startStopFocus.dispose();
    _oneClickInstallFocus.dispose();
    _copyManifestFocus.dispose();
    _openWebFocus.dispose();
    _refreshIpFocus.dispose();
    _torboxKeyController.dispose();
    _torboxInputFocus.dispose();
    _torboxSaveFocus.dispose();
    _torboxKeyLinkFocus.dispose();
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

    return Scaffold(
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
                    final horizontalPadding = isWide ? 36.0 : 16.0;
                    final verticalPadding = isWide ? 24.0 : 16.0;

                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isWide ? 1200 : 600),
                        child: ListView(
                          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
                          children: [
                            // Header
                            _buildHeader(running, isWide: isWide),
                            const SizedBox(height: 18),

                            // Main Tabs Switcher: Server vs Streaming
                            _buildTabSelector(isWide: isWide),
                            const SizedBox(height: 18),

                            if (_selectedTabIndex == 1) ...[
                              // TAB 2: Native Streaming Theater
                              _buildStreamingView(isWide: isWide),
                            ] else if (isWide) ...[
                              // TAB 1: Server (Two-column layout for Android TV, Tablet, or Wide Landscape)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Left Column: Status, Action Buttons, Server Activity
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
                                  // Right Column: TorBox Debrid, Metrics, Optimizations
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        _buildTorboxCard(),
                                        const SizedBox(height: 18),
                                        _buildInfoRow(isWide: true),
                                        const SizedBox(height: 18),
                                        _buildEngineFeaturesCard(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              // TAB 1: Server (Single-column layout for Mobile Portrait)
                              _buildStatusCard(running, ip, port, manifestUrl),
                              const SizedBox(height: 16),
                              _buildActionButtons(running, manifestUrl, dashboardUrl),
                              const SizedBox(height: 16),
                              _buildTorboxCard(),
                              const SizedBox(height: 16),
                              _buildInfoRow(isWide: false),
                              const SizedBox(height: 16),
                              _buildEngineFeaturesCard(),
                              const SizedBox(height: 16),
                              _buildLogsCard(),
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
          Expanded(
            child: _TvFocusableButton(
              focusNode: _serverTabFocus,
              onPressed: () {
                setState(() => _selectedTabIndex = 0);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: _selectedTabIndex == 0
                      ? const LinearGradient(colors: [Color(0xFF195FEB), Color(0xFFFF0C82)])
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.dns_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      '🖥️ Server & Addon',
                      style: TextStyle(
                        fontSize: isWide ? 15 : 13,
                        fontWeight: FontWeight.bold,
                        color: _selectedTabIndex == 0 ? Colors.white : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TvFocusableButton(
              focusNode: _streamingTabFocus,
              onPressed: () {
                setState(() => _selectedTabIndex = 1);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: _selectedTabIndex == 1
                      ? const LinearGradient(colors: [Color(0xFF195FEB), Color(0xFFFF0C82)])
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.movie_filter_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      '🎬 Streaming Theater',
                      style: TextStyle(
                        fontSize: isWide ? 15 : 13,
                        fontWeight: FontWeight.bold,
                        color: _selectedTabIndex == 1 ? Colors.white : Colors.grey.shade400,
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

  Widget _buildHeader(bool running, {bool isWide = false}) {
    return Row(
      children: [
        Container(
          width: isWide ? 58 : 50,
          height: isWide ? 58 : 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF0C82).withOpacity(0.45),
                blurRadius: 18,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: const Color(0xFF195FEB).withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 0,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/images/hostreamio_logo_256.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(
              child: Icon(Icons.play_arrow_rounded, color: const Color(0xFFFF0C82), size: isWide ? 34 : 28),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hostreamio',
                style: TextStyle(
                  fontSize: isWide ? 26 : 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Direct Hosters • Regional OTT • TorBox Debrid (Android TV & Mobile)',
                style: TextStyle(
                  fontSize: isWide ? 14 : 12,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 14 : 10, vertical: isWide ? 8 : 6),
          decoration: BoxDecoration(
            color: running ? const Color(0xFF238636).withOpacity(0.2) : Colors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: running ? const Color(0xFF3FB950) : Colors.redAccent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: running ? const Color(0xFF3FB950) : Colors.redAccent,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                running ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isWide ? 13 : 11,
                  letterSpacing: 0.5,
                  color: running ? const Color(0xFF3FB950) : Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
      ],
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
              const Icon(Icons.router_rounded, color: Color(0xFF195FEB), size: 22),
              const SizedBox(width: 8),
              const Text(
                'Nuvio Addon Manifest URL',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              _TvFocusableButton(
                focusNode: _refreshIpFocus,
                onPressed: () async {
                  await ServerService.instance.updateLanIp();
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF195FEB)),
                    SizedBox(width: 6),
                    Text('Detect IP', style: TextStyle(color: Color(0xFF195FEB), fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
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
              Text(
                'Engine & Network Optimizations',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildFeatureBadge(
                icon: Icons.shield_rounded,
                title: 'DoH DNS Fallback',
                subtitle: 'Cloudflare & Google (Active)',
                color: const Color(0xFF238636),
              ),
              _buildFeatureBadge(
                icon: Icons.memory_rounded,
                title: 'HLS Segment Cache',
                subtitle: '35 MB Ring Buffer (Active)',
                color: const Color(0xFF1F6FEB),
              ),
              _buildFeatureBadge(
                icon: Icons.video_settings_rounded,
                title: 'MPEG-DASH Transmuxer',
                subtitle: 'Virtual HLS Converter (Ready)',
                color: const Color(0xFF7928CA),
              ),
              _buildFeatureBadge(
                icon: Icons.electric_bolt_rounded,
                title: 'Auto Circuit Breaker',
                subtitle: '56 Providers Monitored',
                color: const Color(0xFFD29922),
              ),
            ],
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
        mainAxisSize: MainAxisSize.min,
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
          Column(
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
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8B949E),
                ),
              ),
            ],
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
                  const Icon(Icons.search_rounded, color: Color(0xFFFF0C82), size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Native Search & Stream Theater',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Spacer(),
                  // Media Type Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF08090C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
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
                            child: const Text('🎬 Movie', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            setState(() => _selectedMediaType = 'series');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedMediaType == 'series' ? const Color(0xFF195FEB) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('📺 Series', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
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

        // 4. Series Catalog & Episodes Browser (if Series)
        if (_selectedMediaType == 'series' && _seriesDetails != null) ...[
          _buildSeriesCatalogBrowser(),
          const SizedBox(height: 14),
        ],

        // 5. Scraped Streams List
        _buildStreamsSection(),
      ],
    );
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isCached
                              ? const Color(0xFF238636).withOpacity(0.2)
                              : (isCacheTag ? const Color(0xFF195FEB).withOpacity(0.2) : const Color(0xFF21262D)),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isCached ? const Color(0xFF3FB950) : (isCacheTag ? const Color(0xFF58A6FF) : Colors.grey.shade700),
                          ),
                        ),
                        child: Text(
                          isCached ? '⚡ TorBox Cached' : (isCacheTag ? '🌐 TorBox Cachable' : '🌐 Direct Play'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isCached ? const Color(0xFF3FB950) : (isCacheTag ? const Color(0xFF58A6FF) : Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // Action buttons
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF195FEB),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
                        label: const Text('Play', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                        onPressed: () => _playStream(url),
                      ),
                      const SizedBox(width: 8),
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
                      if (isCachable) ...[
                        const SizedBox(width: 8),
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

    _searchQueryController.text = id;
    setState(() {
      _selectedMediaType = type;
      _selectedMediaMeta = m;
    });

    if (type == 'series') {
      _loadSeriesCatalog(id, name, poster);
    } else {
      _scrapeStreams(id, 'movie', name);
    }
  }

  Future<void> _loadSeriesCatalog(String id, String name, String? poster) async {
    setState(() {
      _selectedMediaMeta = {'id': id, 'name': name, 'poster': poster};
      _seriesDetails = null;
    });

    try {
      final details = await MetadataService.getSeriesDetails(id);
      if (mounted && details != null) {
        setState(() {
          _seriesDetails = details;
          final seasons = (details['seasons'] as List?)?.map((e) => int.tryParse(e.toString()) ?? 1).toList() ?? [1];
          _selectedSeason = seasons.isNotEmpty ? seasons.first : 1;
        });

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
            lower.contains('pixeldrain') || lower.contains('1fichier') || lower.contains('rapidgator') ||
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
          m['is4K'] = rawName.contains('4K') || rawTitle.contains('[4K]');
          m['is1080p'] = rawName.contains('1080p') || rawTitle.contains('[FHD]') || rawTitle.contains('1080p');
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

  Future<void> _playStream(String url) async {
    try {
      final uri = Uri.parse(url);
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        _copyToClipboard(url, 'Stream Link');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open external player. Link copied: $e')),
        );
      }
    }
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
