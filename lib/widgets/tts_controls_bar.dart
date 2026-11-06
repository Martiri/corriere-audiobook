import 'package:flutter/material.dart';
import '../services/audio_tts_service.dart';
import '../views/player_screen.dart';

/// Barra di controllo multimediale compatta (Mini-Player) visualizzata in sovrimpressione
class TtsControlsBar extends StatelessWidget {
  final AudioTtsService ttsService;

  const TtsControlsBar({super.key, required this.ttsService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ttsService,
      builder: (context, _) {
        final article = ttsService.currentArticle;
        if (article == null || ttsService.state == PlaybackState.idle) {
          return const SizedBox.shrink();
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final totalParagraphs = article.paragraphs.length;
        final currentNumber = (ttsService.currentIndex + 1).clamp(1, totalParagraphs);

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  article: article,
                  ttsService: ttsService,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: isDark ? Colors.blueAccent.withOpacity(0.3) : Colors.blue.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                // Icona animata/pulsante
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ttsService.isPlaying ? Icons.graphic_eq_rounded : Icons.pause_rounded,
                    color: Colors.blueAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Titolo e stato
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Paragrafo $currentNumber di $totalParagraphs • Tocca per aprire',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Controlli Play/Pausa e Stop
                IconButton(
                  icon: Icon(
                    ttsService.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                    color: Colors.blueAccent,
                    size: 32,
                  ),
                  onPressed: () {
                    if (ttsService.isPlaying) {
                      ttsService.pause();
                    } else {
                      ttsService.resume();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  onPressed: () => ttsService.stop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
