import 'package:cloud_firestore/cloud_firestore.dart';

class FinanceAccountModel {
  FinanceAccountModel({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
    required this.currentBalance,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String type;
  final double openingBalance;
  final double currentBalance;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory FinanceAccountModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parse(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    double numVal(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return FinanceAccountModel(
      id: id,
      name: data['name']?.toString() ?? '',
      type: data['type']?.toString() ?? 'cash',
      openingBalance: numVal(data['openingBalance']),
      currentBalance: numVal(data['currentBalance']),
      isActive: data['isActive'] != false,
      createdAt: parse(data['createdAt']),
      updatedAt: parse(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'type': type,
        'openingBalance': openingBalance,
        'currentBalance': currentBalance,
        'isActive': isActive,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

