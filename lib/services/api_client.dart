import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiClient {
  static String get _baseUrl {
    // Try --dart-define first, fallback to .env
    const dartDefineUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    final envUrl = dotenv.env['API_BASE_URL'];
    final url = dartDefineUrl.isNotEmpty ? dartDefineUrl : (envUrl ?? 'http://localhost:8080');
    return url;
  }
  
  static const String _tokenKey = 'seeknirvana_jwt_token';
  
  String? _jwtToken;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _jwtToken = prefs.getString(_tokenKey);
  }

  Future<void> setToken(String? token) async {
    _jwtToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

  String? get token => _jwtToken;
  bool get isAuthenticated => _jwtToken != null;

  Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    if (_jwtToken != null) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }
    return headers;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final url = Uri.parse('$_baseUrl$path');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Request timeout - server not responding'),
      );
      return _processResponse(response);
    } on Exception catch (e) {
      debugPrint('[ApiClient] Error POST $path: $e');
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> get(String path) async {
    final url = Uri.parse('$_baseUrl$path');
    try {
      final response = await http.get(url, headers: _headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Request timeout - server not responding'),
      );
      return _processResponse(response);
    } on Exception catch (e) {
      debugPrint('[ApiClient] Error GET $path: $e');
      throw _handleError(e);
    }
  }

  Exception _handleError(Exception e) {
    final errorString = e.toString();
    if (errorString.contains('Connection refused') || errorString.contains('SocketException')) {
      return Exception('Cannot connect to authentication server. Please check your internet connection or try again later.');
    }
    if (errorString.contains('timeout')) {
      return Exception('Server is taking too long to respond. Please try again later.');
    }
    return e;
  }

  Map<String, dynamic> _processResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('API Error ${response.statusCode}: ${response.body}');
    }
  }
}
