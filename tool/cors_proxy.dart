import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8082);
  // ignore: avoid_print
  print('CORS proxy listening on http://${server.address.address}:${server.port}');
  server.autoCompress = false;
  await for (final req in server) {
    final path = req.uri.path;
    if (req.method == 'OPTIONS') {
      _writeCors(req.response, status: HttpStatus.noContent);
      await req.response.close();
      continue;
    }
    if (!path.startsWith('/proxy/')) {
      _writeCors(req.response, status: HttpStatus.notFound);
      await req.response.close();
      continue;
    }
    try {
      final tail = path.substring('/proxy/'.length);
      final firstSlash = tail.indexOf('/');
      if (firstSlash <= 0) {
        _writeCors(req.response, status: HttpStatus.badRequest);
        await req.response.close();
        continue;
      }
      final scheme = tail.substring(0, firstSlash);
      final rest = tail.substring(firstSlash + 1);
      final target = Uri.parse('$scheme://$rest${req.uri.hasQuery ? '?${req.uri.query}' : ''}');

      final client = HttpClient();
      client.autoUncompress = false;
      final upstream = await client.openUrl(req.method, target);
      req.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'host') return;
        for (final v in values) {
          upstream.headers.add(name, v);
        }
      });
      if (req.method != 'GET' && req.method != 'HEAD') {
        final body = await req.fold<List<int>>(<int>[], (p, e) => p..addAll(e));
        upstream.add(body);
      }
      final upsResp = await upstream.close();
      req.response.statusCode = upsResp.statusCode;
      upsResp.headers.forEach((name, values) {
        if (name.toLowerCase() == 'access-control-allow-origin') return;
        for (final v in values) {
          req.response.headers.add(name, v);
        }
      });
      _writeCors(req.response);
      await upsResp.pipe(req.response);
    } catch (e) {
      // ignore: avoid_print
      print('Proxy error: $e');
      _writeCors(req.response, status: HttpStatus.badGateway);
      req.response.write(jsonEncode({'error': 'proxy_failed'}));
      await req.response.close();
    }
  }
}

void _writeCors(HttpResponse resp, {int status = HttpStatus.ok}) {
  resp.statusCode = status;
  resp.headers.set('Access-Control-Allow-Origin', '*');
  resp.headers.set('Access-Control-Allow-Methods', 'GET,HEAD,OPTIONS');
  resp.headers.set('Access-Control-Allow-Headers', '*');
  resp.headers.set('Access-Control-Expose-Headers', '*');
  resp.headers.set('Timing-Allow-Origin', '*');
}
