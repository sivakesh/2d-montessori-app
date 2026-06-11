import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UserViewDialog extends StatefulWidget {
  const UserViewDialog({super.key, required this.userId});

  final String userId;

  @override
  State<UserViewDialog> createState() => _UserViewDialogState();
}

class _UserViewDialogState extends State<UserViewDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, dynamic>? profileData;
  Map<String, dynamic>? userData;
  bool isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final snapshot = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(widget.userId)
          .get();

      if (userSnapshot.exists) {
        userData = userSnapshot.data();
      }
      if (snapshot.exists) {
        profileData = snapshot.data();
      }
    } catch (e) {
      // ignore: avoid_print
      print('PROFILE LOAD ERROR: $e');
    }

    if (!mounted) return;
    setState(() {
      isLoadingProfile = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 35,
                backgroundColor: Colors.green.shade100,
                backgroundImage:
                    (profileData?['profileImageUrl']?.toString() ?? '')
                        .isNotEmpty
                    ? NetworkImage(profileData!['profileImageUrl'].toString())
                    : null,
                child:
                    (profileData?['profileImageUrl']?.toString() ?? '').isEmpty
                    ? const Icon(Icons.person, size: 30, color: Colors.green)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profileData?['fullName']?.toString() ?? 'User',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      userData?['role']?.toString() ?? '',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profileData?['email']?.toString() ?? '',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TabBar(
            controller: _tabController,
            indicatorColor: Colors.green,
            labelColor: Colors.green,
            unselectedLabelColor: Colors.grey,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Profile'),
              Tab(text: 'Students'),
              Tab(text: 'Documents'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildProfileTab(),
              _buildStudentsTab(),
              _buildDocumentsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTab() {
    if (isLoadingProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    if (profileData == null) {
      return const Center(child: Text('No profile found'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: GridView.count(
        crossAxisCount: 2,
        childAspectRatio: 4.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildField('Full Name', profileData!['fullName']),
          _buildField('Phone', profileData!['phone']),
          _buildField('Email', profileData!['email']),
          _buildField('DOB', profileData!['dateOfBirth']),
          _buildField('Gender', profileData!['gender']),
          _buildField('Blood Group', profileData!['bloodGroup']),
          _buildField('Nationality', profileData!['nationality']),
          _buildField('Occupation', profileData!['occupation']),
          _buildField('City', profileData!['city']),
          _buildField('State', profileData!['state']),
          _buildField('Pincode', profileData!['pincode']),
        ],
      ),
    );
  }

  Widget _buildStudentsTab() {
    final students = profileData?['students'] as List<dynamic>? ?? const [];
    if (isLoadingProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    if (students.isEmpty) {
      return const Center(child: Text('No students linked'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: students.length,
      itemBuilder: (context, index) {
        final raw = students[index];
        final student = raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
        final name =
            student['studentName']?.toString() ??
            student['name']?.toString() ??
            'Student';
        final relation =
            student['relation']?.toString() ??
            student['classId']?.toString() ??
            '-';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green.shade100,
              child: const Icon(Icons.school, color: Colors.green),
            ),
            title: Text(name),
            subtitle: Text('Relation: $relation'),
          ),
        );
      },
    );
  }

  Widget _buildDocumentsTab() {
    final documents = profileData?['documents'] as List<dynamic>? ?? const [];
    if (isLoadingProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    if (documents.isEmpty) {
      return const Center(child: Text('No documents available'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final raw = documents[index];
        final doc = raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
        final fileUrl =
            doc['fileUrl']?.toString() ?? doc['url']?.toString() ?? '';
        final fileName =
            doc['fileName']?.toString() ?? doc['name']?.toString() ?? '-';
        final documentType =
            doc['documentType']?.toString() ?? doc['type']?.toString() ?? '-';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListTile(
            leading: const Icon(Icons.insert_drive_file, color: Colors.green),
            title: Text(documentType),
            subtitle: Text(fileName),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                if (fileUrl.isEmpty) return;
                final uri = Uri.parse(fileUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildField(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(
            value?.toString().isNotEmpty == true ? value.toString() : '-',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
