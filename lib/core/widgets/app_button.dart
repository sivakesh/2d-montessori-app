import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_sizes.dart';

enum AppButtonType { primary, secondary, ghost }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.type = AppButtonType.primary,
    this.fullWidth = true,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final AppButtonType type;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb || MediaQuery.of(context).size.width > 600;
    final height = isWeb ? AppSizes.buttonHeightWeb : AppSizes.buttonHeightMobile;
    final radius = isWeb ? AppSizes.borderRadiusWeb : AppSizes.borderRadiusMobile;

    final child = isLoading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: switch (type) {
                AppButtonType.primary => Colors.white,
                _ => AppColors.textPrimary,
              },
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Text(text),
            ],
          );

    final backgroundColor = switch (type) {
      AppButtonType.primary => AppColors.primary,
      AppButtonType.secondary => Colors.grey.shade200,
      AppButtonType.ghost => Colors.transparent,
    };
    final foregroundColor = switch (type) {
      AppButtonType.primary => Colors.white,
      _ => AppColors.textPrimary,
    };

    final button = Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(
            horizontal: type == AppButtonType.ghost ? 8 : 16,
          ),
          alignment: Alignment.center,
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
            child: IconTheme(
              data: IconThemeData(color: foregroundColor),
              child: child,
            ),
          ),
        ),
      ),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
