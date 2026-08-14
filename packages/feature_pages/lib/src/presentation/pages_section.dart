import 'package:core_contracts/core_contracts.dart' show UserRole;
import 'package:feature_media/feature_media.dart' show MediaRepository;
import 'package:flutter/material.dart';

import '../domain/cms_page.dart';
import '../domain/page_repository.dart';
import 'page_editor_controller.dart';
import 'page_editor_screen.dart';
import 'pages_list_screen.dart';

/// The complete "Pages" admin nav section: list <-> editor, self-
/// contained the same way `UserManagementScreen` is for Users. This is
/// the one widget `apps/admin_web`'s composition root needs to build an
/// [AdminNavEntry] for Pages.
class PagesSection extends StatefulWidget {
  const PagesSection({
    super.key,
    required this.repository,
    required this.mediaRepository,
    required this.actingRole,
    required this.actorId,
  });

  final PagesRepository repository;

  /// Backs the "choose from Media Library" picker every image field
  /// uses in place of raw URL entry (SRS "Media selection/reuse from
  /// Pages") — see `PageEditorScreen`/`SectionEditorDialog`.
  final MediaRepository mediaRepository;

  final UserRole actingRole;
  final String actorId;

  @override
  State<PagesSection> createState() => _PagesSectionState();
}

class _PagesSectionState extends State<PagesSection> {
  PageEditorController? _editorController;

  void _open(CmsPage page) {
    _editorController?.dispose();
    setState(() {
      _editorController = PageEditorController(
        repository: widget.repository,
        actingRole: widget.actingRole,
        actorId: widget.actorId,
        initialPage: page,
      );
    });
  }

  void _close() {
    final controller = _editorController;
    setState(() => _editorController = null);
    controller?.dispose();
  }

  @override
  void dispose() {
    _editorController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _editorController;
    if (controller == null) {
      return PagesListScreen(
        repository: widget.repository,
        actingRole: widget.actingRole,
        actorId: widget.actorId,
        onOpenPage: _open,
      );
    }
    return PageEditorScreen(
      controller: controller,
      mediaRepository: widget.mediaRepository,
      onClose: _close,
    );
  }
}
