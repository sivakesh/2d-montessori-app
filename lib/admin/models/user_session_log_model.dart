import 'package:cloud_firestore/cloud_firestore.dart';

class UserSessionLogModel {
  UserSessionLogModel({
    required this.id,
    required this.userId,
    required this.userDocId,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.action,
    required this.module,
    required this.platform,
    required this.userAgent,
    required this.appVersion,
    required this.createdAt,
    required this.createdDate,
    required this.source,
    required this.isDev,
  });

  factory UserSessionLogModel.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    final createdRaw = data['createdAt'];
    return UserSessionLogModel(
      id: id,
      userId: data['userId']?.toString() ?? '',
      userDocId: data['userDocId']?.toString() ?? '',
      name: data['name']?.toString() ?? 'Unknown',
      phone: data['phone']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      role: data['role']?.toString() ?? 'unknown',
      action: data['action']?.toString() ?? 'unknown',
      module: data['module']?.toString() ?? 'unknown',
      platform: data['platform']?.toString() ?? 'unknown',
      userAgent: data['userAgent']?.toString() ?? '',
      appVersion: data['appVersion']?.toString() ?? '',
      createdAt: _toDate(createdRaw),
      createdDate: data['createdDate']?.toString() ?? '',
      source: data['source']?.toString() ?? 'unknown',
      isDev: data['isDev'] == true,
    );
  }

  final String id;
  final String userId;
  final String userDocId;
  final String name;
  final String phone;
  final String email;
  final String role;
  final String action;
  final String module;
  final String platform;
  final String userAgent;
  final String appVersion;
  final DateTime createdAt;
  final String createdDate;
  final String source;
  final bool isDev;

  static DateTime _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
