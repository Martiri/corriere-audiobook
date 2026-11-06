import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config/app_config.dart';
import '../models/article.dart';
import '../services/audio_tts_service.dart';
import '../services/extractor_service.dart';
import '../services/storage_service.dart';
import '../services/updater_service.dart';
import '../widgets/tts_controls_bar.dart';
import '../widgets/update_dialog.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

/// Schermata principale: Browser ibrido ottimizzato per Corriere della Sera con estrazione TTS rapida
class HomeBrowserScreen extends StatefulWidget {
  final StorageService storageService;
  final AudioTtsService ttsService;

  const HomeBrowserScreen({
    super.key,
    required this.storageService,
    required this.ttsService,
  });

  @override
  State<HomeBrowserScreen> createState() => _HomeBrowserScreenState();
}

class _HomeBrowserScreenState extends State<HomeBrowserScreen> {
  late final WebViewController _controller;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();

  String _currentUrl = AppConfig.corriereBaseUrl;
  bool _isLoading = true;
  double _loadingProgress = 0.0;
  bool _isArticlePage = false;
  bool _isExtracting = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _checkInitialUpdates();
  }

  /// Verifica in background gli aggiornamenti dell'APK all'avvio
  void _checkInitialUpdates() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = widget.storageService.getGitHubRepo();
      final result = await UpdaterService.checkForUpdates(repo);
      if (result != null && result.isUpdateAvailable && mounted) {
        UpdateDialog.show(context, result);
      }
    });
  }

  /// Configurazione del WebViewController con gestione cookie e User-Agent
  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AppConfig.customUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            setState(() {
              _loadingProgress = progress / 100.0;
            });
          },
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
              _isArticlePage = _checkIfArticle(url);
            });
          },
          onPageFinished: (url) async {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
              _isArticlePage = _checkIfArticle(url);
            });
            await _syncCookies(url);
          },
          onWebResourceError: (error) {
            debugPrint("WebView Error: ${error.description}");
          },
        ),
      )
      ..loadRequest(Uri.parse(AppConfig.corriereBaseUrl));
  }

  /// Determina se l'URL attuale corrisponde a un articolo leggibile
  bool _checkIfArticle(String url) {
    if (url.isEmpty) return false;
    // Escludi homepage e sezioni principali generiche
    if (url == AppConfig.corriereBaseUrl ||
        url == '${AppConfig.corriereBaseUrl}/' ||
        url.contains('/login') ||
        url.contains('/abbonamenti')) {
      return false;
    }
    return AppConfig.articleUrlPattern.hasMatch(url) ||
        url.endsWith('.shtml') ||
        url.contains('/notizie/');
  }

  /// Intercetta e salva i cookie della sessione autenticata
  Future<void> _syncCookies(String url) async {
    try {
      // WebViewCookieManager gestisce i cookie a livello nativo
      // Possiamo richiedere i cookie del dominio corriere.it
      final cookieString = await _controller.runJavaScriptReturningResult('document.cookie');
      String rawCookie = cookieString.toString();
      if (rawCookie.startsWith('"') && rawCookie.endsWith('"')) {
        rawCookie = rawCookie.substring(1, rawCookie.length - 1);
      }
      if (rawCookie.isNotEmpty && rawCookie != 'null') {
        await widget.storageService.setSavedCookies(rawCookie);
      }
    } catch (_) {}
  }

  /// Estrazione e apertura dell'articolo come audiolibro
  Future<void> _extractAndPlay() async {
    if (_isExtracting) return;

    setState(() {
      _isExtracting = true;
    });

    try {
      // 1. Tentativo di estrazione primaria dal DOM attivo della WebView
      Article? article = await ExtractorService.extractFromWebView(_controller, _currentUrl);

      // 2. Se l'estrazione dal DOM non ha prodotto paragrafi, usa il fallback HTTP con i cookie
      if (article == null || article.paragraphs.isEmpty) {
        final cookies = widget.storageService.getSavedCookies();
        article = await ExtractorService.extractFromHttp(_currentUrl, cookies);
      }

      if (article != null && article.paragraphs.isNotEmpty && mounted) {
        // Naviga al player
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              article: article!,
              ttsService: widget.ttsService,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossibile estrarre il testo. Assicurati di essere sulla pagina di un articolo o di aver effettuato il login.',
            ),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExtracting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
      body: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            // Barra di navigazione web superiore
            _buildBrowserNavBar(isDark),

            // Barra di avanzamento caricamento pagina
            if (_isLoading)
              LinearProgressIndicator(
                value: _loadingProgress,
                backgroundColor: isDark ? Colors.grey[900] : Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                minHeight: 2.5,
              ),

            // WebView a tutto schermo
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),

            // Mini-player per la riproduzione in background
            TtsControlsBar(ttsService: widget.ttsService),
          ],
        ),
      ),
      // Pulsante Flottante "Ascolta Articolo"
      floatingActionButton: _buildFloatingAudioButton(),
    );
  }

  Widget _buildBrowserNavBar(bool isDark) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : const Color(0xFFF2F4F7),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[850]! : Colors.grey[300]!,
          ),
        ),
      ),
      child: Row(
        children: [
          // Indietro
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            onPressed: () async {
              if (await _controller.canGoBack()) {
                await _controller.goBack();
              }
            },
          ),
          // Avanti
          IconButton(
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            onPressed: () async {
              if (await _controller.canGoForward()) {
                await _controller.goForward();
              }
            },
          ),
          // Ricarica
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () => _controller.reload(),
          ),
          // Home Corriere
          IconButton(
            icon: const Icon(Icons.home_rounded, size: 20),
            tooltip: 'Home Corriere',
            onPressed: () => _controller.loadRequest(Uri.parse(AppConfig.corriereBaseUrl)),
          ),
          const Spacer(),
          // Scorciatoia Login
          TextButton.icon(
            icon: const Icon(Icons.account_circle_outlined, size: 18),
            label: const Text('Login', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blueAccent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () => _controller.loadRequest(Uri.parse(AppConfig.corriereLoginUrl)),
          ),
          // Impostazioni
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: 'Impostazioni',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    storageService: widget.storageService,
                    ttsService: widget.ttsService,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget? _buildFloatingAudioButton() {
    // Il pulsante è sempre visibile o in risalto speciale quando si è su un articolo
    return FloatingActionButton.extended(
      heroTag: 'tts_fab',
      backgroundColor: _isArticlePage ? Colors.blueAccent : Colors.grey[700],
      elevation: _isArticlePage ? 8 : 2,
      icon: _isExtracting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.headphones_rounded, color: Colors.white),
      label: Text(
        _isExtracting
            ? 'Estrazione...'
            : (_isArticlePage ? 'Ascolta Articolo' : 'Converti Pagina'),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
      ),
      onPressed: _isExtracting ? null : _extractAndPlay,
    );
  }
}
