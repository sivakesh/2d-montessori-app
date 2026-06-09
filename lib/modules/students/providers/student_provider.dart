import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/student_service.dart';

final studentServiceProvider = Provider<StudentService>((ref) => StudentService());
