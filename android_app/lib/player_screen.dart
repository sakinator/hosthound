import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'window_service.dart';

/// Full-featured, native in-app video player powered by libmpv via media_kit.
/// Supports high-bitrate 4K Remuxes, HDR tonemapping, live IPTV streams (HLS/TS),
/// audio track switching, styled subtitle selection, VLC-style audio gain (up to 200%),
/// dialogue normalization, and Android TV / desktop keyboard navigation.
class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String? subtitle;
  final Map<String, String>? headers;
  final VoidCallback? onOpenExternal;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.subtitle,
    this.headers,
    this.onOpenExternal,
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

  // Audio Gain & Volume State (VLC-Style 0% to 200%)
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

      // Unlock volume-max up to 200% for classic VLC audio gain boost
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
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
          await np.setProperty('af', 'lavfi=[dynaudnorm=f=150:g=15]');
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

  bool get _isLiveStream => _duration == Duration.zero || widget.streamUrl.contains('.m3u8') && _duration.inSeconds > 43200;

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
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF85149)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFF85149), size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'Playback Error',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _hasError = false;
                                  _errorMessage = '';
                                });
                                _initPlayer();
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF195FEB)),
                            ),
                            if (widget.onOpenExternal != null) ...[
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onOpenExternal!();
                                },
                                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                label: const Text('Open External Player'),
                                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF0C82)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // Floating Audio & Volume HUD Notification (VLC Style)
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
                tooltip: 'Open in External Player (VLC / Just Player)',
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
        if (!_isLiveStream)
          IconButton(
            icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 40),
            onPressed: () {
              _showControlsTemporarily();
              _seekRelative(-10);
            },
            tooltip: 'Rewind 10s',
          ),
        const SizedBox(width: 28),
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
        const SizedBox(width: 28),
        if (!_isLiveStream)
          IconButton(
            icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 40),
            onPressed: () {
              _showControlsTemporarily();
              _seekRelative(10);
            },
            tooltip: 'Forward 10s',
          ),
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
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.5,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: const Color(0xFFFF0C82),
                        inactiveTrackColor: Colors.white24,
                        thumbColor: const Color(0xFFFF0C82),
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

                // Subtitle Track Menu
                if (_tracks.subtitle.isNotEmpty)
                  PopupMenuButton<SubtitleTrack>(
                    tooltip: 'Subtitles',
                    icon: const Icon(Icons.subtitles_rounded, color: Colors.white70, size: 20),
                    onSelected: (t) => _player.setSubtitleTrack(t),
                    itemBuilder: (ctx) => [
                      PopupMenuItem<SubtitleTrack>(
                        value: SubtitleTrack.no(),
                        child: const Text('Off', style: TextStyle(color: Colors.white70)),
                      ),
                      ..._tracks.subtitle.map((t) {
                        final selected = t == _selectedSubtitle;
                        final title = t.title ?? t.language ?? 'Subtitle ${t.id}';
                        return PopupMenuItem<SubtitleTrack>(
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
                      }),
                    ],
                  ),

                const SizedBox(width: 6),

                // VLC-Style Audio Gain & Volume Booster Button
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
                                'VLC Audio Gain & Volume Booster',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              Text(
                                isBoosted
                                    ? 'Classic VLC Boost Active (${_volume.round()}%) • Preamp Gain'
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
