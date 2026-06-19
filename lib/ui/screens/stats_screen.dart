import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/game_state_notifier.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsyncValue = ref.watch(historyProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text("Your Progress"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: historyAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text("Failed to load history: $err"),
              TextButton(
                onPressed: () => ref.refresh(historyProvider),
                child: const Text("Retry"),
              )
            ],
          ),
        ),
        data: (historyData) {
          if (historyData.isEmpty) {
            return const Center(
              child: Text("No study sessions yet. Start talking!"),
            );
          }

          // Calculate aggregate stats
          final totalSessions = historyData.length;
          final double averageScore = historyData.fold(0.0, (sum, item) => sum + item.score) / totalSessions;

          return RefreshIndicator(
            onRefresh: () async {
              // Refresh both providers when the user pulls down
              ref.refresh(historyProvider);
              ref.refresh(weaknessProvider);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                
                // ==========================================
                // 1. THE MACRO VIEW: Aggregate Accuracy Stats
                // ==========================================
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: _buildOverviewCard(context, totalSessions, averageScore),
                  ),
                ),

                // ==========================================
                // 2. THE DIAGNOSTIC VIEW: ML Weakness Clustering
                // ==========================================
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 24.0),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome, 
                                color: Theme.of(context).colorScheme.secondary, 
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                "AI Diagnostic Insight",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          
                          // Dynamically load the clustering result
                          ref.watch(weaknessProvider).when(
                            loading: () => const LinearProgressIndicator(),
                            error: (err, stack) => const Text("Unable to run diagnostic clustering."),
                            data: (insight) => Text(
                              insight,
                              style: const TextStyle(fontSize: 14, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ==========================================
                // 3. THE MICRO VIEW: Individual Past Sessions
                // ==========================================
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final session = historyData[index];
                        return _buildSessionTile(context, session);
                      },
                      childCount: historyData.length,
                    ),
                  ),
                ),
                
                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),

                // ==========================================
                // 4. THE ACTION VIEW: Daily Review Button
                // ==========================================
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Analyzing your weak points..."),
                              duration: Duration(seconds: 1)
                            ),
                          );

                          final backend = ref.read(backendServiceProvider);
                          final response = await backend.fetchDailyReview();

                          if (!context.mounted) return;

                          if (response['session_id'] == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("You're all caught up! No failed concepts to review today."),
                                backgroundColor: Color(0xFF4A148C),
                              ),
                            );
                          } else {
                            ref.read(gameStateProvider.notifier).startReviewSession(
                              response['session_id'],
                              List<String>.from(response['questions']),
                            );

                            ref.read(bottomNavProvider.notifier).state = 0;
                          }
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Error: Could not load review. $e"),
                              backgroundColor: Colors.redAccent
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.psychology, color: Colors.white),
                      label: const Text(
                        "Start Daily Review",
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D0C5E),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // The top summary card
  Widget _buildOverviewCard(BuildContext context, int totalSessions, double averageScore) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withOpacity(0.7)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statColumn("Sessions", totalSessions.toString(), Colors.white),
          _statColumn("Avg Accuracy", "${averageScore.toStringAsFixed(1)}%", Colors.white),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: color.withOpacity(0.8)),
        ),
      ],
    );
  }

  // Individual past session rows
  Widget _buildSessionTile(BuildContext context, session) {
    // Color code the score: Green for >= 80%, Orange for 50-79%, Red for < 50%
    final scoreColor = session.score >= 80 
        ? Colors.greenAccent 
        : session.score >= 50 
            ? Colors.orangeAccent 
            : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          // Circular Score Indicator
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  value: session.score / 100,
                  backgroundColor: Colors.white.withOpacity(0.05),
                  color: scoreColor,
                  strokeWidth: 4,
                ),
              ),
              Text(
                "${session.score.toInt()}%",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(width: 16),
          
          // Topic and Date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.date,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  session.topicPreview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}