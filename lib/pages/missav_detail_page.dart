import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flick_video_player/flick_video_player.dart';
import 'package:video_player/video_player.dart';
import 'missav_page.dart';

class MissAVDetailPage extends StatefulWidget {
  final String url;
  const MissAVDetailPage({super.key, required this.url});

  @override
  State<MissAVDetailPage> createState() => _MissAVDetailPageState();
}

class _MissAVDetailPageState extends State<MissAVDetailPage> {
  HeadlessInAppWebView? _headlessWebView;
  bool _isLoading = true;
  String? _error;
  FlickManager? _flickManager;
  String? _m3u8;
  final List<MissAVSection> _sidebarSections = [];
  final List<MissAVSection> _bottomSections = [];
  final List<MissAVSection> _gridSections = [];
  final List<MissAVSection> _orderLastSections = [];
  String? _videoDetailsText;
  int _refreshAttempts = 0;
  bool _incrementalActive = false;
  int _idleRounds = 0;
  final Set<String> _parsedSectionTitles = {};

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _isLoading = false;
      _error = 'Web 版本暂不支持';
    } else {
      _start();
    }
  }

  @override
  void dispose() {
    _flickManager?.dispose();
    _headlessWebView?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    _headlessWebView?.dispose();
    _headlessWebView = null;
    setState(() {
      _isLoading = true;
      _error = null;
      _sidebarSections.clear();
      _bottomSections.clear();
      _m3u8 = null;
      _refreshAttempts = 0;
      _incrementalActive = false;
      _idleRounds = 0;
      _parsedSectionTitles.clear();
    });
    try {
      _headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          userAgent:
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          javaScriptEnabled: true,
        ),
        onLoadStart: (controller, url) async {
          await _injectCapture(controller);
        },
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: 'm3u8',
            callback: (args) {
              if (args.isNotEmpty && args.first is String) {
                final url = args.first as String;
                if (_m3u8 == null) {
                  _m3u8 = url;
                  _initPlayer(url);
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                }
              }
              return null;
            },
          );
        },
        onLoadStop: (controller, url) async {
          if (await _isCloudflareChallenge(controller)) {
            if (_refreshAttempts < 2) {
              _refreshAttempts++;
              await controller.reload();
              return;
            }
          }
          await _injectCapture(controller);
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          await _startIncrementalParse(controller);
        },
        onReceivedHttpError: (controller, request, errorResponse) {},
      );
      await _headlessWebView?.run();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _injectCapture(InAppWebViewController controller) async {
    const String js = r'''
      (function() {
        if (window.__m3u8_hooked) return;
        window.__m3u8_hooked = true;
        window.__m3u8_found = false;
        function report(u) {
          try {
            if (window.__m3u8_found) return;
            var url = String(u || '');
            var pathname = '';
            try {
              pathname = new URL(url, location.href).pathname;
            } catch (e) {
              pathname = url;
            }
            if (/\/playlist\.m3u8$/i.test(pathname)) {
              window.__m3u8_found = true;
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('m3u8', url);
              }
            }
          } catch (e) {}
        }
        try {
          var origOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(method, url) {
            report(url);
            return origOpen.apply(this, arguments);
          };
        } catch (e) {}
        try {
          var origFetch = window.fetch;
          window.fetch = function(input, init) {
            var url = (typeof input === 'string') ? input : (input && input.url);
            report(url);
            return origFetch.apply(this, arguments);
          };
        } catch (e) {}
      })();
    ''';
    await controller.evaluateJavascript(source: js);
  }

  Future<void> _startIncrementalParse(InAppWebViewController controller) async {
    if (!mounted) return;
    _incrementalActive = true;
    _idleRounds = 0;
    while (mounted && _incrementalActive) {
      try {
        final html = await controller.evaluateJavascript(
          source: 'document.documentElement.outerHTML',
        );
        final asideHtml = await controller.evaluateJavascript(
          source: '(document.querySelector("aside")||{innerHTML:""}).innerHTML',
        );
        var added = 0;
        // 解析详情文本：x-show="currentTab === 'video_details'"
        if (asideHtml is String && asideHtml.isNotEmpty) {
          final asideDoc = parser.parse(asideHtml);
          final sec = _parseSidebar(asideDoc);
          if (sec.items.isNotEmpty && !_parsedSectionTitles.contains(sec.title)) {
            _parsedSectionTitles.add(sec.title);
            _sidebarSections.add(sec);
            added++;
          }
        }
        if (html is String && html.isNotEmpty) {
          final document = parser.parse(html);
          added += _extractDetailSections(document);
          final containers = <dom.Element>[];
          final allDivs = document.querySelectorAll('div');
          for (final container in allDivs) {
            final c = container.className;
            final hit = c.contains('sm:container') &&
                c.contains('mx-auto') &&
                c.contains('mb-5') &&
                c.contains('px-4');
            if (hit) containers.add(container);
          }
          for (final container in containers) {
            dom.Element? titleElement;
            for (final child in container.children) {
              final cc = child.className;
              final isHeader = cc.contains('flex') &&
                  cc.contains('items-center') &&
                  cc.contains('justify-between') &&
                  cc.contains('pt-10') &&
                  cc.contains('pb-6');
              if (isHeader) {
                titleElement = child;
                break;
              }
            }
            if (titleElement == null) continue;
            final title = titleElement.children.first.text.trim();
            if (_parsedSectionTitles.contains(title)) continue;
            final tmp = <MissAVSection>[];
            _parseSectionContainer(container, tmp);
            if (tmp.isNotEmpty) {
              _parsedSectionTitles.add(tmp.first.title);
              _bottomSections.addAll(tmp);
              added += tmp.length;
            }
          }
        }
        if (added > 0) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          _idleRounds = 0;
        } else {
          _idleRounds++;
        }
        if (_idleRounds >= 6) {
          _incrementalActive = false;
          break;
        }
      } catch (_) {
        _idleRounds++;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  MissAVSection _parseSidebar(dom.Document doc) {
    final items = <MissAVItem>[];
    final divs = doc.querySelectorAll('div');
    for (final div in divs) {
      final cl = div.className;
      if (!cl.contains('thumbnail') || !cl.contains('group')) continue;
      final firstLink = div.querySelector('a');
      if (firstLink == null) continue;
      final img = firstLink.querySelector('img') ?? div.querySelector('img');
      if (img == null) continue;
      var titleText = '';
      if (div.children.length >= 2) {
        final titleDiv = div.children[1];
        final titleAnchor = titleDiv.querySelector('a');
        if (titleAnchor != null) {
          titleText = titleAnchor.text.trim();
        }
      }
      if (titleText.isEmpty) {
        titleText = img.attributes['alt'] ?? firstLink.attributes['title'] ?? '';
      }
      if (titleText.isEmpty) {
        titleText = div.text.trim();
      }
      var imgUrl = img.attributes['data-src'] ?? img.attributes['src'];
      var videoUrl = firstLink.attributes['href'];
      var previewUrl = img.attributes['data-preview'];
      var duration = '';
      final spans = div.querySelectorAll('span');
      for (final s in spans) {
        final t = s.text.trim();
        if (t.contains(':')) {
          duration = t;
          break;
        }
      }
      if (imgUrl == null || imgUrl.isEmpty) continue;
      if (videoUrl != null && !videoUrl.contains('missav.ai') && !videoUrl.startsWith('/')) {
        continue;
      }
      if (videoUrl != null && !videoUrl.startsWith('http')) {
        videoUrl = 'https://missav.ai$videoUrl';
      }
      items.add(MissAVItem(
        title: titleText,
        imageUrl: imgUrl,
        videoUrl: videoUrl ?? '',
        previewUrl: previewUrl,
        duration: duration,
      ));
    }
    return MissAVSection(title: '右侧列表', items: items);
  }

  void _parseSectionContainer(dom.Element container, List<MissAVSection> sections) {
    dom.Element? titleElement;
    for (final child in container.children) {
      final c = child.className;
      if (c.contains('flex') &&
          c.contains('items-center') &&
          c.contains('justify-between') &&
          c.contains('pt-10') &&
          c.contains('pb-6')) {
        titleElement = child;
        break;
      }
    }
    if (titleElement == null) {
      return;
    }
    final title = titleElement.children.first.text.trim();
    final items = <MissAVItem>[];
    final itemDivs = container.querySelectorAll('div');
    for (final div in itemDivs) {
      final itemClass = div.className;
      if (!itemClass.contains('thumbnail') || !itemClass.contains('group')) {
        continue;
      }
      final firstLink = div.querySelector('a');
      if (firstLink == null) continue;
      final img = firstLink.querySelector('img') ?? div.querySelector('img');
      if (img == null) continue;
      var titleText = '';
      if (div.children.length >= 2) {
        final titleDiv = div.children[1];
        final titleAnchor = titleDiv.querySelector('a');
        if (titleAnchor != null) {
          titleText = titleAnchor.text.trim();
        }
      }
      if (titleText.isEmpty) {
        titleText = img.attributes['alt'] ?? firstLink.attributes['title'] ?? '';
      }
      if (titleText.isEmpty) {
        titleText = div.text.trim();
      }
      var imgUrl = img.attributes['data-src'] ?? img.attributes['src'];
      var videoUrl = firstLink.attributes['href'];
      var previewUrl = img.attributes['data-preview'];
      var duration = '';
      final durationSpans = div.querySelectorAll('span');
      for (final span in durationSpans) {
        final t = span.text.trim();
        if (t.contains(':')) {
          duration = t;
          break;
        }
      }
      if (imgUrl == null || imgUrl.isEmpty) {
        continue;
      }
      if (videoUrl != null &&
          !videoUrl.contains('missav.ai') &&
          !videoUrl.startsWith('/')) {
        continue;
      }
      if (videoUrl != null && !videoUrl.startsWith('http')) {
        videoUrl = 'https://missav.ai$videoUrl';
      }
      items.add(MissAVItem(
        title: titleText,
        imageUrl: imgUrl,
        videoUrl: videoUrl ?? '',
        previewUrl: previewUrl,
        duration: duration,
      ));
    }
    if (items.isNotEmpty) {
      sections.add(MissAVSection(title: title, items: items));
    }
  }

  int _extractDetailSections(dom.Document document) {
    int added = 0;
    if (_videoDetailsText == null) {
      final detailsEl = document.querySelector('[x-show="currentTab === \'video_details\'"]');
      if (detailsEl != null) {
        final text = detailsEl.text.trim();
        if (text.isNotEmpty) {
          _videoDetailsText = text;
          added++;
        }
      }
    }
    if (_gridSections.isEmpty) {
      dom.Element? gridEl;
      for (final div in document.querySelectorAll('div')) {
        final c = div.className;
        final hit = c.contains('grid') &&
            c.contains('grid-cols-2') &&
            c.contains('md:grid-cols-3') &&
            c.contains('xl:grid-cols-4') &&
            c.contains('gap-5');
        if (hit) {
          gridEl = div;
          break;
        }
      }
      if (gridEl != null) {
        final sec = _buildSectionFromContainer(gridEl, '页面中部');
        if (sec.items.isNotEmpty && !_parsedSectionTitles.contains(sec.title)) {
          _parsedSectionTitles.add(sec.title);
          _gridSections.add(sec);
          added++;
        }
      }
    }
    if (_orderLastSections.isEmpty) {
      dom.Element? rightEl;
      for (final div in document.querySelectorAll('div')) {
        final c = div.className;
        final hit = c.contains('hidden') &&
            c.contains('lg:flex') &&
            c.contains('h-full') &&
            c.contains('ml-6') &&
            c.contains('order-last');
        if (hit) {
          rightEl = div;
          break;
        }
      }
      if (rightEl != null) {
        final sec = _buildSectionFromContainer(rightEl, '右侧区域');
        if (sec.items.isNotEmpty && !_parsedSectionTitles.contains(sec.title)) {
          _parsedSectionTitles.add(sec.title);
          _orderLastSections.add(sec);
          added++;
        }
      }
    }
    return added;
  }

  MissAVSection _buildSectionFromContainer(dom.Element root, String fallbackTitle) {
    String title = fallbackTitle;
    dom.Element? header;
    dom.Element? p = root.parent;
    for (int i = 0; i < 4 && p != null; i++) {
      for (final child in p.children) {
        final cc = child.className;
        final isHeader = cc.contains('flex') &&
            cc.contains('items-center') &&
            cc.contains('justify-between') &&
            cc.contains('pt-10') &&
            cc.contains('pb-6');
        if (isHeader) {
          header = child;
          break;
        }
      }
      if (header != null) break;
      p = p.parent;
    }
    if (header != null && header.children.isNotEmpty) {
      title = header.children.first.text.trim();
    }
    final items = <MissAVItem>[];
    final candidates = root.querySelectorAll('div');
    for (final div in candidates) {
      final cl = div.className;
      if (!cl.contains('thumbnail') || !cl.contains('group')) continue;
      final a = div.querySelector('a');
      if (a == null) continue;
      final img = a.querySelector('img') ?? div.querySelector('img');
      if (img == null) continue;
      var titleText = '';
      if (div.children.length >= 2) {
        final tDiv = div.children[1];
        final tAnchor = tDiv.querySelector('a');
        if (tAnchor != null) {
          titleText = tAnchor.text.trim();
        }
      }
      if (titleText.isEmpty) {
        titleText = img.attributes['alt'] ?? a.attributes['title'] ?? '';
      }
      if (titleText.isEmpty) {
        titleText = div.text.trim();
      }
      var imgUrl = img.attributes['data-src'] ?? img.attributes['src'];
      var videoUrl = a.attributes['href'];
      var previewUrl = img.attributes['data-preview'];
      var duration = '';
      final spans = div.querySelectorAll('span');
      for (final s in spans) {
        final t = s.text.trim();
        if (t.contains(':')) {
          duration = t;
          break;
        }
      }
      if (imgUrl == null || imgUrl.isEmpty) continue;
      if (videoUrl != null &&
          !videoUrl.contains('missav.ai') &&
          !videoUrl.startsWith('/')) {
        continue;
      }
      if (videoUrl != null && !videoUrl.startsWith('http')) {
        videoUrl = 'https://missav.ai$videoUrl';
      }
      items.add(MissAVItem(
        title: titleText,
        imageUrl: imgUrl,
        videoUrl: videoUrl ?? '',
        previewUrl: previewUrl,
        duration: duration,
      ));
    }
    if (items.isEmpty) {
      final anchors = root.querySelectorAll('a[href]');
      for (final a in anchors) {
        final img = a.querySelector('img') ?? a.parent?.querySelector('img');
        if (img == null) continue;
        var titleText = img.attributes['alt'] ?? a.attributes['title'] ?? '';
        if (titleText.isEmpty) {
          titleText = (a.parent?.text ?? '').trim();
        }
        var imgUrl = img.attributes['data-src'] ?? img.attributes['src'];
        var videoUrl = a.attributes['href'];
        var previewUrl = img.attributes['data-preview'];
        var duration = '';
        if (imgUrl == null || imgUrl.isEmpty) continue;
        if (videoUrl != null &&
            !videoUrl.contains('missav.ai') &&
            !videoUrl.startsWith('/')) {
          continue;
        }
        if (videoUrl != null && !videoUrl.startsWith('http')) {
          videoUrl = 'https://missav.ai$videoUrl';
        }
        items.add(MissAVItem(
          title: titleText,
          imageUrl: imgUrl,
          videoUrl: videoUrl ?? '',
          previewUrl: previewUrl,
          duration: duration,
        ));
      }
    }
    return MissAVSection(title: title, items: items);
  }


  Future<bool> _isCloudflareChallenge(InAppWebViewController controller) async {
    try {
      final title =
          await controller.evaluateJavascript(source: 'document.title') as String?;
      final bodyText = await controller
          .evaluateJavascript(source: 'document.body.innerText') as String?;
      final hasChallengeElement = await controller.evaluateJavascript(
        source:
            'document.querySelector("[id*=cf-challenge], [class*=cf-challenge]") != null',
      );
      final markers = [
        'Just a moment',
        'Checking your browser',
        'Cloudflare',
        'Verify you are human',
      ];
      final t = title?.toLowerCase() ?? '';
      final b = bodyText?.toLowerCase() ?? '';
      final textHit =
          markers.any((m) => t.contains(m.toLowerCase()) || b.contains(m.toLowerCase()));
      final elemHit = hasChallengeElement == true;
      return textHit || elemHit;
    } catch (_) {
      return false;
    }
  }

  Future<void> _initPlayer(String url) async {
    _flickManager?.dispose();
    _flickManager = null;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _flickManager = FlickManager(
      videoPlayerController: controller,
      autoPlay: false,
    );
  }

  Map<String, String> _headersForUrl(String url) {
    return {
      'Referer': 'https://missav.ai/',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
  }

  Widget _buildCard(int sectionIndex, int index, MissAVItem item) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (item.videoUrl.isNotEmpty) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MissAVDetailPage(url: item.videoUrl),
              ),
            );
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: item.imageUrl,
                    httpHeaders: _headersForUrl(item.imageUrl),
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.error),
                    ),
                  ),
                  if (item.duration != null && item.duration!.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.duration!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('详情'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text('Error: $_error', textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _start,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    if (_flickManager != null)
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: FlickVideoPlayer(
                          flickManager: _flickManager!,
                          flickVideoWithControls: const FlickVideoWithControls(
                            controls: FlickPortraitControls(),
                          ),
                          flickVideoWithControlsFullscreen:
                              const FlickVideoWithControls(
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
                    if (_m3u8 != null)
                      Text(
                        '来源：$_m3u8',
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 12),
                    if (_videoDetailsText != null && _videoDetailsText!.isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(
                            _videoDetailsText!,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    for (var sIndex = 0; sIndex < _gridSections.length; sIndex++)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _gridSections[sIndex].title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          MasonryGridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _gridSections[sIndex].items.length,
                            itemBuilder: (context, index) {
                              final item = _gridSections[sIndex].items[index];
                              return _buildCard(sIndex, index, item);
                            },
                          ),
                        ],
                      ),
                    for (var sIndex = 0; sIndex < _orderLastSections.length; sIndex++)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _orderLastSections[sIndex].title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          MasonryGridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _orderLastSections[sIndex].items.length,
                            itemBuilder: (context, index) {
                              final item = _orderLastSections[sIndex].items[index];
                              return _buildCard(sIndex, index, item);
                            },
                          ),
                        ],
                      ),
                    // 旧的右侧与底部模块
                    for (var sIndex = 0; sIndex < _sidebarSections.length; sIndex++)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _sidebarSections[sIndex].title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          MasonryGridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _sidebarSections[sIndex].items.length,
                            itemBuilder: (context, index) {
                              final item = _sidebarSections[sIndex].items[index];
                              return _buildCard(sIndex, index, item);
                            },
                          ),
                        ],
                      ),
                    for (var sIndex = 0; sIndex < _bottomSections.length; sIndex++)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _bottomSections[sIndex].title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          MasonryGridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _bottomSections[sIndex].items.length,
                            itemBuilder: (context, index) {
                              final item = _bottomSections[sIndex].items[index];
                              return _buildCard(sIndex, index, item);
                            },
                          ),
                        ],
                      ),
                  ],
                ),
    );
  }
}
