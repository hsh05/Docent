import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/backend_service.dart';
import '../../state/game_state_notifier.dart';
import 'home_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final BackendService _backendService = BackendService();
  List<SessionHistoryItem> _history = [];
  bool _isLoading = true;
  bool _isLoadingReview = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    // TODO: change from hardcoded to dynamic
    final history = await _backendService.getUserHistory(1);
    setState(() {
      _history = history;
      _isLoading = false;
    });
  }

  Future<void> _handleDailyReview() async {
    setState(() {
      _isLoadingReview = true;
    });

    try {
      final response = await _backendService.fetchDailyReview();

      if (!mounted) return;

      if (response['session_id'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "You're all caught up! No failed concepts to review today.",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF4A148C),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ref.read(gameStateProvider.notifier).startReviewSession(
          response['session_id'],
          List<String>.from(response['questions']),
        );

        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: Could not load review. $e"),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingReview = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C1B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Learning History",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF7C4DFF)))
                : _history.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(24.0),
                        itemCount: _history.length,
                        itemBuilder: (context, index) {
                          final item = _history[index];
                          final isPass = item.score >= 60.0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1628),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: isPass
                                      ? const Color(0xFF7C4DFF).withOpacity(0.5)
                                      : Colors.white10,
                                  width: 1.5),
                              boxShadow: isPass
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF7C4DFF)
                                            .withOpacity(0.15),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : [],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      item.date,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      "${item.score.toStringAsFixed(0)}%",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isPass ? Colors.white : Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  item.topicPreview,
                                  style: const TextStyle(
                                      color: Colors.white70, height: 1.4),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(
                                      isPass
                                          ? Icons.check_circle
                                          : Icons.refresh,
                                      size: 16,
                                      color: isPass
                                          ? Colors.greenAccent
                                          : Colors.orangeAccent,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "${item.passed} of ${item.total} concepts mastered",
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          );
                        },
                      ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0C1B),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -10),
                )
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isLoadingReview ? null : _handleDailyReview,
                    icon: _isLoadingReview
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(Icons.psychology, color: Colors.white),
                    label: Text(
                      _isLoadingReview
                          ? "Analyzing Weak Points..."
                          : "Start Daily Review",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D0C5E),
                      disabledBackgroundColor:
                          const Color(0xFF2D0C5E).withOpacity(0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO: Navigate to your recording/new topic screen
                    },
                    icon: const Icon(Icons.mic, color: Colors.white),
                    label: const Text(
                      "Brain Dump New Topic",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2D0C5E), width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.history_edu, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            "No sessions yet.",
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            "Start a brain dump to see your history here.",
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }
}