import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/attendance_service.dart';

final attendanceServiceProvider = Provider<AttendanceService>(
  (ref) => AttendanceService(),
);

final hasMarkedTodayProvider = FutureProvider.family<bool, String>(
  (ref, userId) async {
    final service = ref.watch(attendanceServiceProvider);
    return service.hasMarkedToday(userId);
  },
);
