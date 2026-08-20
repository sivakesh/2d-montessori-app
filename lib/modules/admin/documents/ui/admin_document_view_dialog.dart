import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../models/admin_school_document.dart';

class AdminDocumentViewDialog extends StatefulWidget {
  const AdminDocumentViewDialog({super.key, required this.documentId});

  final String documentId;

  @override
  State<AdminDocumentViewDialog> createState() => _AdminDocumentViewDialogState();
}

class _AdminDocumentViewDialogState extends State<AdminDocumentViewDialog> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell(
      desktopWidth: 860,
      desktopHeight: 700,
      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('school_documents').doc(widget.documentId).get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final data = snapshot.data!.data() ?? const <String, dynamic>{};
            final doc = AdminSchoolDocument.fromMap(widget.documentId, data);
            return Column(
              children: [
                ListTile(
                  title: Text(doc.title),
                  subtitle: Text(doc.documentType),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(label: const Text('Overview'), selected: _tab == 0, onSelected: (_) => setState(() => _tab = 0)),
                      ChoiceChip(label: const Text('File'), selected: _tab == 1, onSelected: (_) => setState(() => _tab = 1)),
                      ChoiceChip(label: const Text('Audit'), selected: _tab == 2, onSelected: (_) => setState(() => _tab = 2)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: switch (_tab) {
                      0 => _overview(doc),
                      1 => _fileTab(doc),
                      _ => _auditTab(doc),
                    },
                  ),
                ),
              ],
            );
          },
        ),
    );
  }

  Widget _overview(AdminSchoolDocument doc) {
    return ListView(children: [
      _row('Title', doc.title),
      _row('Type', doc.documentType),
      _row('Category', doc.category),
      _row('Academic Year', doc.academicYear.isEmpty ? '-' : doc.academicYear),
      _row('Visibility', doc.visibility),
      _row('Status', doc.status),
      _row(
        'Applicable Classes',
        doc.appliesToAllClasses
            ? 'All Classes'
            : (doc.applicableClassNames.isEmpty ? 'None' : doc.applicableClassNames.join(', ')),
      ),
      _row('Issue Date', doc.issueDate?.toIso8601String().split('T').first ?? '-'),
      _row('Expiry Date', doc.expiryDate?.toIso8601String().split('T').first ?? '-'),
      _row('Tags', doc.tags.isEmpty ? 'None' : doc.tags.join(', ')),
      _row('Description', doc.description.isEmpty ? '-' : doc.description),
      const SizedBox(height: 12),
      if (doc.appliesToAllClasses)
        const Chip(label: Text('All Classes'))
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: doc.applicableClassNames.map((e) => Chip(label: Text(e))).toList(),
        ),
    ]);
  }

  Widget _fileTab(AdminSchoolDocument doc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('File name: ${doc.fileName.isEmpty ? 'No file attached' : doc.fileName}'),
        Text('File type: ${doc.mimeType.isEmpty ? '-' : doc.mimeType}'),
        Text('File size: ${doc.fileSize?.toString() ?? '-'}'),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton(
              onPressed: doc.fileUrl.isEmpty
                  ? null
                  : () async {
                      await launchUrl(Uri.parse(doc.fileUrl), mode: LaunchMode.externalApplication);
                    },
              child: const Text('Open / Download'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _auditTab(AdminSchoolDocument doc) {
    return ListView(children: [
      _row('Uploaded By', doc.uploadedByName.isEmpty ? doc.uploadedBy : doc.uploadedByName),
      _row('Created At', doc.createdAt?.toIso8601String() ?? '-'),
      _row('Updated At', doc.updatedAt?.toIso8601String() ?? '-'),
    ]);
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 160, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
