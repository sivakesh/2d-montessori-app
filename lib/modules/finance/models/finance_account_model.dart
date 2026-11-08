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
    this.openingBalanceDate,
  });

  final String id;
  final String name;
  final String type;
  final double openingBalance;
  final double currentBalance;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The calendar day [openingBalance] applies from (stored as a Timestamp
  /// at that day's local midnight). Historical month-end balances include
  /// the opening balance only from this day; current balances always
  /// include it. Null on accounts made before it existed, and allowed while
  /// the opening balance is zero.
  final DateTime? openingBalanceDate;

  /// A non-zero opening balance with no [openingBalanceDate]: historical
  /// balances count it from the beginning.
  bool get hasUndatedOpeningBalance => (openingBalance * 100).round() != 0 && openingBalanceDate == null;

  /// [date] as the day an opening balance applies from (time dropped).
  static DateTime openingDay(DateTime date) => DateTime(date.year, date.month, date.day);

  factory FinanceAccountModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parse(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    double numVal(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return FinanceAccountModel(
      id: id,
      name: data['name']?.toString() ?? '',
      // No fallback to 'cash': a missing type is unclassified in the
      // Finance summary, so it must not be shown as Cash either.
      type: data['type']?.toString().trim() ?? '',
      openingBalance: numVal(data['openingBalance']),
      currentBalance: numVal(data['currentBalance']),
      isActive: data['isActive'] != false,
      createdAt: parse(data['createdAt']),
      updatedAt: parse(data['updatedAt']),
      openingBalanceDate: parse(data['openingBalanceDate']),
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
        if (openingBalanceDate != null) 'openingBalanceDate': Timestamp.fromDate(openingDay(openingBalanceDate!)),
      };
}

