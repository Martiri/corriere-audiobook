/// Modello dati che rappresenta un articolo del Corriere della Sera estratto
class Article {
  final String title;
  final String subtitle;
  final String author;
  final String date;
  final String url;
  final List<String> paragraphs;

  Article({
    required this.title,
    this.subtitle = '',
    this.author = '',
    this.date = '',
    required this.url,
    required this.paragraphs,
  });

  /// Calcola il numero approssimativo di parole nell'articolo
  int get totalWords {
    final fullText = '${title} ${subtitle} ${paragraphs.join(" ")}';
    return fullText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  /// Stima dei minuti di ascolto a velocità 1.0x (media 130 parole/minuto per TTS italiano)
  int get estimatedReadingMinutes {
    final words = totalWords;
    final minutes = (words / 130.0).ceil();
    return minutes > 0 ? minutes : 1;
  }

  /// Crea un'istanza da un dizionario JSON (utile per cache e persistenza locale)
  factory Article.fromJson(Map<String, dynamic> json) {
    return Article(
      title: json['title'] as String? ?? 'Senza Titolo',
      subtitle: json['subtitle'] as String? ?? '',
      author: json['author'] as String? ?? '',
      date: json['date'] as String? ?? '',
      url: json['url'] as String? ?? '',
      paragraphs: (json['paragraphs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  /// Serializza l'articolo in formato JSON
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'subtitle': subtitle,
      'author': author,
      'date': date,
      'url': url,
      'paragraphs': paragraphs,
    };
  }
}
