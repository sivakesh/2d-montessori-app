import 'package:cloud_firestore/cloud_firestore.dart';

class VendorModel {
  VendorModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
    required this.gstNo,
    required this.serviceType,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String? gstNo;
  final String serviceType;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory VendorModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parse(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    return VendorModel(
      id: id,
      name: data['name']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      address: data['address']?.toString() ?? '',
      gstNo: data['gstNo']?.toString(),
      serviceType: data['serviceType']?.toString() ?? '',
      isActive: data['isActive'] != false,
      createdAt: parse(data['createdAt']),
      updatedAt: parse(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'gstNo': gstNo,
        'serviceType': serviceType,
        'isActive': isActive,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

