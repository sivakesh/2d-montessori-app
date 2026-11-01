import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../finance/widgets/finance_status_chip.dart';
import '../../admin/website/data/website_copy_status.dart';
import '../../public_website/content/website_content_models.dart';
import '../services/calendar_website_publisher.dart';

/// An Admin's view of one event on the public website, shared by the List
/// view's card and the detail dialog so both offer the same actions.
class CalendarWebsiteActions {
  const CalendarWebsiteActions({
    required this.state,
    this.unavailableReason,
    this.differences = const [],
    this.visibilityReason,
    this.onShow,
    this.onUpdate,
    this.onRemove,
  });

  /// Where the event stands, or null when the website couldn't be read.
  final CalendarWebsiteState? state;

  /// Why the event can't be shown, when it can't.
  final String? unavailableReason;

  /// When out of date: what the website shows differently
  /// ([CalendarWebsitePublisher.differences]).
  final List<String> differences;

  /// When not visible: why visitors don't see the copy
  /// ([CalendarWebsitePublisher.visibilityProblem]).
  final String? visibilityReason;
  final VoidCallback? onShow;
  final VoidCallback? onUpdate;
  final VoidCallback? onRemove;

  bool get hasActions => onShow != null || onUpdate != null || onRemove != null;

  /// The same actions, each run after [before] (closing a dialog first).
  CalendarWebsiteActions after(VoidCallback before) {
    VoidCallback? wrap(VoidCallback? action) => action == null
        ? null
        : () {
            before();
            action();
          };
    return CalendarWebsiteActions(
      state: state,
      unavailableReason: unavailableReason,
      differences: differences,
      visibilityReason: visibilityReason,
      onShow: wrap(onShow),
      onUpdate: wrap(onUpdate),
      onRemove: wrap(onRemove),
    );
  }
}

/// A chip for an event that is on the website (nothing otherwise).
class CalendarWebsiteChip extends StatelessWidget {
  const CalendarWebsiteChip({super.key, required this.state});

  final CalendarWebsiteState? state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      CalendarWebsiteState.current => ('On website', AppColors.secondary),
      CalendarWebsiteState.outOfDate => ('Website out of date', Colors.orange),
      CalendarWebsiteState.noLongerEligible => ('Remove from website', Colors.redAccent),
      CalendarWebsiteState.notVisible => ('Not visible on website', Colors.orange),
      CalendarWebsiteState.notShown || null => (null, null),
    };
    if (label == null || color == null) return const SizedBox.shrink();
    return FinanceStatusChip(key: const Key('calendar-website-chip'), label: label, color: color);
  }
}

/// The buttons for [actions] (none when there are none).
List<Widget> calendarWebsiteButtons(CalendarWebsiteActions? actions) => [
      if (actions?.onShow case final onShow?)
        TextButton.icon(
          key: const Key('calendar-website-show'),
          onPressed: onShow,
          icon: const Icon(Icons.public, size: 18),
          label: const Text('Show on website'),
        ),
      if (actions?.onUpdate case final onUpdate?)
        TextButton.icon(
          key: const Key('calendar-website-update'),
          onPressed: onUpdate,
          icon: const Icon(Icons.sync, size: 18),
          label: const Text('Update website'),
        ),
      if (actions?.onRemove case final onRemove?)
        TextButton.icon(
          key: const Key('calendar-website-remove'),
          onPressed: onRemove,
          icon: const Icon(Icons.public_off, size: 18),
          label: const Text('Remove from website'),
        ),
    ];

/// Where an event's website image stands ([websiteImageStatus]).
({String label, String detail, Color color, bool visible}) calendarEventImageStatus(String? mediaId, WebsiteMedia? media) => websiteImageStatus(mediaId, media);
