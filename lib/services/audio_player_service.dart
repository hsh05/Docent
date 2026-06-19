import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class AudioPlayerService {
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> playAudio(String filePath) async {
    try {
      await _audioPlayer.play(DeviceFileSource(filePath));
    } catch (e) {
      print("Error playing audio: $e");
    }
  }

  Future<void> stopAudio() async {
    await _audioPlayer.stop();
  }

  Future<void> playStreamBytes(Uint8List bytes) async {
    try {
      await stopAudio();

      await _audioPlayer.play(BytesSource(bytes));
    } catch (e) {
      print("Error playing stream bytes: $e");
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}