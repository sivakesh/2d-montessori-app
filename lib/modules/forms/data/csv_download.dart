import 'csv_download_stub.dart' if (dart.library.js_interop) 'csv_download_web.dart' as platform;

/// Saves [csv] as [fileName] in the browser's downloads. Returns false
/// where that isn't possible (not on the web).
bool downloadCsv(String fileName, String csv) => platform.downloadCsv(fileName, csv);
