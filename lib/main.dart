import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ui/screens/home_screen.dart';
import 'ui/screens/auth_screen.dart';
import 'state/game_state_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  runApp(
    const ProviderScope(
      child: DocentApp(),
    ),
  );
}

class DocentApp extends StatelessWidget {
  const DocentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Docent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0C1B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C4DFF),
          secondary: Color(0xFF3E00FF),
          surface: Color(0xFF1A1628),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFE2E1E6)),
          bodyMedium: TextStyle(color: Color(0xFFA5A2B0)),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await ref.read(backendServiceProvider).loadToken();

    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'auth_token');

    if (mounted) {
      setState(() {
        _isAuthenticated = token != null;
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7C4DFF)),
        ),
      );
    }

    return _isAuthenticated ? const HomeScreen() : const AuthScreen();
  }
}
