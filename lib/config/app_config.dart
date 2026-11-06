/// Configurazione globale dell'applicazione Corriere Audiobook
class AppConfig {
  static const String appName = 'Corriere Audiobook';
  static const String appVersion = '1.0.0';

  /// URL di partenza per la navigazione del Corriere della Sera
  static const String corriereBaseUrl = 'https://www.corriere.it';
  static const String corriereLoginUrl = 'https://www.corriere.it/login/';

  /// Coordinate predefinite del repository GitHub per gli aggiornamenti automatici
  static const String defaultGitHubRepo = 'franco-developer/corriere-audiobook';

  /// User Agent mobile moderno per garantire compatibilità ottimale con Corriere.it
  static const String customUserAgent =
      'Mozilla/5.0 (Linux; Android 16; POCO F7 Build/BAK1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Mobile Safari/537.36';

  /// Pattern regex per riconoscere gli URL degli articoli del Corriere
  static final RegExp articleUrlPattern = RegExp(
    r'corriere\.it\/.*\/(20\d\d\/.*|\d{2}_\w+_20\d\d\/.*|[a-zA-Z0-9_\-]+\.shtml)',
    caseSensitive: false,
  );
}
