import 'package:flutter/material.dart';
import '../../services/backend_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final BackendService _backendService = BackendService();
  List<SessionHistoryItem> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    // TODO: chage from hardcoded to dynamic
    final history = await _backendService.getUserHistory(1);
    setState(() {
      _history = history;
      _isLoading = false;
    });
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C4DFF)))
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
                        width: 1.5
                      ),
                      boxShadow: isPass ? [
                        BoxShadow(
                          color: const Color(0xFF7C4DFF).withOpacity(0.15),
                          blurRadius: 10,
                          spreadRadius: 1,
                        )
                      ] : [],
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
                          style: const TextStyle(color: Colors.white70, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              isPass ? Icons.check_circle : Icons.refresh,
                              size: 16,
                              color: isPass ? Colors.greenAccent : Colors.orangeAccent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "${item.passed} of ${item.total} concepts mastered",
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        )
                      ],
                    ),
                  );
                },
              ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_edu, size: 64, color: Colors.white24),
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