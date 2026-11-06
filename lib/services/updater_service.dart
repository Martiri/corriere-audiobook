import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Risultato della verifica degli aggiornamenti da GitHub Releases
class UpdateCheckResult {
  final bool isUpdateAvailable;
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String? downloadUrl;
  final String releasePageUrl;

  UpdateCheckResult({
    required this.isUpdateAvailable,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    this.downloadUrl,
    required this.releasePageUrl,
  });
}

/// Servizio per la gestione degli aggiornamenti in-app via GitHub Releases
/// 100% Google Play Protect Clean (senza permesso rischioso REQUEST_INSTALL_PACKAGES)
class UpdaterService {
  /// Controlla se è disponibile una versione più recente dell'APK su GitHub
  static Future<UpdateCheckResult?> checkForUpdates(String gitHubRepo) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final url = Uri.parse('https://api.github.com/repos/$gitHubRepo/releases/latest');
      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'CorriereAudiobook-Updater',
      });

      if (response.statusCode != 200) {
        return null;
      }

      final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawTag = data['tag_name'] as String? ?? '';
      final latestVersion = rawTag.replaceFirst(RegExp(r'^[vV]'), '').trim();
      final releaseNotes = data['body'] as String? ?? 'Nessuna nota di rilascio fornita.';
      final releasePageUrl = data['html_url'] as String? ?? 'https://github.com/$gitHubRepo/releases';

      // Cerca l'asset APK compilato allegato alla release
      String? apkDownloadUrl;
      final assets = (data['assets'] as List<dynamic>?) ?? [];
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkDownloadUrl = asset['browser_download_url'] as String?;
          break;
        }
      }

      final isNewer = _isNewerVersion(latestVersion, currentVersion);

      return UpdateCheckResult(
        isUpdateAvailable: isNewer,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseNotes: releaseNotes,
        downloadUrl: apkDownloadUrl ?? releasePageUrl,
        releasePageUrl: releasePageUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// Confronto semantico tra versioni (es. "1.0.1" > "1.0.0")
  static bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      while (latestParts.length < 3) latestParts.add(0);
      while (currentParts.length < 3) currentParts.add(0);

      for (int i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Avvia l'apertura del download dell'APK nel browser di sistema Chrome
  /// Questo garantisce che l'installazione avvenga in modo certificato da HyperOS / Play Protect
  static Future<bool> launchDownload(String url) async {
    try {
      final uri = Uri.parse(url);
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
