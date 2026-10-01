import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'window_service.dart';
import 'opensubtitles_service.dart';

/// Full-featured, native in-app video player powered by libmpv via media_kit.
/// Supports high-bitrate 4K Remuxes, HDR tonemapping, live IPTV streams (HLS/TS),
/// audio track switching, styled subtitle selection, audio gain boost (up to 200%),
/// dialogue normalization, and Android TV / desktop keyboard navigation.
class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String? subtitle;
  final Map<String, String>? headers;
  final VoidCallback? onOpenExternal;
  /// Optional IMDb ID (e.g. "tt1375666") for auto-subtitle fetching via OpenSubtitles
  final String? imdbId;
  /// "movie" or "series" — used for OpenSubtitles API query type
  final String? mediaType;
  /// Whether this stream is a live IPTV broadcast (true) or VOD movie/episode (false)
  final bool isLive;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.subtitle,
    this.headers,
    this.onOpenExternal,
    this.imdbId,
    this.mediaType,
    this.isLive = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  // Stream & Playback State
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = true;
  bool _hasError = false;
  String _errorMessage = '';

  // Track State
  Tracks _tracks = const Tracks();
  AudioTrack _selectedAudio = AudioTrack.auto();
  SubtitleTrack _selectedSubtitle = SubtitleTrack.no();

  // Audio Gain & Volume State (0% to 200% with preamp boost)
  double _volume = 100.0;
  bool _dialogueBoost = false;
  String? _hudMessage;
  Timer? _hudTimer;

  // Overlay & TV Navigation State
  bool _showControls = true;
  Timer? _hideControlsTimer;
  final FocusNode _keyboardFocusNode = FocusNode();

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  // Playback Speed State
  double _playbackSpeed = 1.0;
  static const List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  // Gesture State (swipe controls)
  Offset? _gestureStart;
  double _gestureStartVolume = 100.0;
  double _gestureStartBrightness = 0.5;
  bool _isHorizontalGesture = false;

  // Subtitle State — OpenSubtitles fetched list + selected external sub
  List<Map<String, dynamic>> _fetchedSubtitles = [];
  int? _selectedExternalSubIndex; // null = none loaded, -1 = off, ≥0 = index in _fetchedSubtitles
  bool _isLoadingSubtitles = false;
  bool _subtitleAutoLoaded = false;

  @override
  void initState() {
    super.initState();

    // Enable immersive fullscreen on mobile / TV
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024, // 32MB buffer for smooth 4K Debrid & IPTV playback
          logLevel: MPVLogLevel.warn,
        ),
      );

      // Unlock volume-max to 200% for audio gain boost
      if (_player.platform is NativePlayer) {
        final np = _player.platform as NativePlayer;
        try {
          await np.setProperty('volume-max', '200');
        } catch (_) {}
      }

      _controller = VideoController(
        _player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );

      _subscriptions.addAll([
        _player.stream.playing.listen((playing) {
          if (mounted) setState(() => _isPlaying = playing);
        }),
        _player.stream.buffering.listen((buffering) {
          if (mounted) setState(() => _isBuffering = buffering);
        }),
        _player.stream.position.listen((pos) {
          if (mounted) setState(() => _position = pos);
        }),
        _player.stream.duration.listen((dur) {
          if (mounted) setState(() => _duration = dur);
        }),
        _player.stream.buffer.listen((buf) {
          if (mounted) setState(() => _buffer = buf);
        }),
        _player.stream.tracks.listen((tracks) {
          if (mounted) setState(() => _tracks = tracks);
        }),
        _player.stream.track.listen((track) {
          if (mounted) {
            setState(() {
              _selectedAudio = track.audio;
              _selectedSubtitle = track.subtitle;
            });
          }
        }),
        _player.stream.volume.listen((vol) {
          if (mounted) setState(() => _volume = vol);
        }),
        _player.stream.error.listen((err) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = err;
            });
          }
        }),
      ]);

      // Open media with custom headers (essential for IPTV and tokenized debrid hosts)
      final defaultHeaders = <String, String>{
        'User-Agent': 'Hostreamio/1.0.0 (libmpv)',
      };
      if (widget.headers != null) {
        defaultHeaders.addAll(widget.headers!);
      }

      await _player.open(
        Media(
          widget.streamUrl,
          httpHeaders: defaultHeaders,
        ),
        play: true,
      );

      _startHideControlsTimer();

      // Auto-load subtitles from OpenSubtitles in background (non-blocking)
      if (widget.imdbId != null && widget.imdbId!.isNotEmpty) {
        _loadOpenSubtitles(autoSelect: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// Fetches subtitles from OpenSubtitles v3 for the current media.
  /// If [autoSelect] is true, automatically injects the best-matching English subtitle.
  Future<void> _loadOpenSubtitles({bool autoSelect = false}) async {
    if (_isLoadingSubtitles) return;
    if (mounted) setState(() => _isLoadingSubtitles = true);

    try {
      final id = widget.imdbId ?? '';
      final type = widget.mediaType ?? 'movie';
      if (id.isEmpty) return;

      final subs = await OpenSubtitlesService.instance.getSubtitles(
        type: type,
        id: id,
      );

      if (!mounted) return;
      setState(() {
        _fetchedSubtitles = subs;
        _isLoadingSubtitles = false;
      });

      if (autoSelect && subs.isNotEmpty && !_subtitleAutoLoaded) {
        // Pick the best English sub first, then fall back to first available
        final engSub = subs.firstWhere(
          (s) => (s['lang']?.toString() ?? '').toLowerCase().contains('en'),
          orElse: () => subs.first,
        );
        final idx = subs.indexOf(engSub);
        await _loadExternalSubtitle(idx);
        if (mounted) setState(() => _subtitleAutoLoaded = true);
      }
    } catch (e) {
      debugPrint('[Subtitles] Error: $e');
      if (mounted) setState(() => _isLoadingSubtitles = false);
    }
  }

  /// Injects an external subtitle URL into the mpv player via sub-add.
  Future<void> _loadExternalSubtitle(int index) async {
    if (index < 0 || index >= _fetchedSubtitles.length) return;
    final sub = _fetchedSubtitles[index];
    final url = sub['url']?.toString() ?? '';
    if (url.isEmpty) return;

    try {
      if (_player.platform is NativePlayer) {
        final np = _player.platform as NativePlayer;
        // Clear existing external subs, then add new one
        await np.setProperty('sub-files', '');
        await np.command(['sub-add', url, 'select']);
        if (mounted) {
          setState(() => _selectedExternalSubIndex = index);
          final lang = (sub['lang']?.toString() ?? 'unknown').toUpperCase();
          _showHud('Subtitles: $lang ✓');
        }
      }
    } catch (e) {
      debugPrint('[Subtitles] sub-add failed: $e');
      if (mounted) {
        _showHud('Subtitle load failed');
      }
    }
  }

  /// Clears the currently loaded external subtitle.
  Future<void> _clearExternalSubtitle() async {
    try {
      if (_player.platform is NativePlayer) {
        final np = _player.platform as NativePlayer;
        await np.setProperty('sub-files', '');
        await _player.setSubtitleTrack(SubtitleTrack.no());
        if (mounted) {
          setState(() => _selectedExternalSubIndex = -1);
          _showHud('Subtitles: Off');
        }
      }
    } catch (e) {
      debugPrint('[Subtitles] clear failed: $e');
    }
  }

  /// Shows the full subtitle picker sheet with all fetched matches + manual search.
  void _showSubtitlePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11141C),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.35,
              maxChildSize: 0.92,
              expand: false,
              builder: (ctx, scrollCtrl) {
                return Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade600,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF195FEB).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.subtitles_rounded, color: Color(0xFF58A6FF), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Select Subtitles',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                Text(
                                  _isLoadingSubtitles
                                    ? 'Fetching from OpenSubtitles…'
                                    : '${_fetchedSubtitles.length} subtitle track(s) found',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                ),
                              ],
                            ),
                          ),
                          if (_isLoadingSubtitles)
                            const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF58A6FF)),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1, color: Color(0xFF21262D)),

                    // Reload button if empty
                    if (!_isLoadingSubtitles && _fetchedSubtitles.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.subtitles_off_rounded, size: 42, color: Colors.grey.shade600),
                            const SizedBox(height: 10),
                            Text(
                              widget.imdbId != null
                                ? 'No subtitles found for this title.\nTry refreshing or check your network.'
                                : 'Subtitles require an IMDb ID.\nOpen via the Cinema tab to enable auto-fetch.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 13, height: 1.5),
                            ),
                            const SizedBox(height: 14),
                            if (widget.imdbId != null)
                              ElevatedButton.icon(
                                onPressed: () async {
                                  setSheet(() {});
                                  await _loadOpenSubtitles(autoSelect: false);
                                  setSheet(() {});
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Retry'),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF195FEB)),
                              ),
                          ],
                        ),
                      ),
                    ],

                    // Subtitle list
                    if (_fetchedSubtitles.isNotEmpty)
                      Expanded(
                        child: ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _fetchedSubtitles.length + 1, // +1 for "Off" row
                          itemBuilder: (c, i) {
                            // First row = Off
                            if (i == 0) {
                              final isOff = _selectedExternalSubIndex == -1 || _selectedExternalSubIndex == null;
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                                leading: Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: isOff
                                      ? const Color(0xFFFF0C82).withOpacity(0.15)
                                      : const Color(0xFF21262D),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.subtitles_off_rounded,
                                    color: isOff ? const Color(0xFFFF0C82) : Colors.grey,
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  'Off (No Subtitles)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isOff ? FontWeight.bold : FontWeight.normal,
                                    color: isOff ? const Color(0xFFFF0C82) : Colors.white,
                                  ),
                                ),
                                trailing: isOff
                                  ? const Icon(Icons.check_circle_rounded, color: Color(0xFFFF0C82), size: 18)
                                  : null,
                                onTap: () async {
                                  Navigator.of(ctx).pop();
                                  await _clearExternalSubtitle();
                                },
                              );
                            }

                            final idx = i - 1;
                            final sub = _fetchedSubtitles[idx];
                            final lang = sub['lang']?.toString() ?? 'Unknown';
                            final isSelected = _selectedExternalSubIndex == idx;
                            final langUpper = lang.toUpperCase();
                            // Map common lang codes to readable names
                            final langName = _langCodeToName(lang);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                              leading: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: isSelected
                                    ? const Color(0xFF195FEB).withOpacity(0.2)
                                    : const Color(0xFF161B22),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF58A6FF) : const Color(0xFF30363D),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    langUpper.length > 3 ? langUpper.substring(0, 3) : langUpper,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? const Color(0xFF58A6FF) : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                langName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? const Color(0xFF58A6FF) : Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                'Track ${idx + 1} • OpenSubtitles',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                              trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: Color(0xFF58A6FF), size: 18)
                                : const Icon(Icons.download_rounded, color: Colors.grey, size: 16),
                              onTap: () async {
                                Navigator.of(ctx).pop();
                                await _loadExternalSubtitle(idx);
                              },
                            );
                          },
                        ),
                      ),

                    // Bottom note
                    if (_fetchedSubtitles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Powered by OpenSubtitles v3 — 90+ languages',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                            ),
                            if (widget.imdbId != null)
                              TextButton(
                                onPressed: () async {
                                  await _loadOpenSubtitles(autoSelect: false);
                                  setSheet(() {});
                                },
                                child: const Text('Refresh', style: TextStyle(fontSize: 11)),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Maps ISO 639 language codes to human-readable names.
  String _langCodeToName(String code) {
    const Map<String, String> names = {
      'en': 'English', 'eng': 'English',
      'hi': 'Hindi', 'hin': 'Hindi',
      'es': 'Spanish', 'spa': 'Spanish',
      'fr': 'French', 'fre': 'French', 'fra': 'French',
      'de': 'German', 'ger': 'German', 'deu': 'German',
      'it': 'Italian', 'ita': 'Italian',
      'pt': 'Portuguese', 'por': 'Portuguese',
      'ru': 'Russian', 'rus': 'Russian',
      'ar': 'Arabic', 'ara': 'Arabic',
      'zh': 'Chinese', 'chi': 'Chinese', 'zho': 'Chinese',
      'ja': 'Japanese', 'jpn': 'Japanese',
      'ko': 'Korean', 'kor': 'Korean',
      'tr': 'Turkish', 'tur': 'Turkish',
      'pl': 'Polish', 'pol': 'Polish',
      'nl': 'Dutch', 'dut': 'Dutch', 'nld': 'Dutch',
      'sv': 'Swedish', 'swe': 'Swedish',
      'no': 'Norwegian', 'nor': 'Norwegian',
      'da': 'Danish', 'dan': 'Danish',
      'fi': 'Finnish', 'fin': 'Finnish',
      'cs': 'Czech', 'cze': 'Czech',
      'ro': 'Romanian', 'rum': 'Romanian',
      'hu': 'Hungarian', 'hun': 'Hungarian',
      'el': 'Greek', 'gre': 'Greek',
      'he': 'Hebrew', 'heb': 'Hebrew',
      'th': 'Thai', 'tha': 'Thai',
      'vi': 'Vietnamese', 'vie': 'Vietnamese',
      'id': 'Indonesian', 'ind': 'Indonesian',
      'ta': 'Tamil', 'tam': 'Tamil',
      'te': 'Telugu', 'tel': 'Telugu',
      'ml': 'Malayalam', 'mal': 'Malayalam',
      'bn': 'Bengali', 'ben': 'Bengali',
      'pa': 'Punjabi', 'pan': 'Punjabi',
    };
    return names[code.toLowerCase()] ?? code.toUpperCase();
  }

  void _showHud(String msg) {
    _hudTimer?.cancel();
    setState(() => _hudMessage = msg);
    _hudTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _hudMessage = null);
    });
  }

  Future<void> _setVolumeWithGain(double vol) async {
    final clamped = vol.clamp(0.0, 200.0);
    setState(() => _volume = clamped);
    await _player.setVolume(clamped);
    final boostBadge = clamped > 100.0 ? '  ⚡ Gain +${(clamped - 100.0).round()}%' : '';
    _showHud('Volume: ${clamped.round()}%$boostBadge');
  }

  Future<void> _toggleDialogueBoost() async {
    setState(() => _dialogueBoost = !_dialogueBoost);
    if (_player.platform is NativePlayer) {
      final np = _player.platform as NativePlayer;
      try {
        if (_dialogueBoost) {
          await np.setProperty('af', 'lavfi=[dynaudnorm=f=75:g=15:p=0.95:m=10]');
          _showHud('Dialogue Booster: ON (Normalized)');
        } else {
          await np.setProperty('af', '');
          _showHud('Dialogue Booster: OFF');
        }
      } catch (_) {}
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (!_showControls) return;
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    _showControlsTemporarily();

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _player.playOrPause();
    } else if (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.f11) {
      WindowService.instance.toggleFullscreen();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(-10);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekRelative(10);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _setVolumeWithGain(_volume + 5.0);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _setVolumeWithGain(_volume - 5.0);
    } else if (key == LogicalKeyboardKey.escape) {
      if (WindowService.instance.isFullscreen) {
        WindowService.instance.exitFullscreen();
      } else {
        Navigator.of(context).maybePop();
      }
    }
  }

  void _showControlsTemporarily() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideControlsTimer();
  }

  void _seekRelative(int seconds) {
    final target = _position + Duration(seconds: seconds);
    final clamped = Duration(
      milliseconds: target.inMilliseconds.clamp(0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 0),
    );
    _player.seek(clamped);
  }

  void _setPlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _player.setRate(speed);
    _showHud('Playback Speed: ${speed}x');
  }

  bool get _isLiveStream => widget.isLive;

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _hideControlsTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _keyboardFocusNode.dispose();
    _player.dispose();

    if (WindowService.instance.isFullscreen) {
      WindowService.instance.exitFullscreen();
    }

    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          onDoubleTap: () => WindowService.instance.toggleFullscreen(),
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            _gestureStart = details.globalPosition;
            _gestureStartVolume = _volume;
            _isHorizontalGesture = false;
          },
          onPanUpdate: (details) {
            if (_gestureStart == null) return;
            final dx = details.globalPosition.dx - _gestureStart!.dx;
            final dy = details.globalPosition.dy - _gestureStart!.dy;

            if (!_isHorizontalGesture && (dx.abs() > dy.abs() + 10)) {
              _isHorizontalGesture = true;
            }

            if (_isHorizontalGesture) {
              // Horizontal swipe → seek
              if (!_isLiveStream && _duration.inSeconds > 0) {
                final screenWidth = MediaQuery.of(context).size.width;
                final seekSeconds = (dx / screenWidth * 120).round();
                final target = _position + Duration(seconds: seekSeconds);
                final clamped = Duration(milliseconds: target.inMilliseconds.clamp(0, _duration.inMilliseconds));
                _showHud('${seekSeconds > 0 ? '+' : ''}${seekSeconds}s → ${_formatDuration(clamped)}');
              }
            } else {
              // Vertical swipe → volume (right half) or show gesture info
              final screenWidth = MediaQuery.of(context).size.width;
              final isRightSide = (_gestureStart?.dx ?? 0) > screenWidth / 2;
              if (isRightSide) {
                // Right side: volume control
                final screenHeight = MediaQuery.of(context).size.height;
                final volumeDelta = -dy / screenHeight * 150;
                _setVolumeWithGain(_gestureStartVolume + volumeDelta);
              }
            }
          },
          onPanEnd: (details) {
            if (_isHorizontalGesture && !_isLiveStream && _duration.inSeconds > 0) {
              // Commit seek on release
              final dx = _gestureStart != null
                  ? (details.velocity.pixelsPerSecond.dx / 10 + (_gestureStart!.dx))
                  : 0.0;
              final screenWidth = MediaQuery.of(context).size.width;
              final totalDx = (_gestureStart != null) ? 0.0 : 0.0; // we'll use velocity instead
              final seekSeconds = (details.velocity.pixelsPerSecond.dx / screenWidth * 30).round();
              _seekRelative(seekSeconds);
            }
            _gestureStart = null;
          },

          child: Stack(
            fit: StackFit.expand,
            children: [
              // Core libmpv Video Renderer
              Center(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                ),
              ),

              // Buffering indicator
              if (_isBuffering && !_hasError)
                const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFFFF0C82),
                  ),
                ),

              // Error Display
              if (_hasError)
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    constraints: const BoxConstraints(maxWidth: 480),
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22).withOpacity(0.97),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF85149), width: 1.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header row with ✕ close button
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 22),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Close Player',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFF85149), size: 48),
                        const SizedBox(height: 10),
                        const Text(
                          'Playback Error',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 10),
                        // Context-aware hint for stream errors
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF21262D),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Color(0xFF58A6FF), size: 14),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isLiveStream
                                      ? 'Live IPTV broadcast may be temporarily offline or geo-restricted. Try Retry or switch to another channel.'
                                      : 'Stream failed to load or the video host timed out. Try another stream link from the list, or open with an External Player.',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Action buttons — Wrap so they never overflow
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            // Close / Go Back
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back_rounded, size: 16),
                              label: const Text('Go Back'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Color(0xFF30363D)),
                                minimumSize: const Size(110, 38),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                            ),
                            // Retry
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _hasError = false;
                                  _errorMessage = '';
                                  _isBuffering = true;
                                });
                                _initPlayer();
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                              label: const Text(
                                'Retry',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF195FEB),
                                minimumSize: const Size(100, 38),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                            ),
                            // Open External
                            if (widget.onOpenExternal != null)
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onOpenExternal!();
                                },
                                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                label: const Text('External Player'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFFF0C82),
                                  side: const BorderSide(color: Color(0xFFFF0C82)),
                                  minimumSize: const Size(140, 38),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // Floating Audio & Volume HUD Notification
              if (_hudMessage != null)
                Positioned(
                  top: 70,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _hudMessage != null ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1117).withOpacity(0.92),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _volume > 100.0 ? const Color(0xFFFF0C82) : const Color(0xFF195FEB),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_volume > 100.0 ? const Color(0xFFFF0C82) : const Color(0xFF195FEB)).withOpacity(0.4),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _volume > 100.0 ? Icons.bolt_rounded : Icons.volume_up_rounded,
                              color: _volume > 100.0 ? const Color(0xFFFF0C82) : const Color(0xFF58A6FF),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _hudMessage!,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Touch / TV Overlay Controls
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _buildControlsOverlay(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(0.85),
          ],
          stops: const [0.0, 0.25, 0.7, 1.0],
        ),
      ),
      child: Column(
        children: [
          // Top Navigation Bar
          _buildTopBar(),

          // Center Quick Controls (Play/Pause, Rewind, Fast Forward)
          Expanded(
            child: _buildCenterControls(),
          ),

          // Bottom Bar (Progress, Audio Gain, Audio/Subtitle Selectors, Fullscreen)
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.onOpenExternal != null)
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 22),
                tooltip: 'Open in External Player',
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onOpenExternal!();
                },
              ),
            ValueListenableBuilder<bool>(
              valueListenable: WindowService.instance.isFullscreenNotifier,
              builder: (context, isFs, _) {
                return IconButton(
                  icon: Icon(
                    isFs ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    color: Colors.white70,
                    size: 24,
                  ),
                  tooltip: isFs ? 'Exit Fullscreen (F / Esc)' : 'Fullscreen (F / F11)',
                  onPressed: () => WindowService.instance.toggleFullscreen(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!_isLiveStream) ...[
          // −30s button
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_30_rounded, color: Colors.white70, size: 34),
                onPressed: () {
                  _showControlsTemporarily();
                  _seekRelative(-30);
                },
                tooltip: 'Rewind 30s',
              ),
            ],
          ),
          // −10s button
          IconButton(
            icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 40),
            onPressed: () {
              _showControlsTemporarily();
              _seekRelative(-10);
            },
            tooltip: 'Rewind 10s',
          ),
        ],
        const SizedBox(width: 20),
        IconButton(
          icon: Icon(
            _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
            color: const Color(0xFFFF0C82),
            size: 64,
          ),
          onPressed: () {
            _showControlsTemporarily();
            _player.playOrPause();
          },
          tooltip: _isPlaying ? 'Pause' : 'Play',
        ),
        const SizedBox(width: 20),
        if (!_isLiveStream) ...[
          // +10s button
          IconButton(
            icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 40),
            onPressed: () {
              _showControlsTemporarily();
              _seekRelative(10);
            },
            tooltip: 'Forward 10s',
          ),
          // +30s button
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.forward_30_rounded, color: Colors.white70, size: 34),
                onPressed: () {
                  _showControlsTemporarily();
                  _seekRelative(30);
                },
                tooltip: 'Forward 30s',
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBottomBar() {
    final live = _isLiveStream;
    final isGainBoosted = _volume > 100.0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seekbar (VOD) or LIVE Indicator (IPTV)
            if (live)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF85149),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                        SizedBox(width: 4),
                        Text(
                          'LIVE STREAM',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                ],
              )
            else
              Row(
                children: [
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final totalW = constraints.maxWidth;
                        final bufferRatio = _duration.inMilliseconds > 0
                            ? (_buffer.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                            : 0.0;
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            // Buffer progress bar (grey background)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: Container(
                                height: 3.5,
                                width: totalW * bufferRatio,
                                color: Colors.white24,
                              ),
                            ),
                            // Seek Slider (foreground - active position)
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3.5,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                activeTrackColor: const Color(0xFFFF0C82),
                                inactiveTrackColor: Colors.transparent,
                                thumbColor: const Color(0xFFFF0C82),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: _duration.inMilliseconds > 0
                                    ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                                    : 0.0,
                                onChanged: (ratio) {
                                  _showControlsTemporarily();
                                  final target = Duration(milliseconds: (_duration.inMilliseconds * ratio).round());
                                  _player.seek(target);
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),

            const SizedBox(height: 6),

            // Track Selectors & Extra Controls
            Row(
              children: [
                // Audio Track Menu
                if (_tracks.audio.isNotEmpty)
                  PopupMenuButton<AudioTrack>(
                    tooltip: 'Audio Track',
                    icon: const Icon(Icons.audiotrack_rounded, color: Colors.white70, size: 20),
                    onSelected: (t) => _player.setAudioTrack(t),
                    itemBuilder: (ctx) => _tracks.audio.map((t) {
                      final selected = t == _selectedAudio;
                      final title = t.title ?? t.language ?? 'Audio Track ${t.id}';
                      return PopupMenuItem<AudioTrack>(
                        value: t,
                        child: Row(
                          children: [
                            if (selected)
                              const Icon(Icons.check_rounded, color: Color(0xFFFF0C82), size: 16)
                            else
                              const SizedBox(width: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(title, style: TextStyle(color: selected ? const Color(0xFFFF0C82) : Colors.white))),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                // Subtitle Button — always visible, opens full picker
                GestureDetector(
                  onTap: _showSubtitlePicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _selectedExternalSubIndex != null && _selectedExternalSubIndex! >= 0
                          ? const Color(0xFF195FEB).withOpacity(0.2)
                          : const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _selectedExternalSubIndex != null && _selectedExternalSubIndex! >= 0
                            ? const Color(0xFF58A6FF)
                            : const Color(0xFF30363D),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isLoadingSubtitles)
                          const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF58A6FF)),
                          )
                        else
                          Icon(
                            _selectedExternalSubIndex != null && _selectedExternalSubIndex! >= 0
                                ? Icons.subtitles_rounded
                                : Icons.subtitles_off_rounded,
                            color: _selectedExternalSubIndex != null && _selectedExternalSubIndex! >= 0
                                ? const Color(0xFF58A6FF)
                                : Colors.white54,
                            size: 16,
                          ),
                        if (_selectedExternalSubIndex != null && _selectedExternalSubIndex! >= 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            (_fetchedSubtitles.isNotEmpty && _selectedExternalSubIndex! < _fetchedSubtitles.length)
                                ? _langCodeToName(_fetchedSubtitles[_selectedExternalSubIndex!]['lang']?.toString() ?? '').substring(0, 2).toUpperCase()
                                : 'ON',
                            style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Audio Gain & Volume Booster Button
                InkWell(
                  onTap: _showAudioGainDialog,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isGainBoosted
                          ? const Color(0xFFFF0C82).withOpacity(0.2)
                          : const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isGainBoosted ? const Color(0xFFFF0C82) : const Color(0xFF30363D),
                        width: isGainBoosted ? 1.2 : 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isGainBoosted ? Icons.bolt_rounded : Icons.volume_up_rounded,
                          color: isGainBoosted ? const Color(0xFFFF0C82) : Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_volume.round()}%',
                          style: TextStyle(
                            color: isGainBoosted ? const Color(0xFFFF0C82) : Colors.white70,
                            fontSize: 11,
                            fontWeight: isGainBoosted ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        if (isGainBoosted) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF0C82),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'GAIN',
                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Playback Speed Control Button
                if (!live)
                  PopupMenuButton<double>(
                    tooltip: 'Playback Speed',
                    initialValue: _playbackSpeed,
                    onSelected: _setPlaybackSpeed,
                    padding: EdgeInsets.zero,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _playbackSpeed != 1.0
                            ? const Color(0xFF195FEB).withOpacity(0.2)
                            : const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _playbackSpeed != 1.0 ? const Color(0xFF58A6FF) : const Color(0xFF30363D),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.speed_rounded,
                            color: _playbackSpeed != 1.0 ? const Color(0xFF58A6FF) : Colors.white54,
                            size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${_playbackSpeed}x',
                            style: TextStyle(
                              color: _playbackSpeed != 1.0 ? const Color(0xFF58A6FF) : Colors.white70,
                              fontSize: 11,
                              fontWeight: _playbackSpeed != 1.0 ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    itemBuilder: (ctx) => _speedOptions.map((speed) {
                      final selected = (speed - _playbackSpeed).abs() < 0.01;
                      return PopupMenuItem<double>(
                        value: speed,
                        child: Row(
                          children: [
                            if (selected)
                              const Icon(Icons.check_rounded, color: Color(0xFFFF0C82), size: 16)
                            else
                              const SizedBox(width: 16),
                            const SizedBox(width: 8),
                            Text(
                              speed == 1.0 ? '1.0x  Normal' : '${speed}x',
                              style: TextStyle(
                                color: selected ? const Color(0xFFFF0C82) : Colors.white,
                                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                const Spacer(),

                // Engine Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: const Text(
                    'libmpv',
                    style: TextStyle(color: Color(0xFF58A6FF), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(width: 8),

                // Fullscreen Button
                ValueListenableBuilder<bool>(
                  valueListenable: WindowService.instance.isFullscreenNotifier,
                  builder: (context, isFs, _) {
                    return IconButton(
                      icon: Icon(
                        isFs ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      tooltip: isFs ? 'Exit Fullscreen (F / Esc)' : 'Fullscreen (F / F11)',
                      onPressed: () => WindowService.instance.toggleFullscreen(),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAudioGainDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11141C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final isBoosted = _volume > 100.0;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isBoosted ? const Color(0xFFFF0C82).withOpacity(0.2) : const Color(0xFF195FEB).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isBoosted ? Icons.bolt_rounded : Icons.volume_up_rounded,
                            color: isBoosted ? const Color(0xFFFF0C82) : const Color(0xFF58A6FF),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Audio Gain & Volume Booster',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              Text(
                                isBoosted
                                    ? 'Boost Active (${_volume.round()}%) • Preamp Gain'
                                    : 'Standard Volume Range (${_volume.round()}%)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isBoosted ? const Color(0xFFFF0C82) : Colors.grey,
                                  fontWeight: isBoosted ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.grey),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Slider (0 to 200%)
                    Row(
                      children: [
                        const Icon(Icons.volume_mute_rounded, color: Colors.grey, size: 20),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              activeTrackColor: isBoosted ? const Color(0xFFFF0C82) : const Color(0xFF195FEB),
                              thumbColor: isBoosted ? const Color(0xFFFF0C82) : const Color(0xFF195FEB),
                              inactiveTrackColor: Colors.white12,
                              trackHeight: 6,
                            ),
                            child: Slider(
                              min: 0.0,
                              max: 200.0,
                              divisions: 40,
                              value: _volume.clamp(0.0, 200.0),
                              onChanged: (val) {
                                setModalState(() {});
                                _setVolumeWithGain(val);
                              },
                            ),
                          ),
                        ),
                        Container(
                          width: 48,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${_volume.round()}%',
                            style: TextStyle(
                              color: isBoosted ? const Color(0xFFFF0C82) : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Quick Preset Pills
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildGainPill(setModalState, 100.0, '100% Normal'),
                        _buildGainPill(setModalState, 125.0, '125% Mild'),
                        _buildGainPill(setModalState, 150.0, '150% Boost'),
                        _buildGainPill(setModalState, 200.0, '200% Max Gain'),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(color: Color(0xFF21262D), height: 1),
                    const SizedBox(height: 12),

                    // Speech & Dialogue Normalizer (dynaudnorm)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _dialogueBoost,
                      activeColor: const Color(0xFFFF0C82),
                      title: const Text(
                        'Dialogue & Speech Normalizer',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Boosts quiet whispered dialogue while normalizing ear-splitting explosions (mpv dynaudnorm).',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      onChanged: (val) {
                        setModalState(() {});
                        _toggleDialogueBoost();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGainPill(void Function(void Function()) setModalState, double target, String label) {
    final isSelected = (_volume - target).abs() < 2.5;
    final isBoost = target > 100.0;
    return InkWell(
      onTap: () {
        setModalState(() {});
        _setVolumeWithGain(target);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isBoost ? const Color(0xFFFF0C82).withOpacity(0.25) : const Color(0xFF195FEB).withOpacity(0.25))
              : const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? (isBoost ? const Color(0xFFFF0C82) : const Color(0xFF58A6FF))
                : const Color(0xFF30363D),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}
