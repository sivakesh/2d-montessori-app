import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/settings/ui/access_restricted_view.dart';
import '../../admin/ui/admin_layout.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/parent_access.dart';
import '../data/parent_access_service.dart';
import '../data/parent_projection_service.dart';

/// Settings → Parent access: the administrator's reconciliation of parent
/// links into the `parent_access` records the security rules check
/// (docs/parent_access_security.md). "Check" only reads and reports;
/// "Apply" writes the records that changed. Running it again changes
/// nothing. Problems are listed for the administrator to fix in the
/// student or parent forms — nothing is guessed or deleted.
///
/// "Rebuild parent copies" rewrites every parent-safe projection
/// (ParentProjectionService.syncAll). The check also lists accounts the
/// rules can't recognise (id not a phone number, phone edited, shared
/// phone).
///
/// Check also shows how each kind of parent copy compares with its
/// originals and the refreshes that failed (Phase 0.2).
///
/// Keys: `parent-access-` + `check`, `apply`, `rebuild-copies`, `summary`,
/// `issues`, `result`, `copies-result`, `copies-health`.
class ParentAccessScreen extends ConsumerStatefulWidget {
  const ParentAccessScreen({super.key, this.service, this.projections});

  final ParentAccessService? service;
  final ParentProjectionService? projections;

  static const title = 'Parent access';

  @override
  ConsumerState<ParentAccessScreen> createState() => _ParentAccessScreenState();
}

class _ParentAccessScreenState extends ConsumerState<ParentAccessScreen> {
  late final _service = widget.service ?? ParentAccessService();
  late final _projections = widget.projections ?? ParentProjectionService();
  ParentAccessPlan? _plan;
  ParentAccessApplyResult? _result;
  ParentProjectionSyncResult? _copies;
  List<ParentProjectionHealth>? _health;
  List<ParentProjectionFailure>? _failures;
  ParentAccessComparison? _comparison;
  ParentAccountDiagnosis? _diagnosis;
  final _lookup = TextEditingController();
  bool _busy = false;
  String? _error;

  String get _role => ref.read(currentUserProvider)?.role ?? '';

  @override
  void dispose() {
    _lookup.dispose();
    super.dispose();
  }

  Future<void> _diagnose() => _run(() async {
        final id = _lookup.text.replaceAll(RegExp(r'[^0-9]'), '');
        final phone = id.length > 10 ? id.substring(id.length - 10) : id;
        if (phone.isEmpty) return;
        final d = await _projections.diagnoseParent(phone, requesterRole: _role);
        if (mounted) setState(() => _diagnosis = d);
      });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() => _run(() async {
        final plan = await _service.preview(requesterRole: _role);
        final comparison = await _service.compare(plan, requesterRole: _role);
        // Read-only too: how every parent copy compares with its original,
        // and the refreshes that failed since the last repair.
        final health = await _projections.health(requesterRole: _role);
        final failures = await _projections.failures(requesterRole: _role);
        if (mounted) {
          setState(() {
            _plan = plan;
            _comparison = comparison;
            _result = null;
            _health = health;
            _failures = failures;
          });
        }
      });

  Future<void> _refreshStatus() async {
    final health = await _projections.health(requesterRole: _role);
    final failures = await _projections.failures(requesterRole: _role);
    if (mounted) {
      setState(() {
        _health = health;
        _failures = failures;
      });
    }
  }

  Future<void> _apply() => _run(() async {
        final plan = _plan;
        if (plan == null) return;
        final result = await _service.apply(plan, requesterRole: _role, updatedBy: ref.read(currentUserProvider)?.id ?? '');
        // Parents read their children only from the parent-safe copies, so
        // they are rebuilt together with the access records.
        final copies = await _projections.syncAll(requesterRole: _role);
        if (mounted) {
          setState(() {
            _result = result;
            _copies = copies;
          });
        }
        await _refreshStatus();
        final comparison = await _service.compare(plan, requesterRole: _role);
        if (mounted) setState(() => _comparison = comparison);
      });

  Future<void> _rebuildCopies() => _run(() async {
        final r = await _projections.syncAll(requesterRole: _role);
        if (mounted) setState(() => _copies = r);
        await _refreshStatus();
      });

  @override
  Widget build(BuildContext context) {
    final isAdmin = (ref.watch(currentUserProvider)?.role ?? '').toLowerCase() == 'admin';
    final plan = _plan;
    return AdminLayout(
      selectedIndex: 11,
      title: ParentAccessScreen.title,
      body: !isAdmin
          ? const AccessRestrictedView()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(ParentAccessScreen.title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                const Text(
                  'Builds what each parent account may see from the parent links on student records. '
                  'A linked Father or Mother sees the child and their fees; a Guardian or Other sees the child but no fees. '
                  'A relationship that is missing or contradictory links the child but withholds fees until it is fixed.',
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    key: const Key('parent-access-check'),
                    onPressed: _busy ? null : _check,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Check (no changes)'),
                  ),
                  FilledButton.icon(
                    key: const Key('parent-access-apply'),
                    onPressed: _busy || plan == null || _result != null ? null : _apply,
                    icon: const Icon(Icons.lock_person_outlined),
                    label: const Text('Apply'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('parent-access-rebuild-copies'),
                    onPressed: _busy ? null : _rebuildCopies,
                    icon: const Icon(Icons.sync),
                    label: const Text('Rebuild parent copies'),
                  ),
                ]),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Parents read safe copies of student profiles, fees, payments, fee bills and notices. They are refreshed after every admin change; '
                    'Check shows any copy that is out of date or failed to refresh, and Rebuild repairs them (safe to repeat; originals are never changed).',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                if (_copies case final c?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Parent copies rebuilt: ${c.totalWritten} written, ${c.totalUnchanged} already current, ${c.totalRemoved} out-of-date copies removed'
                      '${c.totalFailed > 0 ? ', ${c.totalFailed} failed (see below; run Rebuild again)' : ''}.',
                      key: const Key('parent-access-copies-result'),
                      style: TextStyle(color: c.totalFailed > 0 ? Colors.orange.shade900 : null),
                    ),
                  ),
                if (_copies case final c?)
                  Text(
                    'Fee bills: ${c.written[ParentProjectionKind.feeBills] ?? 0} copies created or updated, '
                    '${c.unchanged[ParentProjectionKind.feeBills] ?? 0} already current, ${c.failed[ParentProjectionKind.feeBills] ?? 0} failed.',
                    key: const Key('parent-access-bills-result'),
                  ),
                if (_health case final health?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      key: const Key('parent-access-copies-health'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          health.every((h) => h.isCurrent) && (_failures ?? const []).isEmpty
                              ? 'All parent copies are up to date.'
                              : 'Some parent copies need a rebuild.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: health.every((h) => h.isCurrent) && (_failures ?? const []).isEmpty ? Colors.green.shade800 : Colors.orange.shade900,
                          ),
                        ),
                        for (final h in health)
                          if (h.error.isNotEmpty)
                            Text('${h.kind.label}: could not be checked — ${h.error}', key: Key('parent-access-health-error-${h.kind.name}'), style: TextStyle(color: Colors.red.shade800))
                          else if (h.kind == ParentProjectionKind.feeBills)
                            Text(
                              'Fee bills: ${h.expected} active bills found; ${h.current} parent copies current, ${h.missing} missing, '
                              '${h.outdated} out of date, ${h.orphaned} no longer needed.',
                              key: const Key('parent-access-bills-health'),
                            )
                          else if (!h.isCurrent)
                            Text('${h.kind.label}: ${h.missing} missing, ${h.outdated} out of date, ${h.orphaned} no longer needed (of ${h.expected}).'),
                        for (final f in _failures ?? const <ParentProjectionFailure>[])
                          Text(
                            'Refresh failed: ${f.scope} ${f.sourceId}${f.at == null ? '' : ' at ${f.at}'} (${f.attempts}×): ${f.error}',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                const Text('Check one parent account', style: TextStyle(fontWeight: FontWeight.w600)),
                const Text('Why a parent does or doesn\'t see their children\'s bills (read-only).', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      key: const Key('parent-access-lookup'),
                      controller: _lookup,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Parent phone number', isDense: true),
                    ),
                  ),
                  OutlinedButton(key: const Key('parent-access-diagnose'), onPressed: _busy ? null : _diagnose, child: const Text('Check account')),
                ]),
                if (_diagnosis case final d?) _DiagnosisView(diagnosis: d),
                if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                if (plan != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${plan.linkCount} link records • ${plan.records.length} parents • '
                    '${plan.records.values.fold<int>(0, (t, r) => t + r.studentIds.length)} child links • '
                    '${plan.records.values.fold<int>(0, (t, r) => t + r.financeStudentIds.length)} with fee access • '
                    '${plan.unresolved.length} needing attention',
                    key: const Key('parent-access-summary'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (_comparison case final c?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        c.missing.isEmpty && c.outdated.isEmpty
                            ? 'Every linked parent has a current access record (${c.current}).'
                            : '${c.missing.length} linked parent${c.missing.length == 1 ? ' has' : 's have'} no access record'
                                '${c.missing.isEmpty ? '' : ' (${c.missing.join(', ')})'}; ${c.outdated.length} out of date'
                                '${c.outdated.isEmpty ? '' : ' (${c.outdated.join(', ')})'}. '
                                'Until Apply writes them, those parents can see fees but not issued bills.',
                        key: const Key('parent-access-records'),
                        style: TextStyle(color: c.missing.isEmpty && c.outdated.isEmpty ? Colors.green.shade800 : Colors.orange.shade900),
                      ),
                    ),
                  if (_result case final r?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Applied: ${r.written} written, ${r.unchanged} already correct, ${r.cleared} emptied (no remaining links).',
                        key: const Key('parent-access-result'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Column(
                    key: const Key('parent-access-issues'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (plan.issues.isEmpty) const Text('No problems found.'),
                      for (final issue in plan.issues)
                        ListTile(
                          dense: true,
                          leading: Icon(issue.kind.unresolved ? Icons.error_outline : Icons.info_outline,
                              color: issue.kind.unresolved ? Colors.orange.shade800 : Colors.blueGrey),
                          title: Text(issue.kind.label),
                          subtitle: Text([
                            if (issue.userId.isNotEmpty) 'Parent ${issue.userId}',
                            if (issue.studentId.isNotEmpty) 'Student ${issue.studentId}',
                            if (issue.detail.isNotEmpty) issue.detail,
                          ].join(' • ')),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _DiagnosisView extends StatelessWidget {
  const _DiagnosisView({required this.diagnosis});
  final ParentAccountDiagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final d = diagnosis;
    String yes(bool v) => v ? 'yes' : 'NO';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        key: const Key('parent-access-diagnosis'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Account ${d.userId}: user record ${yes(d.userRecord)} · access record ${yes(d.accessRecord)} · ${d.links} link record${d.links == 1 ? '' : 's'}'),
          if (!d.accessRecord && d.links > 0)
            Text(
              'This parent has no access record, so their dashboard can\'t read issued bills. Run Check, then Apply.',
              key: const Key('parent-access-diagnosis-no-record'),
              style: TextStyle(color: Colors.orange.shade900),
            ),
          for (final c in d.children)
            Text(
              'Student ${c.studentId}: ${c.relation.isEmpty ? 'relationship not set' : c.relation} · in access record ${yes(c.inAccessRecord)} · '
              'fee access ${yes(c.financeAccess)} · profile copy ${yes(c.profileCopy)} · '
              'active bills ${c.billOriginals ?? '?'} · parent bill copies ${c.billCopies ?? '?'}'
              '${c.errors.isEmpty ? '' : ' · errors: ${c.errors.join('; ')}'}',
              style: const TextStyle(fontSize: 13),
            ),
          for (final e in d.errors) Text('Could not read $e', style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
        ],
      ),
    );
  }
}
