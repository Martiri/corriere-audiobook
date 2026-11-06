import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:webview_flutter/webview_flutter.dart';
import '../config/app_config.dart';
import '../models/article.dart';

/// Servizio intelligente per l'estrazione pulita del testo degli articoli
/// Implementa l'approccio duale: estrazione diretta dal DOM (principale) + fallback HTTP con cookie
class ExtractorService {
  /// Script JavaScript pulito ed innocuo eseguito nel contesto della pagina per estrarre il testo
  static const String _domExtractorScript = r'''
  (function() {
    try {
      // 0. Se l'utente ha selezionato del testo sullo schermo, estrai direttamente quello
      let selection = window.getSelection ? window.getSelection().toString().trim() : '';
      if (selection && selection.length > 25) {
        return JSON.stringify({
          title: document.title || 'Estratto Selezionato',
          subtitle: 'Lettura del testo evidenziato sullo schermo',
          author: 'Corriere della Sera',
          date: '',
          paragraphs: selection.split(/\n+/).map(s => s.trim()).filter(s => s.length > 10)
        });
      }

      // 1. Estrazione del Titolo (supporta sia Sito Web che Edicola Digitale)
      let title = '';
      const titleSelectors = [
        'h1.chapter-title',
        'h1.title-art',
        'h1.article-title',
        'h1[data-qa="article-title"]',
        '.article-detail h1',
        '.article-detail .title',
        '.reader-title',
        '.article-head',
        'h1[itemprop="headline"]',
        'h1'
      ];
      for (const sel of titleSelectors) {
        const el = document.querySelector(sel);
        if (el && el.innerText.trim().length > 0) {
          title = el.innerText.trim();
          break;
        }
      }
      if (!title) {
        const ogTitle = document.querySelector('meta[property="og:title"]');
        if (ogTitle && ogTitle.content) title = ogTitle.content.trim();
      }

      // 2. Estrazione del Sottotitolo / Sommario
      let subtitle = '';
      const subtitleSelectors = [
        'h2.chapter-summary',
        '.article-detail .subtitle',
        '.subtitle-art',
        '.article-subtitle',
        '.sommario',
        '.lead',
        'h2'
      ];
      for (const sel of subtitleSelectors) {
        const el = document.querySelector(sel);
        if (el && el.innerText.trim().length > 0 && el.innerText.trim() !== title) {
          subtitle = el.innerText.trim();
          break;
        }
      }
      if (!subtitle) {
        const ogDesc = document.querySelector('meta[property="og:description"]');
        if (ogDesc && ogDesc.content) subtitle = ogDesc.content.trim();
      }

      // 3. Estrazione dell'Autore
      let author = '';
      const authorSelectors = [
        '.author-name',
        '.article-detail .author',
        '.author-art',
        '.signature',
        '.autore',
        '[itemprop="author"]',
        '.byline'
      ];
      for (const sel of authorSelectors) {
        const el = document.querySelector(sel);
        if (el && el.innerText.trim().length > 0) {
          author = el.innerText.trim();
          break;
        }
      }
      if (!author) {
        const metaAuthor = document.querySelector('meta[name="author"]');
        if (metaAuthor && metaAuthor.content) author = metaAuthor.content.trim();
      }

      // 4. Estrazione della Data
      let date = '';
      const dateEl = document.querySelector('time') || document.querySelector('.date-art') || document.querySelector('.data');
      if (dateEl) {
        date = dateEl.innerText.trim() || dateEl.getAttribute('datetime') || '';
      }

      // 5. Estrazione dei Paragrafi dell'articolo (Sito ed Edicola)
      const paragraphs = [];
      const blacklistedTerms = [
        'iscriviti alla newsletter',
        'tutti i diritti riservati',
        'copyright',
        'leggi anche',
        'guarda anche',
        'video correlati',
        'pubblicità',
        'banner',
        'accetta i cookie',
        'abbonati a corriere',
        'scarica l\'app'
      ];

      // Prova prima con i selettori di paragrafo standard Corriere
      const articleParagraphs = document.querySelectorAll(
        'p.chapter-paragraph, p.is-paragraph, .article-body p, [data-qa="article-body"] p, .reader-text p, .page-article p, .modal-body p, article p'
      );

      articleParagraphs.forEach(p => {
        if (p.closest('header, footer, nav, aside, .adv, .banner, .comments, .related, .modal-access__footer')) {
          return;
        }
        const text = p.innerText ? p.innerText.trim() : '';
        if (text.length >= 25) {
          const lower = text.toLowerCase();
          const isSpam = blacklistedTerms.some(term => lower.includes(term));
          if (!isSpam && !paragraphs.includes(text)) {
            paragraphs.push(text);
          }
        }
      });

      // Se non ha trovato paragrafi di un articolo singolo, cerca nel contenitore generico
      if (paragraphs.length === 0) {
        const container = document.querySelector('article, main, #articleContent, .content');
        if (container) {
          const pElements = container.querySelectorAll('p');
          pElements.forEach(p => {
            if (p.closest('header, footer, nav, aside, .adv, .banner')) return;
            const text = p.innerText ? p.innerText.trim() : '';
            if (text.length >= 25 && !paragraphs.includes(text)) {
              paragraphs.push(text);
            }
          });
        }
      }

      // 6. FALLBACK RASSEGNA STAMPA: Se ci si trova sulla home page o sull'edicola principale,
      // estrai i titoli e i sommari delle notizie principali di oggi
      if (paragraphs.length === 0) {
        const headlines = [];
        const newsCards = document.querySelectorAll(
          '.media-news, article, div[class*="card"], div[class*="story"], .has_text, .has-text, .b-story'
        );
        newsCards.forEach(card => {
          const h = card.querySelector('h1, h2, h3, h4, .title, a[class*="title"]');
          const lead = card.querySelector('p, .summary, .lead, .sommario');
          if (h) {
            const hText = h.innerText.trim();
            if (hText.length >= 15 && !headlines.some(item => item.includes(hText))) {
              let full = hText;
              if (lead && lead.innerText.trim().length >= 20) {
                full += '. ' + lead.innerText.trim();
              }
              headlines.push(full);
            }
          }
        });

        if (headlines.length >= 3) {
          return JSON.stringify({
            title: 'Corriere della Sera • Notizie di Oggi',
            subtitle: 'Rassegna audio con le notizie e i titoli principali del momento',
            author: 'Redazione Corriere della Sera',
            date: new Date().toLocaleDateString('it-IT'),
            paragraphs: headlines.slice(0, 25)
          });
        }
      }

      return JSON.stringify({
        title: title || document.title || 'Articolo Corriere',
        subtitle: subtitle,
        author: author,
        date: date,
        paragraphs: paragraphs
      });
    } catch (e) {
      return JSON.stringify({ error: e.toString() });
    }
  })();
  ''';

  /// Estrazione primaria: Esegue il parser direttamente sul DOM attivo della WebView
  static Future<Article?> extractFromWebView(
    WebViewController controller,
    String pageUrl,
  ) async {
    try {
      final rawResult = await controller.runJavaScriptReturningResult(_domExtractorScript);
      String resultString = rawResult.toString();

      // Rimuovi eventuali doppi apici e escape di stringhe JSON generati dal wrapper nativo
      if (resultString.startsWith('"') && resultString.endsWith('"')) {
        resultString = jsonDecode(resultString) as String;
      }

      final Map<String, dynamic> data = jsonDecode(resultString) as Map<String, dynamic>;

      if (data.containsKey('error')) {
        return null;
      }

      final title = data['title'] as String? ?? 'Articolo Corriere';
      final subtitle = data['subtitle'] as String? ?? '';
      final author = data['author'] as String? ?? '';
      final date = data['date'] as String? ?? '';
      final rawParagraphs = (data['paragraphs'] as List<dynamic>?) ?? [];

      final List<String> paragraphs = rawParagraphs
          .map((p) => _cleanText(p.toString()))
          .where((p) => p.isNotEmpty)
          .toList();

      if (paragraphs.isEmpty) {
        return null;
      }

      return Article(
        title: _cleanText(title),
        subtitle: _cleanText(subtitle),
        author: _cleanText(author),
        date: _cleanText(date),
        url: pageUrl,
        paragraphs: paragraphs,
      );
    } catch (e) {
      // In caso di errore nel DOM, si rimanda al fallback HTTP
      return null;
    }
  }

  /// Estrazione da link incollato o da testo inserito direttamente
  static Future<Article?> extractFromUrlOrText(String input, String cookies) async {
    final trimmed = input.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return extractFromHttp(trimmed, cookies);
    } else {
      // Testo grezzo inserito dall'utente
      final lines = trimmed
          .split(RegExp(r'\n+'))
          .map((l) => _cleanText(l))
          .where((l) => l.length >= 10)
          .toList();
      if (lines.isEmpty) return null;

      final title = lines.first.length < 100 ? lines.first : 'Testo Incollato';
      final paragraphs = lines.first.length < 100 && lines.length > 1
          ? lines.sublist(1)
          : lines;

      return Article(
        title: title,
        subtitle: 'Audiolibro generato da testo inserito',
        author: 'Lettore Utente',
        date: '',
        url: 'manual-input',
        paragraphs: paragraphs,
      );
    }
  }

  /// Estrazione secondaria di fallback: Richiesta HTTP con i cookie di sessione autenticati
  static Future<Article?> extractFromHttp(String pageUrl, String cookies) async {
    try {
      final uri = Uri.parse(pageUrl);
      final headers = {
        'User-Agent': AppConfig.customUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7',
      };

      if (cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
      }

      final response = await http.get(uri, headers: headers);
      if (response.statusCode != 200) {
        return null;
      }

      final document = html_parser.parse(response.body);

      // Titolo
      final h1El = document.querySelector('h1.chapter-title') ??
          document.querySelector('h1.title-art') ??
          document.querySelector('h1.article-title') ??
          document.querySelector('h1');
      final title = h1El?.text.trim() ?? document.querySelector('title')?.text.trim() ?? 'Articolo';

      // Sottotitolo
      final subEl = document.querySelector('h2.chapter-summary') ??
          document.querySelector('.subtitle-art') ??
          document.querySelector('.article-subtitle') ??
          document.querySelector('.sommario');
      final subtitle = subEl?.text.trim() ?? '';

      // Autore
      final authorEl = document.querySelector('.author-name') ??
          document.querySelector('.author-art') ??
          document.querySelector('.signature') ??
          document.querySelector('.autore');
      final author = authorEl?.text.trim() ?? '';

      // Paragrafi
      final pElements = document.querySelectorAll(
        'p.chapter-paragraph, p.is-paragraph, .article-body p, article p, main p'
      );
      final List<String> paragraphs = [];

      for (final p in pElements) {
        final text = _cleanText(p.text);
        if (text.length >= 25 && !paragraphs.contains(text)) {
          paragraphs.add(text);
        }
      }

      if (paragraphs.isEmpty) {
        return null;
      }

      return Article(
        title: _cleanText(title),
        subtitle: _cleanText(subtitle),
        author: _cleanText(author),
        date: '',
        url: pageUrl,
        paragraphs: paragraphs,
      );
    } catch (_) {
      return null;
    }
  }

  /// Pulisce spazi multipli, newline e caratteri non stampabili
  static String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(' ', ' ') // non-breaking space
        .trim();
  }
}
