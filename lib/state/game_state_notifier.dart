import 'package:flutter_riverpod/flutter_riverpod.dart';
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

// Provide the OpenAI service
final backendServiceProvider = Provider<BackendService>((ref) {
  return BackendService();
});

// Provide the game state notifier
final gameStateProvider = NotifierProvider<GameStateNotifier, GameState>(() {
  return GameStateNotifier();
});

class GameStateNotifier extends Notifier<GameState> {
  late AudioRecorderService _audioRecorder;
  late AudioPlayerService _audioPlayer;
  late BackendService _backendService;

  @override
  GameState build() {
    _audioRecorder = ref.read(audioServiceProvider);
    _audioPlayer = ref.read(audioPlayerServiceProvider);
    _backendService = ref.read(backendServiceProvider);
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
    state = state.copyWith(status: GameStatus.listening, currentDecibels: -60.0);

    await _audioRecorder.startRecording(
      onAmplitudeChanged: (db) {
        if (state.status == GameStatus.listening) {
          state = state.copyWith(currentDecibels: db);
        }
      },
    );
  }

  Future<void> stopListeningAndProcess() async {
    state = state.copyWith(
      status: GameStatus.processing,
      currentDecibels: -60.0,
      aiMessage: state.questionsList.isEmpty
          ? "Preparing questions..."
          : "Thinking...",
    );

    final audioPath = await _audioRecorder.stopRecording();

    if (audioPath != null) {
      // Setup
      if (state.questionsList.isEmpty) {
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
        return;
      }

      // Active Gameplay
      final activeQuestion = state.questionsList[state.currentQuestionIndex];
      final evaluation = await _backendService.evaluateAnswer(state.sessionId!, activeQuestion, audioPath);

      if (evaluation != null) {
        bool moveOnToNext = false;
        int nextStrikes = evaluation.isAccurate ? 0 : state.currentQuestionStrikes + 1;
        int nextCorrect = evaluation.isAccurate ? state.correctAnswers + 1 : state.correctAnswers;
        String nextAiMessage = evaluation.dialogue;

        List<bool> nextResults = List.from(state.answerResults);

        if (evaluation.isAccurate) {
          moveOnToNext = true;
          nextResults.add(true);
        } else if (nextStrikes >= 3) {
          moveOnToNext = true;
          nextResults.add(false);
          nextAiMessage = "I'm just not getting this part. Let's skip it and move to the next topic.";
        }

        int nextIndex = state.currentQuestionIndex;
        if (moveOnToNext) {
          nextIndex++;
          nextStrikes = 0;
        }

        if (nextIndex >= state.questionsList.length) {
          double finalPercentage = (nextCorrect / state.questionsList.length) * 100;

          if (finalPercentage >= 60.0) {
            nextAiMessage = "Wow, I actually get it now! You're an amazing teacher!";
          } else {
            nextAiMessage = "I appreciate you trying to explain all of this, but honestly, I'm still really confused.";
          }

          state = state.copyWith(
            status: GameStatus.gameOver,
            aiMessage: nextAiMessage,
            correctAnswers: nextCorrect,
            currentQuestionStrikes: nextStrikes,
            currentQuestionIndex: nextIndex,
            answerResults: nextResults,
          );
        } else {
          if (moveOnToNext) {
            nextAiMessage += " Okay, next question: ${state.questionsList[nextIndex]}";
          }

          state = state.copyWith(
            status: GameStatus.questioning,
            aiMessage: nextAiMessage,
            correctAnswers: nextCorrect,
            currentQuestionStrikes: nextStrikes,
            currentQuestionIndex: nextIndex,
            answerResults: nextResults,
            score: state.score + (evaluation.isAccurate ? 25 : 0),
          );
        }

        await _audioPlayer.playAudio(evaluation.audioPath);

      } else {
        // Fallback for API failure
        state = state.copyWith(status: GameStatus.idle, aiMessage: "I had trouble understanding that. Could you repeat?");
      }
    } else {
      // Fallback for Mic failure
      state = state.copyWith(status: GameStatus.idle, aiMessage: "Oops, microphone error. Try again.");
    }
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