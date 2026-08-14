import 'package:flutter/material.dart';

/// Collected before an upload starts, and reused for editing an existing
/// asset's metadata afterwards — SRS "File name, title, description and
/// accessible alt text" are gathered up front, never added later.
class MediaMetadataDialogResult {
  const MediaMetadataDialogResult({
    required this.title,
    required this.altText,
    required this.description,
  });

  final String title;
  final String altText;
  final String description;
}

class MediaMetadataDialog extends StatefulWidget {
  const MediaMetadataDialog({
    super.key,
    this.initialTitle = '',
    this.initialAltText = '',
    this.initialDescription = '',
  });

  final String initialTitle;
  final String initialAltText;
  final String initialDescription;

  @override
  State<MediaMetadataDialog> createState() => _MediaMetadataDialogState();
}

class _MediaMetadataDialogState extends State<MediaMetadataDialog> {
  late final _title = TextEditingController(text: widget.initialTitle);
  late final _altText = TextEditingController(text: widget.initialAltText);
  late final _description = TextEditingController(
    text: widget.initialDescription,
  );
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _altText.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'A title is required.');
      return;
    }
    if (_altText.text.trim().isEmpty) {
      setState(() => _error = 'Accessible alt text is required.');
      return;
    }
    Navigator.of(context).pop(
      MediaMetadataDialogResult(
        title: _title.text.trim(),
        altText: _altText.text.trim(),
        description: _description.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Media details'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _altText,
              decoration: const InputDecoration(
                labelText: 'Alt text (required for accessibility)',
              ),
            ),
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
