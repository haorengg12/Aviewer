import 'package:flutter/material.dart';
import 'package:flick_video_player/flick_video_player.dart';
import 'package:video_player/video_player.dart';

class FlickPlayerPage extends StatefulWidget {
  const FlickPlayerPage({super.key});

  @override
  State<FlickPlayerPage> createState() => _FlickPlayerPageState();
}

class _FlickPlayerPageState extends State<FlickPlayerPage> {
  String _url =
      'https://surrit.com/8f9f4ec3-df8e-466f-889a-fdb43039cd4c/playlist.m3u8';
  late final TextEditingController _urlController;

  FlickManager? _flickManager;
  bool _useProxy = false;

  String _applyProxy(String url) {
    if (!_useProxy) return url;
    final u = Uri.parse(url);
    final hostWithPort = u.hasPort && u.port != 0 ? '${u.host}:${u.port}' : u.host;
    final pathWithQuery = u.hasQuery ? '${u.path}?${u.query}' : u.path;
    return 'http://127.0.0.1:8082/proxy/${u.scheme}/$hostWithPort$pathWithQuery';
  }

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _url);
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    // Dispose previous manager if exists
    _flickManager?.dispose();
    _flickManager = null;

    if (mounted) {
      setState(() {});
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(_applyProxy(_url)),
      );

      _flickManager = FlickManager(
        videoPlayerController: controller,
      );
    } catch (e) {
      debugPrint('Error initializing player: $e');
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _flickManager?.dispose();
    super.dispose();
  }

  Future<void> _loadUrl(String url) async {
    _url = url.trim();
    await _initializePlayer();
  }

  @override
  Widget build(BuildContext context) {
    // FlickVideoPlayer needs to be inside a Scaffold or similar structure, 
    // but here we are part of a tab view. 
    // Ideally FlickVideoPlayer handles fullscreen by pushing a new route.
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flick Player (Video Player)'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'HLS 地址',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final nextUrl = _urlController.text.trim();
                      if (nextUrl.isEmpty) return;
                      await _loadUrl(nextUrl);
                    },
                    child: const Text('加载'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _useProxy,
                    onChanged: (v) async {
                      setState(() {
                        _useProxy = v ?? false;
                        // Re-initialize player when proxy setting changes? 
                        // Or just wait for next load? User usually clicks load.
                        // Let's just update state.
                      });
                    },
                  ),
                  const Text('通过本地代理'),
                ],
              ),
              const SizedBox(height: 8),
              if (_flickManager != null)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: FlickVideoPlayer(
                    flickManager: _flickManager!,
                    flickVideoWithControls: const FlickVideoWithControls(
                      controls: FlickPortraitControls(),
                    ),
                    flickVideoWithControlsFullscreen: const FlickVideoWithControls(
                      controls: FlickLandscapeControls(),
                    ),
                  ),
                )
              else
                const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
                
              const SizedBox(height: 12),
              Text(
                '来源：$_url',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
