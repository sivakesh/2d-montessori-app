import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AdminUserFormScreen extends StatefulWidget {
  const AdminUserFormScreen({
    super.key,
    this.userId,
    this.initialData,
  });

  final String? userId;
  final Map<String, dynamic>? initialData;

  @override
  State<AdminUserFormScreen> createState() => _AdminUserFormScreenState();
}

class _AdminUserFormScreenState extends State<AdminUserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  String _role = 'parent';
  bool _isActive = true;
  String _profileImageUrl = '';
  XFile? _pickedImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? {};
    _nameController = TextEditingController(text: data['name']?.toString() ?? '');
    _emailController = TextEditingController(text: data['email']?.toString() ?? '');
    _phoneController = TextEditingController(text: data['phone']?.toString() ?? '');
    _role = data['role']?.toString() ?? 'parent';
    _isActive = data['isActive'] == null ? true : data['isActive'] == true;
    _profileImageUrl = data['profileImageUrl']?.toString() ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;
    setState(() => _pickedImage = picked);
  }

  Future<String> _uploadProfileImage(String userId) async {
    if (_pickedImage == null) return _profileImageUrl;
    final ref = FirebaseStorage.instance.ref('users/profile/$userId.jpg');
    if (kIsWeb) {
      final bytes = await _pickedImage!.readAsBytes();
      await ref.putData(bytes);
    } else {
      await ref.putFile(File(_pickedImage!.path));
    }
    return ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final users = FirebaseFirestore.instance.collection('users');
      final userId = widget.userId ?? users.doc().id;
      final imageUrl = await _uploadProfileImage(userId);
      await users.doc(userId).set({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': _role,
        'profileImageUrl': imageUrl,
        'isActive': _isActive,
        'createdAt': widget.userId == null ? FieldValue.serverTimestamp() : (widget.initialData?['createdAt'] ?? FieldValue.serverTimestamp()),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.userId != null;
    final previewImage = _pickedImage != null ? _pickedImage!.path : _profileImageUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit User' : 'Add User'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundImage: previewImage.isNotEmpty
                      ? (kIsWeb
                          ? NetworkImage(previewImage)
                          : (previewImage.startsWith('http')
                              ? NetworkImage(previewImage)
                              : FileImage(File(previewImage)) as ImageProvider))
                      : null,
                  child: previewImage.isEmpty ? const Icon(Icons.person, size: 36) : null,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _pickImage,
                  child: const Text('Upload Profile Image'),
                ),
              ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email *'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Email is required';
                  if (!text.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone *'),
                keyboardType: TextInputType.phone,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Phone is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'parent', child: Text('parent')),
                  DropdownMenuItem(value: 'staff', child: Text('staff')),
                  DropdownMenuItem(value: 'admin', child: Text('admin')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _role = value);
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Auto fill sample data',
                    onPressed: _isSaving
                        ? null
                        : () {
                            _nameController.text = 'Rahul Sharma';
                            _emailController.text = 'rahul.sharma@example.com';
                            _phoneController.text = '9876543210';
                            _role = 'parent';
                            _isActive = true;
                            setState(() {});
                          },
                    icon: const Icon(Icons.casino),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: Text(_isSaving ? 'Saving...' : 'Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
