import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  String lastInstruction = "";

  TtsService() {
    _flutterTts.setLanguage("en-US");
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setVolume(1.0);
    _flutterTts.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    if (text != lastInstruction) {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
      lastInstruction = text;
    }
  }

  void dispose() {
    _flutterTts.stop();
  }
}
