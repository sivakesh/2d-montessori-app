import 'package:flutter/material.dart';

class MoodOptionModel {
  const MoodOptionModel({
    required this.moodCode,
    required this.moodLabel,
    required this.moodCategory,
    required this.icon,
  });

  final String moodCode;
  final String moodLabel;
  final String moodCategory;
  final IconData icon;
}

const moodOptions = <MoodOptionModel>[
  MoodOptionModel(moodCode: 'happy', moodLabel: 'Happy', moodCategory: 'positive', icon: Icons.sentiment_very_satisfied_outlined),
  MoodOptionModel(moodCode: 'calm', moodLabel: 'Calm', moodCategory: 'regulated', icon: Icons.self_improvement_outlined),
  MoodOptionModel(moodCode: 'excited', moodLabel: 'Excited', moodCategory: 'high_energy_positive', icon: Icons.celebration_outlined),
  MoodOptionModel(moodCode: 'sad', moodLabel: 'Sad', moodCategory: 'low_mood', icon: Icons.sentiment_dissatisfied_outlined),
  MoodOptionModel(moodCode: 'crying', moodLabel: 'Crying', moodCategory: 'distress', icon: Icons.water_drop_outlined),
  MoodOptionModel(moodCode: 'angry', moodLabel: 'Angry', moodCategory: 'anger', icon: Icons.local_fire_department_outlined),
  MoodOptionModel(moodCode: 'anxious', moodLabel: 'Anxious', moodCategory: 'worry', icon: Icons.psychology_alt_outlined),
  MoodOptionModel(moodCode: 'tired', moodLabel: 'Tired', moodCategory: 'low_energy', icon: Icons.bedtime_outlined),
  MoodOptionModel(moodCode: 'withdrawn', moodLabel: 'Quiet / Withdrawn', moodCategory: 'withdrawn', icon: Icons.visibility_off_outlined),
  MoodOptionModel(moodCode: 'not_observed', moodLabel: 'Not Observed', moodCategory: 'neutral', icon: Icons.remove_red_eye_outlined),
];

const studentMoodOptions = moodOptions;

const staffMoodOptions = <MoodOptionModel>[
  MoodOptionModel(moodCode: 'positive', moodLabel: 'Positive', moodCategory: 'positive', icon: Icons.sentiment_very_satisfied_outlined),
  MoodOptionModel(moodCode: 'calm_focused', moodLabel: 'Calm / Focused', moodCategory: 'regulated', icon: Icons.center_focus_strong_outlined),
  MoodOptionModel(moodCode: 'energetic', moodLabel: 'Energetic', moodCategory: 'high_energy_positive', icon: Icons.bolt_outlined),
  MoodOptionModel(moodCode: 'tired', moodLabel: 'Tired', moodCategory: 'low_energy', icon: Icons.bedtime_outlined),
  MoodOptionModel(moodCode: 'stressed', moodLabel: 'Stressed', moodCategory: 'stress', icon: Icons.warning_amber_outlined),
  MoodOptionModel(moodCode: 'overwhelmed', moodLabel: 'Overwhelmed', moodCategory: 'high_stress', icon: Icons.indeterminate_check_box_outlined),
  MoodOptionModel(moodCode: 'unwell', moodLabel: 'Unwell', moodCategory: 'health', icon: Icons.sick_outlined),
  MoodOptionModel(moodCode: 'reserved', moodLabel: 'Quiet / Reserved', moodCategory: 'withdrawn', icon: Icons.do_not_disturb_on_outlined),
  MoodOptionModel(moodCode: 'not_observed', moodLabel: 'Not Observed', moodCategory: 'neutral', icon: Icons.remove_red_eye_outlined),
];
