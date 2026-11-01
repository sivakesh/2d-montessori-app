import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../content/blocks/website_block.dart';
import '../../public_strings.dart';
import 'public_map_frame.dart';

/// A Map block's settings, read safely from the block (a missing or
/// unknown value is the field's default), and the Google Maps addresses
/// they give. Keyless: the embed is Google's public `output=embed` map
/// (no API key, nothing secret), the link Google's documented Maps URLs.
@immutable
class MapBlockConfig {
  const MapBlockConfig({required this.address, this.satellite = false, this.zoom = 15, this.height = 320, this.showDirections = true});

  factory MapBlockConfig.of(StructuredBlock block) => MapBlockConfig(
        address: block.text('address').en.trim(),
        satellite: block.option('mapType') == 'satellite',
        zoom: int.parse(block.option('zoom')),
        height: double.parse(block.option('height')),
        showDirections: block.toggle('showDirections'),
      );

  /// Where the map is centred: an address or a place name.
  final String address;
  final bool satellite;
  final int zoom;
  final double height;
  final bool showDirections;

  /// The embedded map, in [language] where Google has it.
  Uri embedUrl({String language = 'en'}) => Uri.https('maps.google.com', '/maps', {
        'q': address,
        't': satellite ? 'k' : 'm',
        'z': '$zoom',
        'hl': language,
        'output': 'embed',
      });

  /// Directions to [address] in Google Maps (its app on phones).
  Uri get directionsUrl => Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': address});
}

/// The Map block: a heading, optional text (beside the map on wide
/// screens, above it on phones), the map at its height and the full
/// width it has, and a "Get directions" link, which is also the way to
/// the place when the map can't load. In the editor ([interactive]
/// false) the map is a picture: it doesn't take clicks, and the link
/// doesn't open.
class PublicMapBlock extends StatelessWidget {
  const PublicMapBlock({
    super.key,
    required this.config,
    required this.heading,
    required this.details,
    required this.language,
    required this.wide,
    required this.headingStyle,
    required this.bodyStyle,
    required this.accent,
    required this.interactive,
  });

  final MapBlockConfig config;
  final String heading;
  final String details;
  final PublicLanguage language;

  /// Text beside the map (tablets and desktops).
  final bool wide;
  final TextStyle headingStyle;
  final TextStyle bodyStyle;
  final Color accent;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final strings = PublicStrings.of(language);
    final title = strings.mapTitle(config.address);
    final map = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        key: const Key('public-map-area'),
        height: config.height,
        width: double.infinity,
        child: Semantics(
          container: true,
          label: title,
          child: PublicMapFrame(src: config.embedUrl(language: language.code).toString(), title: title, interactive: interactive),
        ),
      ),
    );
    final directions = config.showDirections
        ? Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextButton.icon(
              key: const Key('public-map-directions'),
              onPressed: interactive ? () => launchUrl(config.directionsUrl, mode: LaunchMode.externalApplication) : null,
              icon: Icon(Icons.directions_outlined, size: 18, color: accent),
              label: Text(strings.mapDirections),
              style: TextButton.styleFrom(foregroundColor: accent, disabledForegroundColor: accent, padding: EdgeInsets.zero),
            ),
          )
        : null;
    final text = details.isEmpty ? null : Text(details, key: const Key('public-map-details'), style: bodyStyle);
    final mapWithLink = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [map, ?directions]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading.isNotEmpty) ...[Text(heading, style: headingStyle), const SizedBox(height: 20)],
        if (text != null && wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(flex: 2, child: text), const SizedBox(width: 32), Expanded(flex: 3, child: mapWithLink)],
          )
        else ...[
          if (text != null) ...[text, const SizedBox(height: 16)],
          mapWithLink,
        ],
      ],
    );
  }
}
