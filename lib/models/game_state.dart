enum GameStatus {
  setup,
  idle,
  listening,
  processing,
  questioning,
  gameOver
}

class GameState {
  final GameStatus status;
  final int? sessionId;
  final double currentDecibels;
  final int score;
  final int currentQuestionStrikes;
  final int correctAnswers;
  final int currentQuestionIndex;
  final List<String> questionsList;
  final List<bool> answerResults;
  final String aiMessage;

  const GameState({
    required this.status,
    this.sessionId,
    required this.currentDecibels,
    required this.score,
    required this.currentQuestionStrikes,
    required this.correctAnswers,
    required this.currentQuestionIndex,
    required this.questionsList,
    required this.answerResults,
    required this.aiMessage,
  });

  factory GameState.initial() {
    return const GameState(
      status: GameStatus.setup,
      sessionId: null,
      currentDecibels: -60.0,
      score: 0,
      currentQuestionStrikes: 0,
      correctAnswers: 0,
      currentQuestionIndex: 0,
      questionsList: [],
      answerResults: [],
      aiMessage: "Ready to learn! What are we studying today?",
    );
  }

  // Calculate percentage
  double get currentPercentage =>
      questionsList.isEmpty ? 0.0 : (correctAnswers / questionsList.length) * 100;

  GameState copyWith({
    GameStatus? status,
    int? sessionId,
    double? currentDecibels,
    int? score,
    int? currentQuestionStrikes,
    int? correctAnswers,
    int? currentQuestionIndex,
    List<String>? questionsList,
    List<bool>? answerResults,
    String? aiMessage,
  }) {
    return GameState(
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      currentDecibels: currentDecibels ?? this.currentDecibels,
      score: score ?? this.score,
      currentQuestionStrikes: currentQuestionStrikes ?? this.currentQuestionStrikes,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      currentQuestionIndex: currentQuestionStrikes ?? this.currentQuestionIndex,
      questionsList: questionsList ?? this.questionsList,
      answerResults: answerResults ?? this.answerResults,
      aiMessage: aiMessage ?? this.aiMessage,
    );
  }
}