import 'package:flutter/material.dart';

import '../theme/app_sizes.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget web;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    required this.web,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width >= AppSizes.mobileBreakpoint) {
      return web;
    } else {
      return mobile;
    }
  }
}
