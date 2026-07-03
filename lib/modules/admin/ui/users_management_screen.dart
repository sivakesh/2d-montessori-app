import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UsersManagementScreen extends StatelessWidget {
  const UsersManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No users found'));
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final name = data['name']?.toString();
              final phone = data['phoneNumber']?.toString() ?? data['phone']?.toString();
              final email = data['email']?.toString();
              return ListTile(
                title: Text(name ?? 'User'),
                subtitle: Text(phone ?? email ?? '-'),
              );
            },
          );
        },
      ),
    );
  }
}
