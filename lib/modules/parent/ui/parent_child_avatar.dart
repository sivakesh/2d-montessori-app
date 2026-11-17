import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/parent_file_service.dart';

/// A child's photo for parents. From the parent-safe profile it has only a
/// Storage path ([photoPath]); the photo is downloaded by
/// ParentFileService.readChildPhoto, which first checks that [studentId] is
/// one of the signed-in parent's linked children. Before the reconciliation
/// the legacy record's [photoUrl] is used as before. Falls back to the
/// initial.
class ParentChildAvatar extends StatefulWidget {
  const ParentChildAvatar({super.key, required this.name, this.studentId = '', this.photoPath = '', this.photoUrl = '', this.radius = 36, this.fileService});

  final String name, studentId, photoPath, photoUrl;
  final double radius;
  final ParentFileService? fileService;

  @override
  State<ParentChildAvatar> createState() => _ParentChildAvatarState();
}

class _ParentChildAvatarState extends State<ParentChildAvatar> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ParentChildAvatar old) {
    super.didUpdateWidget(old);
    if (old.photoPath != widget.photoPath || old.studentId != widget.studentId) _load();
  }

  void _load() {
    final files = widget.fileService;
    _bytes = widget.photoPath.isEmpty || widget.studentId.isEmpty || files == null
        ? null
        : files.readChildPhoto(widget.studentId).then<Uint8List?>((b) => b, onError: (_) => null);
  }

  Widget _avatar(ImageProvider? image) => CircleAvatar(
        radius: widget.radius,
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        backgroundImage: image,
        child: image == null
            ? Text(
                widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                style: TextStyle(fontSize: widget.radius * 0.66, fontWeight: FontWeight.w700, color: AppColors.primary),
              )
            : null,
      );

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return _avatar(widget.photoUrl.isNotEmpty ? NetworkImage(widget.photoUrl) : null);
    return FutureBuilder<Uint8List?>(
      future: bytes,
      builder: (context, snap) => _avatar(snap.data == null ? null : MemoryImage(snap.data!)),
    );
  }
}
