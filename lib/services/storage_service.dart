import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/article.dart';

/// Servizio di memorizzazione locale basato su SharedPreferences
class StorageService {
  static const String _keySpeechRate = 'tts_speech_rate';
  static const String _keyPitch = 'tts_pitch';
  static const String _keyVoice = 'tts_voice';
  static const String _keyGitHubRepo = 'github_repo';
  static const String _keySavedCookies = 'saved_cookies';
  static const String _keyHistory = 'articles_history';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // --- Impostazioni TTS ---

  double getSpeechRate() {
    return _prefs.getDouble(_keySpeechRate) ?? 1.0;
  }

  Future<void> setSpeechRate(double rate) async {
    await _prefs.setDouble(_keySpeechRate, rate);
  }

  double getPitch() {
    return _prefs.getDouble(_keyPitch) ?? 1.0;
  }

  Future<void> setPitch(double pitch) async {
    await _prefs.setDouble(_keyPitch, pitch);
  }

  String? getVoice() {
    return _prefs.getString(_keyVoice);
  }

  Future<void> setVoice(String voice) async {
    await _prefs.setString(_keyVoice, voice);
  }

  // --- Configurazione GitHub Repository ---

  String getGitHubRepo() {
    return _prefs.getString(_keyGitHubRepo) ?? AppConfig.defaultGitHubRepo;
  }

  Future<void> setGitHubRepo(String repo) async {
    await _prefs.setString(_keyGitHubRepo, repo.trim());
  }

  // --- Gestione Cookie di Sessione ---

  String getSavedCookies() {
    return _prefs.getString(_keySavedCookies) ?? '';
  }

  Future<void> setSavedCookies(String cookies) async {
    await _prefs.setString(_keySavedCookies, cookies);
  }

  Future<void> clearCookies() async {
    await _prefs.remove(_keySavedCookies);
  }

  // --- Cronologia Articoli Ascoltati ---

  List<Article> getHistory() {
    final rawList = _prefs.getStringList(_keyHistory) ?? [];
    return rawList.map((str) {
      try {
        final map = jsonDecode(str) as Map<String, dynamic>;
        return Article.fromJson(map);
      } catch (_) {
        return null;
      }
    }).whereType<Article>().toList();
  }

  Future<void> saveToHistory(Article article) async {
    final currentList = getHistory();
    // Evita duplicati rimuovendo eventuale voce con stesso URL
    currentList.removeWhere((a) => a.url == article.url);
    // Inserisci in cima
    currentList.insert(0, article);
    // Limita la cronologia agli ultimi 30 articoli
    if (currentList.length > 30) {
      currentList.removeRange(30, currentList.length);
    }
    final encoded = currentList.map((a) => jsonEncode(a.toJson())).toList();
    await _prefs.setStringList(_keyHistory, encoded);
  }

  Future<void> clearHistory() async {
    await _prefs.remove(_keyHistory);
  }
}
