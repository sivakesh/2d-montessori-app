import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../models/admin_notification_model.dart';

class AdminNotificationViewDialog extends StatefulWidget {
  const AdminNotificationViewDialog({super.key, required this.notificationId});
  final String notificationId;
  @override
  State<AdminNotificationViewDialog> createState() => _AdminNotificationViewDialogState();
}

class _AdminNotificationViewDialogState extends State<AdminNotificationViewDialog> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell(
      desktopWidth: 900,
      desktopHeight: 720,
      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('school_notifications').doc(widget.notificationId).get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final doc = AdminNotificationModel.fromMap(widget.notificationId, snapshot.data!.data() ?? {});
            return Column(
              children: [
                ListTile(
                  title: Text(doc.title),
                  subtitle: Text('${doc.notificationType} • ${doc.category}'),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(label: const Text('Overview'), selected: _tab == 0, onSelected: (_) => setState(() => _tab = 0)),
                      ChoiceChip(label: const Text('Attachment'), selected: _tab == 1, onSelected: (_) => setState(() => _tab = 1)),
                      ChoiceChip(label: const Text('Audit'), selected: _tab == 2, onSelected: (_) => setState(() => _tab = 2)),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: switch (_tab) {
                      0 => _overview(doc),
                      1 => _attachment(doc),
                      _ => _audit(doc),
                    },
                  ),
                ),
              ],
            );
          },
        ),
    );
  }

  Widget _overview(AdminNotificationModel doc) => ListView(children: [
    _row('Title', doc.title),
    _row('Message', doc.message),
    _row('Audience', doc.audience),
    _row('Visibility', doc.visibility),
    _row('Priority', doc.priority),
    _row('Status', doc.status),
    _row('Academic Year', doc.academicYear),
    _row('Publish Date', doc.publishDate?.toIso8601String().split('T').first ?? '-'),
    _row('Expiry Date', doc.expiryDate?.toIso8601String().split('T').first ?? '-'),
    _row('Target Summary', doc.isPublic ? 'Public' : (doc.appliesToAllClasses ? 'All Classes' : doc.applicableClassNames.join(', '))),
    if (doc.appliesToAllClasses) const Chip(label: Text('All Classes')) else Wrap(spacing: 8, children: doc.applicableClassNames.map((e) => Chip(label: Text(e))).toList()),
  ]);

  Widget _attachment(AdminNotificationModel doc) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Attachment: ${doc.attachmentName.isEmpty ? 'No file attached' : doc.attachmentName}'),
      Text('Type: ${doc.attachmentMimeType.isEmpty ? '-' : doc.attachmentMimeType}'),
      Text('Size: ${doc.attachmentSize?.toString() ?? '-'}'),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: doc.attachmentUrl.isEmpty ? null : () async => launchUrl(Uri.parse(doc.attachmentUrl), mode: LaunchMode.externalApplication),
        child: const Text('Open / Download'),
      ),
    ],
  );

  Widget _audit(AdminNotificationModel doc) => ListView(children: [
    _row('Created By', doc.createdByName.isEmpty ? doc.createdBy : doc.createdByName),
    _row('Created At', doc.createdAt?.toIso8601String() ?? '-'),
    _row('Updated At', doc.updatedAt?.toIso8601String() ?? '-'),
    _row('Sent At', doc.sentAt?.toIso8601String() ?? '-'),
  ]);

  Widget _row(String a, String b) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [SizedBox(width: 160, child: Text(a, style: const TextStyle(fontWeight: FontWeight.w600))), Expanded(child: Text(b))]),
  );
}
