import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/models/app_user.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../public_website/content/website_content_repository.dart';
import '../../settings/ui/access_restricted_view.dart';
import '../data/website_publishing_manager.dart';
import 'website_content_screen.dart';

/// Settings → Website → Publishing manager: every website page, calendar
/// event and school announcement in one place, with where it stands on
/// the public website, and individual or bulk publish, update and remove
/// ([WebsitePublishingManager], which works through the existing
/// publishing services).
///
/// - Unpublished items: what has no website copy, whether it can be
///   published and, when not, why.
/// - Published items & website status: events and announcements with a
///   website copy — whether visitors see it, whether it is out of date,
///   and its image.
///
/// Admin only (others see the locked view; every call re-checks).
class WebsitePublishingManagerScreen extends ConsumerWidget {
  const WebsitePublishingManagerScreen({super.key, this.manager});

  final WebsitePublishingManager? manager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null || user.role.toLowerCase() != 'admin') {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(title: const Text('Website Publishing Manager')),
        body: const AccessRestrictedView(),
      );
    }
    return _ManagerBody(manager: manager ?? WebsitePublishingManager(), user: user);
  }
}

/// Rows shown per page of results.
const publishingPageSize = 20;

class _TabState {
  PublishingQuery query = const PublishingQuery();
  Set<String> selected = {};
  int page = 0;
}

class _ManagerBody extends ConsumerStatefulWidget {
  const _ManagerBody({required this.manager, required this.user});

  final WebsitePublishingManager manager;
  final AppUser user;

  @override
  ConsumerState<_ManagerBody> createState() => _ManagerBodyState();
}

class _ManagerBodyState extends ConsumerState<_ManagerBody> {
  PublishingSnapshot? _snapshot;
  Object? _loadError;
  bool _loading = false;

  /// Why the last action on each item failed, until it succeeds.
  final Map<String, String> _failures = {};
  final Map<PublishingTab, _TabState> _tabs = {for (final t in PublishingTab.values) t: _TabState()};
  ({int done, int total, PublishingAction action})? _progress;
  PublishingRunResult? _lastResult;

  String get _role => widget.user.role.toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final snapshot = await widget.manager.load(requesterRole: _role);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// This session's public pages pick up the change at once.
  void _refreshPublicSite() {
    ref.invalidate(liveWebsiteContentProvider);
    ref.invalidate(publicEventItemsProvider);
    ref.invalidate(publicEventProvider);
    ref.invalidate(publicAnnouncementItemsProvider);
    ref.invalidate(publicAnnouncementProvider);
  }

  List<PublishingEntry> _matching(PublishingTab tab) =>
      _tabs[tab]!.query.apply(_snapshot?.entries ?? const [], tab, failed: _failures.keys.toSet());

  static List<PublishingAction> _actionsFor(PublishingTab tab) => switch (tab) {
        PublishingTab.unpublished => const [PublishingAction.publish],
        PublishingTab.published => const [PublishingAction.publish, PublishingAction.update, PublishingAction.remove],
      };

  void _setQuery(PublishingTab tab, PublishingQuery query) => setState(() {
        _tabs[tab]!
          ..query = query
          ..page = 0;
      });

  /// Asks, runs, reports and refreshes. [keys]: the chosen rows.
  Future<void> _act(PublishingTab tab, PublishingAction action, Set<String> keys) async {
    final snapshot = _snapshot;
    if (snapshot == null || _progress != null) return;
    final plan = PublishingSelection.plan(keys, snapshot, action);
    final go = await showDialog<bool>(context: context, builder: (_) => _ConfirmDialog(action: action, selected: keys.length, plan: plan));
    if (go != true || !mounted) return;

    setState(() => _progress = (done: 0, total: plan.eligible.length, action: action));
    PublishingRunResult result;
    try {
      result = await widget.manager.run(
        requesterRole: _role,
        actor: widget.user,
        action: action,
        keys: [for (final e in plan.eligible) e.key],
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = (done: done, total: total, action: action));
        },
      );
    } catch (e) {
      // Nothing was attempted (the website couldn't be read first).
      if (mounted) {
        setState(() => _progress = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Nothing was changed: ${WebsitePublishingManager.describeError(e)}'),
          backgroundColor: Colors.red.shade700,
        ));
      }
      return;
    }
    if (!mounted) return;
    _refreshPublicSite();
    setState(() {
      _progress = null;
      _lastResult = result;
      for (final o in result.outcomes) {
        o.kind == PublishingOutcomeKind.failed ? _failures[o.key] = o.message : _failures.remove(o.key);
      }
      final state = _tabs[tab]!;
      state.selected = PublishingSelection.afterRun(state.selected, result);
      if (result.snapshot != null) _snapshot = result.snapshot;
    });
    if (result.snapshot == null) await _load();
    if (mounted) await showDialog<void>(context: context, builder: (_) => _ResultDialog(result: result));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text('Website Publishing Manager'),
          actions: [
            IconButton(
              key: const Key('publishing-refresh'),
              tooltip: 'Refresh',
              onPressed: _loading || _progress != null ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(key: Key('publishing-tab-unpublished'), text: 'Unpublished items'),
              Tab(key: Key('publishing-tab-published'), text: 'Published items & website status'),
            ],
          ),
        ),
        body: _loadError != null && _snapshot == null
            ? _LoadFailed(error: _loadError!, onRetry: _load)
            : _snapshot == null
                ? const Center(key: Key('publishing-loading'), child: CircularProgressIndicator())
                : TabBarView(children: [for (final tab in PublishingTab.values) _tab(tab)]),
      ),
    );
  }

  Widget _tab(PublishingTab tab) {
    final state = _tabs[tab]!;
    final matching = _matching(tab);
    final actions = _actionsFor(tab);
    final pages = (matching.length / publishingPageSize).ceil();
    final page = pages == 0 ? 0 : state.page.clamp(0, pages - 1);
    final shown = matching.skip(page * publishingPageSize).take(publishingPageSize).toList();
    final allEligible = PublishingSelection.allEligible(matching, actions);
    final selected = state.selected;
    final t = tab.name;

    int count(PublishingAction a) => [for (final k in selected) if (_snapshot!.byKey[k]?.can(a) ?? false) k].length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: Key('publishing-list-$t'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tab == PublishingTab.unpublished
                ? 'Pages, calendar events and announcements that aren’t on the public website. Only those that pass the website’s '
                    'publishing rules can be published; the others say why.'
                : 'Events and announcements with a copy on the public website: whether visitors see it now, and whether it is out of date. '
                    'Pages are managed in the Pages tab.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          _Filters(
            keyPrefix: t,
            query: state.query,
            types: tab == PublishingTab.unpublished ? PublishingType.values : const [PublishingType.event, PublishingType.announcement],
            statuses: tab == PublishingTab.unpublished ? PublishingStatusFilter.forUnpublishedTab : PublishingStatusFilter.forPublishedTab,
            schoolId: _snapshot!.schoolId,
            onChanged: (q) => _setQuery(tab, q),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${selected.length} selected', key: Key('publishing-selected-count-$t'), style: const TextStyle(fontWeight: FontWeight.w600)),
              TextButton(
                key: Key('publishing-select-all-$t'),
                onPressed: allEligible.isEmpty ? null : () => setState(() => state.selected = {...selected, ...allEligible}),
                child: Text('Select all eligible (${allEligible.length})'),
              ),
              TextButton(
                key: Key('publishing-clear-selection-$t'),
                onPressed: selected.isEmpty ? null : () => setState(() => state.selected = {}),
                child: const Text('Clear selection'),
              ),
              for (final a in actions)
                if (tab == PublishingTab.unpublished || count(a) > 0 || a != PublishingAction.publish)
                FilledButton.icon(
                  key: Key('publishing-bulk-${a.name}-$t'),
                  onPressed: selected.isEmpty || _progress != null ? null : () => _act(tab, a, {...selected}),
                  icon: Icon(_icon(a), size: 18),
                  label: Text('${a == PublishingAction.publish ? (tab == PublishingTab.unpublished ? 'Publish selected' : 'Show on website') : a.label} (${count(a)})'),
                  style: a == PublishingAction.remove ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)) : null,
                ),
            ],
          ),
          if (_progress case final p?) ...[
            const SizedBox(height: 8),
            Column(
              key: const Key('publishing-progress'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: p.total == 0 ? null : p.done / p.total),
                const SizedBox(height: 4),
                Text('${p.action.label}: ${p.done} of ${p.total} done…', style: const TextStyle(fontSize: 13)),
              ],
            ),
          ],
          if (_lastResult case final r? when _progress == null) ...[
            const SizedBox(height: 8),
            _ResultBanner(result: r, onDetails: () => showDialog<void>(context: context, builder: (_) => _ResultDialog(result: r))),
          ],
          if (_loadError != null) ...[
            const SizedBox(height: 8),
            Text(
              'The latest refresh failed, so this may be out of date: ${WebsitePublishingManager.describeError(_loadError!)}',
              key: const Key('publishing-refresh-error'),
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Padding(
              key: Key('publishing-empty-$t'),
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                (_snapshot!.entries.isEmpty || state.query == const PublishingQuery())
                    ? (tab == PublishingTab.unpublished ? 'Everything is on the website.' : 'Nothing is on the website yet.')
                    : 'Nothing matches these filters.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final e in shown)
            _Row(
              entry: e,
              tab: tab,
              selected: selected.contains(e.key),
              selectable: actions.any(e.can),
              failure: _failures[e.key],
              busy: _progress != null,
              onSelected: (on) => setState(() => on ? selected.add(e.key) : selected.remove(e.key)),
              onAction: (a) => _act(tab, a, {e.key}),
            ),
          if (matching.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${page * publishingPageSize + 1}–${page * publishingPageSize + shown.length} of ${matching.length}',
                  key: Key('publishing-page-label-$t'),
                  style: const TextStyle(fontSize: 13),
                ),
                IconButton(
                  key: Key('publishing-prev-$t'),
                  tooltip: 'Previous page',
                  onPressed: page == 0 ? null : () => setState(() => state.page = page - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  key: Key('publishing-next-$t'),
                  tooltip: 'Next page',
                  onPressed: page >= pages - 1 ? null : () => setState(() => state.page = page + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

IconData _icon(PublishingAction a) => switch (a) {
      PublishingAction.publish => Icons.public,
      PublishingAction.update => Icons.sync,
      PublishingAction.remove => Icons.public_off,
    };

Color _statusColor(PublishingStatus s) => switch (s) {
      PublishingStatus.onWebsite => const Color(0xFF2E7D5B),
      PublishingStatus.outOfDate || PublishingStatus.notVisible => const Color(0xFF8A6A33),
      PublishingStatus.shouldRemove => const Color(0xFFB3261E),
      PublishingStatus.unpublished => const Color(0xFF6E6E73),
    };

String _date(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

class _Filters extends StatefulWidget {
  const _Filters({
    required this.keyPrefix,
    required this.query,
    required this.types,
    required this.statuses,
    required this.schoolId,
    required this.onChanged,
  });

  final String keyPrefix;
  final PublishingQuery query;
  final List<PublishingType> types;
  final List<PublishingStatusFilter> statuses;
  final String schoolId;
  final ValueChanged<PublishingQuery> onChanged;

  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  late final _search = TextEditingController(text: widget.query.search);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.query;
    final t = widget.keyPrefix;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            key: Key('publishing-search-$t'),
            controller: _search,
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search by title', border: OutlineInputBorder()),
            onChanged: (v) => widget.onChanged(q.copyWith(search: v)),
          ),
        ),
        for (final type in widget.types)
          FilterChip(
            key: Key('publishing-type-${type.name}-$t'),
            label: Text(type.label),
            selected: q.types.contains(type),
            onSelected: (on) => widget.onChanged(q.copyWith(types: on ? {...q.types, type} : ({...q.types}..remove(type)))),
          ),
        DropdownButton<PublishingStatusFilter>(
          key: Key('publishing-status-filter-$t'),
          value: q.status,
          items: [for (final s in widget.statuses) DropdownMenuItem(value: s, child: Text(s.label))],
          onChanged: (s) => widget.onChanged(q.copyWith(status: s)),
        ),
        WebsiteStatusChip(key: Key('publishing-school-$t'), label: 'School: ${widget.schoolId}', color: const Color(0xFF6E6E73)),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.tab,
    required this.selected,
    required this.selectable,
    required this.failure,
    required this.busy,
    required this.onSelected,
    required this.onAction,
  });

  final PublishingEntry entry;
  final PublishingTab tab;
  final bool selected;
  final bool selectable;
  final String? failure;
  final bool busy;
  final ValueChanged<bool> onSelected;
  final ValueChanged<PublishingAction> onAction;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final k = e.key;
    final details = <(String, Key, Color)>[
      if (e.problem case final p?) (p, Key('publishing-problem-$k'), const Color(0xFFB3261E)),
      if (e.differences.isNotEmpty) ('Changed since it was published: ${e.differences.join(', ')}.', Key('publishing-differences-$k'), const Color(0xFF8A6A33)),
      if (e.visibilityProblem case final v?) (v, Key('publishing-visibility-$k'), const Color(0xFF8A6A33)),
      if (e.image case final img?) ('Image: ${img.label}. ${img.detail}', Key('publishing-image-$k'), img.color),
      if (e.note case final n?) (n, Key('publishing-note-$k'), AppColors.textSecondary),
      if (failure case final f?) ('Last action failed: $f', Key('publishing-failure-$k'), const Color(0xFFB3261E)),
    ];
    final actions = switch (tab) {
      PublishingTab.unpublished => const [PublishingAction.publish],
      PublishingTab.published => const [PublishingAction.publish, PublishingAction.update, PublishingAction.remove],
    };
    return Card(
      key: Key('publishing-row-$k'),
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: Key('publishing-select-$k'),
              value: selected,
              onChanged: selectable || selected ? (on) => onSelected(on ?? false) : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      WebsiteStatusChip(label: e.type.label, color: AppColors.primary),
                      WebsiteStatusChip(key: Key('publishing-status-$k'), label: e.status.label, color: _statusColor(e.status)),
                      if (failure != null) WebsiteStatusChip(key: Key('publishing-failed-$k'), label: 'Failed', color: const Color(0xFFB3261E)),
                      if (!e.hasCopy)
                        WebsiteStatusChip(
                          key: Key('publishing-eligibility-$k'),
                          label: e.problem == null ? 'Can be published' : 'Can’t be published',
                          color: e.problem == null ? const Color(0xFF2E7D5B) : const Color(0xFF6E6E73),
                        ),
                      Text('Source: ${e.sourceStatus}', style: const TextStyle(fontSize: 12)),
                      if (e.date case final d?) Text(e.type == PublishingType.announcement ? 'Shown from ${_date(d)}' : _date(d), style: const TextStyle(fontSize: 12)),
                      if (e.route case final r?) Text(r, style: const TextStyle(fontSize: 12)),
                      Text('School: ${e.schoolId}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                  for (final (text, key, color) in details) Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, key: key, style: TextStyle(fontSize: 12.5, color: color))),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final a in actions)
                        if (e.can(a))
                          TextButton.icon(
                            key: Key('publishing-${a.name}-$k'),
                            onPressed: busy ? null : () => onAction(a),
                            icon: Icon(_icon(a), size: 18),
                            label: Text(a == PublishingAction.publish && tab == PublishingTab.published ? 'Show on website' : a.label),
                            style: a == PublishingAction.remove ? TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)) : null,
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.action, required this.selected, required this.plan});

  final PublishingAction action;
  final int selected;
  final ({List<PublishingEntry> eligible, List<({PublishingEntry entry, String reason})> ineligible, int missing}) plan;

  @override
  Widget build(BuildContext context) {
    final n = plan.eligible.length;
    final pages = plan.eligible.where((e) => e.isPage).length;
    final warning = switch (action) {
      PublishingAction.publish => 'Visitors will see ${n == 1 ? 'it' : 'them'} straight away. Events and announcements show their title, '
          'text, dates and category; who wrote them, who they were sent to and attachments stay in the app.'
          '${pages > 0 ? ' $pages page${pages == 1 ? '' : 's'} will be published from ${pages == 1 ? 'its' : 'their'} saved draft.' : ''}',
      PublishingAction.update => 'Each website copy is replaced with the item as saved now. Visitors see the new version straight away.',
      PublishingAction.remove => 'Visitors will no longer see ${n == 1 ? 'it' : 'them'}. The events and announcements themselves are unchanged, '
          'and can be shown again later.',
    };
    return AlertDialog(
      key: const Key('publishing-confirm-dialog'),
      title: Text(switch (action) {
        PublishingAction.publish => 'Publish $n item${n == 1 ? '' : 's'}?',
        PublishingAction.update => 'Update $n website cop${n == 1 ? 'y' : 'ies'}?',
        PublishingAction.remove => 'Remove $n item${n == 1 ? '' : 's'} from the website?',
      }),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Selected: $selected', key: const Key('publishing-confirm-selected')),
              Text('Will be ${action.done.toLowerCase()}: $n', key: const Key('publishing-confirm-eligible')),
              Text('Skipped (not eligible): ${plan.ineligible.length + plan.missing}', key: const Key('publishing-confirm-ineligible')),
              if (plan.ineligible.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final i in plan.ineligible.take(8)) Text('• ${i.entry.title}: ${i.reason}', style: const TextStyle(fontSize: 12.5)),
                if (plan.ineligible.length > 8) Text('…and ${plan.ineligible.length - 8} more.', style: const TextStyle(fontSize: 12.5)),
              ],
              const SizedBox(height: 12),
              Text(n == 0 ? 'Nothing selected can be ${action.done.toLowerCase()}.' : warning, key: const Key('publishing-confirm-warning')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(key: const Key('publishing-confirm-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('publishing-confirm-go'),
          onPressed: n == 0 ? null : () => Navigator.pop(context, true),
          style: action == PublishingAction.remove ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)) : null,
          child: Text(action.label),
        ),
      ],
    );
  }
}

String _summary(PublishingRunResult r) {
  final parts = [
    '${r.succeeded.length} ${r.action.done.toLowerCase()}',
    if (r.failed.isNotEmpty) '${r.failed.length} failed',
    if (r.skipped.isNotEmpty) '${r.skipped.length} skipped',
  ];
  return parts.join(', ');
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result, required this.onDetails});

  final PublishingRunResult result;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final ok = result.complete;
    return Container(
      key: const Key('publishing-result'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (ok ? const Color(0xFF2E7D5B) : const Color(0xFFB3261E)).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: ok ? const Color(0xFF2E7D5B) : const Color(0xFFB3261E)),
          const SizedBox(width: 8),
          Expanded(child: Text('Last action: ${_summary(result)}.', style: const TextStyle(fontSize: 13))),
          TextButton(key: const Key('publishing-result-details'), onPressed: onDetails, child: const Text('Details')),
        ],
      ),
    );
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({required this.result});

  final PublishingRunResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    Widget section(String title, List<PublishingOutcome> items, Key key, Color color) => Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text('$title (${items.length})', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            for (final o in items) Text('• ${o.title}: ${o.message}', style: const TextStyle(fontSize: 12.5)),
          ],
        );
    return AlertDialog(
      key: const Key('publishing-result-dialog'),
      title: Text(r.complete
          ? 'All done'
          : r.succeeded.isEmpty
              ? 'Nothing was changed'
              : 'Finished with problems'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${_summary(r)}.', key: const Key('publishing-result-summary')),
              if (r.reloadError != null)
                const Text('The website couldn’t be re-read afterwards, so changes that couldn’t be confirmed are listed as failed.', style: TextStyle(fontSize: 12.5)),
              if (r.succeeded.isNotEmpty) section(r.action.done, r.succeeded, const Key('publishing-result-succeeded'), const Color(0xFF2E7D5B)),
              if (r.failed.isNotEmpty) section('Failed', r.failed, const Key('publishing-result-failed'), const Color(0xFFB3261E)),
              if (r.skipped.isNotEmpty) section('Skipped', r.skipped, const Key('publishing-result-skipped'), const Color(0xFF6E6E73)),
              if (r.failed.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Failed items stay selected, so you can try them again.', style: TextStyle(fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
      actions: [FilledButton(key: const Key('publishing-result-close'), onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        key: const Key('publishing-load-error'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40, color: Colors.grey),
              const SizedBox(height: 12),
              Text('The website’s publishing status couldn’t be loaded. ${WebsitePublishingManager.describeError(error)}', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(key: const Key('publishing-retry'), onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}
