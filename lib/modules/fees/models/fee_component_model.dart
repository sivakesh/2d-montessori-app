import 'package:cloud_firestore/cloud_firestore.dart';

class FeeComponentModel {
  FeeComponentModel({
    required this.name,
    required this.amount,
    required this.frequency,
    this.termName,
    this.dueDate,
    this.dueDayOfMonth,
    required this.isOptional,
  });

  final String name;
  final double amount;
  final String frequency;
  final String? termName;
  final DateTime? dueDate;
  final int? dueDayOfMonth;
  final bool isOptional;

  factory FeeComponentModel.fromMap(Map<String, dynamic> data) {
    final rawDueDate = data['dueDate'];
    final legacyFrequency = data['dueType']?.toString();
    return FeeComponentModel(
      name: data['name']?.toString() ?? '',
      amount: double.tryParse(data['amount']?.toString() ?? '') ?? 0,
      frequency: data['frequency']?.toString() ?? legacyFrequency ?? 'oneTime',
      termName: data['termName']?.toString(),
      dueDate: rawDueDate is Timestamp ? rawDueDate.toDate() : rawDueDate is DateTime ? rawDueDate : null,
      dueDayOfMonth: int.tryParse(data['dueDayOfMonth']?.toString() ?? ''),
      isOptional: data['isOptional'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'amount': amount,
        'frequency': frequency,
        'dueType': frequency,
        'termName': termName,
        'dueDate': dueDate,
        'dueDayOfMonth': dueDayOfMonth,
        'isOptional': isOptional,
      };
}
