import 'picked_file_data.dart';

/// Non-web platforms don't have a browser file picker; this feature is
/// currently web-only, so this always resolves to null.
Future<PickedFileData?> pickWebFile({String accept = '*/*'}) async => null;
