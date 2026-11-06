import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/app_config.dart';
import 'services/audio_tts_service.dart';
import 'services/storage_service.dart';
import 'views/home_browser_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configura stile di sistema Edge-to-Edge coerente con HyperOS 3
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Inizializzazione servizi di memorizzazione e audio
  final storageService = await StorageService.init();
  final ttsService = AudioTtsService(storageService);

  runApp(CorriereAudiobookApp(
    storageService: storageService,
    ttsService: ttsService,
  ));
}

/// Applicazione principale Corriere Audiobook
class CorriereAudiobookApp extends StatelessWidget {
  final StorageService storageService;
  final AudioTtsService ttsService;

  const CorriereAudiobookApp({
    super.key,
    required this.storageService,
    required this.ttsService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,

      // Tema Scuro ottimizzato per pannelli AMOLED 120Hz di POCO F7 (True Black #000000)
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2979FF),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF121212),
          background: Color(0xFF000000),
          onPrimary: Colors.white,
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF141414),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),

      // Tema Chiaro
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1565C0),
          secondary: Color(0xFF0288D1),
          surface: Colors.white,
          background: Color(0xFFF8F9FA),
          onPrimary: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),

      themeMode: ThemeMode.system,

      home: HomeBrowserScreen(
        storageService: storageService,
        ttsService: ttsService,
      ),
    );
  }
}
