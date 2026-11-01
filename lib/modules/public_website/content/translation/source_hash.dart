import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Change detection for translation sources. A translation remembers the
/// hash of the English text it was made from; when the English text's hash
/// changes, the translation is outdated (its text is kept).
class SourceHash {
  SourceHash._();

  /// [text] as it is compared: Windows (`\r\n`) and old Mac (`\r`) line
  /// endings become `\n`, and surrounding whitespace is removed — edits
  /// that don't change the words don't outdate a translation.
  static String normalize(String text) => text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();

  /// The SHA-256 of the [normalize]d UTF-8 text, as lowercase hex. Computed
  /// with `package:crypto` (pure Dart, the same result on the web and on
  /// devices).
  static String of(String text) => sha256.convert(utf8.encode(normalize(text))).toString();
}
