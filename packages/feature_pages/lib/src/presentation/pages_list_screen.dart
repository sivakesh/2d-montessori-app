import 'package:core_contracts/core_contracts.dart' show UserRole;
import 'package:feature_publishing/feature_publishing.dart';
import 'package:flutter/material.dart';

import '../domain/cms_page.dart';
import '../domain/page_repository.dart';
import '../domain/use_cases/create_page_use_case.dart';
import '../domain/use_cases/list_pages_use_case.dart';

/// SRS CMS-10 "Lists and filters" for Pages: search by title/summary,
/// filter by status, create a new draft. No own [Scaffold]/[AppBar] —
/// embedded inside `AdminShell`'s single Scaffold, matching
/// `UserManagementScreen`'s convention.
class PagesListScreen extends StatefulWidget {
  const PagesListScreen({
    super.key,
    required this.repository,
    required this.actingRole,
    required this.actorId,
    required this.onOpenPage,
  });

  final PagesRepository repository;
  final UserRole actingRole;
  final String actorId;
  final ValueChanged<CmsPage> onOpenPage;

  @override
  State<PagesListScreen> createState() => _PagesListScreenState();
}

class _PagesListScreenState extends State<PagesListScreen> {
  late final ListPagesUseCase _listPages = ListPagesUseCase(widget.repository);
  late final CreatePageUseCase _createPage = CreatePageUseCase(
    widget.repository,
  );

  final _searchController = TextEditingController();
  PublishingStatus? _statusFilter;
  bool _loading = true;
  String? _error;
  List<CmsPage> _pages = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await _listPages(
      query: PagesQuery(
        status: _statusFilter,
        searchText: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      ),
    );
    if (!mounted) return;
    result.fold(
      (page) => setState(() {
        _pages = page.items;
        _loading = false;
        _error = null;
      }),
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
      }),
    );
  }

  Future<void> _createNewPage() async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _NewPageDialog(),
    );
    if (title == null || title.trim().isEmpty) return;
    final result = await _createPage(
      title: title.trim(),
      ownerId: widget.actorId,
    );
    if (!mounted) return;
    result.fold(widget.onOpenPage, (failure) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search pages',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<PublishingStatus?>(
                value: _statusFilter,
                hint: const Text('All statuses'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All statuses'),
                  ),
                  ...PublishingStatus.values.map(
                    (s) =>
                        DropdownMenuItem(value: s, child: Text(s.storageValue)),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _statusFilter = value);
                  _load();
                },
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _createNewPage,
                icon: const Icon(Icons.add),
                label: const Text('New page'),
              ),
            ],
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator())),
        if (!_loading && _error != null)
          Expanded(child: Center(child: Text(_error!))),
        if (!_loading && _error == null && _pages.isEmpty)
          const Expanded(child: Center(child: Text('No pages yet.'))),
        if (!_loading && _error == null && _pages.isNotEmpty)
          Expanded(
            child: ListView.separated(
              itemCount: _pages.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final page = _pages[index];
                return ListTile(
                  title: Text(page.title.isEmpty ? '(untitled)' : page.title),
                  subtitle: Text('/${page.slug} · ${page.status.storageValue}'),
                  trailing: Text(
                    page.updatedAt.toLocal().toString().split('.').first,
                  ),
                  onTap: () => widget.onOpenPage(page),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _NewPageDialog extends StatefulWidget {
  @override
  State<_NewPageDialog> createState() => _NewPageDialogState();
}

class _NewPageDialogState extends State<_NewPageDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New page'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Page title'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
