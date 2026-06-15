import 'dart:async';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class AudioRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSubscription;


  Future <void> startRecording({
    required Function(double db) onAmplitudeChanged,
  }) async {
    try {
      // Request hardware permissions
      if (await _audioRecorder.hasPermission()) {
        // Get a safe temp directory
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/docent_explanation.m4a';

        // Start the hardware recording
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
          ),
          path: filePath,
        );

        _amplitudeSubscription = _audioRecorder
            .onAmplitudeChanged(const Duration(milliseconds: 50))
            .listen((amplitude) {
              onAmplitudeChanged(amplitude.current);
            });
      }
    } catch (e) {
      print("Error starting recorder: $e");
    }
  }

  Future<String?> stopRecording() async {
    try {
      // Stop listening
      _amplitudeSubscription?.cancel();
      
      // Stop the hardware and get the file path
      final path = await _audioRecorder.stop();
      return path;
    } catch (e) {
      print("Error stopping recorder: $e");
      return null;
    }
  }

  void dispose() {
    _amplitudeSubscription?.cancel();
    _audioRecorder.dispose();
  }
}