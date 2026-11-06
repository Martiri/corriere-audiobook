import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_session/audio_session.dart';
import '../models/article.dart';
import 'storage_service.dart';

enum PlaybackState { idle, playing, paused }

/// Servizio audio Text-to-Speech avanzato con supporto alla riproduzione a blocchi/paragrafi
/// e integrazione con audio focus Android per la massima stabilità in background su HyperOS
class AudioTtsService extends ChangeNotifier {
  final FlutterTts _flutterTts = FlutterTts();
  final StorageService _storageService;

  PlaybackState _state = PlaybackState.idle;
  PlaybackState get state => _state;
  bool get isPlaying => _state == PlaybackState.playing;
  bool get isPaused => _state == PlaybackState.paused;

  Article? _currentArticle;
  Article? get currentArticle => _currentArticle;

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  double _speechRate = 1.0;
  double get speechRate => _speechRate;

  double _pitch = 1.0;
  double get pitch => _pitch;

  List<dynamic> _availableVoices = [];
  List<dynamic> get availableVoices => _availableVoices;

  Timer? _sleepTimer;
  int? _sleepTimerMinutes;
  int? get sleepTimerMinutes => _sleepTimerMinutes;

  AudioTtsService(this._storageService) {
    _initTts();
  }

  Future<void> _initTts() async {
    // Configura AudioSession per la gestione del focus audio su Android
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          if (isPlaying) pause();
        } else {
          if (event.type != AudioInterruptionType.unknown && isPaused) {
            resume();
          }
        }
      });
      session.becomingNoisyEventStream.listen((_) {
        // Quando si scollegano le cuffie, metti in pausa
        if (isPlaying) pause();
      });
    } catch (_) {}

    // Imposta parametri salvati
    _speechRate = _storageService.getSpeechRate();
    _pitch = _storageService.getPitch();

    await _flutterTts.setLanguage('it-IT');
    // Su Android flutter_tts mappa la velocità da 0.0 a 1.0, dove 0.5 è la normale
    await _flutterTts.setSpeechRate(_mapRateToNative(_speechRate));
    await _flutterTts.setPitch(_pitch);

    // Callbacks TTS
    _flutterTts.setCompletionHandler(() {
      _onParagraphCompleted();
    });

    _flutterTts.setErrorHandler((dynamic msg) {
      debugPrint("TTS Error: $msg");
      _onParagraphCompleted();
    });

    // Recupera le voci italiane disponibili
    try {
      final voices = await _flutterTts.getVoices;
      if (voices is List) {
        _availableVoices = voices.where((v) {
          final locale = v['locale']?.toString().toLowerCase() ?? '';
          return locale.contains('it');
        }).toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Mappa una velocità umana (es. 0.5x - 2.0x con base 1.0x) alla scala FlutterTts Android
  double _mapRateToNative(double rate) {
    // 1.0 corrisponde a circa 0.5 in Android TextToSpeech standard
    return (rate * 0.5).clamp(0.2, 1.0);
  }

  /// Avvia la lettura di un nuovo articolo
  Future<void> playArticle(Article article, {int startParagraph = 0}) async {
    await stop();
    _currentArticle = article;
    _currentIndex = startParagraph.clamp(0, article.paragraphs.length - 1);
    await _storageService.saveToHistory(article);

    _state = PlaybackState.playing;
    notifyListeners();

    await _speakCurrent();
  }

  /// Pronuncia il paragrafo corrente
  Future<void> _speakCurrent() async {
    if (_currentArticle == null || _state != PlaybackState.playing) return;

    if (_currentIndex >= _currentArticle!.paragraphs.length) {
      await stop();
      return;
    }

    final text = _currentArticle!.paragraphs[_currentIndex];
    if (text.trim().isEmpty) {
      _onParagraphCompleted();
      return;
    }

    await _flutterTts.speak(text);
  }

  /// Callback scatenato quando il paragrafo corrente termina di essere letto
  void _onParagraphCompleted() {
    if (_state != PlaybackState.playing || _currentArticle == null) return;

    if (_currentIndex < _currentArticle!.paragraphs.length - 1) {
      _currentIndex++;
      notifyListeners();
      _speakCurrent();
    } else {
      // Articolo completato
      stop();
    }
  }

  /// Mette in pausa la lettura
  Future<void> pause() async {
    if (_state != PlaybackState.playing) return;
    await _flutterTts.stop();
    _state = PlaybackState.paused;
    notifyListeners();
  }

  /// Riprende la lettura
  Future<void> resume() async {
    if (_state != PlaybackState.paused || _currentArticle == null) return;
    _state = PlaybackState.playing;
    notifyListeners();
    await _speakCurrent();
  }

  /// Interrompe completamente la lettura
  Future<void> stop() async {
    await _flutterTts.stop();
    _state = PlaybackState.idle;
    cancelSleepTimer();
    notifyListeners();
  }

  /// Salta al paragrafo successivo
  Future<void> nextParagraph() async {
    if (_currentArticle == null) return;
    if (_currentIndex < _currentArticle!.paragraphs.length - 1) {
      await _flutterTts.stop();
      _currentIndex++;
      notifyListeners();
      if (_state == PlaybackState.playing) {
        await _speakCurrent();
      }
    }
  }

  /// Torna al paragrafo precedente
  Future<void> previousParagraph() async {
    if (_currentArticle == null) return;
    if (_currentIndex > 0) {
      await _flutterTts.stop();
      _currentIndex--;
      notifyListeners();
      if (_state == PlaybackState.playing) {
        await _speakCurrent();
      }
    }
  }

  /// Salta direttamente a uno specifico paragrafo selezionato dall'utente
  Future<void> jumpToParagraph(int index) async {
    if (_currentArticle == null) return;
    if (index >= 0 && index < _currentArticle!.paragraphs.length) {
      await _flutterTts.stop();
      _currentIndex = index;
      notifyListeners();
      if (_state == PlaybackState.playing) {
        await _speakCurrent();
      }
    }
  }

  /// Imposta la velocità di lettura (0.5x - 2.0x)
  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    await _storageService.setSpeechRate(rate);
    await _flutterTts.setSpeechRate(_mapRateToNative(rate));
    notifyListeners();
  }

  /// Imposta l'intonazione vocale (0.5 - 1.5)
  Future<void> setPitch(double pitch) async {
    _pitch = pitch;
    await _storageService.setPitch(pitch);
    await _flutterTts.setPitch(pitch);
    notifyListeners();
  }

  /// Imposta una voce specifica
  Future<void> setVoice(Map<String, String> voice) async {
    await _flutterTts.setVoice(voice);
    if (voice['name'] != null) {
      await _storageService.setVoice(voice['name']!);
    }
    notifyListeners();
  }

  /// Timer di spegnimento automatico (in minuti)
  void setSleepTimer(int minutes) {
    cancelSleepTimer();
    _sleepTimerMinutes = minutes;
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      stop();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerMinutes = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _flutterTts.stop();
    super.dispose();
  }
}
