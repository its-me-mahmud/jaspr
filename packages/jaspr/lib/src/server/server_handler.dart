import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hotreloader/hotreloader.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_gzip/shelf_gzip.dart';
import 'package:shelf_proxy/shelf_proxy.dart';
import 'package:shelf_static/shelf_static.dart';

import '../../server.dart';
import 'server_renderer.dart';

const String kDevProxy = String.fromEnvironment('jaspr.dev.proxy');
const bool kDevHotreload = bool.fromEnvironment('jaspr.dev.hotreload');

/// A [Handler] that can be refreshed to update any used resources
class RefreshableHandler {

  final Handler _handler;
  final void Function()? onRefresh;

  RefreshableHandler(this._handler, {this.onRefresh});

  void refresh() {
    if (_handler is RefreshableHandler) {
      (_handler as RefreshableHandler).refresh();
    }
    if (onRefresh != null) {
      onRefresh!();
    }
  }

  FutureOr<Response> call(Request request) => _handler(request);
}


FutureOr<Response> Function(Request, String) _proxyFileLoader(Handler proxyHandler) {
  return (Request req, String fileName) {
    final indexRequest = Request('GET', req.requestedUri.replace(path: '/$fileName'),
        context: req.context, encoding: req.encoding, headers: req.headers, protocolVersion: req.protocolVersion);
    return proxyHandler(indexRequest);
  };
}

// coverage:ignore-start

Handler _webdevProxyHandler(String port) {
  var client = http.Client();
  var handler = proxyHandler('http://localhost:$port/', client: client);
  return RefreshableHandler((Request req) async {
    var res = await handler(req);
    if (res.statusCode == 200 && res.headers['content-type'] == 'application/javascript') {
      var body = await res.readAsString();
      res = res.change(body: body.replaceAll('http://localhost:$port/', ''));
    }
    return res;
  }, onRefresh: () {
    client.close();
    client = http.Client();
    handler = proxyHandler('http://localhost:$port/', client: client);
  });
}

String _sseHeaders(String? origin) => 'HTTP/1.1 200 OK\r\n'
    'Content-Type: text/event-stream\r\n'
    'Cache-Control: no-cache\r\n'
    'Connection: keep-alive\r\n'
    'Access-Control-Allow-Credentials: true\r\n'
    'Access-Control-Allow-Origin: $origin\r\n'
    '\r\n';

Handler _sseProxyHandler(Uri proxyUri, Uri serverUri) {
  Handler? _incomingMessageProxyHandler;
  var _httpClient = http.Client();

  Future<Response> _createSseConnection(Request req, String path) async {
    final serverReq = http.StreamedRequest(req.method, serverUri.replace(query: req.requestedUri.query))
      ..followRedirects = false
      ..headers.addAll(req.headers)
      ..headers['Host'] = serverUri.authority
      ..sink.close();

    final serverResponse = await _httpClient.send(serverReq);

    req.hijack((channel) {
      final sink = utf8.encoder.startChunkedConversion(channel.sink)..add(_sseHeaders(req.headers['origin']));

      StreamSubscription? serverSseSub;
      StreamSubscription? reqChannelSub;

      serverSseSub = utf8.decoder.bind(serverResponse.stream).listen(sink.add, onDone: () {
        reqChannelSub?.cancel();
        sink.close();
      });

      reqChannelSub = channel.stream.listen((_) {
        // SSE is unidirectional.
      }, onDone: () {
        serverSseSub?.cancel();
        sink.close();
      });
    });
  }

  Future<Response> _handleIncomingMessage(Request req) async {
    _incomingMessageProxyHandler ??= proxyHandler(
      serverUri,
      client: _httpClient,
    );
    return _incomingMessageProxyHandler!(req);
  }

  return (Request req) async {
    var path = req.url.path;
    if (!path.startsWith('/')) path = '/$path';
    if (path != proxyUri.path) {
      return Response.notFound('');
    }

    if (req.headers['accept'] == 'text/event-stream' && req.method == 'GET') {
      return _createSseConnection(req, path);
    }

    if (req.headers['accept'] != 'text/event-stream' && req.method == 'POST') {
      return _handleIncomingMessage(req);
    }

    return Response.notFound('');
  };
}

// coverage:ignore-end

final staticFileHandler = kDevProxy.isNotEmpty
    ? _webdevProxyHandler(kDevProxy)
    : createStaticHandler(join(dirname(Platform.script.path), 'web'), defaultDocument: 'index.html');

typedef _SetupHandler = FutureOr<Response> Function(Request, FutureOr<Response> Function(SetupFunction setup));

Handler createHandler(_SetupHandler handle, {List<Middleware> middleware = const [], Handler? fileHandler}) {
  var staticHandler = fileHandler ?? staticFileHandler;

  var cascade = Cascade();

  if (kDevProxy.isNotEmpty) {
    final serverUri = Uri.parse('http://localhost:$kDevProxy');
    final serverSseUri = serverUri.replace(path: r'/$dwdsSseHandler');
    final sseUri = Uri.parse(r'/$dwdsSseHandler');

    cascade = cascade.add(_sseProxyHandler(sseUri, serverSseUri));
  }

  var fileLoader = _proxyFileLoader(staticHandler);
  cascade = cascade.add(gzipMiddleware(staticHandler)).add((request) async {
    return handle(request, (setup) => renderApp(setup, request, (name) async {
      var response = await fileLoader(request, name);
      return response.readAsString();
    }));
  });

  var pipeline = const Pipeline();
  for (var m in middleware) {
    pipeline = pipeline.addMiddleware(m);
  }

  return RefreshableHandler(pipeline.addHandler(cascade.handler), onRefresh: () {
    if (staticHandler is RefreshableHandler) {
      (staticHandler as RefreshableHandler).refresh();
    }
  });
}
