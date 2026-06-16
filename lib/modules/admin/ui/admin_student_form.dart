// ignore_for_file: use_build_context_synchronously
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../students/data/admin_student_service.dart';
import '../students/models/admin_student_model.dart';

class AdminStudentForm extends StatefulWidget {
  const AdminStudentForm({
    super.key,
    this.studentId,
    this.initialData,
  });

  final String? studentId;
  final Map<String, dynamic>? initialData;

  @override
  State<AdminStudentForm> createState() => _AdminStudentFormState();
}

class _AdminStudentFormState extends State<AdminStudentForm>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _service = AdminStudentService();
  final _picker = ImagePicker();

  final _nameController = TextEditingController();
  final _admissionController = TextEditingController();
  final _sectionController = TextEditingController();
  final _rollNumberController = TextEditingController();
  final _dobController = TextEditingController();
  final _bloodGroupController = TextEditingController();
  final _nationalityController = TextEditingController();
  final _motherTongueController = TextEditingController();
  final _address1Controller = TextEditingController();
  final _address2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  List<dynamic> _classes = [];
  bool _loading = true;
  bool _isActive = true;
  bool isUploadingImage = false;
  bool isSaving = false;
  bool isSavingParents = false;
  bool isUploadingDocument = false;
  bool isSavingDocuments = false;
  String? _classId;
  String _gender = 'Male';
  String _selectedBloodGroup = 'A+';
  String _profileImageUrl = '';
  XFile? _pickedImage;
  Uint8List? _pickedImageBytes;
  List<Map<String, dynamic>> _documents = [];
  List<Map<String, dynamic>> _parentLinks = [];
  List<Map<String, dynamic>> _allUsers = [];
  String _searchQuery = '';

  static const _bloodGroups = <String>[
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final data = widget.initialData ?? const {};
    _nameController.text = data['name']?.toString() ?? '';
    _admissionController.text = data['admissionNo']?.toString() ?? '';
    _sectionController.text = data['section']?.toString() ?? '';
    _rollNumberController.text = data['rollNumber']?.toString() ?? '';
    _dobController.text = data['dateOfBirth']?.toString() ?? '';
    _bloodGroupController.text = data['bloodGroup']?.toString() ?? '';
    _nationalityController.text = data['nationality']?.toString() ?? '';
    _motherTongueController.text = data['motherTongue']?.toString() ?? '';
    _address1Controller.text = data['addressLine1']?.toString() ?? '';
    _address2Controller.text = data['addressLine2']?.toString() ?? '';
    _cityController.text = data['city']?.toString() ?? '';
    _stateController.text = data['state']?.toString() ?? '';
    _pincodeController.text = data['pincode']?.toString() ?? '';
    _classId = data['classId']?.toString();
    _gender = data['gender']?.toString() ?? 'Male';
    _selectedBloodGroup = _bloodGroups.contains(_bloodGroupController.text)
        ? _bloodGroupController.text
        : (_bloodGroupController.text.isNotEmpty
            ? _bloodGroupController.text
            : 'A+');
    _bloodGroupController.text = _selectedBloodGroup;
    _isActive = data['isActive'] != false;
    _profileImageUrl = data['profileImageUrl']?.toString() ?? '';
    _parentLinks = _normalizeParentLinks(data['parentLinks']);
    _documents = _normalizeDocuments(data['documents']);
    _loadClasses();
    _fetchUsers();
    _loadDocuments();
    debugPrint('Loaded Parent Links: ${_parentLinks.length}');
    debugPrint('Loaded Documents: ${_documents.length}');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _admissionController.dispose();
    _sectionController.dispose();
    _rollNumberController.dispose();
    _dobController.dispose();
    _bloodGroupController.dispose();
    _nationalityController.dispose();
    _motherTongueController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  void fillSampleData() {
    _nameController.text = 'Aarav Kumar';
    _admissionController.text = 'ADM2026001';
    _sectionController.text = 'A';
    _rollNumberController.text = '12';
    _dobController.text = '2019-06-15';
    _gender = 'Male';
    _selectedBloodGroup = 'O+';
    _bloodGroupController.text = 'O+';
    _nationalityController.text = 'Indian';
    _motherTongueController.text = 'Tamil';
    _address1Controller.text = '12, Gandhi Street';
    _address2Controller.text = 'Near Temple Road';
    _cityController.text = 'Coimbatore';
    _stateController.text = 'Tamil Nadu';
    _pincodeController.text = '641001';
    _isActive = true;
    safeSetState(() {});
  }

  void safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  List<Map<String, dynamic>> _normalizeParentLinks(dynamic rawLinks) {
    return (rawLinks as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) {
          final map = Map<String, dynamic>.from(e);
          return {
            'id': map['userId'] ?? map['id'],
            'name': map['name'] ?? '',
            'email': map['email'] ?? '',
            'relation': map['relation'] ?? 'Father',
          };
        })
        .where((e) => (e['id']?.toString() ?? '').isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> _normalizeDocuments(dynamic rawDocs) {
    return (rawDocs as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) {
          final map = Map<String, dynamic>.from(e);
          return {
            'name': map['name'] ?? '',
            'fileName': map['fileName'] ?? '',
            'url': map['url'] ?? '',
          };
        })
        .where((e) => (e['url']?.toString() ?? '').isNotEmpty)
        .toList();
  }

  Future<void> _fetchUsers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'parent')
        .get();

    if (!mounted) return;
    safeSetState(() {
      _allUsers = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'email': data['email'] ?? '',
        };
      }).toList();
    });
  }

  Future<void> _loadDocuments() async {
    final studentId = widget.studentId;
    if (studentId == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('students')
        .doc(studentId)
        .get();
    final data = doc.data();

    final rawDocs = data?['documents'];
    final loadedDocs = (rawDocs as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['url']?.toString() ?? '').isNotEmpty)
        .toList();

    if (mounted) {
      setState(() {
        _documents = loadedDocs;
      });
    }
    debugPrint('Loaded Documents: ${loadedDocs.length}');
  }

  Future<void> _loadClasses() async {
    final classes = await _service.getClasses();
    if (!mounted) return;
    safeSetState(() {
      _classes = classes;
      _classId ??= classes.isNotEmpty ? classes.first.id : null;
      _loading = false;
    });
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      initialDate: DateTime.tryParse(_dobController.text) ?? DateTime.now(),
    );
    if (picked == null) return;
    safeSetState(() {
      _dobController.text = picked.toIso8601String().split('T').first;
    });
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    safeSetState(() {
      _pickedImage = file;
      _pickedImageBytes = bytes;
    });
  }

  Future<String> _uploadImage() async {
    if (_pickedImage == null) return _profileImageUrl;

    try {
      if (!mounted) return _profileImageUrl;
      safeSetState(() => isUploadingImage = true);

      final bytes = await _pickedImage!.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('students/${widget.studentId ?? DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(bytes);
      if (!mounted) return _profileImageUrl;
      final url = await ref.getDownloadURL();

      if (!mounted) return url;
      safeSetState(() {
        _pickedImageBytes = bytes;
        isUploadingImage = false;
      });
      return url;
    } catch (_) {
      if (mounted) safeSetState(() => isUploadingImage = false);
      return _profileImageUrl;
    }
  }

  Future<void> _saveStudent() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;

    final classId = _classId ?? '';
    if (classId.isEmpty) return;

    safeSetState(() => isSaving = true);

    try {
      debugPrint('Student ID: ${widget.studentId}');
      debugPrint('Saving Parent Links: ${_parentLinks.length}');
      debugPrint('Saving Documents: ${_documents.length}');
      debugPrint('Existing documents before student save: ${widget.initialData?['documents']}');
      final admissionNo = _admissionController.text.trim();
      final isDuplicate = await _service.isAdmissionNoTaken(
        admissionNo,
        ignoreId: widget.studentId,
      );
      if (isDuplicate) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admission number already exists')),
        );
        return;
      }

      final imageUrl = await _uploadImage();
      if (!mounted) return;

      final model = AdminStudentModel(
        id: widget.studentId ?? '',
        name: _nameController.text.trim(),
        admissionNo: admissionNo,
        classId: classId,
        dateOfBirth: _dobController.text.trim(),
        gender: _gender,
        isActive: _isActive,
        isApproved: widget.initialData?['isApproved'] == true,
        createdAt: null,
        createdBy: widget.initialData?['createdBy']?.toString(),
        parentLinks: _parentLinks
            .where((e) => (e['id']?.toString() ?? '').isNotEmpty)
            .map(
              (e) => AdminStudentParentLink.fromMap({
                'userId': e['id'],
                'name': e['name'] ?? '',
                'email': e['email'] ?? '',
                'relation': e['relation'] ?? 'Father',
              }),
            )
            .toList(),
        documents: const [],
        profileImageUrl: imageUrl,
      );

      final studentId = widget.studentId;
      if (studentId == null) {
        await _service.createStudent(student: model, createdBy: 'admin');
      } else {
        await _service.updateStudent(
          studentId: studentId,
          student: model,
        );
      }
      debugPrint('Existing documents after student save: $_documents');

      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) safeSetState(() => isSaving = false);
    }
  }

  Future<void> _saveParentLinks() async {
    if (widget.studentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save student first')),
      );
      return;
    }

    setState(() => isSavingParents = true);

    try {
      final studentId = widget.studentId!;

      debugPrint("Saving Parents: $_parentLinks");

      final linksRef =
          FirebaseFirestore.instance.collection('user_student_links');

      final existing = await linksRef
          .where('studentId', isEqualTo: studentId)
          .get();

      for (final doc in existing.docs) {
        await doc.reference.delete();
      }

      for (final parent in _parentLinks) {
        final parentId = parent['id']?.toString() ?? '';
        if (parentId.isEmpty) continue;

        await linksRef.add({
          'userId': parentId,
          'studentId': studentId,
          'relation': parent['relation'] ?? 'Father',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await FirebaseFirestore.instance
          .collection('students')
          .doc(studentId)
          .set({
        'parentLinks': _parentLinks
            .where((e) => (e['id']?.toString() ?? '').isNotEmpty)
            .map((e) => {
                  'userId': e['id'],
                  'relation': e['relation'],
                })
            .toList(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      debugPrint("Saved Parents SUCCESS");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parents saved successfully')),
      );
    } catch (e) {
      debugPrint("SAVE PARENTS ERROR: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save parents')),
      );
    }

    if (mounted) {
      setState(() => isSavingParents = false);
    }
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _fieldShell({
    required String label,
    required Widget child,
    bool fullWidth = false,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: content);
    }
    return content;
  }

  Widget _textField({
    required TextEditingController controller,
    String? hintText,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        hintText: hintText,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: onTap != null
            ? const Icon(Icons.calendar_month, size: 20)
            : null,
      ),
      validator: (value) {
        if (controller == _nameController ||
            controller == _admissionController ||
            controller == _address1Controller ||
            controller == _cityController ||
            controller == _stateController ||
            controller == _pincodeController) {
          return value == null || value.trim().isEmpty ? 'Required' : null;
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.studentId == null ? 'Add Student' : 'Edit Student'),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: Colors.green,
            labelColor: Colors.green,
            unselectedLabelColor: Colors.grey,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Students'),
              Tab(text: 'Parents'),
              Tab(text: 'Documents'),
            ],
          ),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    _buildStudentsTab(),
                    _buildParentsTab(),
                    _buildDocumentsTab(),
                  ],
                ),
                if (isSaving)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.3),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth = constraints.maxWidth < 700
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 16) / 2;

              Widget halfField({required Widget child}) {
                return SizedBox(width: fieldWidth, child: child);
              }

              final ImageProvider<Object>? avatarImage =
                  _pickedImageBytes != null
                      ? MemoryImage(_pickedImageBytes!)
                      : (_profileImageUrl.isNotEmpty
                          ? NetworkImage(_profileImageUrl)
                          : null);

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            GestureDetector(
                              onTap: _pickImage,
                              child: CircleAvatar(
                                radius: 40,
                                backgroundImage: avatarImage,
                                child: avatarImage == null
                                    ? const Icon(Icons.camera_alt)
                                    : null,
                              ),
                            ),
                            if (isUploadingImage)
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('Upload Image'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('Basic Info'),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: fillSampleData,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Seed Sample'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      halfField(
                        child: _fieldShell(
                          label: 'Full Name',
                          child: _textField(controller: _nameController),
                        ),
                      ),
                      halfField(
                        child: _fieldShell(
                          label: 'Admission No',
                          child: _textField(controller: _admissionController),
                        ),
                      ),
                      halfField(
                        child: _fieldShell(
                          label: 'Class',
                          child: DropdownButtonFormField<String>(
                            initialValue: _classId,
                            items: [
                              for (final c in _classes)
                                DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.data()['name']?.toString() ?? ''),
                                ),
                            ],
                            onChanged: (value) => setState(() => _classId = value),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (value) =>
                                value == null || value.isEmpty ? 'Required' : null,
                          ),
                        ),
                      ),
                      halfField(
                        child: _fieldShell(
                          label: 'Section',
                          child: _textField(controller: _sectionController),
                        ),
                      ),
                      halfField(
                        child: _fieldShell(
                          label: 'Roll Number',
                          child: _textField(controller: _rollNumberController),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle('Personal Details'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      halfField(
                        child: _fieldShell(
                          label: 'Date of Birth',
                          child: _textField(
                            controller: _dobController,
                            readOnly: true,
                            onTap: _pickDob,
                          ),
                        ),
                      ),
                      halfField(
                        child: _fieldShell(
                          label: 'Gender',
                          child: DropdownButtonFormField<String>(
                            initialValue: _gender,
                            items: const [
                              DropdownMenuItem(value: 'Male', child: Text('Male')),
                              DropdownMenuItem(value: 'Female', child: Text('Female')),
                              DropdownMenuItem(value: 'Other', child: Text('Other')),
                            ],
                            onChanged: (value) =>
                                setState(() => _gender = value ?? 'Male'),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      halfField(
                        child: _fieldShell(
                          label: 'Blood Group',
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedBloodGroup,
                            items: [
                              for (final bloodGroup in _bloodGroups)
                                DropdownMenuItem(
                                  value: bloodGroup,
                                  child: Text(bloodGroup),
                                ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedBloodGroup = value ?? 'A+';
                                _bloodGroupController.text = _selectedBloodGroup;
                              });
                            },
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      halfField(
                        child: _fieldShell(
                          label: 'Nationality',
                          child: _textField(controller: _nationalityController),
                        ),
                      ),
                      halfField(
                        child: _fieldShell(
                          label: 'Mother Tongue',
                          child: _textField(controller: _motherTongueController),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle('Address'),
                  const SizedBox(height: 16),
                  _fieldShell(
                    fullWidth: true,
                    label: 'Address Line 1',
                    child: _textField(controller: _address1Controller),
                  ),
                  const SizedBox(height: 12),
                  _fieldShell(
                    fullWidth: true,
                    label: 'Address Line 2',
                    child: _textField(controller: _address2Controller),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      halfField(
                        child: _fieldShell(
                          label: 'City',
                          child: _textField(controller: _cityController),
                        ),
                      ),
                      halfField(
                        child: _fieldShell(
                          label: 'State',
                          child: _textField(controller: _stateController),
                        ),
                      ),
                      halfField(
                        child: _fieldShell(
                          label: 'Pincode',
                          child: _textField(controller: _pincodeController),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: _isActive,
                    onChanged: (value) => setState(() => _isActive = value),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : _saveStudent,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildParentsTab() {
    final filteredUsers = _allUsers.where((user) {
      final q = _searchQuery.toLowerCase();
      return user['name'].toString().toLowerCase().contains(q) ||
          user['email'].toString().toLowerCase().contains(q);
    }).toList();

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search by name/email',
                  prefixIcon: Icon(Icons.search),
                  border: UnderlineInputBorder(),
                ),
                onChanged: (value) {
                  safeSetState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: filteredUsers.isEmpty
                        ? const Center(child: Text('No parents found'))
                        : ListView.builder(
                            itemCount: filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = filteredUsers[index];
                              return ListTile(
                                title: Text(user['name']?.toString() ?? ''),
                                subtitle: Text(user['email']?.toString() ?? ''),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.add_circle,
                                    color: Colors.green,
                                  ),
                                  onPressed: () => _addParent(user),
                                ),
                              );
                            },
                          ),
                  ),
                  Expanded(
                    child: _parentLinks.isEmpty
                        ? const Center(child: Text('No parents linked'))
                        : ListView.builder(
                            itemCount: _parentLinks.length,
                            itemBuilder: (context, index) {
                              final parent = _parentLinks[index];
                              return Card(
                                margin: const EdgeInsets.all(8),
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person),
                                  ),
                                  title: Text(parent['name']?.toString() ?? 'Parent'),
                                  subtitle: Text(parent['email']?.toString() ?? ''),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      DropdownButton<String>(
                                        value: parent['relation']?.toString() ??
                                            'Father',
                                        underline: const SizedBox(),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'Father',
                                            child: Text('Father'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'Mother',
                                            child: Text('Mother'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'Guardian',
                                            child: Text('Guardian'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          safeSetState(() {
                                            _parentLinks[index]['relation'] = value;
                                          });
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        onPressed: () {
                                          safeSetState(() {
                                            _parentLinks.removeAt(index);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSavingParents ? null : _saveParentLinks,
                  child: isSavingParents
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Parent Links'),
                ),
              ),
            ),
          ],
        ),
        if (isSavingParents)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }

  void _addParent(Map<String, dynamic> user) {
    final exists = _parentLinks.any((p) => p['id'] == user['id']);
    if (exists) return;

    safeSetState(() {
      _parentLinks.add({
        'id': user['id'],
        'name': user['name'],
        'email': user['email'],
        'relation': 'Father',
      });
    });
  }

  Widget _buildDocumentsTab() {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: _documents.isEmpty
                  ? const Center(child: Text('No documents uploaded'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 16),
                      itemCount: _documents.length,
                      itemBuilder: (context, index) {
                        final doc = _documents[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 16,
                          ),
                          child: ListTile(
                            leading: const Icon(
                              Icons.insert_drive_file,
                              color: Colors.green,
                            ),
                            title: Text(doc['name']?.toString() ?? ''),
                            subtitle: Text(doc['fileName']?.toString() ?? ''),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.open_in_new),
                                  onPressed: () async {
                                    final url = doc['url'];
                                    if (url != null) {
                                      await launchUrl(
                                        Uri.parse(url.toString()),
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _documents.removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        Positioned(
          top: 10,
          right: 16,
          child: FloatingActionButton(
            mini: true,
            onPressed: _openUploadDialog,
            child: const Icon(Icons.add),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSavingDocuments ? null : _saveDocuments,
                child: isSavingDocuments
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Documents'),
              ),
            ),
          ),
        ),
        if (isUploadingDocument)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _pickAndUploadDocument(String type) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    try {
      setState(() => isUploadingDocument = true);
      final studentKey = widget.studentId ??
          'temp_${DateTime.now().millisecondsSinceEpoch}';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final ref = FirebaseStorage.instance
          .ref()
          .child('students/$studentKey/documents/$fileName');
      final uploadTask = ref.putData(file.bytes!);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      setState(() {
        _documents.add({
          'name': type,
          'fileName': file.name,
          'url': downloadUrl,
        });
      });
      debugPrint('Documents after upload: $_documents');
    } catch (e) {
      debugPrint('UPLOAD ERROR: $e');
    } finally {
      if (mounted) setState(() => isUploadingDocument = false);
    }
  }

  void _openUploadDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        String selectedType = 'Aadhar Card';

        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Upload Document'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Document Type',
                    ),
                    items: const [
                      'Aadhar Card',
                      'Birth Certificate',
                      'Transfer Certificate',
                      'Medical Record',
                    ].map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setModalState(() => selectedType = val);
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: isUploadingDocument
                        ? null
                        : () async {
                            await _pickAndUploadDocument(selectedType);
                            if (mounted && Navigator.of(dialogContext).canPop()) {
                              Navigator.pop(dialogContext);
                            }
                          },
                    icon: isUploadingDocument
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload),
                    label: Text(
                      isUploadingDocument ? 'Uploading...' : 'Upload File',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveDocuments() async {
    final studentId = widget.studentId;
    debugPrint("Using studentId: ${widget.studentId}");
    if (studentId == null || studentId.isEmpty) {
      debugPrint("❌ ERROR: studentId is NULL");
      return;
    }

    setState(() => isSavingDocuments = true);

    try {
      debugPrint("Student ID: $studentId");
      debugPrint("Documents BEFORE SAVE: $_documents");

      final cleanDocs = _documents
          .where((doc) => (doc['url']?.toString() ?? '').isNotEmpty)
          .map(
            (doc) => {
              'name': doc['name']?.toString() ?? '',
              'fileName': doc['fileName']?.toString() ?? '',
              'url': doc['url']?.toString() ?? '',
            },
          )
          .toList();

      debugPrint("Saving documents: $cleanDocs");

      await FirebaseFirestore.instance
          .collection('students')
          .doc(studentId)
          .set({
        'documents': cleanDocs,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final snap = await FirebaseFirestore.instance
          .collection('students')
          .doc(studentId)
          .get();

      debugPrint("Documents AFTER SAVE: ${snap.data()?['documents']}");
      debugPrint("✅ Documents saved successfully");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Documents saved")),
        );
      }
    } catch (e) {
      debugPrint("❌ SAVE ERROR: $e");
    } finally {
      if (mounted) {
        setState(() => isSavingDocuments = false);
      }
    }
  }

}
