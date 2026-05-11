import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Typed exception hierarchy for HTTP failures. Each variant carries a
/// user-facing message so screens can render specific guidance instead of a
/// generic "Failed to fetch" string.
sealed class ApiException implements Exception {
  final String userMessage;
  final bool retry;
  const ApiException(this.userMessage, {this.retry = false});
  @override
  String toString() => '$runtimeType: $userMessage';
}

class ConfigurationException extends ApiException {
  const ConfigurationException(super.msg);
}

class RequestTimeoutException extends ApiException {
  const RequestTimeoutException()
      : super('Alfred took longer than usual to respond. Tap retry.',
            retry: true);
}

class ServerException extends ApiException {
  final int statusCode;
  const ServerException(this.statusCode, super.msg, {super.retry});
}

class NotFoundException extends ApiException {
  const NotFoundException(super.msg);
}

class NetworkException extends ApiException {
  const NetworkException()
      : super("Can't reach Alfred. Check your connection and try again.",
            retry: true);
}

/// Thin wrapper around `http` that centralises [BACKEND_URL] resolution,
/// timeouts, a single retry on transient browser-level fetch failures, and
/// mapping of raw errors to [ApiException] subclasses.
class ApiClient {
  ApiClient._();

  static String get backendUrl {
    final url = dotenv.env['BACKEND_URL'];
    if (url == null || url.isEmpty) {
      throw const ConfigurationException(
          'BACKEND_URL is not configured. The app cannot reach the server.');
    }
    return url;
  }

  static Uri _uri(String path) =>
      Uri.parse('$backendUrl${path.startsWith('/') ? path : '/$path'}');

  /// POST JSON to [path]. Returns the parsed JSON body on 2xx; throws an
  /// [ApiException] otherwise.
  static Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (bearer != null) headers['Authorization'] = 'Bearer $bearer';
    final encoded = jsonEncode(body);

    Future<http.Response> doRequest() => http
        .post(_uri(path), headers: headers, body: encoded)
        .timeout(timeout);

    http.Response response;
    try {
      response = await doRequest();
    } on TimeoutException {
      throw const RequestTimeoutException();
    } on http.ClientException {
      // Browser-level fetch failure — could be a transient blip. Retry once.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      try {
        response = await doRequest();
      } on TimeoutException {
        throw const RequestTimeoutException();
      } on http.ClientException {
        throw const NetworkException();
      }
    }

    return _decode(response);
  }

  static Map<String, dynamic> _decode(http.Response r) {
    final ct = (r.headers['content-type'] ?? '').toLowerCase();
    Map<String, dynamic> bodyJson = const {};
    if (ct.contains('application/json') && r.body.isNotEmpty) {
      try {
        final parsed = jsonDecode(r.body);
        if (parsed is Map<String, dynamic>) bodyJson = parsed;
      } catch (_) {
        // fall through — leave bodyJson empty
      }
    }

    if (r.statusCode >= 200 && r.statusCode < 300) return bodyJson;

    if (r.statusCode == 404) {
      throw NotFoundException(
        (bodyJson['detail'] is String)
            ? bodyJson['detail'] as String
            : 'Not found.',
      );
    }
    if (r.statusCode == 504) {
      // Our backend's structured gemini_timeout response.
      throw const RequestTimeoutException();
    }
    if (r.statusCode >= 500) {
      // 5xx is treated as retryable by default; the backend can opt out by
      // returning detail.retry == false explicitly.
      final detail = bodyJson['detail'];
      final retry = detail is Map ? detail['retry'] != false : true;
      throw ServerException(
        r.statusCode,
        'Alfred hit a temporary issue. Tap retry.',
        retry: retry,
      );
    }
    // 4xx other than 404 — usually a client bug, no retry.
    throw ServerException(r.statusCode, 'Request failed (${r.statusCode}).');
  }
}
