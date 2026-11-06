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
      // 1. Estrazione del Titolo
      let title = '';
      const titleSelectors = ['h1.title-art', 'h1.article-title', 'h1[itemprop="headline"]', 'h1'];
      for (const sel of titleSelectors) {
        const el = document.querySelector(sel);
        if (el && el.innerText.trim().length > 0) {
          title = el.innerText.trim();
          break;
        }
      }

      // 2. Estrazione del Sottotitolo / Sommario
      let subtitle = '';
      const subtitleSelectors = ['.subtitle-art', '.article-subtitle', '.sommario', '.lead', 'h2'];
      for (const sel of subtitleSelectors) {
        const el = document.querySelector(sel);
        if (el && el.innerText.trim().length > 0 && el.innerText.trim() !== title) {
          subtitle = el.innerText.trim();
          break;
        }
      }

      // 3. Estrazione dell'Autore
      let author = '';
      const authorSelectors = ['.author-art', '.signature', '.autore', '[itemprop="author"]', '.byline'];
      for (const sel of authorSelectors) {
        const el = document.querySelector(sel);
        if (el && el.innerText.trim().length > 0) {
          author = el.innerText.trim();
          break;
        }
      }

      // 4. Estrazione della Data
      let date = '';
      const dateEl = document.querySelector('time') || document.querySelector('.date-art') || document.querySelector('.data');
      if (dateEl) {
        date = dateEl.innerText.trim() || dateEl.getAttribute('datetime') || '';
      }

      // 5. Estrazione dei Paragrafi dell'articolo
      const paragraphs = [];
      const containerSelectors = [
        '.article-body',
        '.content',
        '.story-body',
        '.body-article',
        'article',
        'main'
      ];

      let container = null;
      for (const sel of containerSelectors) {
        const el = document.querySelector(sel);
        if (el) {
          container = el;
          break;
        }
      }

      const searchRoot = container || document.body;
      const pElements = searchRoot.querySelectorAll('p');

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
        'abbonati a corriere'
      ];

      pElements.forEach(p => {
        // Ignora paragrafi dentro header, footer, adv o commenti
        if (p.closest('header, footer, nav, aside, .adv, .banner, .comments, .related')) {
          return;
        }

        const text = p.innerText ? p.innerText.trim() : '';
        // Considera solo paragrafi con contenuto significativo (almeno 25 caratteri)
        if (text.length >= 25) {
          const lower = text.toLowerCase();
          const isSpam = blacklistedTerms.some(term => lower.includes(term));
          if (!isSpam && !paragraphs.includes(text)) {
            paragraphs.push(text);
          }
        }
      });

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
      final h1El = document.querySelector('h1.title-art') ??
          document.querySelector('h1.article-title') ??
          document.querySelector('h1');
      final title = h1El?.text.trim() ?? document.querySelector('title')?.text.trim() ?? 'Articolo';

      // Sottotitolo
      final subEl = document.querySelector('.subtitle-art') ??
          document.querySelector('.article-subtitle') ??
          document.querySelector('.sommario');
      final subtitle = subEl?.text.trim() ?? '';

      // Autore
      final authorEl = document.querySelector('.author-art') ??
          document.querySelector('.signature') ??
          document.querySelector('.autore');
      final author = authorEl?.text.trim() ?? '';

      // Paragrafi
      final pElements = document.querySelectorAll('.article-body p, article p, main p');
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
