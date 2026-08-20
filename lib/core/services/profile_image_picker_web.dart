import 'dart:html' as html;
import 'dart:typed_data';

import 'picked_file_data.dart';

/// Opens the browser's native file picker and reads the selected file into
/// memory. Returns null if the user cancels the picker.
Future<PickedFileData?> pickWebFile({String accept = '*/*'}) async {
  final uploadInput = html.FileUploadInputElement();
  uploadInput.accept = accept;
  uploadInput.click();

  await uploadInput.onChange.first;
  final file = uploadInput.files?.first;
  if (file == null) return null;

  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoad.first;

  return PickedFileData(name: file.name, bytes: reader.result as Uint8List);
}
