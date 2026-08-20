import 'dart:typed_data';

class PickedFileData {
  const PickedFileData({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}
