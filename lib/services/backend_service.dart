import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SessionSetupResponse {
  final int sessionId;
  final List<String> questions;

  SessionSetupResponse({required this.sessionId, required this.questions});
}

class StudentEvaluation {
  final String dialogue;
  final bool isAccurate;
  final String audioPath;

  StudentEvaluation({required this.dialogue, required this.isAccurate, required this.audioPath});
}

class SessionHistoryItem {
  final int sessionId;
  final String date;
  final String topicPreview;
  final double score;
  final int passed;
  final int total;

  SessionHistoryItem({
    required this.sessionId,
    required this.date,
    required this.topicPreview,
    required this.score,
    required this.passed,
    required this.total,
  });

  factory SessionHistoryItem.fromJson(Map<String, dynamic> json) {
    return SessionHistoryItem(
      sessionId: json['session_id'],
      date: json['date'],
      topicPreview: json['topic_preview'],
      score: (json['score'] as num).toDouble(),
      passed: json['passed'],
      total: json['total'],
    );
  }
}

class BackendService {
  final String _baseUrl = 'https://docent-um0q.onrender.com/api';
  final String _wsBaseUrl = 'wss://docent-um0q.onrender.com/api';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _token;

  Future<void> loadToken() async {
    _token = await _storage.read(key: 'auth_token');
  }

  Future<void> logout() async {
    _token = null;
    await _storage.delete(key: 'auth_token');
  }

  Future<String?> register(String username, String password) async {
    try {
      var response = await http.post(
        Uri.parse('$_baseUrl/auth/register'),
        body: {'username': username, 'password': password},
      );
      
      if (response.statusCode == 201) {
        return null;
      } else {
        return "Error ${response.statusCode} : ${response.body}";
      }
    } catch (e) {
      return "Connection Error: $e";
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      var response = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        body: {'username': username, 'password': password},
      );

      if (response.statusCode == 200) {
        var jsonResponse = json.decode(response.body);
        _token = jsonResponse['access_token'];
        await _storage.write(key: 'auth_token', value: _token);
        return true;
      }
      return false;
    } catch (e) {
      print("Login Error: $e");
      return false;
    }
  }

  Future<SessionSetupResponse?> startSession(String audioFilePath) async {
    if (_token == null) return null;

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/sessions/start'));
      request.headers['Authorization'] = 'Bearer $_token';
      request.files.add(await http.MultipartFile.fromPath('audio_file', audioFilePath));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        var jsonResponse = json.decode(responseData);
        List<dynamic> dynamicList = jsonResponse['questions'] ?? [];
        
        return SessionSetupResponse(
          sessionId: jsonResponse['session_id'],
          questions: dynamicList.map((e) => e.toString()).toList(),
        );
      } else {
        print("Backend Setup Error: $responseData");
        return null;
      }
    } catch (e) {
      print("Connection Error: $e");
      return null;
    }
  }

  Future<StudentEvaluation?> evaluateAnswer(int sessionId, String currentQuestion, String audioFilePath) async {
    if (_token == null) return null;
    
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/sessions/evaluate'));
      request.headers['Authorization'] = 'Bearer $_token';
      request.fields['session_id'] = sessionId.toString();
      request.fields['current_question'] = currentQuestion;
      request.files.add(await http.MultipartFile.fromPath('audio_file', audioFilePath));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        var jsonResponse = json.decode(responseData);
        String base64Audio = jsonResponse['audio_base64'];
        var audioBytes = base64Decode(base64Audio);

        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/ai_response_${DateTime.now().millisecondsSinceEpoch}.mp3');
        await file.writeAsBytes(audioBytes);

        return StudentEvaluation(
          dialogue: jsonResponse['dialogue'] ?? "I'm a bit lost.",
          isAccurate: jsonResponse['is_accurate'] ?? false,
          audioPath: file.path,
        );
      } else {
        print("Backend Evaluation Error: $responseData");
        return null;
      }
    } catch (e) {
      print("Connection Error: $e");
      return null;
    }
  }

  Future<List<SessionHistoryItem>> getUserHistory(int userId) async {
    if (_token == null) return [];
    
    try {
      var response = await http.get(
        Uri.parse('$_baseUrl/users/history'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        var jsonResponse = json.decode(response.body);
        List<dynamic> historyList = jsonResponse['history'] ?? [];
        return historyList.map((item) => SessionHistoryItem.fromJson(item)).toList();
      } else {
        print("Failed to fetch history: ${response.body}");
        return [];
      }
    } catch (e) {
      print("Connection Error: $e");
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchDailyReview() async {
    if (_token == null) throw Exception('No authentication token found');

    final response = await http.get(
      Uri.parse('$_baseUrl/sessions/daily-review'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch daily review');
    }
  }

  Future<String> fetchWeaknessInsight() async {
    if (_token == null) return "Keep studying to unlock insights.";

    try {
      var response = await http.get(
        Uri.parse('$_baseUrl/users/weakness-insight'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        var jsonResponse = json.decode(response.body);
        return jsonResponse['insight'] ?? "Keep studying to unlock insights.";
      }
      return "Data processing error.";
    } catch (e) {
      return "Connection error.";
    }
  }

  Future<String?> wakeUpServer() async {
    String lastError = "Unknown network error";

    for (int i = 0; i < 3; i++) {
      try {
        var response = await http
            .get(Uri.parse('$_baseUrl/health'))
            .timeout(const Duration(seconds: 60));

        if (response.statusCode != 502 && response.statusCode != 503) {
          return null;
        } else {
          lastError = "Server Error: ${response.statusCode}";
        }
      } catch (e) {
        lastError = "Network Crash: $e";
      }

      await Future.delayed(const Duration(seconds: 2));
    }

    return lastError;
  }

  WebSocketChannel connectToSessionStream(int sessionId) {
    final wsUrl = Uri.parse('$_wsBaseUrl/sessions/$sessionId/stream');

    return WebSocketChannel.connect(
      wsUrl,
    );
  }
}