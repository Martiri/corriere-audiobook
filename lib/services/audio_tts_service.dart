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

  String? _selectedVoiceName;
  String? get selectedVoiceName => _selectedVoiceName;

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

    // Imposta motore Google Text-to-Speech se presente sul dispositivo
    try {
      final engines = await _flutterTts.getEngines;
      if (engines is List && engines.contains('com.google.android.tts')) {
        await _flutterTts.setEngine('com.google.android.tts');
      }
    } catch (_) {}

    // Imposta parametri salvati
    _speechRate = _storageService.getSpeechRate();
    _pitch = _storageService.getPitch();

    await _flutterTts.setLanguage('it-IT');
    // Su Android standard, 1.0 corrisponde alla velocità normale naturale
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

    // Recupera e seleziona le migliori voci neurali italiane
    await _loadVoices();
  }

  /// Carica le voci italiane e imposta per default la migliore voce neurale
  Future<void> _loadVoices() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices is List) {
        final itVoices = voices.where((v) {
          final locale = (v['locale']?.toString() ?? '').toLowerCase().replaceAll('_', '-');
          return locale.startsWith('it') || locale.contains('it-it');
        }).toList();

        // Ordina per favorire voci ad alta fedeltà neurale / network di Google
        itVoices.sort((a, b) {
          final nameA = (a['name']?.toString() ?? '').toLowerCase();
          final nameB = (b['name']?.toString() ?? '').toLowerCase();
          final isNetworkA = nameA.contains('network') || nameA.contains('natural') || nameA.contains('wavenet');
          final isNetworkB = nameB.contains('network') || nameB.contains('natural') || nameB.contains('wavenet');
          if (isNetworkA && !isNetworkB) return -1;
          if (!isNetworkA && isNetworkB) return 1;
          return nameA.compareTo(nameB);
        });

        _availableVoices = itVoices;

        // Se c'è una voce salvata, usala; altrimenti usa la migliore disponibile
        final savedVoiceName = _storageService.getVoice();
        if (savedVoiceName != null && savedVoiceName.isNotEmpty) {
          final found = itVoices.firstWhere(
            (v) => v['name'] == savedVoiceName,
            orElse: () => null,
          );
          if (found != null) {
            await _flutterTts.setVoice({
              'name': found['name'].toString(),
              'locale': found['locale'].toString(),
            });
            _selectedVoiceName = savedVoiceName;
          }
        } else if (itVoices.isNotEmpty) {
          final bestVoice = itVoices.first;
          await _flutterTts.setVoice({
            'name': bestVoice['name'].toString(),
            'locale': bestVoice['locale'].toString(),
          });
          _selectedVoiceName = bestVoice['name'].toString();
          await _storageService.setVoice(_selectedVoiceName!);
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Pulisce ed espande il testo prima della lettura per un parlato umano e fluido
  static String cleanTextForSpeech(String text) {
    String cleaned = text;

    // Espansione abbreviazioni giornalistiche comuni per un parlato naturale
    final abbreviations = {
      RegExp(r'\bdott\.ssa\b', caseSensitive: false): 'dottoressa',
      RegExp(r'\bdott\.\b', caseSensitive: false): 'dottor',
      RegExp(r'\bprof\.ssa\b', caseSensitive: false): 'professoressa',
      RegExp(r'\bprof\.\b', caseSensitive: false): 'professor',
      RegExp(r'\bing\.\b', caseSensitive: false): 'ingegner',
      RegExp(r'\bavv\.\b', caseSensitive: false): 'avvocato',
      RegExp(r'\bon\.\b', caseSensitive: false): 'onorevole',
      RegExp(r'\bsen\.\b', caseSensitive: false): 'senatore',
      RegExp(r'\bpagg?\.\b', caseSensitive: false): 'pagine',
      RegExp(r'\bpag\.\b', caseSensitive: false): 'pagina',
      RegExp(r'\becc\.\b', caseSensitive: false): 'eccetera',
      RegExp(r'\bart\.\b', caseSensitive: false): 'articolo',
      RegExp(r'\bc\.d\.\b', caseSensitive: false): 'cosiddetto',
      RegExp(r'\bUe\b'): 'Unione Europea',
      RegExp(r'\bUE\b'): 'Unione Europea',
      RegExp(r'\bUsa\b'): 'Stati Uniti',
      RegExp(r'\bUSA\b'): 'Stati Uniti',
      RegExp(r'\bBce\b'): 'Banca Centrale Europea',
      RegExp(r'\bBCE\b'): 'Banca Centrale Europea',
      RegExp(r'\bFmi\b'): 'Fondo Monetario Internazionale',
      RegExp(r'\bFMI\b'): 'Fondo Monetario Internazionale',
      RegExp(r'\bPil\b'): 'Pil',
      RegExp(r'\bPIL\b'): 'Pil',
      RegExp(r'\bTar\b'): 'Tar',
      RegExp(r'\bTAR\b'): 'Tar',
      RegExp(r'\bPm\b'): 'Pubblico Ministero',
      RegExp(r'\bPM\b'): 'Pubblico Ministero',
      RegExp(r'\bPg\b'): 'Procuratore Generale',
      RegExp(r'\bPG\b'): 'Procuratore Generale',
    };

    abbreviations.forEach((pattern, replacement) {
      cleaned = cleaned.replaceAll(pattern, replacement);
    });

    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\b[nN]\.\s*(\d+)'),
      (match) => 'numero ${match.group(1)}',
    );

    // Rimuovi virgolette e simboli che possono provocare pronunce sgradevoli nel TTS
    cleaned = cleaned
        .replaceAll(RegExp(r'[«»""“”‘’]'), '')
        .replaceAll(RegExp(r'[—–-]'), ', ')
        .replaceAll('...', ', ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return cleaned;
  }

  /// Mappa la velocità naturale alla scala del TextToSpeech Android nativo (1.0 = normale)
  double _mapRateToNative(double rate) {
    return rate.clamp(0.5, 2.0);
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

  /// Pronuncia il paragrafo corrente applicando le ottimizzazioni di prosodia
  Future<void> _speakCurrent() async {
    if (_currentArticle == null || _state != PlaybackState.playing) return;

    if (_currentIndex >= _currentArticle!.paragraphs.length) {
      await stop();
      return;
    }

    final rawText = _currentArticle!.paragraphs[_currentIndex];
    final text = cleanTextForSpeech(rawText);
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
      _selectedVoiceName = voice['name']!;
      await _storageService.setVoice(_selectedVoiceName!);
    }
    notifyListeners();
  }

  /// Esegue un breve test di ascolto della voce selezionata
  Future<void> testVoice(Map<String, String> voice) async {
    await stop();
    await setVoice(voice);
    const sample = 'Questa è la nuova voce naturale italiana per la lettura del Corriere della Sera.';
    await _flutterTts.speak(sample);
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
