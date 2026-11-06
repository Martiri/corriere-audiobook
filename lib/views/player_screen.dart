import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/article.dart';
import '../services/audio_tts_service.dart';

/// Schermata del Player Audiobook con visualizzazione e navigazione interattiva dei paragrafi
/// Totalmente protetta da SafeArea per evitare interferenze con la gesture bar di HyperOS
class PlayerScreen extends StatefulWidget {
  final Article article;
  final AudioTtsService ttsService;

  const PlayerScreen({
    super.key,
    required this.article,
    required this.ttsService,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final ScrollController _scrollController = ScrollController();
  int _lastAutoScrolledIndex = -1;

  @override
  void initState() {
    super.initState();
    // Se non sta già riproducendo questo articolo, avvia la lettura dall'inizio
    if (widget.ttsService.currentArticle?.url != widget.article.url ||
        widget.ttsService.state == PlaybackState.idle) {
      widget.ttsService.playArticle(widget.article);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Esegue lo scroll automatico per mantenere in vista il paragrafo corrente
  void _checkAutoScroll(int currentIndex) {
    if (_lastAutoScrolledIndex != currentIndex && _scrollController.hasClients) {
      _lastAutoScrolledIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        // Calcolo approssimativo dell'offset basato sull'indice del paragrafo
        final targetOffset = (currentIndex * 130.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: widget.ttsService,
      builder: (context, _) {
        final currentIndex = widget.ttsService.currentIndex;
        _checkAutoScroll(currentIndex);

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF8F9FA),
          body: SafeArea(
            top: true,
            bottom: true,
            child: Column(
              children: [
                // Top App Bar
                _buildHeader(context, isDark),

                // Lista scorrevole dei paragrafi
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: widget.article.paragraphs.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildArticleInfoCard(isDark);
                      }
                      final pIndex = index - 1;
                      final paragraphText = widget.article.paragraphs[pIndex];
                      final isCurrent = pIndex == currentIndex;

                      return _buildParagraphItem(
                        pIndex: pIndex,
                        text: paragraphText,
                        isCurrent: isCurrent,
                        isDark: isDark,
                      );
                    },
                  ),
                ),

                // Pannello di controllo audio inferiore
                _buildControlDeck(isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[850]! : Colors.grey[300]!,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Lettore Audiolibro',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          // Pulsante apri link originale
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded),
            tooltip: 'Apri articolo sul browser',
            onPressed: () async {
              final uri = Uri.tryParse(widget.article.url);
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          // Menu Sleep Timer
          PopupMenuButton<int>(
            icon: Icon(
              widget.ttsService.sleepTimerMinutes != null
                  ? Icons.timer_rounded
                  : Icons.timer_outlined,
              color: widget.ttsService.sleepTimerMinutes != null ? Colors.blueAccent : null,
            ),
            tooltip: 'Timer spegnimento',
            onSelected: (minutes) {
              if (minutes == 0) {
                widget.ttsService.cancelSleepTimer();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Timer di spegnimento annullato')),
                );
              } else {
                widget.ttsService.setSleepTimer(minutes);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Timer impostato su $minutes minuti')),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 5, child: Text('5 minuti')),
              const PopupMenuItem(value: 15, child: Text('15 minuti')),
              const PopupMenuItem(value: 30, child: Text('30 minuti')),
              const PopupMenuItem(value: 60, child: Text('60 minuti')),
              if (widget.ttsService.sleepTimerMinutes != null)
                const PopupMenuItem(value: 0, child: Text('Disattiva timer')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArticleInfoCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.article.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          if (widget.article.subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.article.subtitle,
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.grey[400] : Colors.grey[700],
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (widget.article.author.isNotEmpty) ...[
                const Icon(Icons.person_outline, size: 14, color: Colors.blueAccent),
                const SizedBox(width: 4),
                Text(
                  widget.article.author,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 12),
              ],
              const Icon(Icons.access_time_rounded, size: 14, color: Colors.blueAccent),
              const SizedBox(width: 4),
              Text(
                '~${widget.article.estimatedReadingMinutes} min di ascolto',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParagraphItem({
    required int pIndex,
    required String text,
    required bool isCurrent,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () {
        widget.ttsService.jumpToParagraph(pIndex);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrent
              ? (isDark ? Colors.blue.withOpacity(0.18) : Colors.blue.withOpacity(0.1))
              : (isDark ? const Color(0xFF141414) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrent
                ? Colors.blueAccent
                : (isDark ? Colors.grey[850]! : Colors.grey[200]!),
            width: isCurrent ? 1.5 : 1.0,
          ),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 10, top: 2),
              decoration: BoxDecoration(
                color: isCurrent ? Colors.blueAccent : (isDark ? Colors.grey[800] : Colors.grey[300]),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${pIndex + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isCurrent ? Colors.white : (isDark ? Colors.grey[300] : Colors.grey[700]),
                ),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  color: isCurrent
                      ? (isDark ? Colors.white : Colors.blue[900])
                      : (isDark ? Colors.grey[300] : Colors.black87),
                ),
              ),
            ),
            if (isCurrent)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Icon(
                  widget.ttsService.isPlaying ? Icons.volume_up_rounded : Icons.pause_rounded,
                  color: Colors.blueAccent,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlDeck(bool isDark) {
    final total = widget.article.paragraphs.length;
    final current = widget.ttsService.currentIndex;
    final currentHuman = (current + 1).clamp(1, total);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slider di progresso dei paragrafi
          Row(
            children: [
              Text(
                '$currentHuman',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Expanded(
                child: Slider(
                  value: current.toDouble().clamp(0.0, (total - 1).toDouble()),
                  min: 0.0,
                  max: (total - 1).toDouble() > 0 ? (total - 1).toDouble() : 1.0,
                  divisions: total > 1 ? total - 1 : 1,
                  activeColor: Colors.blueAccent,
                  onChanged: (val) {
                    widget.ttsService.jumpToParagraph(val.round());
                  },
                ),
              ),
              Text(
                '$total',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),

          // Pulsanti multimediali
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Salta al paragrafo precedente
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded),
                iconSize: 32,
                tooltip: 'Paragrafo precedente',
                onPressed: () => widget.ttsService.previousParagraph(),
              ),
              const SizedBox(width: 16),
              // Play / Pausa Principale
              GestureDetector(
                onTap: () {
                  if (widget.ttsService.isPlaying) {
                    widget.ttsService.pause();
                  } else {
                    widget.ttsService.resume();
                  }
                },
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Colors.blueAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent,
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.ttsService.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Salta al paragrafo successivo
              IconButton(
                icon: const Icon(Icons.skip_next_rounded),
                iconSize: 32,
                tooltip: 'Paragrafo successivo',
                onPressed: () => widget.ttsService.nextParagraph(),
              ),
              const SizedBox(width: 8),
              // Stop
              IconButton(
                icon: const Icon(Icons.stop_rounded),
                iconSize: 28,
                tooltip: 'Interrompi',
                onPressed: () => widget.ttsService.stop(),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Selettore rapido di velocità di lettura
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Velocità: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ...[0.75, 1.0, 1.25, 1.5, 2.0].map((rate) {
                  final isSelected = (widget.ttsService.speechRate - rate).abs() < 0.05;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text('${rate}x'),
                      selected: isSelected,
                      selectedColor: Colors.blueAccent.withOpacity(0.2),
                      side: BorderSide(
                        color: isSelected ? Colors.blueAccent : Colors.transparent,
                      ),
                      onSelected: (_) => widget.ttsService.setSpeechRate(rate),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
