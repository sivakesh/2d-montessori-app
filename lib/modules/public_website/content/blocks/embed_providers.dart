import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// A service whose content an Embed block may show: the addresses it
/// accepts (exact hosts and paths), the embed address rebuilt from them,
/// and what its frame may do. Nothing pasted is ever used as it is: only
/// the ids read from an accepted address go into the rebuilt one.
@immutable
class EmbedProvider {
  const EmbedProvider._({
    required this.id,
    required this.label,
    required this.frameHost,
    required this.sandbox,
    required this.allow,
    required this.fullscreen,
    required this.aspect,
    required this.height,
    required this.examples,
  });

  final String id;

  /// Its name (a brand; the same in every language).
  final String label;

  /// Where the frame's content comes from (told to visitors).
  final String frameHost;

  /// The frame's `sandbox` tokens. `allow-same-origin` is the provider's
  /// own origin here, never this website's.
  final List<String> sandbox;

  /// The frame's `allow` features (fullscreen only if the block asks).
  final List<String> allow;
  final bool fullscreen;

  /// The frame's default shape (width / height), or null for [height].
  final double? aspect;

  /// The default height (px) when the frame has no shape.
  final double height;

  /// Addresses shown as examples in the editor.
  final List<String> examples;

  static const youtube = EmbedProvider._(
    id: 'youtube',
    label: 'YouTube',
    frameHost: 'www.youtube-nocookie.com',
    sandbox: ['allow-scripts', 'allow-same-origin', 'allow-presentation', 'allow-popups', 'allow-popups-to-escape-sandbox'],
    allow: ['encrypted-media', 'picture-in-picture'],
    fullscreen: true,
    aspect: 16 / 9,
    height: 360,
    examples: ['https://www.youtube.com/watch?v=…', 'https://youtu.be/…'],
  );

  static const vimeo = EmbedProvider._(
    id: 'vimeo',
    label: 'Vimeo',
    frameHost: 'player.vimeo.com',
    sandbox: ['allow-scripts', 'allow-same-origin', 'allow-presentation', 'allow-popups', 'allow-popups-to-escape-sandbox'],
    allow: ['encrypted-media', 'picture-in-picture'],
    fullscreen: true,
    aspect: 16 / 9,
    height: 360,
    examples: ['https://vimeo.com/123456789'],
  );

  static const googleForms = EmbedProvider._(
    id: 'google_forms',
    label: 'Google Forms',
    frameHost: 'docs.google.com',
    sandbox: ['allow-scripts', 'allow-same-origin', 'allow-forms', 'allow-popups', 'allow-popups-to-escape-sandbox'],
    allow: [],
    fullscreen: false,
    aspect: null,
    height: 800,
    examples: ['https://docs.google.com/forms/d/e/…/viewform'],
  );

  static const googleCalendar = EmbedProvider._(
    id: 'google_calendar',
    label: 'Google Calendar',
    frameHost: 'calendar.google.com',
    sandbox: ['allow-scripts', 'allow-same-origin', 'allow-popups', 'allow-popups-to-escape-sandbox'],
    allow: [],
    fullscreen: false,
    aspect: null,
    height: 600,
    examples: ['https://calendar.google.com/calendar/embed?src=…'],
  );

  static const all = [youtube, vimeo, googleForms, googleCalendar];

  static EmbedProvider? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// What a pasted address or `<iframe>` code becomes: the provider and its
/// rebuilt embed address, or why it can't be shown.
@immutable
class EmbedSource {
  const EmbedSource._({this.provider, this.embedUrl, this.openUrl, this.error, this.ignored = const []});

  final EmbedProvider? provider;

  /// The frame's address, rebuilt from the ids read (never the pasted one).
  final Uri? embedUrl;

  /// The provider's own page for it (a link for visitors), if any.
  final Uri? openUrl;

  /// Why it can't be shown (a sentence for the editor), or null.
  final String? error;

  /// Parts of pasted code that are not used (scripts, attributes …).
  final List<String> ignored;

  bool get isValid => error == null && provider != null && embedUrl != null;

  static EmbedSource _fail(String error, [List<String> ignored = const []]) => EmbedSource._(error: error, ignored: ignored);

  static const supported = 'YouTube, Vimeo, Google Forms and Google Calendar';

  /// [source]: an address, or a provider's `<iframe>` code (only its
  /// `src` is read; nothing else in it is used or run).
  static EmbedSource parse(String source) {
    final text = source.trim();
    if (text.isEmpty) return _fail('Paste a link, or the provider’s <iframe> embed code.');
    var address = text;
    final ignored = <String>[];
    if (text.startsWith('<')) {
      final fragment = html_parser.parseFragment(text);
      final frames = fragment.querySelectorAll('iframe');
      final scripts = fragment.querySelectorAll('script');
      if (frames.isEmpty) {
        return _fail(scripts.isNotEmpty
            ? 'This embed code needs a script, which isn’t supported. Only $supported embeds (their link, or their <iframe> code) can be shown.'
            : 'No link or <iframe> found. Paste the provider’s link, or its <iframe> embed code.');
      }
      final frame = frames.first;
      for (final name in frame.attributes.keys) {
        final key = name.toString().toLowerCase();
        if (key != 'src') ignored.add(key.startsWith('on') ? 'on… (event handlers)' : key);
      }
      void others(dom.Node node) {
        for (final child in node.nodes) {
          if (child is dom.Element && child != frame) {
            ignored.add('<${child.localName}>');
          } else if (child is dom.Element) {
            continue;
          }
          others(child);
        }
      }

      others(fragment);
      if (frames.length > 1) ignored.add('more <iframe> elements (one embed per block)');
      address = (frame.attributes['src'] ?? '').trim();
      if (address.isEmpty) return _fail('The <iframe> has no address (src).', ignored);
    }
    final result = _fromAddress(address);
    return EmbedSource._(provider: result.provider, embedUrl: result.embedUrl, openUrl: result.openUrl, error: result.error, ignored: [...{...ignored}]);
  }

  static EmbedSource _fromAddress(String raw) {
    var value = raw.trim();
    // A link pasted without https:// ("youtu.be/…"): the host is checked
    // exactly all the same.
    if (!value.contains('://') && !value.startsWith('//') && RegExp(r'^[a-zA-Z0-9.-]+\.[a-z]{2,}/').hasMatch(value)) value = 'https://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return _fail('This isn’t a link. Paste a $supported link, or its <iframe> code.');
    if (uri.scheme != 'https') return _fail('Only https:// links can be embedded.');
    if (uri.userInfo.isNotEmpty || uri.hasPort) return _fail('This link isn’t a plain provider address.');
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return switch (host) {
      'youtube.com' || 'www.youtube.com' || 'm.youtube.com' || 'youtube-nocookie.com' || 'www.youtube-nocookie.com' || 'youtu.be' => _youtube(uri, host, segments),
      'vimeo.com' || 'www.vimeo.com' || 'player.vimeo.com' => _vimeo(uri, host, segments),
      'docs.google.com' || 'forms.gle' => _googleForms(uri, host, segments),
      'calendar.google.com' => _googleCalendar(uri, segments),
      _ => _fail('$host isn’t a supported provider. Supported: $supported.'),
    };
  }

  static final _youtubeId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static EmbedSource _youtube(Uri uri, String host, List<String> s) {
    String? id;
    if (host == 'youtu.be') {
      if (s.length == 1) id = s[0];
    } else if (s.length == 1 && s[0] == 'watch') {
      id = uri.queryParameters['v'];
    } else if (s.length == 2 && ['embed', 'shorts', 'live'].contains(s[0])) {
      id = s[1];
    }
    if (id == null || !_youtubeId.hasMatch(id)) return _fail('This isn’t a link to one YouTube video. Use the video’s Share link (playlists and channels aren’t supported).');
    final start = _seconds(uri.queryParameters['start'] ?? uri.queryParameters['t']);
    return EmbedSource._(
      provider: EmbedProvider.youtube,
      embedUrl: Uri.https('www.youtube-nocookie.com', '/embed/$id', {'rel': '0', if (start != null) 'start': '$start'}),
      openUrl: Uri.https('www.youtube.com', '/watch', {'v': id, if (start != null) 't': '${start}s'}),
    );
  }

  /// A start time: `90`, `90s` or `1m30s` (seconds), or null.
  static int? _seconds(String? value) {
    if (value == null) return null;
    final m = RegExp(r'^(?:(\d{1,2})h)?(?:(\d{1,3})m)?(?:(\d{1,5})s?)?$').firstMatch(value.trim());
    if (m == null || value.trim().isEmpty) return null;
    final total = int.parse(m[1] ?? '0') * 3600 + int.parse(m[2] ?? '0') * 60 + int.parse(m[3] ?? '0');
    return total > 0 && total < 100000 ? total : null;
  }

  static final _vimeoId = RegExp(r'^\d{1,12}$');
  static final _vimeoHash = RegExp(r'^[0-9a-f]{6,20}$');

  static EmbedSource _vimeo(Uri uri, String host, List<String> s) {
    String? id;
    String? hash;
    if (host == 'player.vimeo.com') {
      if (s.length == 2 && s[0] == 'video') id = s[1];
      hash = uri.queryParameters['h'];
    } else if (s.isNotEmpty && s.length <= 2) {
      id = s[0];
      if (s.length == 2) hash = s[1];
    }
    if (id == null || !_vimeoId.hasMatch(id) || (hash != null && !_vimeoHash.hasMatch(hash))) {
      return _fail('This isn’t a link to one Vimeo video. Use the video’s Share link.');
    }
    return EmbedSource._(
      provider: EmbedProvider.vimeo,
      embedUrl: Uri.https('player.vimeo.com', '/video/$id', {'dnt': '1', 'h': ?hash}),
      openUrl: Uri.https('vimeo.com', hash == null ? '/$id' : '/$id/$hash'),
    );
  }

  static final _formId = RegExp(r'^[A-Za-z0-9_-]{20,120}$');

  static EmbedSource _googleForms(Uri uri, String host, List<String> s) {
    if (host == 'forms.gle') return _fail('Short form links (forms.gle) can’t be checked. Open it, and paste the full docs.google.com/forms address.');
    if (s.length >= 4 && s[0] == 'forms' && s[1] == 'd' && s[2] != 'e') {
      return _fail('This is the form’s editing link. In Google Forms choose Send, then the link or embed (<>) option, and paste that.');
    }
    final ok = s.length == 5 && s[0] == 'forms' && s[1] == 'd' && s[2] == 'e' && _formId.hasMatch(s[3]) && s[4] == 'viewform';
    if (!ok) return _fail('This isn’t a Google Forms form link (docs.google.com/forms/d/e/…/viewform).');
    return EmbedSource._(
      provider: EmbedProvider.googleForms,
      embedUrl: Uri.https('docs.google.com', '/forms/d/e/${s[3]}/viewform', {'embedded': 'true'}),
      openUrl: Uri.https('docs.google.com', '/forms/d/e/${s[3]}/viewform'),
    );
  }

  static final _calendarId = RegExp(r'^[A-Za-z0-9._%+-]{1,120}@([A-Za-z0-9-]{1,63}\.){1,6}[A-Za-z]{2,24}$');
  static final _timeZone = RegExp(r'^[A-Za-z_]{1,30}(/[A-Za-z0-9_+-]{1,30}){0,2}$');

  static EmbedSource _googleCalendar(Uri uri, List<String> s) {
    // /calendar/embed, or /calendar/u/<n>/embed.
    final ok = (s.length == 2 && s[0] == 'calendar' && s[1] == 'embed') || (s.length == 4 && s[0] == 'calendar' && s[1] == 'u' && RegExp(r'^\d$').hasMatch(s[2]) && s[3] == 'embed');
    if (!ok) return _fail('This isn’t a calendar embed link. In Google Calendar open the calendar’s settings, Integrate calendar, and paste the embed code.');
    final ids = uri.queryParametersAll['src'] ?? const [];
    if (ids.isEmpty || ids.length > 10 || !ids.every(_calendarId.hasMatch)) return _fail('The calendar link has no valid calendar (src) in it.');
    final tz = uri.queryParameters['ctz'];
    final mode = uri.queryParameters['mode'];
    final query = <String, dynamic>{
      'src': ids,
      if (tz != null && _timeZone.hasMatch(tz)) 'ctz': tz,
      if (mode != null && ['WEEK', 'MONTH', 'AGENDA'].contains(mode)) 'mode': mode,
    };
    final url = Uri.https('calendar.google.com', '/calendar/embed', query);
    return EmbedSource._(provider: EmbedProvider.googleCalendar, embedUrl: url, openUrl: url);
  }
}
