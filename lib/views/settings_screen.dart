import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/audio_tts_service.dart';
import '../services/storage_service.dart';
import '../services/updater_service.dart';
import '../widgets/update_dialog.dart';

/// Schermata delle impostazioni e preferenze dell'applicazione
class SettingsScreen extends StatefulWidget {
  final StorageService storageService;
  final AudioTtsService ttsService;

  const SettingsScreen({
    super.key,
    required this.storageService,
    required this.ttsService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _repoController;
  bool _isCheckingUpdate = false;
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _repoController = TextEditingController(text: widget.storageService.getGitHubRepo());
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = info.version;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _repoController.dispose();
    super.dispose();
  }

  Future<void> _checkManualUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      final repo = _repoController.text.trim();
      await widget.storageService.setGitHubRepo(repo);

      final result = await UpdaterService.checkForUpdates(repo);
      if (!mounted) return;

      if (result != null && result.isUpdateAvailable) {
        UpdateDialog.show(context, result);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result != null
                  ? 'Nessun aggiornamento. Sei all\'ultima versione (v${result.currentVersion}).'
                  : 'Impossibile verificare gli aggiornamenti. Controlla il nome del repo o la connessione.',
            ),
            backgroundColor: result != null ? Colors.green[700] : Colors.orangeAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('Impostazioni', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Sezione 1: Sintesi Vocale (TTS)
            _buildSectionHeader('Sintesi Vocale & Audio', Icons.record_voice_over_rounded),
            _buildTtsSettingsCard(isDark),

            const SizedBox(height: 24),

            // Sezione 2: Aggiornamenti In-App GitHub
            _buildSectionHeader('Aggiornamenti In-App (GitHub Releases)', Icons.system_update_alt_rounded),
            _buildUpdaterCard(isDark),

            const SizedBox(height: 24),

            // Sezione 3: Sessione & Privacy
            _buildSectionHeader('Sessione & Memoria Locale', Icons.security_rounded),
            _buildSessionCard(isDark),

            const SizedBox(height: 24),

            // Sezione 4: Ottimizzazioni Hardware POCO F7
            _buildSectionHeader('Ottimizzazioni Xiaomi POCO F7', Icons.speed_rounded),
            _buildHardwareCard(isDark),

            const SizedBox(height: 32),
            Center(
              child: Text(
                'Corriere Audiobook v$_appVersion\nProgettato per Android 16 & HyperOS 3',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[600] : Colors.grey[500],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTtsSettingsCard(bool isDark) {
    return ListenableBuilder(
      listenable: widget.ttsService,
      builder: (context, _) {
        final rate = widget.ttsService.speechRate;
        final pitch = widget.ttsService.pitch;

        return Card(
          color: isDark ? const Color(0xFF161616) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Velocità di lettura
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Velocità di lettura', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text(
                      '${rate.toStringAsFixed(2)}x',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                  ],
                ),
                Slider(
                  value: rate,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  activeColor: Colors.blueAccent,
                  onChanged: (val) => widget.ttsService.setSpeechRate(val),
                ),

                const Divider(height: 24),

                // Tono vocale (Pitch)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tono vocale (Pitch)', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text(
                      pitch.toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                  ],
                ),
                Slider(
                  value: pitch,
                  min: 0.5,
                  max: 1.5,
                  divisions: 10,
                  activeColor: Colors.blueAccent,
                  onChanged: (val) => widget.ttsService.setPitch(val),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUpdaterCard(bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF161616) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Repository GitHub Releases (owner/repo):',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _repoController,
              decoration: InputDecoration(
                hintText: 'es. Martiri/corriere-audiobook',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (val) {
                widget.storageService.setGitHubRepo(val);
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: _isCheckingUpdate
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(_isCheckingUpdate ? 'Controllo in corso...' : 'Verifica Aggiornamenti'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isCheckingUpdate ? null : _checkManualUpdate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 14, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Standard Play Protect Clean: installazione delegata al browser di sistema con zero avvisi.',
                    style: TextStyle(fontSize: 11, color: Colors.green[600]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF161616) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.cookie_outlined, color: Colors.orangeAccent),
            title: const Text('Cancella Cookie di Sessione', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Rimuove i cookie del Corriere salvati localmente'),
            trailing: const Icon(Icons.delete_outline_rounded),
            onTap: () async {
              await widget.storageService.clearCookies();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cookie di sessione rimossi con successo')),
                );
              }
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.history_rounded, color: Colors.blueAccent),
            title: const Text('Svuota Cronologia Articoli', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Cancella gli articoli memorizzati nella cronologia'),
            trailing: const Icon(Icons.cleaning_services_rounded),
            onTap: () async {
              await widget.storageService.clearHistory();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cronologia svuotata')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareCard(bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF161616) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatusRow(
              icon: Icons.speed_rounded,
              title: 'Display Refresh Rate',
              value: '120 Hz AMOLED Lock',
              color: Colors.green,
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
              icon: Icons.android_rounded,
              title: 'Compatibilità OS',
              value: 'Android 16 / HyperOS 3',
              color: Colors.blueAccent,
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
              icon: Icons.fullscreen_rounded,
              title: 'Gestione Inset & Gesture',
              value: 'SafeArea & Edge-to-Edge Attivi',
              color: Colors.teal,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ],
    );
  }
}
