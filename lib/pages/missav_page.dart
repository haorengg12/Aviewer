import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
  bool _hasParsed = false;

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
      _hasParsed = false;
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
          await _waitForFullLoadAndParse(controller);
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

  Future<void> _waitForFullLoadAndParse(
      InAppWebViewController controller) async {
    if (_hasParsed || !mounted) {
      return;
    }
    try {
      // 轮询 document.readyState，直到变为 complete 或超时
      for (var i = 0; i < 10; i++) {
        final state = await controller.evaluateJavascript(
          source: 'document.readyState',
        );
        if (state == 'complete') {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      // 再额外等待一小段时间，给异步渲染/广告位预留缓冲
      await Future.delayed(const Duration(seconds: 1));
      if (_hasParsed || !mounted) {
        return;
      }
      final html = await controller.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      if (html != null) {
        _hasParsed = true;
        // 将完整的 MissAV 首页 HTML 交给解析函数，转换为 Section + Item 数据
        _parseHtml(html.toString());
      } else {
        if (mounted) {
          setState(() {
            _error = '无法获取页面 HTML';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '解析页面失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _parseHtml(String htmlContent) {
    try {
      final document = parser.parse(htmlContent);

      final allContainers = document.querySelectorAll('div');
      final sections = <MissAVSection>[];
      var sectionContainerIndex = 0;

      for (final container in allContainers) {
        final className = container.className;
        // MissAV 首页各个主要内容区域的外层 container：
        //  - 第一部分：「推薦給你」以及其后紧跟的几个推荐模块
        //  - 第二部分：常规模块（之前规则就能匹配）
        //  - 第三部分：class="sm:container mx-auto px-4" 的模块（有的没有 mb-5）
        final isSectionContainer =
            className.contains('sm:container') &&
                className.contains('mx-auto') &&
                className.contains('px-4');
        if (!isSectionContainer) {
          continue;
        }

        sectionContainerIndex++;

        if (sectionContainerIndex <= 4) {
          _parseFirstPartSection(container, sections);
        } else {
          _parseCommonSection(container, sections);
        }
      }

      if (mounted) {
        setState(() {
          // 解析完成后，得到的 sections 即为首页上各个模块（顺序与网页接近）
          _sections = sections;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
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

    final title = titleElement.text.trim();

    final List<MissAVItem> items = [];

    final grid = container.children.firstWhere(
      (e) =>
          e.className.contains('grid') &&
          e.className.contains('grid-cols-2') &&
          e.className.contains('gap-5'),
      orElse: () => dom.Element.tag('div'),
    );

    final gridChildren = grid.children.toList(growable: false);

    for (var i = 0; i < gridChildren.length; i++) {
      final card = gridChildren[i];
      final itemClass = card.className;
      if (!itemClass.contains('thumbnail') || !itemClass.contains('group')) {
        continue;
      }

      final firstLink = card.querySelector('a[href]');
      if (firstLink == null) continue;

      final img = card.querySelector('img');
      if (img == null) continue;

      var titleText = '';
      // 第一部分标题：取当前卡片后面的第二个 div（紧跟的标题行）里的 <a> 文本
      if (i + 1 < gridChildren.length) {
        final titleDiv = gridChildren[i + 1];
        if (titleDiv.className.contains('my-2') &&
            titleDiv.className.contains('text-sm')) {
          final titleAnchor = titleDiv.querySelector('a');
          if (titleAnchor != null) {
            titleText = titleAnchor.text.trim();
          }
        }
      }

      if (titleText.isEmpty) {
        titleText =
            img.attributes['alt'] ?? firstLink.attributes['title'] ?? '';
      }
      if (titleText.isEmpty) {
        titleText = card.text.trim();
      }

      var imgUrl = img.attributes['data-src'] ?? img.attributes['src'];
      var videoUrl = firstLink.attributes['href'];
      var previewUrl = img.attributes['data-preview'];
      var duration = '';

      final durationSpans = card.querySelectorAll('span');
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

    final title = titleElement.text.trim();

    final List<MissAVItem> items = [];
    // 模块内部所有可能包含缩略图的格子，通常是 grid 布局中的每个卡片
    final itemDivs = container.querySelectorAll('div');
    for (final div in itemDivs) {
      final itemClass = div.className;
      // 单个视频卡片外层 div，类名中通常带有 thumbnail 和 group
      if (!itemClass.contains('thumbnail') || !itemClass.contains('group')) {
        continue;
      }

      final firstLink = div.querySelector('a');
      if (firstLink == null) continue;

      // 缩略图 img，既可能在 a 下，也可能直接在卡片 div 内
      final img = firstLink.querySelector('img') ?? div.querySelector('img');
      if (img == null) continue;

      // 视频标题：优先使用封面上的 alt，其次使用 a 标签 title，最后回退到文本
      var titleText =
          img.attributes['alt'] ?? firstLink.attributes['title'] ?? '';
      if (titleText.isEmpty) {
        titleText = div.text.trim();
      }

      // 封面图：data-src / src，对应列表页每个视频的封面缩略图
      var imgUrl = img.attributes['data-src'] ?? img.attributes['src'];
      // 视频详情页链接：点击卡片跳转的 href
      var videoUrl = firstLink.attributes['href'];
      // 预览图（序列帧 gif / jpg），有些卡片上会有 data-preview
      var previewUrl = img.attributes['data-preview'];
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
        title: const Text('MissAV Discovery'),
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
        onTap: () {
          if (item.videoUrl.isNotEmpty) {
            launchUrl(Uri.parse(item.videoUrl),
                mode: LaunchMode.externalApplication);
          }
        },
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
          }
        },
        onLongPress: () {
          if (item.previewUrl != null) {
            setState(() {
              _hoverIndexSection = sectionIndex;
              _hoverIndexItem = index;
            });
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
                  // 静态封面：列表页中看到的主缩略图
                  CachedNetworkImage(
                    imageUrl: item.imageUrl,
                    httpHeaders: const {
                      'Referer': 'https://missav.ai/',
                      'User-Agent':
                          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    },
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
                  // 动态预览（如果有）：鼠标悬停/长按时切换到 data-preview 对应的预览序列帧
                  if (showPreview)
                    Positioned.fill(
                      child: CachedNetworkImage(
                        imageUrl: item.previewUrl!,
                        httpHeaders: const {
                          'Referer': 'https://missav.ai/',
                          'User-Agent':
                              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                        },
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.black12,
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) =>
                            const SizedBox(), // 加载失败时不显示错误图标，直接透出底图
                      ),
                    ),
                  // 视频时长：卡片右下角的小黑底时间条
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
                  // 预览图标：右上角的小播放图标，提示该卡片支持预览
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
