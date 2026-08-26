import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../ui/admin_fab.dart';
import '../data/admin_student_service.dart';
import '../models/admin_student_model.dart';
import 'academic_history_section.dart';

class AdminStudentViewDialog extends StatefulWidget {
  const AdminStudentViewDialog({
    super.key,
    required this.studentId,
    this.readOnly = false,
  });

  final String studentId;

  /// When true, hides parent-linking and document management mutations
  /// (used when Staff opens the shared Student View from the main
  /// Students screen). Admin section usage is unaffected.
  final bool readOnly;

  @override
  State<AdminStudentViewDialog> createState() => _AdminStudentViewDialogState();
}

class _AdminStudentViewDialogState extends State<AdminStudentViewDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final AdminStudentService _service = AdminStudentService();
  final TextEditingController _docNameController = TextEditingController();
  Map<String, dynamic>? _studentData;
  Map<String, String> _classNames = <String, String>{};
  List<Map<String, dynamic>> linkedParents = [];
  Map<String, String> selectedRelations = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadStudent();
    _loadLinkedParents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _docNameController.dispose();
    super.dispose();
  }

  Future<void> _loadStudent() async {
    final studentSnapshot = await FirebaseFirestore.instance
        .collection('students')
        .doc(widget.studentId)
        .get();
    final classesSnapshot = await FirebaseFirestore.instance.collection('classes').get();
    if (!mounted) return;
    setState(() {
      _studentData = studentSnapshot.data();
      _classNames = {
        for (final doc in classesSnapshot.docs)
          doc.id: doc.data()['name']?.toString() ?? doc.id,
      };
      _loading = false;
    });
  }

  Future<void> _loadLinkedParents() async {
    final studentDoc = await FirebaseFirestore.instance
        .collection('students')
        .doc(widget.studentId)
        .get();

    final parentLinks = List<Map<String, dynamic>>.from(
      studentDoc.data()?['parentLinks'] ?? [],
    );

    final temp = <Map<String, dynamic>>[];
    for (final link in parentLinks) {
      final userId = link['userId']?.toString() ?? '';
      if (userId.isEmpty) continue;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = userDoc.data() ?? <String, dynamic>{};

      temp.add({
        'userId': userId,
        'name': data['name']?.toString() ?? '',
        'email': data['email']?.toString() ?? '',
        'phone': data['phone']?.toString() ?? '',
        'relation': link['relation']?.toString() ?? 'Father',
      });
    }

    if (!mounted) return;
    setState(() {
      linkedParents = temp;
      selectedRelations = {
        for (final parent in temp)
          parent['userId']?.toString() ?? '': parent['relation']?.toString() ?? 'Father',
      };
    });
  }

  AdminStudentModel? get _student {
    final data = _studentData;
    if (data == null) return null;
    return AdminStudentModel.fromMap(widget.studentId, data);
  }

  Future<void> _refresh() async {
    await _loadStudent();
    await _loadLinkedParents();
    if (mounted) setState(() {});
  }

  Future<void> _uploadDocument() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? 'dat').toLowerCase();
    final ref = FirebaseStorage.instance
        .ref()
        .child('students/${widget.studentId}/${DateTime.now().millisecondsSinceEpoch}.$ext');
    final task = await ref.putData(bytes);
    final url = await task.ref.getDownloadURL();
    final docName = _docNameController.text.trim().isEmpty
        ? file.name.split('.').first
        : _docNameController.text.trim();

    await FirebaseFirestore.instance.collection('students').doc(widget.studentId).set({
      'documents': FieldValue.arrayUnion([
        {
          'name': docName,
          'url': url,
          'uploadedAt': FieldValue.serverTimestamp(),
        },
      ]),
    }, SetOptions(merge: true));

    _docNameController.clear();
    await _refresh();
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete document?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _deleteDocument(String url) async {
    if (!await _confirmDelete()) return;
    await _service.removeStudentDocument(
      studentId: widget.studentId,
      documentUrl: url,
    );
    await _refresh();
  }

  void _addParent(DocumentSnapshot<Map<String, dynamic>> user) {
    final exists = linkedParents.any((e) => e['userId']?.toString() == user.id);
    if (exists) return;

    final data = user.data() ?? <String, dynamic>{};

    setState(() {
      linkedParents.add({
        'userId': user.id,
        'name': data['name']?.toString() ?? '',
        'email': data['email']?.toString() ?? '',
        'phone': data['phone']?.toString() ?? '',
        'relation': 'Father',
      });
      selectedRelations[user.id] = 'Father';
    });
  }

  Future<void> _saveParentLinks() async {
    final links = selectedRelations.entries
        .map(
          (e) => {
            'userId': e.key,
            'relation': e.value,
          },
        )
        .toList();

    await FirebaseFirestore.instance.collection('students').doc(widget.studentId).set({
      'parentLinks': links,
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Parents linked successfully')),
    );
    await _refresh();
  }

  Future<void> _openParentLookup() async {
    final searchController = TextEditingController();

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return ResponsiveDialogShell(
          desktopWidth: 700,
          desktopHeight: 600,
          child: StatefulBuilder(
            builder: (context, setLocalState) {
              return Column(
                  children: [
                    AppBar(
                      automaticallyImplyLeading: false,
                      title: const Text('Add Parent'),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(dialogContext, false),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: searchController,
                            decoration: const InputDecoration(
                              labelText: 'Search parent users',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (_) => setLocalState(() {}),
                          ),
                          const SizedBox(height: 12),
                          FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                            future: _service.searchParentUsers(searchController.text),
                            builder: (context, snapshot) {
                              final parents = snapshot.data ?? const [];
                              return Column(
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: null,
                                    items: [
                                      for (final parent in parents)
                                        DropdownMenuItem(
                                          value: parent.id,
                                          child: Text(parent.data()['name']?.toString() ?? parent.id),
                                        ),
                                    ],
                                    onChanged: (value) async {
                                      if (value == null) return;
                                      final selected = parents.firstWhere(
                                        (parent) => parent.id == value,
                                      );
                                      _addParent(selected);
                                      if (mounted) Navigator.pop(dialogContext, true);
                                    },
                                    decoration: const InputDecoration(labelText: 'Select Parent'),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
            },
          ),
        );
      },
    );
  }

  Future<void> _openDocument(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = _student;
    final isMobile = MediaQuery.of(context).size.width < 700;

    final body = _loading || student == null
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: (student.profileImageUrl.isNotEmpty)
                          ? NetworkImage(student.profileImageUrl)
                          : null,
                      backgroundColor: Colors.green.shade100,
                      child: student.profileImageUrl.isEmpty
                          ? const Icon(Icons.school, color: Colors.green)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            student.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            student.admissionNo,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
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
                    Tab(text: 'Parents'),
                    Tab(text: 'Documents'),
                    Tab(text: 'Academic History'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProfileTab(student),
                    _buildParentsTab(student),
                    _buildDocumentsTab(student),
                    _buildAcademicHistoryTab(student),
                  ],
                ),
              ),
            ],
          );

    if (isMobile) {
      return Scaffold(body: SafeArea(child: body));
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(width: 900, height: 680, child: body),
    );
  }

  Widget _buildProfileTab(AdminStudentModel student) {
    final data = _studentData ?? const <String, dynamic>{};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            context,
            'Basic Information',
            [
              _info('Full Name', _display(data['name'])),
              _info('Admission No', _display(data['admissionNo'])),
              _info('Class', _classNames[data['classId']?.toString()] ?? _display(data['classId'])),
              _info('Section', _display(data['section'])),
              _info('Roll Number', _display(data['rollNumber'])),
            ],
          ),
          const SizedBox(height: 12),
          _buildSection(
            context,
            'Personal Details',
            [
              _info('Date of Birth', _formatDate(data['dateOfBirth'])),
              _info('Gender', _display(data['gender'])),
              _info('Blood Group', _display(data['bloodGroup'])),
              _info('Nationality', _display(data['nationality'])),
              _info('Mother Tongue', _display(data['motherTongue'])),
            ],
          ),
          const SizedBox(height: 12),
          _buildSection(
            context,
            'Address',
            [
              _info('Address', _display(data['addressLine'] ?? data['address'])),
            ],
            fullWidth: true,
          ),
        ],
      ),
    );
  }

  Widget _buildParentsTab(AdminStudentModel student) {
    if (widget.readOnly) {
      return _buildParentList();
    }
    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: _buildParentList()),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveParentLinks,
                  child: const Text('Save Parent Links'),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 80,
          child: AdminFab(
            icon: Icons.add,
            onPressed: _openParentLookup,
          ),
        ),
      ],
    );
  }

  Widget _buildParentList() {
    if (linkedParents.isEmpty) {
      return const Center(child: Text('No parents linked'));
    }

    return ListView.builder(
      itemCount: linkedParents.length,
      itemBuilder: (context, index) {
        final parent = linkedParents[index];
        final userId = parent['userId']?.toString() ?? '';
        final relation = selectedRelations[userId] ?? parent['relation']?.toString() ?? 'Father';

        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            title: Text(parent['name']?.toString() ?? ''),
            subtitle: Text(parent['email']?.toString() ?? ''),
            trailing: widget.readOnly
                ? Text(relation, style: const TextStyle(fontWeight: FontWeight.w600))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<String>(
                        value: relation,
                        items: const [
                          DropdownMenuItem(value: 'Father', child: Text('Father')),
                          DropdownMenuItem(value: 'Mother', child: Text('Mother')),
                          DropdownMenuItem(value: 'Guardian', child: Text('Guardian')),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            parent['relation'] = val;
                            selectedRelations[userId] = val;
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          setState(() {
                            selectedRelations.remove(userId);
                            linkedParents.removeAt(index);
                          });
                        },
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildDocumentsTab(AdminStudentModel student) {
    final docs = student.documents;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: docs.isEmpty
                ? const Center(child: Text('No documents uploaded'))
                : ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (context, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.insert_drive_file, color: Colors.green),
                          title: Text(doc.name),
                          subtitle: Text(doc.url),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.open_in_new),
                                onPressed: () => _openDocument(doc.url),
                              ),
                              if (!widget.readOnly)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteDocument(doc.url),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (!widget.readOnly) ...[
            TextField(
              controller: _docNameController,
              decoration: const InputDecoration(
                labelText: 'Document Name',
                prefixIcon: Icon(Icons.drive_file_rename_outline),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _uploadDocument,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A student's full enrollment history plus the "Assign to Academic
  /// Year" action — delegates entirely to [AcademicHistorySection] (its
  /// own [ConsumerWidget], independently testable) rather than converting
  /// this whole (already Firestore-heavy, tab-crash-prone — see
  /// admin_student_form_class_dropdown_test.dart) `StatefulWidget` into a
  /// `ConsumerStatefulWidget`, so this addition can't affect the
  /// Profile/Parents/Documents tabs' existing behavior at all.
  Widget _buildAcademicHistoryTab(AdminStudentModel student) {
    return AcademicHistorySection(
      studentId: widget.studentId,
      currentClassId: student.classId,
      classNames: _classNames,
      readOnly: widget.readOnly,
      onAssigned: _refresh,
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> items, {
    bool fullWidth = false,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (fullWidth)
              Column(children: items)
            else
              GridView.count(
                crossAxisCount: isMobile ? 1 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 12,
                childAspectRatio: 3.5,
                children: items,
              ),
          ],
        ),
      ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _display(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    if (value is Timestamp) return MaterialLocalizations.of(context).formatMediumDate(value.toDate());
    if (value is DateTime) return MaterialLocalizations.of(context).formatMediumDate(value);
    final parsed = DateTime.tryParse(value.toString());
    if (parsed != null) return MaterialLocalizations.of(context).formatMediumDate(parsed);
    return _display(value);
  }
}
