// ignore_for_file: use_build_context_synchronously
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_env.dart';
import '../../../core/theme/app_colors.dart';
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
  final _ageController = TextEditingController();
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
  String _selectedDocumentType = 'Aadhar Card';
  String _selectedDocumentFileName = '';
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
    _ageController.text = _initialAgeText(data['age'], data['dateOfBirth']);
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
    _ageController.dispose();
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
    _ageController.text =
        _calculateAgeFromDob(_dobController.text)?.toString() ?? '';
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

  int? _calculateAgeFromDob(String dobText) {
    final dob = DateTime.tryParse(dobText.trim());
    if (dob == null) return null;
    final today = DateTime.now();
    final normalizedDob = DateTime(dob.year, dob.month, dob.day);
    final normalizedToday = DateTime(today.year, today.month, today.day);
    if (normalizedDob.isAfter(normalizedToday)) return null;
    var age = normalizedToday.year - normalizedDob.year;
    final hadBirthday =
        normalizedToday.month > normalizedDob.month ||
        (normalizedToday.month == normalizedDob.month &&
            normalizedToday.day >= normalizedDob.day);
    if (!hadBirthday) age -= 1;
    return age < 0 ? null : age;
  }

  String _initialAgeText(Object? age, Object? dob) {
    final parsedAge = int.tryParse(age?.toString() ?? '');
    if (parsedAge != null) return parsedAge.toString();
    return _calculateAgeFromDob(dob?.toString() ?? '')?.toString() ?? '';
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
            'phone': map['phone'] ?? '',
            'relation': map['relation'] ?? 'Guardian',
            'linkedAt': map['linkedAt'],
          };
        })
        .where((e) => (e['id']?.toString() ?? '').isNotEmpty)
        .toList();
  }

  Map<String, dynamic>? _findUserById(String userId) {
    for (final user in _allUsers) {
      if (user['id']?.toString() == userId) return user;
    }
    return null;
  }

  List<Map<String, dynamic>> _resolvedParentLinks() {
    return _parentLinks.map((parent) {
      final userId = parent['id']?.toString() ?? '';
      final resolved = _findUserById(userId);
      return {
        'id': userId,
        'name': (parent['name']?.toString().isNotEmpty ?? false)
            ? parent['name']
            : resolved?['name'] ?? '',
        'email': (parent['email']?.toString().isNotEmpty ?? false)
            ? parent['email']
            : resolved?['email'] ?? '',
        'phone': (parent['phone']?.toString().isNotEmpty ?? false)
            ? parent['phone']
            : resolved?['phone'] ?? '',
        'relation': parent['relation']?.toString().isNotEmpty == true
            ? parent['relation']
            : 'Guardian',
        'linkedAt': parent['linkedAt'],
      };
    }).toList();
  }

  List<Map<String, dynamic>> _normalizeDocuments(dynamic rawDocs) {
    return (rawDocs as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) {
          final map = Map<String, dynamic>.from(e);
          return {
            'type': map['type'] ?? map['documentType'] ?? '',
            'name': map['name'] ?? map['fileName'] ?? '',
            'fileName': map['fileName'] ?? map['name'] ?? '',
            'url': map['url'] ?? '',
            'storagePath': map['storagePath'] ?? '',
            'uploadedBy': map['uploadedBy'] ?? 'admin',
            'uploadedAt': map['uploadedAt'],
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
          'phone': data['phone'] ?? '',
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
      _ageController.text =
          _calculateAgeFromDob(_dobController.text)?.toString() ?? '';
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
        section: _sectionController.text.trim(),
        rollNumber: _rollNumberController.text.trim(),
        dateOfBirth: _dobController.text.trim(),
        age: _calculateAgeFromDob(_dobController.text),
        gender: _gender,
        bloodGroup: _bloodGroupController.text.trim(),
        nationality: _nationalityController.text.trim(),
        motherTongue: _motherTongueController.text.trim(),
        addressLine1: _address1Controller.text.trim(),
        addressLine2: _address2Controller.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        pincode: _pincodeController.text.trim(),
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
        documents: _documents
            .map(
              (doc) => AdminStudentDocument.fromMap(
                Map<String, dynamic>.from(doc),
              ),
            )
            .toList(),
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
      debugPrint('Student ID being updated for parents: $studentId');
      debugPrint('Parent links before save: $_parentLinks');

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
          'relation': parent['relation'] ?? 'Guardian',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      final normalizedParents = _parentLinks
          .where((e) => (e['id']?.toString() ?? '').isNotEmpty)
          .map((e) => {
                'userId': e['id'],
                'name': e['name'] ?? '',
                'email': e['email'] ?? '',
                'phone': e['phone'] ?? '',
                'relation': e['relation'] ?? 'Guardian',
                'linkedAt': Timestamp.now(),
              })
          .toList();

      await FirebaseFirestore.instance
          .collection('students')
          .doc(studentId)
          .set({
        'parentLinks': normalizedParents,
      }, SetOptions(merge: true));

      debugPrint('Parent links after save: $normalizedParents');

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
                  if (currentEnvironment == AppEnvironment.dev)
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
                          label: 'Age',
                          child: _textField(
                            controller: _ageController,
                            readOnly: true,
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
    final linkedIds = _parentLinks
        .map((e) => e['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final filteredUsers = _allUsers.where((user) {
      final q = _searchQuery.toLowerCase();
      final id = user['id']?.toString() ?? '';
      if (linkedIds.contains(id)) return false;
      return user['name'].toString().toLowerCase().contains(q) ||
          user['email'].toString().toLowerCase().contains(q) ||
          user['phone'].toString().toLowerCase().contains(q);
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
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'Linked Parents',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (_parentLinks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No parents linked yet.')),
                    )
                  else
                    ..._resolvedParentLinks().asMap().entries.map((entry) {
                      final index = entry.key;
                      final parent = entry.value;
                      final displayName = parent['name']?.toString().isNotEmpty == true
                          ? parent['name'].toString()
                          : 'Parent';
                      final email = parent['email']?.toString() ?? '';
                      final phone = parent['phone']?.toString() ?? '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const CircleAvatar(child: Icon(Icons.person)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (email.isNotEmpty)
                                      Text(
                                        email,
                                        style: const TextStyle(color: Colors.grey),
                                      ),
                                    if (phone.isNotEmpty)
                                      Text(
                                        phone,
                                        style: const TextStyle(color: Colors.grey),
                                      ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      initialValue: parent['relation']?.toString().isNotEmpty == true
                                          ? parent['relation'].toString()
                                          : 'Guardian',
                                      decoration: const InputDecoration(
                                        labelText: 'Relationship',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'Father', child: Text('Father')),
                                        DropdownMenuItem(value: 'Mother', child: Text('Mother')),
                                        DropdownMenuItem(value: 'Guardian', child: Text('Guardian')),
                                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                                      ],
                                      onChanged: (value) {
                                        if (value == null) return;
                                        safeSetState(() {
                                          _parentLinks[index]['relation'] = value;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
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
                    }),
                  const SizedBox(height: 8),
                  const Text(
                    'Available Parents',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (filteredUsers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No matching parents found.')),
                    )
                  else
                    ...filteredUsers.map((user) {
                      final name = user['name']?.toString() ?? '';
                      final email = user['email']?.toString() ?? '';
                      final phone = user['phone']?.toString() ?? '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (email.isNotEmpty) Text(email),
                              if (phone.isNotEmpty) Text(phone),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.add_circle,
                              color: Colors.green,
                            ),
                            onPressed: () => _addParent(user),
                          ),
                        ),
                      );
                    }),
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

    debugPrint('Selected parent added: ${user['name']} (${user['email']})');
    safeSetState(() {
      _parentLinks.add({
        'id': user['id'],
        'name': user['name'],
        'email': user['email'],
        'phone': user['phone'] ?? '',
        'relation': 'Guardian',
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
                        final docType = doc['type']?.toString().isNotEmpty == true
                            ? doc['type'].toString()
                            : (doc['documentType']?.toString() ?? 'Other');
                        final fileName = doc['name']?.toString().isNotEmpty == true
                            ? doc['name'].toString()
                            : (doc['fileName']?.toString() ?? '');
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
                            title: Text(docType),
                            subtitle: Text(fileName),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.open_in_new),
                                  onPressed: () async {
                                    final url = doc['url'];
                                    if (url == null ||
                                        url.toString().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Document URL is missing'),
                                        ),
                                      );
                                      return;
                                    }
                                    await launchUrl(
                                      Uri.parse(url.toString()),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _confirmDeleteDocument(index),
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
            backgroundColor: AppColors.primary,
            elevation: 4,
            onPressed: _openUploadDialog,
            child: const Icon(Icons.add, color: Colors.white),
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

  Future<void> _confirmDeleteDocument(int index) async {
    final doc = _documents[index];
    final storagePath = doc['storagePath']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete document?'),
          content: Text(
            doc['name']?.toString().isNotEmpty == true
                ? 'Delete ${doc['name']}?'
                : 'Delete this document?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      if (storagePath.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref(storagePath).delete();
        } catch (e) {
          final message = e.toString().toLowerCase();
          if (!message.contains('object-not-found') &&
              !message.contains('not found')) {
            debugPrint('Storage delete failed for $storagePath: $e');
          }
        }
      }

      setState(() {
        _documents.removeAt(index);
      });
      await _saveDocuments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document deleted successfully')),
      );
    } catch (e) {
      debugPrint('DELETE DOCUMENT ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete document')),
        );
      }
    }
  }

  Future<void> _pickAndUploadDocument(String type) async {
    final studentId = widget.studentId;
    if (studentId == null || studentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save student first before uploading documents')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    try {
      setState(() => isUploadingDocument = true);
      _selectedDocumentFileName = file.name;
      debugPrint('Selected document file name: ${file.name}');
      debugPrint('Student ID: $studentId');
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final storagePath = 'student_documents/$studentId/$fileName';
      debugPrint('Document storage path: $storagePath');
      final ref = FirebaseStorage.instance
          .ref()
          .child(storagePath);
      final uploadTask = ref.putData(file.bytes!);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('Document download URL: $downloadUrl');

      setState(() {
        _documents.add(
          {
            'type': type,
            'name': file.name,
            'fileName': file.name,
            'url': downloadUrl,
            'storagePath': storagePath,
            'uploadedBy': 'admin',
            'uploadedAt': Timestamp.now(),
          },
        );
      });
      debugPrint('Documents before save: $_documents');
      await _saveDocuments();
      debugPrint('Documents after save: $_documents');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document uploaded successfully')),
      );
    } catch (e) {
      debugPrint('UPLOAD ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload document')),
        );
      }
    } finally {
      if (mounted) setState(() => isUploadingDocument = false);
    }
  }

  void _openUploadDialog() {
    _selectedDocumentType = 'Aadhar Card';
    _selectedDocumentFileName = '';
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool dialogUploading = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: SizedBox(
                width: MediaQuery.of(dialogContext).size.width,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Upload Document',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedDocumentType,
                        decoration: const InputDecoration(
                          labelText: 'Document Type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          'Aadhar Card',
                          'Birth Certificate',
                          'Transfer Certificate',
                          'Medical Certificate',
                          'Photo',
                          'Address Proof',
                          'Parent ID Proof',
                          'Other',
                        ].map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: dialogUploading
                            ? null
                            : (val) {
                                if (val == null) return;
                                setModalState(() => _selectedDocumentType = val);
                              },
                      ),
                      if (_selectedDocumentFileName.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Selected file: $_selectedDocumentFileName'),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: dialogUploading
                              ? null
                              : () async {
                                  setModalState(() => dialogUploading = true);
                                  try {
                                    await _pickAndUploadDocument(_selectedDocumentType);
                                  } finally {
                                    if (context.mounted) {
                                      setModalState(() => dialogUploading = false);
                                    }
                                  }
                                },
                          icon: dialogUploading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.upload),
                          label: Text(
                            dialogUploading ? 'Uploading...' : 'Upload File',
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: dialogUploading || isSavingDocuments || _documents.isEmpty
                              ? null
                              : () async {
                                  await _saveDocuments();
                                  if (mounted && Navigator.of(dialogContext).canPop()) {
                                    Navigator.pop(dialogContext);
                                  }
                                },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save student first before uploading documents')),
        );
      }
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
              'type': doc['type']?.toString() ??
                  doc['documentType']?.toString() ??
                  '',
              'name': doc['name']?.toString() ?? doc['fileName']?.toString() ?? '',
              'fileName': doc['fileName']?.toString() ?? doc['name']?.toString() ?? '',
              'url': doc['url']?.toString() ?? '',
              'storagePath': doc['storagePath']?.toString() ?? '',
              'uploadedBy': doc['uploadedBy']?.toString() ?? 'admin',
              'uploadedAt': doc['uploadedAt'] is Timestamp
                  ? doc['uploadedAt']
                  : Timestamp.now(),
            },
          )
          .toList();

      debugPrint("Saving documents: $cleanDocs");

      await FirebaseFirestore.instance
          .collection('students')
          .doc(studentId)
          .update({
        'documents': cleanDocs,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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
