import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/attendance_service.dart';
import '../../classes/providers/class_provider.dart';
import '../../students/providers/student_provider.dart';
import '../providers/attendance_provider.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  String _mode = 'students';
  String? _selectedClassId;

  final Map<String, String> _photoUrls = {};
  final Set<String> _marked = {};

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final attendanceService = ref.watch(attendanceServiceProvider);
    final classService = ref.watch(classServiceProvider);

    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Attendance', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Capture photo to mark present',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'students', label: Text('Students')),
              ButtonSegment(value: 'staff', label: Text('Staff')),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.first),
          ),
          const SizedBox(height: 16),
          if (_mode == 'students')
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: classService.watchClasses(),
              builder: (context, snapshot) {
                final classes = snapshot.data?.docs ?? [];
                return DropdownButtonFormField<String>(
                  initialValue: _selectedClassId,
                  decoration: const InputDecoration(labelText: 'Select Class'),
                  items: classes
                      .map(
                        (doc) => DropdownMenuItem(
                          value: doc.id,
                          child: Text(doc.data()['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedClassId = value),
                );
              },
            ),
          const SizedBox(height: 16),
          Expanded(
            child: _mode == 'students'
                ? _StudentAttendanceList(
                    classId: _selectedClassId,
                    attendanceService: attendanceService,
                    marked: _marked,
                    photoUrls: _photoUrls,
                    currentUserId: currentUser.id,
                    onChanged: () => setState(() {}),
                  )
                : _StaffAttendanceList(
                    attendanceService: attendanceService,
                    marked: _marked,
                    photoUrls: _photoUrls,
                    currentUserId: currentUser.id,
                    onChanged: () => setState(() {}),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StudentAttendanceList extends ConsumerWidget {
  const _StudentAttendanceList({
    required this.classId,
    required this.attendanceService,
    required this.marked,
    required this.photoUrls,
    required this.currentUserId,
    required this.onChanged,
  });

  final String? classId;
  final AttendanceService attendanceService;
  final Set<String> marked;
  final Map<String, String> photoUrls;
  final String currentUserId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentService = ref.watch(studentServiceProvider);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: studentService.watchStudents(classId: classId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.where((doc) => (doc.data()['isActive'] ?? true) == true).toList();
        if (docs.isEmpty) {
          return const Center(child: Text('No students found.'));
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final id = doc.id;
            final isMarked = marked.contains('student_$id');
            final photoUrl = photoUrls['student_$id'];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['name']?.toString() ?? ''),
                          const SizedBox(height: 4),
                          Text(data['admissionNo']?.toString() ?? '',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (photoUrl != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(photoUrl, width: 48, height: 48, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                    ],
                    ElevatedButton.icon(
                      onPressed: isMarked
                          ? null
                          : () async {
                              try {
                                final url = await attendanceService.captureAndUploadPhoto(
                                  entityType: 'student',
                                  entityId: id,
                                );
                                if (url == null) return;
                                await attendanceService.markStudentAttendance(
                                  studentId: id,
                                  studentName: data['name']?.toString() ?? '',
                                  classId: classId ?? '',
                                  markedBy: currentUserId,
                                  photoUrl: url,
                                );
                                photoUrls['student_$id'] = url;
                                marked.add('student_$id');
                                onChanged();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Student attendance marked.')),
                                  );
                                }
                              } on StateError catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.message)),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed: $e')),
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(isMarked ? 'Present' : 'Capture'),
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
}

class _StaffAttendanceList extends ConsumerWidget {
  const _StaffAttendanceList({
    required this.attendanceService,
    required this.marked,
    required this.photoUrls,
    required this.currentUserId,
    required this.onChanged,
  });

  final AttendanceService attendanceService;
  final Set<String> marked;
  final Map<String, String> photoUrls;
  final String currentUserId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'staff')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No staff found.'));
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final id = doc.id;
            final isMarked = marked.contains('staff_$id');
            final photoUrl = photoUrls['staff_$id'];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(child: Text(data['name']?.toString() ?? data['phone']?.toString() ?? '')),
                    if (photoUrl != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(photoUrl, width: 48, height: 48, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                    ],
                    ElevatedButton.icon(
                      onPressed: isMarked
                          ? null
                          : () async {
                              try {
                                final url = await attendanceService.captureAndUploadPhoto(
                                  entityType: 'staff',
                                  entityId: id,
                                );
                                if (url == null) return;
                                await attendanceService.markStaffAttendance(
                                  staffId: id,
                                  staffName: data['name']?.toString() ?? data['phone']?.toString() ?? '',
                                  markedBy: currentUserId,
                                  photoUrl: url,
                                );
                                photoUrls['staff_$id'] = url;
                                marked.add('staff_$id');
                                onChanged();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Staff attendance marked.')),
                                  );
                                }
                              } on StateError catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.message)),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed: $e')),
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(isMarked ? 'Present' : 'Capture'),
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
}
