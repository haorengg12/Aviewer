import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:video_player/video_player.dart';
import 'missav_detail_page.dart';

class MissAVPage extends StatefulWidget {
  const MissAVPage({super.key});

  @override
  State<MissAVPage> createState() => _MissAVPageState();
}

class _MissAVPageState extends State<MissAVPage> {
  List<MissAVSection> _sections = [];
  bool _isLoading = true;
  String? _error;
  int? _hoverIndexSection;
  int? _hoverIndexItem;
  HeadlessInAppWebView? _headlessWebView;
    int _refreshAttempts = 0;
    bool _incrementalActive = false;
    int _idleRounds = 0;
    final Set<String> _parsedSectionTitles = {};
  final Map<String, VideoPlayerController> _previewControllers = {};

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _isLoading = false;
      _error = 'Web 版本暂不支持直接抓取 MissAV，请在移动或桌面平台运行';
    } else {
      // 首次进入页面时，启动抓取 MissAV 首页流程
      _fetchData();
    }
  }

  @override
  void dispose() {
    for (final c in _previewControllers.values) {
      c.dispose();
    }
    _headlessWebView?.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    if (kIsWeb) {
      setState(() {
        _isLoading = false;
        _error = 'Web 版本暂不支持直接抓取 MissAV，请在移动或桌面平台运行';
      });
      return;
    }

    // 每次刷新前先释放上一次的隐藏 WebView
    _headlessWebView?.dispose();
    _headlessWebView = null;

    setState(() {
      _isLoading = true;
      _error = null;
      _sections = [];
      _hoverIndexSection = null;
      _hoverIndexItem = null;
      _refreshAttempts = 0;
      _incrementalActive = false;
      _idleRounds = 0;
      _parsedSectionTitles.clear();
    });

    try {
      // 隐藏 WebView，在后台完整打开 https://missav.ai/ 首页
      _headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri('https://missav.ai/'),
        ),
        initialSettings: InAppWebViewSettings(
          // 模拟桌面 Chrome，避免被简单识别为嵌入式 WebView
          userAgent:
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          javaScriptEnabled: true,
        ),
        onLoadStop: (controller, url) async {
          // WebView 报告“某个地址加载结束”时，并不一定所有异步内容都完成，
          // 这里再额外等待页面 readyState 完成后再抓取 HTML
          // Cloudflare 检测与最多两次刷新
          if (await _isCloudflareChallenge(controller)) {
            if (_refreshAttempts < 2) {
              _refreshAttempts++;
              await controller.reload();
              return;
            }
          }
          await _startIncrementalParse(controller);
        },
        onReceivedHttpError: (controller, request, errorResponse) {
          // Cloudflare 校验阶段会有 403，这里不立即报错，等待最终页面
        },
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

 

  Future<void> _startIncrementalParse(
      InAppWebViewController controller) async {
    if (!mounted) return;
    _incrementalActive = true;
    _idleRounds = 0;
    while (mounted && _incrementalActive) {
      try {
        final html = await controller.evaluateJavascript(
          source: 'document.documentElement.outerHTML',
        );
        var added = 0;
        if (html is String && html.isNotEmpty) {
          final document = parser.parse(html);
          final allDivs = document.querySelectorAll('div');
          final containers = <dom.Element>[];
          for (final container in allDivs) {
            final className = container.className;
            final isSectionContainer =
                    className.contains('sm:container') &&
                    className.contains('mx-auto') &&
                    className.contains('mb-5') &&
                    className.contains('px-4');
            if (!isSectionContainer) continue;
            containers.add(container);
          }
          final firstCount = containers.length >= 4 ? 4 : containers.length;
          final firstPart = containers.take(firstCount);
          final secondPart = containers.skip(firstCount);

          // 先处理第一部分
          for (final container in firstPart) {
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
            if (titleElement == null) continue;
            final title = titleElement.children.first.text.trim();
            if (_parsedSectionTitles.contains(title)) continue;
            final tmp = <MissAVSection>[];
            // FIXME: 未加载成功时tmp 为空
            _parseFirstPartSection(container, tmp);
            if (tmp.isNotEmpty) {
              _parsedSectionTitles.add(tmp.first.title);
              _sections.addAll(tmp);
              added += tmp.length;
            }
          }

          // 再处理第二、三部分
          for (final container in secondPart) {
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
            if (titleElement == null) continue;
            final title = titleElement.children.first.text.trim();
            if (_parsedSectionTitles.contains(title)) continue;
            final tmp = <MissAVSection>[];
            _parseCommonSection(container, tmp);
            if (tmp.isNotEmpty) {
              _parsedSectionTitles.add(tmp.first.title);
              _sections.addAll(tmp);
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

 

  void _parseFirstPartSection(
      dom.Element container, List<MissAVSection> sections) {
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

    final List<MissAVItem> items = [];

    final grid = container.children.firstWhere(
      (e) =>
          e.className.contains('grid') &&
          e.className.contains('grid-cols-2') &&
          e.className.contains('gap-5'),
      orElse: () => dom.Element.tag('div'),
    );

    final gridChildren = grid.children.toList(growable: false);

    for (var i = 2; i < gridChildren.length; i++) {
      final wrapper = gridChildren[i];
      if (wrapper.children.length < 2) {
        continue;
      }
      // 列表第一个元素：缩略图容器（thumbnail group）
      final thumb = wrapper.children[0];
      // dom.Element? hero;
      // for (final child in thumb.children) {
        final hc = thumb.className;
        if (!hc.contains('relative') ||
            !hc.contains('aspect-w-16') ||
            !hc.contains('aspect-h-9') ||
            !hc.contains('rounded') ||
            !hc.contains('overflow-hidden') ||
            !hc.contains('shadow-lg')) {
          // hero = child;
          // break;
          continue;
        }
      // }
      // if (hero == null) {
      //   continue;
      // }
      // 列表第二个元素：标题容器，取其中 <a> 的文本
      final titleDiv = wrapper.children[1];
      var titleText = '';
      final titleAnchor = titleDiv.querySelector('a');
      if (titleAnchor != null) {
        titleText = titleAnchor.text.trim();
      }

      final firstLink = thumb.querySelector('a[href]');
      if (firstLink == null) continue;

      final img = thumb.querySelector('img');
      if (img == null) continue;

      final video = thumb.querySelector('video');
      if (video == null) continue;

      if (titleText.isEmpty) {
        titleText =
            img.attributes['alt'] ?? firstLink.attributes['title'] ?? '';
      }
      if (titleText.isEmpty) {
        titleText = wrapper.text.trim();
      }

      var imgUrl = img.attributes['data-src'] ?? img.attributes['src'];
      var videoUrl = firstLink.attributes['href'];
      var previewUrl = video.attributes['data-src'] ?? img.attributes['src'];
      var duration = '';

      final durationSpans = thumb.querySelectorAll('span');
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

  void _parseCommonSection(
      dom.Element container, List<MissAVSection> sections) {
    _parseSectionContainer(container, sections);
  }

  void _parseSectionContainer(
      dom.Element container, List<MissAVSection> sections) {
    dom.Element? titleElement;
    for (final child in container.children) {
      final c = child.className;
      // 模块头部：左侧标题 + 右侧「更多」等入口，位于模块顶部
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

    final List<MissAVItem> items = [];
    // 模块内部所有可能包含缩略图的格子，通常是 grid 布局中的每个卡片
    final itemDivs = container.querySelectorAll('div');
    for (final div in itemDivs) {
      final itemClass = div.className;
      // 单个视频卡片外层 div，类名中通常带有 thumbnail 和 group
      if (!itemClass.contains('thumbnail') || !itemClass.contains('group')) {
        continue;
      }
      // TODO: 应该同时获取元数据，比如番号等，用于数据库匹配
      final firstLink = div.querySelector('a');
      if (firstLink == null) continue;

      // 缩略图 img，既可能在 a 下，也可能直接在卡片 div 内
      final img = firstLink.querySelector('img') ?? div.querySelector('img');
      if (img == null) continue;

      final video = div.querySelector('video');
      if (video == null) continue;

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

      // 封面图：data-src / src，对应列表页每个视频的封面缩略图
      var imgUrl = img.attributes['data-src'] ?? img.attributes['src'];
      // 视频详情页链接：点击卡片跳转的 href
      var videoUrl = firstLink.attributes['href'];
      // 预览图（序列帧 gif / jpg），有些卡片上会有 data-preview
      var previewUrl = video.attributes['data-src'] ?? img.attributes['src'];
      var duration = '';

      // 时长：卡片右下角的小标签，一般是 00:10:23 这样的格式
      final durationSpans = div.querySelectorAll('span');
      for (final span in durationSpans) {
        final t = span.text.trim();
        if (t.contains(':')) {
          duration = t;
          break;
        }
      }

      // 没有封面图的元素直接跳过
      if (imgUrl == null || imgUrl.isEmpty) {
        continue;
      }

      // 过滤掉纯广告块：通常是外部跳转链接，不是 missav 自己的详情页
      if (videoUrl != null &&
          !videoUrl.contains('missav.ai') &&
          !videoUrl.startsWith('/')) {
        continue;
      }

      // 相对路径转为完整 https://missav.ai/... 链接
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 顶部应用栏：不是 MissAV 原站的一部分，仅用于本 App 的标题与刷新按钮
        title: const Text('Aviewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fetchData();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Error: $_error', textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_sections.isEmpty) {
      return const Center(child: Text('No items found'));
    }

    // 外层 ListView：每个 MissAVSection 对应首页的一个内容模块区域
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _sections.length,
      itemBuilder: (context, sectionIndex) {
        final section = _sections[sectionIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                // 模块标题，和网页中「最新上傳」「熱門影片」等标题一致
                section.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // MasonryGridView.count：对应该模块内部的视频卡片瀑布流区域
            MasonryGridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: section.items.length,
              itemBuilder: (context, index) {
                final item = section.items[index];
                return _buildCard(sectionIndex, index, item);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildCard(int sectionIndex, int index, MissAVItem item) {
    final showPreview =
        _hoverIndexSection == sectionIndex &&
        _hoverIndexItem == index &&
        item.previewUrl != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onHover: (isHovering) {
          if (item.previewUrl != null) {
            setState(() {
              if (isHovering) {
                _hoverIndexSection = sectionIndex;
                _hoverIndexItem = index;
              } else {
                _hoverIndexSection = null;
                _hoverIndexItem = null;
              }
            });
            if (isHovering) {
              _startPreview(item.previewUrl);
            } else {
              _stopPreview(item.previewUrl);
            }
          }
        },
        // 禁用长按触发预览，避免与点击播放逻辑冲突
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                final url = item.previewUrl;
                final isVideo = _isVideoPreview(url);
                final playing = isVideo && url != null && _previewControllers[url]?.value.isPlaying == true;
                final isImageActive = !isVideo &&
                    _hoverIndexSection == sectionIndex &&
                    _hoverIndexItem == index;
                if (playing || isImageActive) {
                  if (item.videoUrl.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MissAVDetailPage(url: item.videoUrl),
                      ),
                    );
                  }
                } else {
                  if (isVideo) {
                    _startPreview(url);
                  } else if (item.previewUrl != null) {
                    setState(() {
                      _hoverIndexSection = sectionIndex;
                      _hoverIndexItem = index;
                    });
                  }
                }
              },
              child: AspectRatio(
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
                    if (item.previewUrl != null) ...[
                      if (_isVideoPreview(item.previewUrl) &&
                          _previewControllers[item.previewUrl!] != null)
                        Positioned.fill(
                          child: _buildPreviewWidget(item.previewUrl!),
                        )
                      else if (showPreview)
                        Positioned.fill(
                          child: _buildPreviewWidget(item.previewUrl!),
                        ),
                    ],
                    if (item.duration != null && item.duration!.isNotEmpty)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
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
                    if (item.previewUrl != null)
                      const Positioned(
                        right: 4,
                        top: 4,
                        child: Icon(Icons.play_circle_outline,
                            color: Colors.white70, size: 20),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
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
                child: SizedBox(
                  width: double.infinity,
                  child: _buildTwoLineTitle(item.title),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildTwoLineTitle(String title) {
    final parts = title.trim().split(RegExp(r'\s+'));
    final line1 = parts.isNotEmpty ? parts.first : '';
    final line2 = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          line2,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  bool _isVideoPreview(String? url) {
    if (url == null) return false;
    final u = url.toLowerCase();
    return u.endsWith('.mp4') || u.endsWith('.webm');
  }
  Future<void> _startPreview(String? url) async {
    if (!_isVideoPreview(url)) return;
    final key = url!;
    var c = _previewControllers[key];
    if (c == null) {
      try {
        c = VideoPlayerController.networkUrl(Uri.parse(url));
        _previewControllers[key] = c;
        if (mounted) {
          setState(() {});
        }
        await c.initialize();
        await c.setLooping(true);
        await c.setVolume(0);
        await c.play();
        if (mounted) {
          setState(() {});
        }
      } catch (_) {}
    } else {
      try {
        await c.play();
      } catch (_) {}
    }
  }
  void _stopPreview(String? url) {
    if (!_isVideoPreview(url)) return;
    final c = _previewControllers[url!];
    try {
      c?.pause();
    } catch (_) {}
  }
  Widget _buildPreviewWidget(String url) {
    if (_isVideoPreview(url)) {
      final c = _previewControllers[url];
      if (c != null && c.value.isInitialized) {
        return FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: VideoPlayer(c),
          ),
        );
      }
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: _headersForUrl(url),
      fit: BoxFit.cover,
      placeholder: (context, u) => Container(
        color: Colors.black12,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      errorWidget: (context, u, e) => const SizedBox(),
    );
  }
  Map<String, String> _headersForUrl(String url) {
    return {
      'Referer': 'https://missav.ai/',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
  }

  Future<bool> _isCloudflareChallenge(
      InAppWebViewController controller) async {
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

}

class MissAVSection {
  final String title;
  final List<MissAVItem> items;

  MissAVSection({
    required this.title,
    required this.items,
  });
}

class MissAVItem {
  final String title;
  final String imageUrl;
  final String videoUrl;
  final String? previewUrl;
  final String? duration;

  MissAVItem({
    required this.title,
    required this.imageUrl,
    required this.videoUrl,
    this.previewUrl,
    this.duration,
  });
}
