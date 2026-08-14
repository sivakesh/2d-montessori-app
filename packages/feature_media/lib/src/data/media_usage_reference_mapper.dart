import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/media_usage_reference.dart';

abstract final class MediaUsageReferenceMapper {
  static MediaUsageReference fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => MediaUsageReference.fromMap(snapshot.data() ?? const {});
}
