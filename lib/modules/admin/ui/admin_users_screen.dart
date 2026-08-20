import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/widgets/responsive_dialog_shell.dart';
import '../../finance/widgets/finance_status_chip.dart';
import 'admin_fab.dart';
import 'admin_layout.dart';
import 'admin_user_form_screen.dart';
import 'admin_profile_screen.dart';
import 'user_view_dialog.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openForm({
    String? userId,
    Map<String, dynamic>? initialData,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AdminUserFormScreen(userId: userId, initialData: initialData),
      ),
    );
  }

  Future<void> _openProfile(String userId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdminProfileScreen(userId: userId)),
    );
  }

  Future<void> _confirmDelete(String userId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete User'),
        content: const Text('Are you sure you want to delete this user?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    await FirebaseFirestore.instance.collection('users').doc(userId).delete();
  }

  void _openUserViewDialog(BuildContext context, String userId) {
    showDialog(
      context: context,
      builder: (_) => ResponsiveDialogShell(
        desktopWidth: 700,
        desktopHeight: 600,
        child: UserViewDialog(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final isMobile =
        MediaQuery.of(context).size.width < AppSizes.mobileBreakpoint;

    return AdminLayout(
      selectedIndex: 1,
      title: 'Users',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Users',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Manage staff, administrators, and user access.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name, email, or phone',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text('Failed to load users: ${snapshot.error}'),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data();
                    final name = data['name']?.toString().toLowerCase() ?? '';
                    final email = data['email']?.toString().toLowerCase() ?? '';
                    final phone =
                        (data['phoneNumber']?.toString() ??
                                data['phone']?.toString() ??
                                '')
                            .toLowerCase();
                    return query.isEmpty ||
                        name.contains(query) ||
                        email.contains(query) ||
                        phone.contains(query);
                  }).toList();

                  if (docs.isEmpty) {
                    return const _UsersEmptyState();
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final name = data['name']?.toString() ?? 'User';
                      final email = data['email']?.toString() ?? '-';
                      final phone =
                          data['phoneNumber']?.toString() ??
                          data['phone']?.toString() ??
                          '-';
                      final role = data['role']?.toString() ?? 'parent';
                      final imageUrl =
                          data['profileImageUrl']?.toString() ?? '';
                      final isActive = data['isActive'] == true;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _UserRow(
                          name: name,
                          role: role,
                          contact: [phone, email].where((v) => v.isNotEmpty && v != '-').join(' • '),
                          isActive: isActive,
                          imageUrl: imageUrl,
                          isMobile: isMobile,
                          onView: () => _openUserViewDialog(context, doc.id),
                          onProfile: () => _openProfile(doc.id),
                          onEdit: () => _openForm(userId: doc.id, initialData: data),
                          onDelete: () => _confirmDelete(doc.id),
                        ),
                      );
                    },
                  );
                },
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      floatingActionButton: AdminFab(
        icon: Icons.add,
        onPressed: () => _openForm(),
      ),
    );
  }
}

/// Compact user row: avatar, name, role/status chips, contact line, and
/// grouped actions — matching the card style established for Finance and
/// Attendance. Presentation only; all callbacks are the screen's existing
/// handlers, unchanged.
class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.name,
    required this.role,
    required this.contact,
    required this.isActive,
    required this.imageUrl,
    required this.isMobile,
    required this.onView,
    required this.onProfile,
    required this.onEdit,
    required this.onDelete,
  });

  final String name;
  final String role;
  final String contact;
  final bool isActive;
  final String imageUrl;
  final bool isMobile;
  final VoidCallback onView;
  final VoidCallback onProfile;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
            child: imageUrl.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FinanceStatusChip(label: role.toUpperCase(), color: AppColors.secondary),
                    FinanceStatusChip(label: isActive ? 'ACTIVE' : 'INACTIVE', color: isActive ? AppColors.primary : Colors.grey),
                  ],
                ),
                if (contact.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    contact,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isMobile)
            PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (value) {
                switch (value) {
                  case 'view':
                    onView();
                    break;
                  case 'profile':
                    onProfile();
                    break;
                  case 'edit':
                    onEdit();
                    break;
                  case 'delete':
                    onDelete();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'view',
                  child: ListTile(
                    leading: Icon(Icons.visibility_outlined),
                    title: Text('View'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'profile',
                  child: ListTile(
                    leading: Icon(Icons.person_outline),
                    title: Text('Profile'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Color(0xFFD32F2F)),
                    title: Text('Delete', style: TextStyle(color: Color(0xFFD32F2F))),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: 2,
              children: [
                IconButton(
                  tooltip: 'View',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.visibility_outlined, size: 20),
                  onPressed: onView,
                ),
                IconButton(
                  tooltip: 'Profile',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.person_outline, size: 20),
                  onPressed: onProfile,
                ),
                IconButton(
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFD32F2F)),
                  onPressed: onDelete,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _UsersEmptyState extends StatelessWidget {
  const _UsersEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 36, color: AppColors.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text(
            'No users found',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'No users match your current search or filters.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
