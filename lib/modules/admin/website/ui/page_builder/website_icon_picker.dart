import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../public_website/content/blocks/website_icons.dart';

/// Chooses an icon of the website's icon library ([WebsiteIcons]) for the
/// Icon block and Text blocks: search, browse by category, a compact grid
/// of named icons, the chosen one previewed large before Choose. Returns
/// its id, or null when cancelled.
///
/// Keys: `website-icon-picker`, `-search`, `-category-<id>` (`-all`),
/// `website-icon-option-<id>`, `-preview`, `-choose`, `-cancel`, `-empty`.
Future<String?> showWebsiteIconPicker(BuildContext context, {String? selected}) => showDialog<String>(
      context: context,
      builder: (_) => _WebsiteIconPicker(selected: selected),
    );

class _WebsiteIconPicker extends StatefulWidget {
  const _WebsiteIconPicker({this.selected});

  final String? selected;

  @override
  State<_WebsiteIconPicker> createState() => _WebsiteIconPickerState();
}

class _WebsiteIconPickerState extends State<_WebsiteIconPicker> {
  final _search = TextEditingController();
  String _query = '';

  /// null: every category.
  String? _category;
  late String? _chosen = WebsiteIcons.lookup(widget.selected ?? '') == null ? null : widget.selected;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _chip(String? id, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          key: Key('website-icon-picker-category-${id ?? 'all'}'),
          label: Text(label),
          selected: _category == id,
          onSelected: (_) => setState(() => _category = id),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final shown = WebsiteIcons.search(_query, category: _category);
    final chosen = _chosen == null ? null : WebsiteIcons.lookup(_chosen!);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      key: const Key('website-icon-picker'),
      insetPadding: EdgeInsets.all(narrow ? 12 : 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Choose an icon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                key: const Key('website-icon-picker-search'),
                controller: _search,
                autofocus: !narrow,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search icons (book, phone, calendar…)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 10),
              // Every category at a glance; on phones, one scrolling row.
              if (narrow)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [_chip(null, 'All'), for (final (id, label) in WebsiteIcons.categories) _chip(id, label)]),
                )
              else
                Wrap(runSpacing: 6, children: [_chip(null, 'All'), for (final (id, label) in WebsiteIcons.categories) _chip(id, label)]),
              const SizedBox(height: 8),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          'No icons match “${_query.trim()}”${_category == null ? '' : ' in ${WebsiteIcons.categoryLabel(_category!)}'}.',
                          key: const Key('website-icon-picker-empty'),
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : GridView.builder(
                        key: const Key('website-icon-picker-grid'),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 96, mainAxisExtent: 84, crossAxisSpacing: 6, mainAxisSpacing: 6),
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final icon = shown[i];
                          final selected = icon.id == _chosen;
                          return Semantics(
                            selected: selected,
                            button: true,
                            label: icon.label,
                            excludeSemantics: true,
                            child: InkWell(
                              key: Key('website-icon-option-${icon.id}'),
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() => _chosen = icon.id),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: selected ? AppColors.primary.withValues(alpha: 0.10) : null,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: selected ? AppColors.primary : Colors.black.withValues(alpha: 0.08), width: selected ? 2 : 1),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(icon.data, size: 28, color: selected ? AppColors.primary : AppColors.textPrimary),
                                    const SizedBox(height: 6),
                                    Text(icon.label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, height: 1.2)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 20),
              Row(
                children: [
                  Container(
                    key: const Key('website-icon-picker-preview'),
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                    child: chosen == null ? const Icon(Icons.touch_app_outlined, color: AppColors.textSecondary) : Icon(chosen.data, size: 40, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      chosen == null ? 'Select an icon to preview it.' : '${chosen.label} · ${WebsiteIcons.categoryLabel(chosen.category)}',
                      key: const Key('website-icon-picker-chosen'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(key: const Key('website-icon-picker-cancel'), onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 4),
                  FilledButton(
                    key: const Key('website-icon-picker-choose'),
                    onPressed: chosen == null ? null : () => Navigator.pop(context, chosen.id),
                    child: const Text('Choose'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
