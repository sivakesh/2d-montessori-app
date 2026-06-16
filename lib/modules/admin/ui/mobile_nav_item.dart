import 'package:flutter/material.dart';

class MobileNavItem {
  const MobileNavItem({
    required this.label,
    required this.icon,
    required this.route,
    this.screenIndex,
    this.builder,
  });

  final String label;
  final IconData icon;
  final String route;
  final int? screenIndex;
  final WidgetBuilder? builder;
}
