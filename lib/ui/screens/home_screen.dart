import 'package:docent/ui/screens/auth_screen.dart';
import 'package:docent/ui/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/game_state_notifier.dart';
import '../../models/game_state.dart';
import '../widgets/audio_visualizer.dart';
import 'results_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override





  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<GameState>(gameStateProvider, (previous, next) {
      if (next.status == GameStatus.gameOver && previous?.status != GameStatus.gameOver) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const ResultsScren()),
        );
      }
    });

    final gameState = ref.watch(gameStateProvider);
    final isListening = gameState.status == GameStatus.listening;
    final isProcessing = gameState.status == GameStatus.processing;
    final isSetup = gameState.status == GameStatus.setup || gameState.questionsList.isEmpty;
    final isGameOver = gameState.status == GameStatus.gameOver;
    final isReconnecting = gameState.status == GameStatus.reconnecting;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.white54),
          onPressed: () async {
            await ref.read(backendServiceProvider).logout();
            ref.read(gameStateProvider.notifier).resetGame();
            if (context.mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const AuthScreen()),
              );
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const DashboardScreen()),
              );
            },
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header Tracker
              if (!isSetup)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatChip(context, Icons.analytics, "Score: ${gameState.currentPercentage.toStringAsFixed(0)}%"),
                    _buildStatChip(context, Icons.quiz, "Q: ${gameState.currentQuestionIndex + 1}/${gameState.questionsList.length}"),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatChip(context, Icons.upload_file, "Brain Dump Mode"),
                  ],
                ),

              // AI Student Conversation Box
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    gameState.aiMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ),

              // Strikes Indicator for Current Question (Only during gameplay)
              if (!isSetup && !isGameOver)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Icon(
                          Icons.close,
                          color: index < gameState.currentQuestionStrikes 
                              ? Colors.redAccent 
                              : Colors.white24,
                          size: 24,
                        ),
                      );
                    }),
                  ),
                ),

              // Audio Waveform Visualizer Section
              AudioVisualizer(
                currentDecibels: gameState.currentDecibels,
                isListening: isListening,
              ),

              const SizedBox(height: 32),

              // Live User Captions
              AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: gameState.userTranscript.isNotEmpty ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsetsGeometry.symmetric(horizontal: 32.0),
                  child: Text(
                    '"${gameState.userTranscript}"',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Interaction Button
              Column(
                children: [
                  GestureDetector(
                    // Lock the button if processing or reconnecting
                    onTap: (isProcessing || isReconnecting)
                        ? null
                        : isGameOver
                            ? () => ref.read(gameStateProvider.notifier).resetGame()
                            : () => ref.read(gameStateProvider.notifier).toggleRecording(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isReconnecting 
                            ? Colors.orangeAccent // Warning color for dropped connection
                            : isGameOver
                                ? Colors.blueAccent
                                : isListening
                                    ? Colors.redAccent
                                    : Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (isReconnecting 
                                ? Colors.orangeAccent
                                : isGameOver 
                                    ? Colors.blueAccent 
                                    : isListening 
                                        ? Colors.redAccent 
                                        : Theme.of(context).colorScheme.primary)
                                .withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: isReconnecting
                          ? const Icon(Icons.wifi_off, size: 32, color: Colors.white)
                          : isProcessing
                              ? const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                )
                              : Icon(
                                  isGameOver 
                                      ? Icons.refresh 
                                      : isListening 
                                          ? Icons.stop 
                                          : Icons.mic,
                                  size: 32,
                                  color: Colors.white,
                              ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isReconnecting
                        ? "Reconnecting to server..." // New UI Text
                        : isGameOver
                            ? "Tap to start a new session"
                            : isListening
                                ? "Tap to submit"
                                : isProcessing
                                    ? "Processing audio..."
                                    : isSetup 
                                        ? "Tap to explain your topic" 
                                        : "Tap to unmute and explain",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF26213F)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}