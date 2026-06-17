import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/mood_checkin_service.dart';

final moodCheckinServiceProvider = Provider<MoodCheckinService>(
  (ref) => MoodCheckinService(),
);
