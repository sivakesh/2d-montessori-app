import 'package:cloud_firestore/cloud_firestore.dart';

class DocumentNumberService {
  DocumentNumberService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<String> generateDocumentNumber({
    required String counterKey,
    required String defaultPrefix,
    int defaultStartNumber = 10010,
    int defaultPadLength = 8,
  }) async {
    final counterRef = _firestore.collection('system_counters').doc(counterKey);
    return _firestore.runTransaction((txn) async {
      final snap = await txn.get(counterRef);
      if (!snap.exists || snap.data() == null) {
        final currentNumber = defaultStartNumber;
        txn.set(counterRef, {
          'prefix': defaultPrefix,
          'nextNumber': defaultStartNumber + 1,
          'padLength': defaultPadLength,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return '$defaultPrefix${currentNumber.toString().padLeft(defaultPadLength, '0')}';
      }

      final data = snap.data()!;
      final prefix = data['prefix']?.toString().isNotEmpty == true
          ? data['prefix'].toString()
          : defaultPrefix;
      final nextNumber = (data['nextNumber'] as num?)?.toInt() ?? defaultStartNumber;
      final padLength = (data['padLength'] as num?)?.toInt() ?? defaultPadLength;

      txn.set(counterRef, {
        'prefix': prefix,
        'nextNumber': nextNumber + 1,
        'padLength': padLength,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return '$prefix${nextNumber.toString().padLeft(padLength, '0')}';
    });
  }
}
