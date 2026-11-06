/// Configurazione globale dell'applicazione Corriere Audiobook
class AppConfig {
  static const String appName = 'Corriere Audiobook';
  static const String appVersion = '1.0.2';

  /// URL di partenza per la navigazione del Corriere della Sera (Sito web)
  static const String corriereBaseUrl = 'https://www.corriere.it';
  
  /// URL dell'Edicola Digitale / Quotidiano sfogliabile
  static const String corriereEdicolaUrl = 'https://digitaledition.corriere.it';
  
  /// URL diretto di login
  static const String corriereLoginUrl = 'https://www.corriere.it/account/login';

  /// Coordinate predefinite del repository GitHub per gli aggiornamenti automatici
  static const String defaultGitHubRepo = 'Martiri/corriere-audiobook';

  /// User Agent Mobile
  static const String mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 16; POCO F7 Build/BAK1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Mobile Safari/537.36';

  /// User Agent Desktop/Tablet (indispensabile per l'Edicola Digitale per bypassare il blocco Play Store)
  static const String tabletUserAgent =
      'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

  static const String desktopUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

  /// Default user agent
  static const String customUserAgent = tabletUserAgent;

  /// Pattern regex per riconoscere gli URL degli articoli del Corriere (Sito ed Edicola)
  static final RegExp articleUrlPattern = RegExp(
    r'corriere\.it\/.*\/(20\d\d\/.*|\d{2}_\w+_20\d\d\/.*|[a-zA-Z0-9_\-]+\.shtml|sfogliatore|articolo|detail)',
    caseSensitive: false,
  );
}
