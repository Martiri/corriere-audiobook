import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

/// Schermata principale: Interfaccia editoriale moderna con supporto completo all'Edicola Digitale
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

  String _currentUrl = AppConfig.corriereEdicolaUrl;
  bool _isLoading = true;
  double _loadingProgress = 0.0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isExtracting = false;
  bool _isTabletMode = true; // Modalità Tablet abilitata di default per lo sfogliatore

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

  /// Inizializza il WebViewController con supporto a touch nativo, popups e override intent
  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_isTabletMode ? AppConfig.tabletUserAgent : AppConfig.mobileUserAgent)
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
            });
          },
          onPageFinished: (url) async {
            final canBack = await _controller.canGoBack();
            final canForward = await _controller.canGoForward();
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUrl = url;
                _canGoBack = canBack;
                _canGoForward = canForward;
              });
            }
            // Inietta script per sbloccare popup, gestire target=_blank e nascondere banner app
            await _injectPageTouchFixes();
            await _syncCookies(url);
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            // Intercetta intent:// o market:// usati da Corriere per forzare l'app Google Play
            if (url.startsWith('intent://') || url.startsWith('market://')) {
              final fallbackMatch = RegExp(r'browser_fallback_url=([^;]+)').firstMatch(url);
              if (fallbackMatch != null) {
                final fallbackUrl = Uri.decodeComponent(fallbackMatch.group(1)!);
                _controller.loadRequest(Uri.parse(fallbackUrl));
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            debugPrint("WebView Error: ${error.description}");
          },
        ),
      )
      ..loadRequest(Uri.parse(AppConfig.corriereEdicolaUrl));
  }

  /// Inietta JavaScript per garantire che toccare il giornale apra sempre lo sfogliatore
  Future<void> _injectPageTouchFixes() async {
    const jsScript = r'''
      (function() {
        try {
          // 1. Rimuovi banner fastidiosi che bloccano i touch (es. banner Google Play "OTTIENI")
          const banners = document.querySelectorAll('.smartbanner, [class*="smartbanner"], [id*="smartbanner"], .app-banner');
          banners.forEach(b => b.remove());

          // 2. Forza tutti i link target="_blank" ad aprirsi nella stessa finestra
          document.querySelectorAll('a[target="_blank"]').forEach(a => a.removeAttribute('target'));
          document.addEventListener('click', function(e) {
            var a = e.target.closest('a');
            if (a && a.target === '_blank') {
              a.target = '_self';
            }
          }, true);

          // 3. Override window.open per reindirizzare nella stessa WebView invece di venire bloccato
          window.open = function(url, target, features) {
            if (url) {
              window.location.href = url;
            }
            return window;
          };

          // 4. Assicurati che le copertine dei giornali abbiano cursore pointer e touch abilitato
          document.querySelectorAll('img, div[class*="cover"], div[class*="edition"], a').forEach(el => {
            el.style.pointerEvents = 'auto';
            el.style.cursor = 'pointer';
          });
        } catch(e) {}
      })();
    ''';
    try {
      await _controller.runJavaScript(jsScript);
    } catch (_) {}
  }

  /// Alterna tra visualizzazione Tablet/Desktop edicola e visualizzazione Mobile
  Future<void> _toggleUserAgent() async {
    final newMode = !_isTabletMode;
    setState(() {
      _isTabletMode = newMode;
      _isLoading = true;
    });

    final newUa = newMode ? AppConfig.tabletUserAgent : AppConfig.mobileUserAgent;
    await _controller.setUserAgent(newUa);
    await _controller.reload();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newMode
                ? '🖥️ Modalità Tablet/Desktop attiva (consigliata per lo sfoglio del quotidiano).'
                : '📱 Modalità Mobile attiva.',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Intercetta e salva i cookie di sessione autenticata
  Future<void> _syncCookies(String url) async {
    try {
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
      // 1. Estrazione primaria dal DOM attivo della WebView
      Article? article = await ExtractorService.extractFromWebView(_controller, _currentUrl);

      // 2. Se non ha trovato paragrafi, fallback su chiamata HTTP con cookie
      if (article == null || article.paragraphs.isEmpty) {
        final cookies = widget.storageService.getSavedCookies();
        article = await ExtractorService.extractFromHttp(_currentUrl, cookies);
      }

      if (article != null && article.paragraphs.isNotEmpty && mounted) {
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
              'Nessun testo rilevato nella schermata corrente. Apri un articolo o una pagina del quotidiano prima di convertire.',
            ),
            backgroundColor: Colors.orangeAccent,
            behavior: SnackBarBehavior.floating,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isEdicola = _currentUrl.contains('digitaledition') || _currentUrl.contains('edicola');
    final isWebSite = !_currentUrl.contains('digitaledition') && !_currentUrl.contains('edicola') && !_currentUrl.contains('login');
    final isLogin = _currentUrl.contains('login') || _currentUrl.contains('abbonamenti');

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
      body: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            // Header Superiore Editoriale Raffinato
            _buildModernHeader(isDark),

            // Barra di Selezione Rapida a Pillole (Edicola, Sito Notizie, Login)
            _buildSectionTabBar(isDark, isEdicola, isWebSite, isLogin),

            // Barra di avanzamento caricamento fluida
            if (_isLoading)
              LinearProgressIndicator(
                value: _loadingProgress > 0.05 ? _loadingProgress : null,
                backgroundColor: isDark ? Colors.grey[900] : Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2979FF)),
                minHeight: 2.5,
              ),

            // WebView a tutto schermo con intercettazione diretta di TUTTI i gesti touch
            Expanded(
              child: WebViewWidget(
                controller: _controller,
                gestureRecognizers: {
                  Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                },
              ),
            ),

            // Mini-player multimediale quando l'audio è attivo
            TtsControlsBar(ttsService: widget.ttsService),
          ],
        ),
      ),
      // Pulsante Audio Flottante Moderno a Pillola con Glow
      floatingActionButton: _buildModernAudioPill(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildModernHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101216) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[850]! : Colors.grey[200]!,
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          // Logo / Titolo Editoriale
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'CORRIERE DELLA SERA',
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2979FF), Color(0xFF00E5FF)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'AUDIO',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  _isTabletMode ? 'Edicola Sfogliabile • Display 120Hz' : 'Sito Web Mobile',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          // Tasto Navigazione Indietro
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: _canGoBack ? (isDark ? Colors.white : Colors.black87) : Colors.grey[600],
            ),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            onPressed: _canGoBack ? () => _controller.goBack() : null,
          ),
          const SizedBox(width: 8),

          // Tasto Ricarica
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            tooltip: 'Ricarica',
            onPressed: () => _controller.reload(),
          ),
          const SizedBox(width: 8),

          // Tasto Toggle Modalità Desktop/Tablet
          IconButton(
            icon: Icon(
              _isTabletMode ? Icons.laptop_mac_rounded : Icons.phone_android_rounded,
              size: 20,
              color: _isTabletMode ? const Color(0xFF2979FF) : (isDark ? Colors.white : Colors.black87),
            ),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            tooltip: _isTabletMode ? 'Passa a Mobile' : 'Passa a Tablet/Desktop',
            onPressed: _toggleUserAgent,
          ),
          const SizedBox(width: 8),

          // Impostazioni
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
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

  Widget _buildSectionTabBar(bool isDark, bool isEdicola, bool isWebSite, bool isLogin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isDark ? const Color(0xFF0A0C10) : const Color(0xFFF6F8FA),
      child: Row(
        children: [
          // Scheda 1: Quotidiano (Edicola Digitale)
          _buildPillTab(
            label: 'Quotidiano (Edicola)',
            icon: Icons.newspaper_rounded,
            isSelected: isEdicola,
            isDark: isDark,
            onTap: () {
              _controller.loadRequest(Uri.parse(AppConfig.corriereEdicolaUrl));
            },
          ),
          const SizedBox(width: 8),

          // Scheda 2: Notizie Web
          _buildPillTab(
            label: 'Sito Web',
            icon: Icons.language_rounded,
            isSelected: isWebSite,
            isDark: isDark,
            onTap: () {
              _controller.loadRequest(Uri.parse(AppConfig.corriereBaseUrl));
            },
          ),
          const SizedBox(width: 8),

          // Scheda 3: Accedi (Login)
          _buildPillTab(
            label: 'Login',
            icon: Icons.account_circle_outlined,
            isSelected: isLogin,
            isDark: isDark,
            onTap: () {
              _controller.loadRequest(Uri.parse(AppConfig.corriereLoginUrl));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPillTab({
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF2979FF).withOpacity(0.2) : Colors.blueAccent.withOpacity(0.12))
                : (isDark ? const Color(0xFF16181D) : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF2979FF)
                  : (isDark ? Colors.grey[850]! : Colors.grey[300]!),
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? const Color(0xFF2979FF) : (isDark ? Colors.grey[400] : Colors.grey[700]),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? const Color(0xFF2979FF)
                        : (isDark ? Colors.grey[300] : Colors.black87),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernAudioPill() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isExtracting ? null : _extractAndPlay,
        borderRadius: BorderRadius.circular(30),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2979FF), Color(0xFF00B0FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2979FF).withOpacity(0.4),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isExtracting)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else
                  const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  _isExtracting ? 'Conversione in corso...' : 'Ascolta Articolo',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
