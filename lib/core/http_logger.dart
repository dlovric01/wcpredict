import 'package:http/http.dart' as http;

import 'logger.dart';

/// [http.BaseClient] that logs every outgoing request and its response to
/// [talker].
///
/// Plugged into [Supabase.initialize] via the `httpClient` parameter so every
/// Supabase REST / Auth / Storage call is visible in the Talker log.
///
/// Sensitive headers (Authorization, apikey) are stripped before logging so
/// credentials never appear in the ring-buffer.
class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  static const _redacted = {'authorization', 'apikey'};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sw = Stopwatch()..start();
    final label = '${request.method} ${_path(request.url)}';

    talker.info('[HTTP →] $label');

    try {
      final response = await _inner.send(request);
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      final status = response.statusCode;

      if (status >= 500) {
        talker.error('[HTTP ←] $status $label (${ms}ms)');
      } else if (status >= 400) {
        talker.warning('[HTTP ←] $status $label (${ms}ms)');
      } else {
        talker.info('[HTTP ←] $status $label (${ms}ms)');
      }

      return response;
    } catch (e, st) {
      sw.stop();
      talker.error('[HTTP ✗] $label (${sw.elapsedMilliseconds}ms)', e, st);
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  /// Returns path + query, never the scheme/host (those are in the Supabase URL
  /// config and add noise), and never auth credentials.
  static String _path(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (uri.query.isEmpty) return path;
    // Filter any credential-looking query params just in case.
    final filtered = uri.queryParameters.entries
        .where((e) => !_redacted.contains(e.key.toLowerCase()))
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    return filtered.isEmpty ? path : '$path?$filtered';
  }
}
