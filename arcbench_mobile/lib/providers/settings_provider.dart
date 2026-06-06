import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyVoiceEnabled = 'settings_voice_enabled';
  static const _keyFontSize = 'settings_font_size';
  static const _keyVoiceSpeed = 'settings_voice_speed';
  static const _keyAutoScroll = 'settings_auto_scroll';

  static const double defaultFontSize = 13.0;
  static const double defaultVoiceSpeed = 0.5;

  bool _voiceEnabled = true;
  double _fontSize = defaultFontSize;
  double _voiceSpeed = defaultVoiceSpeed;
  bool _autoScroll = true;

  bool get voiceEnabled => _voiceEnabled;
  double get fontSize => _fontSize;
  double get voiceSpeed => _voiceSpeed;
  bool get autoScroll => _autoScroll;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _voiceEnabled = prefs.getBool(_keyVoiceEnabled) ?? true;
    _fontSize = prefs.getDouble(_keyFontSize) ?? defaultFontSize;
    _voiceSpeed = prefs.getDouble(_keyVoiceSpeed) ?? defaultVoiceSpeed;
    _autoScroll = prefs.getBool(_keyAutoScroll) ?? true;
    notifyListeners();
  }

  Future<void> setVoiceEnabled(bool enabled) async {
    _voiceEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVoiceEnabled, enabled);
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size.clamp(8.0, 24.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, _fontSize);
  }

  Future<void> setVoiceSpeed(double speed) async {
    _voiceSpeed = speed.clamp(0.25, 2.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyVoiceSpeed, _voiceSpeed);
  }

  Future<void> setAutoScroll(bool enabled) async {
    _autoScroll = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoScroll, enabled);
  }
}
