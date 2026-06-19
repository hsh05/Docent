import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/audio_recorder_service.dart';
import '../services/audio_player_service.dart';
import '../services/backend_service.dart';
import '../models/game_state.dart';

// Provide the audio recorder service
final audioServiceProvider = Provider<AudioRecorderService>((ref) {
  final service = AudioRecorderService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Provide the audio player service
final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = AudioPlayerService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Provide the backend service
final backendServiceProvider = Provider<BackendService>((ref) {
  return BackendService();
});

// Provide the history service
final historyProvider = FutureProvider<List<SessionHistoryItem>>((ref) async {
  final backendService = ref.read(backendServiceProvider);
  return await backendService.getUserHistory(0); 
});

final weaknessProvider = FutureProvider<String>((ref) async {
  final backendService = ref.read(backendServiceProvider);
  return await backendService.fetchWeaknessInsight();
});

// Provide the game state notifier
final gameStateProvider = NotifierProvider<GameStateNotifier, GameState>(() {
  return GameStateNotifier();
});

final bottomNavProvider = StateProvider<int>((ref) => 0);

class GameStateNotifier extends Notifier<GameState> { 
  late AudioRecorderService _audioRecorder;
  late AudioPlayerService _audioPlayer;
  late BackendService _backendService;
  
  WebSocketChannel? _webSocketChannel;
  StreamSubscription? _micStreamSub;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  @override
  GameState build() {
    _audioRecorder = ref.read(audioServiceProvider);
    _audioPlayer = ref.read(audioPlayerServiceProvider);
    _backendService = ref.read(backendServiceProvider);
    
    // Clean up timers and streams when the provider is destroyed
    ref.onDispose(() {
      _reconnectTimer?.cancel();
      _micStreamSub?.cancel();
    });

    return GameState.initial();
  }

  // Toggle between starting and stopping
  Future<void> toggleRecording() async {
    await _audioPlayer.stopAudio();

    if (state.status == GameStatus.listening) {
      await stopListeningAndProcess();
    } else {
      await startListening();
    }
  }

  Future<void> startListening() async {
    state = state.copyWith(status: GameStatus.listening, currentDecibels: -60.0, userTranscript: "");

    if (state.sessionId == null) {
      // Phase 1: SETUP MODE (Uses standard file recording)
      await _audioRecorder.startRecording(
        onAmplitudeChanged: (db) {
          if (state.status == GameStatus.listening) {
            state = state.copyWith(currentDecibels: db);
          }
        },
      );
    } else {
      // Phase 2: ACTIVE GAMEPLAY (Uses WebSocket streaming)
      _webSocketChannel = _backendService.connectToSessionStream(state.sessionId!);
      _listenToWebSocket();

      final micStream = await _audioRecorder.startAudioStream(
        onAmplitudeChanged: (db) {
          if (state.status == GameStatus.listening) {
            state = state.copyWith(currentDecibels: db);
          }
        },
      );

      if (micStream != null) {
        _micStreamSub = micStream.listen((audioChunk) {
          _webSocketChannel?.sink.add(audioChunk);
        });
      }
    }
  }

  Future<void> stopListeningAndProcess() async {
    state = state.copyWith(
      status: GameStatus.processing,
      currentDecibels: -60.0,
    );

    if (state.sessionId == null) {
      // Phase 1: SETUP MODE END (Upload file to REST API)
      state = state.copyWith(aiMessage: "Preparing questions...");
      final audioPath = await _audioRecorder.stopRecording();

      if (audioPath != null) {
        final setupData = await _backendService.startSession(audioPath);

        if (setupData != null && setupData.questions.isNotEmpty) {
          String firstQuestion = setupData.questions[0];
          String startMessage = "Okay, I've got my notes ready. First question: $firstQuestion";

          state = state.copyWith(
            status: GameStatus.questioning,
            sessionId: setupData.sessionId,
            questionsList: setupData.questions,
            currentQuestionIndex: 0,
            aiMessage: startMessage,
          );
        } else {
          state = state.copyWith(
            status: GameStatus.setup,
            aiMessage: "I couldn't quite catch that. Could you summarize the topic again?",
          );
        }
      } else {
        state = state.copyWith(status: GameStatus.idle, aiMessage: "Oops, microphone error. Try again.");
      }
      
    } else {
      // Phase 2: ACTIVE GAMEPLAY END (Close pipes, wait for AI stream)
      state = state.copyWith(aiMessage: "Thinking...");
      
      await _micStreamSub?.cancel();
      await _audioRecorder.stopRecording(); 
      await _webSocketChannel?.sink.close();
      
      // Keep status as questioning so the UI knows to render the AI's streaming response
      state = state.copyWith(status: GameStatus.questioning);
    }
  }

  void _listenToWebSocket() {
    _webSocketChannel?.stream.listen(
      (message) {
        _reconnectAttempts = 0;

        if (message is String) {
          final data = jsonDecode(message);
          if (data['event'] == 'user_transcript') {
            // Render the user's captions live
            state = state.copyWith(userTranscript: data['text']);
          } else if (data['event'] == 'ai_transcript_delta') {
            // Clear the "Thinking..." text on the first word, then append
            final currentMsg = state.aiMessage == "Thinking..." ? "" : state.aiMessage;
            state = state.copyWith(aiMessage: currentMsg + data['text']);
          }
        } else {
          // Stream the raw audio bytes through the speaker
          _audioPlayer.playStreamBytes(message as Uint8List);
        }
      },
      onDone: () => _handleDisconnect(),
      onError: (err) => _handleDisconnect(),
      cancelOnError: true,
    );
  }

  void _handleDisconnect() {
    if (state.status == GameStatus.gameOver || state.sessionId == null) return;

    _audioRecorder.stopRecording();
    _micStreamSub?.cancel();

    state = state.copyWith(
      status: GameStatus.reconnecting,
      aiMessage: "Connection Lost. Attempting to reconnect...",
      currentDecibels: -60.0,
    );

    _attemptReconnect();
  }

  void _attemptReconnect() {
    if (_reconnectAttempts >= 5) {
      state = state.copyWith(
        status: GameStatus.idle,
        aiMessage: "Connection completely failed. Please check your WI-Fi and restart the session."
      );
      return;
    }

    _reconnectTimer?.cancel();

    final waitTime = Duration(seconds: 2 * (_reconnectAttempts + 1));

    _reconnectTimer = Timer(waitTime, () {
      _reconnectAttempts++;

      try {
        // Fixed: Added the ! operator to state.sessionId
        _webSocketChannel = _backendService.connectToSessionStream(state.sessionId!);
        _listenToWebSocket();

        state = state.copyWith(
          status: GameStatus.questioning,
          aiMessage: "Reconnected! Where were we?",
        );
      } catch (e) {
        _handleDisconnect();
      }
    });
  }

  void resetGame() {
    state = GameState.initial();
  }

  void startReviewSession(int sessionId, List<String> questions) {
    state = state.copyWith(
      status: GameStatus.listening,
      sessionId: sessionId,
      questionsList: questions,
      currentQuestionIndex: 0,
      currentQuestionStrikes: 0,
      correctAnswers: 0,
      score: 0,
      answerResults: [],
      aiMessage: questions.isNotEmpty ? questions.first : "No questions found.",
    );
  }
}