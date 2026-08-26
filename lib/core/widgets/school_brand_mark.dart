import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/admin/settings/providers/school_identity_provider.dart';

/// The school logo + name shown in app chrome (AppSidebar/AdminSidebar) —
/// watches [schoolIdentityProvider] for the saved School Settings identity
/// and falls back to the app's original hardcoded identity
/// ("2D Montessori" / `assets/logo.png`) whenever there's nothing saved
/// yet, the provider is still loading, or the saved logo URL fails to
/// load. This fallback is deliberate, not a placeholder to remove later —
/// existing installs with no School Settings saved must keep seeing
/// exactly what they always have, never a blank/broken sidebar.
class SchoolBrandMark extends ConsumerWidget {
  const SchoolBrandMark({super.key, this.logoHeight = 64, this.nameStyle, this.spacing = 8});

  final double logoHeight;
  final TextStyle? nameStyle;
  final double spacing;

  static const String defaultName = '2D Montessori';
  static const String defaultLogoAsset = 'assets/logo.png';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(schoolIdentityProvider).valueOrNull;
    final name = identity?.name.trim().isNotEmpty == true ? identity!.name.trim() : defaultName;
    final logoUrl = identity?.logoUrl ?? '';

    return Column(
      children: [
        SizedBox(
          height: logoHeight,
          child: logoUrl.isNotEmpty
              ? Image.network(
                  logoUrl,
                  height: logoHeight,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      Image.asset(defaultLogoAsset, height: logoHeight, fit: BoxFit.contain),
                )
              : Image.asset(defaultLogoAsset, height: logoHeight, fit: BoxFit.contain),
        ),
        SizedBox(height: spacing),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: nameStyle ?? Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}
