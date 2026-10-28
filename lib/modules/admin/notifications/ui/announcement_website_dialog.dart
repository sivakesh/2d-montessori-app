import 'package:flutter/material.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../../auth/models/app_user.dart';
import '../../../public_website/content/website_public_item.dart';
import '../../website/data/website_copy_status.dart';
import '../../website/ui/website_content_screen.dart';
import '../../website/ui/website_item_image_section.dart';
import '../data/announcement_website_publisher.dart';
import '../models/admin_notification_model.dart';

/// The label and colour of an announcement's website state, for chips.
(String, Color)? announcementWebsiteChip(WebsiteCopyState? state) => switch (state) {
      WebsiteCopyState.current => ('On website', const Color(0xFF2E7D5B)),
      WebsiteCopyState.outOfDate => ('Website out of date', Colors.orange),
      WebsiteCopyState.noLongerEligible => ('Remove from website', Colors.redAccent),
      WebsiteCopyState.notVisible => ('Not visible on website', Colors.orange),
      WebsiteCopyState.notShown || null => null,
    };

/// An announcement's Public website settings: whether it is shown on the
/// website ("Show on website"), its image, and where its copy stands.
/// Saving applies only these (the announcement itself is saved in its own
/// form): it shows, updates or removes the copy, explicitly. Pops with what
/// to tell the admin after a change; failures stay here, shown as such.
class AnnouncementWebsiteDialog extends StatefulWidget {
  const AnnouncementWebsiteDialog({
    super.key,
    required this.notice,
    required this.item,
    required this.publisher,
    required this.requesterRole,
    this.actor,
  });

  final AdminNotificationModel notice;

  /// Its copy on the website, if it has one.
  final WebsitePublicItem? item;
  final AnnouncementWebsitePublisher publisher;
  final String requesterRole;
  final AppUser? actor;

  @override
  State<AnnouncementWebsiteDialog> createState() => _AnnouncementWebsiteDialogState();
}

class _AnnouncementWebsiteDialogState extends State<AnnouncementWebsiteDialog> {
  late bool _show = widget.item != null;
  late String? _imageId = widget.item?.imageMediaId;
  bool _imageChanged = false;
  bool _saving = false;
  String? _error;

  bool get _wasOnWebsite => widget.item != null;

  Future<void> _save() async {
    final notice = widget.notice;
    final eligible = AnnouncementWebsitePublisher.ineligibility(notice) == null;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? message;
      if (_show && eligible) {
        final item = await widget.publisher.show(
          requesterRole: widget.requesterRole,
          notice: notice,
          approvedForWebsite: true,
          image: _imageChanged ? () => _imageId : null,
        );
        // Never reported as shown when visitors won't see it.
        final hidden = AnnouncementWebsitePublisher.visibilityProblem(item);
        message = hidden == null
            ? (_wasOnWebsite ? 'Public website updated' : 'Shown on the public website')
            : 'Saved to the public website, but not shown to visitors. $hidden';
      } else if (_wasOnWebsite) {
        await widget.publisher.withdraw(requesterRole: widget.requesterRole, noticeId: notice.id);
        message = 'Removed from the public website';
      }
      if (mounted) Navigator.of(context).pop(message);
    } catch (e) {
      if (mounted) setState(() => _error = 'The public website wasn’t changed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    final item = widget.item;
    final state = AnnouncementWebsitePublisher.stateOf(notice, item);
    final chip = announcementWebsiteChip(state);
    final differences = item == null ? const <String>[] : AnnouncementWebsitePublisher.differences(notice, item);
    final problem = AnnouncementWebsitePublisher.ineligibility(notice) ?? (_wasOnWebsite ? null : AnnouncementWebsitePublisher.endedReason(notice));
    final on = _show && problem == null;
    final status = switch (state) {
      WebsiteCopyState.notShown => 'Not on the public website.',
      WebsiteCopyState.current => 'On the public website; visitors see it.',
      WebsiteCopyState.outOfDate => 'On the public website, but it shows an older version${differences.isEmpty ? '' : ' (its ${differences.join(', ')} differ${differences.length == 1 ? 's' : ''})'}. '
          'Visitors see it until you update it, or remove it.',
      WebsiteCopyState.noLongerEligible => 'Still on the public website, but it can’t be shown any more. Remove it.',
      WebsiteCopyState.notVisible => AnnouncementWebsitePublisher.visibilityProblem(item!) ?? '',
    };
    final explanation = switch ((problem, on, _wasOnWebsite)) {
      (final String problem, _, true) => 'Saving removes it from the website. $problem',
      (final String problem, _, false) => problem,
      (null, true, true) => 'Saving updates the website with the announcement as saved now.',
      (null, true, false) => 'Saving shows this announcement on the public website, to anyone on the internet: its title, '
          'message, date, category and image. Who wrote it, who it was sent to and its attachment stay in the app.',
      (null, false, true) => 'Saving removes this announcement from the public website.',
      (null, false, false) => 'Not shown on the public website.',
    };

    return ResponsiveDialogShell.form(
      desktopWidth: 560,
      title: 'Public website',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(notice.title.isEmpty ? 'Announcement' : notice.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          if (chip case (final label, final color)) ...[
            WebsiteStatusChip(key: const Key('announcement-website-chip'), label: label, color: color),
            const SizedBox(height: 6),
          ],
          Text(status, key: const Key('announcement-website-status'), style: const TextStyle(fontSize: 13)),
          const Divider(height: 24),
          SwitchListTile(
            key: const Key('announcement-website-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Show on website'),
            value: on,
            onChanged: problem == null && !_saving ? (value) => setState(() => _show = value) : null,
          ),
          Text(explanation, key: const Key('announcement-website-explanation'), style: const TextStyle(fontSize: 13)),
          if (on)
            WebsiteItemImageSection(
              media: widget.publisher.mediaIfAvailable,
              requesterRole: widget.requesterRole,
              actor: widget.actor,
              initialMediaId: _imageId,
              keyPrefix: 'announcement-website-image',
              what: 'announcement',
              onChanged: (id) => setState(() {
                _imageId = id;
                _imageChanged = id != widget.item?.imageMediaId;
              }),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, key: const Key('announcement-website-error'), style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('announcement-website-save'),
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }
}
