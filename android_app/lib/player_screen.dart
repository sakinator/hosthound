import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Full-featured, native in-app video player powered by libmpv via media_kit.
/// Supports high-bitrate 4K Remuxes, HDR tonemapping, live IPTV streams (HLS/TS),
/// audio track switching, styled subtitle selection, and Android TV / desktop keyboard navigation.
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
  Track _selectedAudio = const Track();
  Track _selectedSubtitle = const Track();

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
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(-10);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekRelative(10);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      final vol = (_player.state.volume + 5.0).clamp(0.0, 100.0);
      _player.setVolume(vol);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      final vol = (_player.state.volume - 5.0).clamp(0.0, 100.0);
      _player.setVolume(vol);
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
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
    _hideControlsTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _keyboardFocusNode.dispose();
    _player.dispose();

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

          // Bottom Bar (Progress, Audio/Subtitle Selectors, Fullscreen)
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
                  PopupMenuButton<Track>(
                    tooltip: 'Audio Track',
                    icon: const Icon(Icons.audiotrack_rounded, color: Colors.white70, size: 20),
                    onSelected: (t) => _player.setAudioTrack(t),
                    itemBuilder: (ctx) => _tracks.audio.map((t) {
                      final selected = t == _selectedAudio;
                      final title = t.title ?? t.language ?? 'Audio Track ${t.id}';
                      return PopupMenuItem<Track>(
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
                  PopupMenuButton<Track>(
                    tooltip: 'Subtitles',
                    icon: const Icon(Icons.subtitles_rounded, color: Colors.white70, size: 20),
                    onSelected: (t) => _player.setSubtitleTrack(t),
                    itemBuilder: (ctx) => [
                      PopupMenuItem<Track>(
                        value: Track.subtitleNone(),
                        child: const Text('Off', style: TextStyle(color: Colors.white70)),
                      ),
                      ..._tracks.subtitle.map((t) {
                        final selected = t == _selectedSubtitle;
                        final title = t.title ?? t.language ?? 'Subtitle ${t.id}';
                        return PopupMenuItem<Track>(
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
