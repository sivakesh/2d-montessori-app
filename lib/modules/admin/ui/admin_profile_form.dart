import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/admin_profile_service.dart';
import '../models/admin_profile_model.dart';

class AdminProfileForm extends StatefulWidget {
  const AdminProfileForm({super.key, this.userId, this.isEdit});

  final String? userId;
  final bool? isEdit;

  @override
  State<AdminProfileForm> createState() => _AdminProfileFormState();
}

class _AdminProfileFormState extends State<AdminProfileForm>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<DocumentSnapshot<Map<String, dynamic>>> lookupStudents = [];
  DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  bool lookupIsLoading = false;
  bool lookupHasMore = true;
  String searchText = '';
  bool _initialLoadDone = false;
  final _formKey = GlobalKey<FormState>();
  final _service = AdminProfileService();
  html.File? _pickedImage;
  bool isUploadingImage = false;
  bool isSaving = false;
  bool isLoadingProfile = true;
  AdminProfileModel? _profile;
  bool _loaded = false;
  String _userId = '';
  Map<String, dynamic> _userData = <String, dynamic>{};
  String _selectedGender = '';
  final Map<String, String> selectedRelations = {};
  List<Map<String, dynamic>> linkedStudents = [];
  final List<Map<String, dynamic>> documents = [];
  String _selectedDocumentType = '';
  bool _isUploadingDocument = false;
  final List<String> documentTypes = const [
    'Aadhar Card',
    'PAN Card',
    'Address Proof',
    'Photo',
    'Birth Certificate',
    'Medical Record',
    'Other',
  ];

  late final _fullName = TextEditingController();
  late final _dob = TextEditingController();
  late final _bloodGroup = TextEditingController();
  late final _phone = TextEditingController();
  late final _alternatePhone = TextEditingController();
  late final _email = TextEditingController();
  late final _addressLine1 = TextEditingController();
  late final _addressLine2 = TextEditingController();
  late final _city = TextEditingController();
  late final _state = TextEditingController();
  late final _country = TextEditingController();
  late final _pincode = TextEditingController();
  late final _emergencyName = TextEditingController();
  late final _emergencyPhone = TextEditingController();
  late final _occupation = TextEditingController();
  late final _nationality = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _userId = _resolveUserId();
    _load();
    _loadLinkedStudents();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  Future<void> _load() async {
    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .get();
      final profile = await _service.fetchProfile(_userId);
      if (!mounted) return;
      _profile = profile;
      _userData = userSnapshot.data() ?? <String, dynamic>{};
      final userName = _userData['name']?.toString() ?? '';
      final userEmail = _userData['email']?.toString() ?? '';
      final userPhone = _userData['phone']?.toString() ?? '';
      if (profile != null) {
        _fullName.text = userName;
        _dob.text = profile.dateOfBirth;
        _selectedGender = profile.gender;
        _bloodGroup.text = profile.bloodGroup;
        _phone.text = userPhone;
        _alternatePhone.text = profile.alternatePhone;
        _email.text = userEmail;
        _addressLine1.text = profile.addressLine1;
        _addressLine2.text = profile.addressLine2;
        _city.text = profile.city;
        _state.text = profile.state;
        _country.text = profile.country;
        _pincode.text = profile.pincode;
        _emergencyName.text = profile.emergencyContactName;
        _emergencyPhone.text = profile.emergencyContactPhone;
        _occupation.text = profile.occupation;
        _nationality.text = profile.nationality;
        documents.clear();
        documents.addAll(
          profile.documents.map(
            (e) => <String, dynamic>{
              'id': e.documentId,
              'type': e.documentType,
              'name': e.fileName,
              'url': e.fileUrl,
              'uploadedAt': Timestamp.now(),
            },
          ),
        );
        linkedStudents = profile.students
            .map(
              (student) => <String, dynamic>{
                'studentId': student.studentId,
                'studentName': student.studentName,
                'name': student.studentName,
                'relation': student.classId,
                'classId': student.classId,
              },
            )
            .toList();
      } else {
        _fullName.text = userName;
        _phone.text = userPhone;
        _email.text = userEmail;
        _selectedGender = '';
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoadingProfile = false;
        });
      }
    }
  }

  Future<void> _loadLinkedStudents() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('user_student_links')
        .where('userId', isEqualTo: _userId)
        .get();

    final temp = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final studentId = doc.data()['studentId']?.toString() ?? '';
      if (studentId.isEmpty) continue;
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(studentId)
          .get();
      final data = studentDoc.data() ?? <String, dynamic>{};
      temp.add({
        'studentId': studentId,
        'name': data['name']?.toString() ?? '',
        'admissionNo': data['admissionNo']?.toString() ?? '',
        'relation': doc.data()['relation']?.toString() ?? 'Father',
      });
    }

    if (!mounted) return;
    setState(() {
      linkedStudents = temp;
      selectedRelations
        ..clear()
        ..addEntries(
          temp.map(
            (student) => MapEntry(
              student['studentId']?.toString() ?? '',
              student['relation']?.toString() ?? 'Father',
            ),
          ),
        );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fullName.dispose();
    _dob.dispose();
    _bloodGroup.dispose();
    _phone.dispose();
    _alternatePhone.dispose();
    _email.dispose();
    _addressLine1.dispose();
    _addressLine2.dispose();
    _city.dispose();
    _state.dispose();
    _country.dispose();
    _pincode.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    _occupation.dispose();
    _nationality.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final uploadInput = html.FileUploadInputElement();
    uploadInput.accept = 'image/*';
    uploadInput.click();

    await uploadInput.onChange.first;
    _pickedImage = uploadInput.files?.first;
    if (mounted) setState(() {});
  }

  Future<void> _pickDob() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dob.text.isNotEmpty
          ? (DateTime.tryParse(_dob.text) ?? DateTime.now())
          : DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (selected == null) return;
    setState(() {
      _dob.text = selected.toIso8601String().split('T').first;
    });
  }

  Future<String> _uploadImage() async {
    if (_pickedImage == null) return _profile?.profileImageUrl ?? '';
    try {
      setState(() {
        isUploadingImage = true;
      });

      final reader = html.FileReader();
      reader.readAsArrayBuffer(_pickedImage!);
      await reader.onLoad.first;

      final data = reader.result as Uint8List;
      final ref = FirebaseStorage.instance.ref('profiles/$_userId/profile.jpg');
      await ref.putData(data);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('profiles').doc(_userId).set({
        'profileImageUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return url;
      setState(() {
        isUploadingImage = false;
      });
      return url;
    } catch (e) {
      if (!mounted) return _profile?.profileImageUrl ?? '';
      setState(() {
        isUploadingImage = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Image upload failed')));
      return _profile?.profileImageUrl ?? '';
    }
  }

  Future<void> pickAndUploadDocument(StateSetter setStateDialog) async {
    try {
      setStateDialog(() => _isUploadingDocument = true);

      final uploadInput = html.FileUploadInputElement();
      uploadInput.accept = '*/*';
      uploadInput.click();

      await uploadInput.onChange.first;

      final file = uploadInput.files?.first;
      if (file == null) {
        return;
      }

      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;

      final data = reader.result as Uint8List;
      final fileName = file.name;

      final storageRef = FirebaseStorage.instance.ref().child(
        'profile_documents/$_userId/${DateTime.now().millisecondsSinceEpoch}_$fileName',
      );

      final uploadTask = storageRef.putData(data);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      final doc = Map<String, Object>.from({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'type': _selectedDocumentType,
        'url': downloadUrl,
        'name': fileName,
        'uploadedAt': Timestamp.now(),
      });

      setState(() {
        debugPrint('Document added: ${doc.runtimeType} ${doc.toString()}');
        documents.add(Map<String, dynamic>.from(doc));
      });

      final profileRef = FirebaseFirestore.instance
          .collection('profiles')
          .doc(_userId);
      final profileSnapshot = await profileRef.get();
      final existingDocuments = List<Map<String, dynamic>>.from(
        profileSnapshot.data()?['documents'] as List<dynamic>? ?? const [],
      );
      final mergedDocuments =
          existingDocuments
              .where((e) => e['id']?.toString() != doc['id']?.toString())
              .toList()
            ..add(<String, dynamic>{
              'id': doc['id'],
              'documentType': doc['type'],
              'fileUrl': doc['url'],
              'fileName': doc['name'],
              'type': doc['type'],
              'url': doc['url'],
              'name': doc['name'],
              'uploadedAt': doc['uploadedAt'],
            });
      await profileRef.set({
        'documents': mergedDocuments,
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      print('DOCUMENT UPLOAD ERROR: $e');
    } finally {
      if (mounted) {
        setStateDialog(() => _isUploadingDocument = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isSaving = true);
    try {
      final imageUrl = await _uploadImage();
      final batch = FirebaseFirestore.instance.batch();
      final profileRef = FirebaseFirestore.instance
          .collection('profiles')
          .doc(_userId);

      final profileData = <String, dynamic>{
        'fullName': _userData['name']?.toString() ?? _fullName.text.trim(),
        'email': _userData['email']?.toString() ?? _email.text.trim(),
        'phone': _userData['phone']?.toString() ?? _phone.text.trim(),
        'dateOfBirth': _dob.text.trim(),
        'gender': _selectedGender.trim(),
        'bloodGroup': _bloodGroup.text.trim(),
        'alternatePhone': _alternatePhone.text.trim(),
        'addressLine1': _addressLine1.text.trim(),
        'addressLine2': _addressLine2.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'country': _country.text.trim(),
        'pincode': _pincode.text.trim(),
        'emergencyContactName': _emergencyName.text.trim(),
        'emergencyContactPhone': _emergencyPhone.text.trim(),
        'occupation': _occupation.text.trim(),
        'nationality': _nationality.text.trim(),
        'profileImageUrl': imageUrl,
        'students': linkedStudents
            .map(
              (student) => <String, dynamic>{
                'studentId': student['studentId']?.toString() ?? '',
                'studentName':
                    student['studentName']?.toString() ??
                    student['name']?.toString() ??
                    '',
                'relation':
                    student['relation']?.toString() ??
                    student['classId']?.toString() ??
                    '',
              },
            )
            .toList(),
        'documents': documents
            .map(
              (e) => <String, dynamic>{
                'id': e['id']?.toString() ?? '',
                'documentType': e['type']?.toString() ?? '',
                'fileUrl': e['url']?.toString() ?? '',
                'fileName': e['name']?.toString() ?? '',
              },
            )
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      batch.set(profileRef, profileData, SetOptions(merge: true));
      await batch.commit();
      if (!mounted) return;
      setState(() {
        isSaving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isSaving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Save failed')));
    } finally {
      if (mounted && isSaving) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _profile?.profileImageUrl ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: 'Auto Fill Sample Data',
            onPressed: _fillSampleData,
          ),
        ],
      ),
      body: Stack(
        children: [
          AnimatedOpacity(
            opacity: isLoadingProfile ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            child: isLoadingProfile
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      TabBar(
                        controller: _tabController,
                        labelColor: Colors.green,
                        tabs: const [
                          Tab(text: 'Profile'),
                          Tab(text: 'Students'),
                          Tab(text: 'Documents'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildProfileForm(imageUrl),
                            _buildStudentLinking(),
                            _documentsTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          if (isLoadingProfile)
            Container(
              color: Colors.white,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileForm(String imageUrl) {
    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[300],
                          backgroundImage: imageUrl.isEmpty
                              ? null
                              : NetworkImage(imageUrl),
                          child: imageUrl.isEmpty
                              ? const Icon(Icons.person, size: 40)
                              : null,
                        ),
                        if (isUploadingImage)
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    TextButton(
                      onPressed: isUploadingImage ? null : _pickImage,
                      child: const Text('Upload Image'),
                    ),
                    const SizedBox(height: 12),
                    if (isWide)
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: _buildFormFields(isWide),
                      )
                    else
                      Column(children: _buildFormFields(isWide)),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isSaving ? null : _save,
                        child: isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
                if (isSaving)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.3),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStudentLinking() {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: _buildLinkedStudentsList()),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveStudentLinks,
                  child: const Text('Save Student Links'),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 80,
          child: FloatingActionButton(
            backgroundColor: const Color(0xFF2E7D32),
            elevation: 4,
            onPressed: _openStudentLookup,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildLinkedStudentsList() {
    if (linkedStudents.isEmpty) {
      return const Center(child: Text('No students linked'));
    }

    return ListView.builder(
      itemCount: linkedStudents.length,
      itemBuilder: (context, index) {
        final student = linkedStudents[index];

        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            title: Text(student['name']?.toString() ?? ''),
            subtitle: Text(student['admissionNo']?.toString() ?? ''),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: student['relation']?.toString(),
                  items: const [
                    DropdownMenuItem(value: 'Father', child: Text('Father')),
                    DropdownMenuItem(value: 'Mother', child: Text('Mother')),
                    DropdownMenuItem(
                      value: 'Guardian',
                      child: Text('Guardian'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      student['relation'] = val;
                      selectedRelations[student['studentId']?.toString() ??
                              ''] =
                          val;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    setState(() {
                      selectedRelations.remove(
                        student['studentId']?.toString() ?? '',
                      );
                      linkedStudents.removeAt(index);
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

  Widget _documentsTab() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 16, top: 10),
            child: FloatingActionButton(
              backgroundColor: const Color(0xFF2E7D32),
              elevation: 4,
              onPressed: _openUploadDialog,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ),
        Expanded(
          child: documents.isEmpty
              ? const Center(child: Text('No documents uploaded'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final doc = documents[index];

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(
                          Icons.insert_drive_file,
                          color: Colors.green,
                        ),
                        title: Text(
                          doc['type']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(doc['name']?.toString() ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.open_in_new),
                              onPressed: () async {
                                final url = doc['url']?.toString() ?? '';
                                if (url.isEmpty) return;
                                final uri = Uri.parse(url);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri);
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  documents.removeAt(index);
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
    );
  }

  void _openUploadDialog() {
    _selectedDocumentType = documentTypes.first;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Upload Document',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedDocumentType,
                      decoration: const InputDecoration(
                        labelText: 'Document Type',
                        border: OutlineInputBorder(),
                      ),
                      items: documentTypes
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setStateDialog(() => _selectedDocumentType = val);
                      },
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: SizedBox(
                        width: 220,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.upload),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text('Upload File'),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            await pickAndUploadDocument(setStateDialog);
                          },
                        ),
                      ),
                    ),
                    if (_isUploadingDocument)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: documents.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  final safeDocuments = documents
                                      .map((e) => Map<String, dynamic>.from(e))
                                      .toList();
                                  documents
                                    ..clear()
                                    ..addAll(safeDocuments);
                                });
                                Navigator.pop(dialogContext);
                              },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openStudentLookup() {
    lookupStudents.clear();
    lastDocument = null;
    searchText = '';
    lookupIsLoading = false;
    _initialLoadDone = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            if (!_initialLoadDone) {
              _initialLoadDone = true;
              Future.microtask(() async {
                await _loadStudents(setStateDialog: setStateDialog);
              });
            }
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 500,
                height: 600,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search by name/admission',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (val) async {
                        searchText = val.trim();
                        lastDocument = null;
                        await _loadStudents(setStateDialog: setStateDialog);
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: lookupIsLoading && lookupStudents.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : lookupStudents.isEmpty
                          ? const Center(child: Text('No results'))
                          : ListView.builder(
                              itemCount: lookupStudents.length,
                              itemBuilder: (context, index) {
                                final student = lookupStudents[index];
                                final data =
                                    student.data() ?? <String, dynamic>{};
                                final name = data['name']?.toString() ?? '';
                                final admissionNo =
                                    data['admissionNo']?.toString() ?? '';
                                return ListTile(
                                  title: Text(name),
                                  subtitle: Text(admissionNo),
                                  trailing: const Icon(
                                    Icons.add_circle,
                                    color: Colors.green,
                                  ),
                                  onTap: () {
                                    Navigator.pop(dialogContext);
                                    _addStudentToList(student);
                                  },
                                );
                              },
                            ),
                    ),
                    if (lookupHasMore)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 10,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              await _loadStudents(
                                loadMore: true,
                                setStateDialog: setStateDialog,
                              );
                            },
                            child: const Text('Load More'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _addStudentToList(DocumentSnapshot<Map<String, dynamic>> student) {
    final exists = linkedStudents.any((e) => e['studentId'] == student.id);
    if (exists) return;

    setState(() {
      final data = student.data() ?? <String, dynamic>{};
      linkedStudents.add({
        'studentId': student.id,
        'name': data['name']?.toString() ?? '',
        'admissionNo': data['admissionNo']?.toString() ?? '',
        'relation': 'Father',
      });
      selectedRelations[student.id] = 'Father';
    });
  }

  Future<void> _loadStudents({
    bool loadMore = false,
    required void Function(void Function()) setStateDialog,
  }) async {
    if (lookupIsLoading) return;

    setState(() => lookupIsLoading = true);

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('students')
        .orderBy('name')
        .limit(10);

    if (searchText.isNotEmpty) {
      query = FirebaseFirestore.instance
          .collection('students')
          .orderBy('name')
          .startAt([searchText])
          .endAt(['$searchText\uf8ff'])
          .limit(10);
    }

    if (loadMore && lastDocument != null) {
      query = query.startAfterDocument(lastDocument!);
    }

    final snapshot = await query.get();

    if (snapshot.docs.isNotEmpty) {
      lastDocument = snapshot.docs.last;
    }

    setState(() {
      if (loadMore) {
        lookupStudents.addAll(snapshot.docs);
      } else {
        lookupStudents = snapshot.docs;
      }
      lookupHasMore = snapshot.docs.length == 10;
      lookupIsLoading = false;
    });
    setStateDialog(() {});
  }

  Future<void> _saveStudentLinks() async {
    final userId = _userId;
    final linksRef = FirebaseFirestore.instance.collection(
      'user_student_links',
    );
    final existing = await linksRef.where('userId', isEqualTo: userId).get();
    for (final doc in existing.docs) {
      await doc.reference.delete();
    }

    final profileRef = FirebaseFirestore.instance
        .collection('profiles')
        .doc(userId);
    final profileSnapshot = await profileRef.get();
    final existingProfileStudents = List<Map<String, dynamic>>.from(
      profileSnapshot.data()?['students'] as List<dynamic>? ?? const [],
    );
    final updatedProfileStudents = <Map<String, dynamic>>[];
    final selectedStudentIds = <String>{};

    for (final entry in selectedRelations.entries) {
      final studentId = entry.key;
      final relation = entry.value;
      selectedStudentIds.add(studentId);
      final studentData = linkedStudents.firstWhere(
        (student) => student['studentId']?.toString() == studentId,
        orElse: () => <String, dynamic>{},
      );
      final studentName =
          studentData['name']?.toString() ??
          studentData['studentName']?.toString() ??
          '';

      await linksRef.add(
        Map<String, Object>.from({
          'userId': userId,
          'studentId': studentId,
          'relation': relation,
          'createdAt': FieldValue.serverTimestamp(),
        }),
      );

      final studentRef = FirebaseFirestore.instance
          .collection('students')
          .doc(studentId);
      final studentDoc = await studentRef.get();
      final existingParentLinks = List<Map<String, dynamic>>.from(
        studentDoc.data()?['parentLinks'] as List<dynamic>? ?? const [],
      );
      final updatedParentLinks =
          existingParentLinks
              .where((p) => p['userId']?.toString() != userId)
              .toList()
            ..add(<String, dynamic>{'userId': userId, 'relation': relation});
      await studentRef.set({
        'parentLinks': updatedParentLinks,
      }, SetOptions(merge: true));

      updatedProfileStudents.add(<String, dynamic>{
        'studentId': studentId,
        'studentName': studentName,
        'name': studentName,
        'relation': relation,
        'classId': relation,
      });
    }

    for (final student in existingProfileStudents) {
      final studentId = student['studentId']?.toString() ?? '';
      if (studentId.isEmpty || selectedStudentIds.contains(studentId)) {
        continue;
      }
      updatedProfileStudents.add(student);
    }

    await profileRef.set({
      'students': updatedProfileStudents,
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Students linked successfully')),
    );
  }

  void _fillSampleData() {
    setState(() {
      _fullName.text = 'Rajesh Kumar';
      _dob.text = '1990-05-15';
      _selectedGender = 'Male';
      _bloodGroup.text = 'B+';
      _nationality.text = 'Indian';
      _occupation.text = 'Software Engineer';
      _phone.text = '9876543210';
      _alternatePhone.text = '9123456780';
      _email.text = 'rajesh.kumar@gmail.com';
      _addressLine1.text = 'No. 45, MG Road';
      _addressLine2.text = 'Near Metro Station';
      _city.text = 'Bangalore';
      _state.text = 'Karnataka';
      _pincode.text = '560001';
    });
  }

  String _resolveUserId() {
    if ((widget.userId ?? '').isNotEmpty) return widget.userId!;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final userId = args['userId']?.toString();
      if (userId != null && userId.isNotEmpty) return userId;
    }
    return widget.userId ?? '';
  }

  List<Widget> _buildFormFields(bool isWide) {
    final width = isWide ? 400.0 : double.infinity;
    return [
      SizedBox(
        width: width,
        child: _field(
          _fullName,
          'Full Name *',
          readOnly: true,
          helperText: 'Managed from User details',
        ),
      ),
      SizedBox(width: width, child: _dateField(_dob, 'Date of Birth')),
      SizedBox(width: width, child: _genderField()),
      SizedBox(width: width, child: _field(_bloodGroup, 'Blood Group')),
      SizedBox(width: width, child: _field(_nationality, 'Nationality')),
      SizedBox(width: width, child: _field(_occupation, 'Occupation')),
      SizedBox(
        width: width,
        child: _field(
          _phone,
          'Phone *',
          readOnly: true,
          helperText: 'Managed from User details',
        ),
      ),
      SizedBox(width: width, child: _field(_alternatePhone, 'Alternate Phone')),
      SizedBox(
        width: width,
        child: _field(
          _email,
          'Email *',
          readOnly: true,
          helperText: 'Managed from User details',
        ),
      ),
      SizedBox(width: width, child: _field(_addressLine1, 'Address Line 1')),
      SizedBox(width: width, child: _field(_addressLine2, 'Address Line 2')),
      SizedBox(width: width, child: _field(_city, 'City')),
      SizedBox(width: width, child: _field(_state, 'State')),
      SizedBox(width: width, child: _field(_pincode, 'Pincode')),
    ];
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool readOnly = false,
    String? helperText,
  }) {
    return TextField(
      controller: c,
      readOnly: readOnly,
      decoration: InputDecoration(labelText: label, helperText: helperText),
    );
  }

  Widget _dateField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      readOnly: true,
      onTap: _pickDob,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_month),
      ),
    );
  }

  Widget _genderField() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedGender.isEmpty ? null : _selectedGender,
      decoration: const InputDecoration(labelText: 'Gender'),
      items: const [
        DropdownMenuItem(value: 'Male', child: Text('Male')),
        DropdownMenuItem(value: 'Female', child: Text('Female')),
        DropdownMenuItem(value: 'Other', child: Text('Other')),
      ],
      onChanged: (val) {
        if (val == null) return;
        setState(() {
          _selectedGender = val;
        });
      },
    );
  }
}
