/// Voice input (speech-to-text) and output (text-to-speech) service.
/// Voice-first design: large mic button → dictation → auto-submit.

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

enum VoiceState { idle, listening, processing }

class VoiceService extends ChangeNotifier {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  VoiceState _state = VoiceState.idle;
  String _currentText = '';
  bool _isAvailable = false;
  double _confidence = 0.0;

  VoiceState get state => _state;
  String get currentText => _currentText;
  bool get isAvailable => _isAvailable;
  bool get isListening => _state == VoiceState.listening;
  double get confidence => _confidence;

  /// Initialize speech recognition and TTS
  Future<void> initialize() async {
    _isAvailable = await _speech.initialize(
      onStatus: _onStatus,
      onError: _onError,
    );

    // Configure TTS
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    notifyListeners();
    debugPrint('[Voice] Available: $_isAvailable');
  }

  /// Start listening for voice input
  Future<void> startListening() async {
    if (!_isAvailable) return;

    _currentText = '';
    _state = VoiceState.listening;
    notifyListeners();

    await _speech.listen(
      onResult: (result) {
        _currentText = result.recognizedWords;
        _confidence = result.confidence;
        notifyListeners();
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
      cancelOnError: true,
      partialResults: true,
    );
  }

  /// Stop listening and return the final text
  Future<String> stopListening() async {
    await _speech.stop();
    _state = VoiceState.idle;
    notifyListeners();
    return _currentText;
  }

  /// Cancel listening without returning text
  Future<void> cancelListening() async {
    await _speech.cancel();
    _currentText = '';
    _state = VoiceState.idle;
    notifyListeners();
  }

  /// Speak a summary of the AI response
  Future<void> speak(String text) async {
    // Truncate very long responses for TTS
    final toSpeak = text.length > 300 ? '${text.substring(0, 300)}... and more.' : text;
    await _tts.speak(toSpeak);
  }

  /// Stop TTS
  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  void _onStatus(String status) {
    debugPrint('[Voice] Status: $status');
    if (status == 'done' || status == 'notListening') {
      _state = VoiceState.idle;
      notifyListeners();
    }
  }

  void _onError(dynamic error) {
    debugPrint('[Voice] Error: $error');
    _state = VoiceState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }
}
