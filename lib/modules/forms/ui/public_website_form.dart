import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../public_website/content/website_content_models.dart';
import '../../public_website/content/website_content_repository.dart';
import '../../public_website/public_strings.dart';
import '../../public_website/public_website_theme.dart';
import '../../public_website/widgets/public_website_image.dart';
import '../data/form_submission_service.dart';
import '../models/public_submission_settings.dart';
import '../models/website_form.dart';
import '../public/public_forms_repository.dart';

/// A form's visitor-facing wording, in English and Tamil (other languages
/// fall back to English).
class FormStrings {
  const FormStrings._(this._ta);

  factory FormStrings.of(PublicLanguage language) => FormStrings._(language.code == 'ta' || language.fallbackCode == 'ta');

  final bool _ta;

  String _t(String en, String ta) => _ta ? ta : en;

  String get send => _t('Send', 'அனுப்பு');
  String get sending => _t('Sending…', 'அனுப்பப்படுகிறது…');
  String get choose => _t('Choose…', 'தேர்ந்தெடுக்கவும்…');
  String get optional => _t('optional', 'விருப்பத்தேர்வு');
  String get pickDate => _t('Choose a date', 'தேதியைத் தேர்ந்தெடுக்கவும்');
  String get dateHint => _t('YYYY-MM-DD', 'YYYY-MM-DD');
  String get fixErrors => _t('Please check the highlighted answers.', 'குறிக்கப்பட்ட பதில்களைச் சரிபார்க்கவும்.');
  String get preview => _t('Preview: responses aren’t sent from here.', 'முன்னோட்டம்: இங்கிருந்து பதில்கள் அனுப்பப்படாது.');
  String get loading => _t('Loading the form…', 'படிவம் ஏற்றப்படுகிறது…');
  String get loadFailed => _t('The form couldn’t be loaded.', 'படிவத்தை ஏற்ற முடியவில்லை.');
  String get retry => _t('Try again', 'மீண்டும் முயற்சிக்கவும்');
  String get upload => _t('Upload', 'பதிவேற்று');
  String get uploadsUnavailable => _t(
        'Document uploads aren’t available yet. Please send documents to the school directly.',
        'ஆவணப் பதிவேற்றம் இன்னும் கிடைக்கவில்லை. ஆவணங்களைப் பள்ளிக்கு நேரடியாக அனுப்பவும்.',
      );
  String uploadLimits(String types, int mb, int files) => _t(
        '$types · up to $mb MB${files > 1 ? ' · up to $files files' : ''}',
        '$types · அதிகபட்சம் $mb MB${files > 1 ? ' · அதிகபட்சம் $files கோப்புகள்' : ''}',
      );
  String reference(String ref) => _t('Your reference: $ref', 'உங்கள் குறிப்பு எண்: $ref');
  String get next => _t('Next', 'அடுத்து');
  String get previous => _t('Previous', 'முந்தையது');
  String get review => _t('Review your answers', 'உங்கள் பதில்களைச் சரிபார்க்கவும்');
  String get edit => _t('Change', 'மாற்று');
  String get notAnswered => _t('Not answered', 'பதில் இல்லை');
  String get yes => _t('Yes', 'ஆம்');
  String get no => _t('No', 'இல்லை');
  String get requiredNote => _t('Fields marked * are required.', '* குறியிட்ட புலங்கள் அவசியம்.');
  String step(int n, int total) => _t('Step $n of $total', 'படி $n / $total');
  String errorCount(int n) => _t(n == 1 ? 'There is 1 answer to check:' : 'There are $n answers to check:', 'சரிபார்க்க வேண்டிய பதில்கள்: $n');
  String characters(int n, int max) => _t('$n of $max characters', '$max இல் $n எழுத்துகள்');

  String error(FormAnswerError e) => switch (e) {
        FormAnswerError.required => _t('This is required.', 'இது அவசியம்.'),
        FormAnswerError.tooLong => _t('This answer is too long.', 'இந்தப் பதில் மிக நீளமாக உள்ளது.'),
        FormAnswerError.tooShort => _t('This answer is too short.', 'இந்தப் பதில் மிகச் சிறியதாக உள்ளது.'),
        FormAnswerError.number => _t('Enter a number.', 'ஒரு எண்ணை உள்ளிடவும்.'),
        FormAnswerError.outOfRange => _t('This is outside the accepted range.', 'இது ஏற்கப்படும் வரம்பிற்கு வெளியே உள்ளது.'),
        FormAnswerError.email => _t('Enter a valid email address.', 'சரியான மின்னஞ்சல் முகவரியை உள்ளிடவும்.'),
        FormAnswerError.phone => _t('Enter a valid phone number.', 'சரியான தொலைபேசி எண்ணை உள்ளிடவும்.'),
        FormAnswerError.date => _t('Enter a date as YYYY-MM-DD.', 'தேதியை YYYY-MM-DD என உள்ளிடவும்.'),
        FormAnswerError.option => _t('Choose one of the options.', 'விருப்பங்களில் ஒன்றைத் தேர்ந்தெடுக்கவும்.'),
        FormAnswerError.invalid => _t('This answer can’t be accepted.', 'இந்தப் பதிலை ஏற்க முடியாது.'),
      };

  String failure(FormSubmissionErrorCode code) => switch (code) {
        FormSubmissionErrorCode.unavailable =>
          _t('Online submissions aren’t open yet. Please contact the school directly.', 'இணைய வழிச் சமர்ப்பிப்புகள் இன்னும் தொடங்கவில்லை. பள்ளியை நேரடியாகத் தொடர்பு கொள்ளவும்.'),
        FormSubmissionErrorCode.notAvailable => _t('This form is no longer accepting responses.', 'இந்தப் படிவம் இப்போது பதில்களை ஏற்கவில்லை.'),
        FormSubmissionErrorCode.formChanged => _t('This form has been updated. Reload the page and try again.', 'இந்தப் படிவம் புதுப்பிக்கப்பட்டுள்ளது. பக்கத்தை மீண்டும் ஏற்றி முயற்சிக்கவும்.'),
        FormSubmissionErrorCode.invalid => fixErrors,
        FormSubmissionErrorCode.permissionDenied => _t(
            'The website couldn’t save your response. Please contact the school directly.',
            'இணையதளத்தால் உங்கள் பதிலைச் சேமிக்க முடியவில்லை. பள்ளியை நேரடியாகத் தொடர்பு கொள்ளவும்.'),
        FormSubmissionErrorCode.badRequest ||
        FormSubmissionErrorCode.failed =>
          _t('Your response couldn’t be sent. Check your connection and try again.', 'உங்கள் பதிலை அனுப்ப முடியவில்லை. இணைப்பைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.'),
      };
}

/// The Form block's content on a page: form [formId]'s active version
/// ([publicWebsiteFormProvider], which reads only the visitor copy), under
/// [heading] and [intro]. A form that isn't active (or was deleted) shows
/// nothing to visitors; in the editor ([interactive] false) it says so.
class WebsiteFormBlockView extends ConsumerWidget {
  const WebsiteFormBlockView({
    super.key,
    required this.formId,
    required this.language,
    required this.heading,
    required this.intro,
    required this.headingStyle,
    required this.bodyStyle,
    required this.accent,
    this.interactive = true,
  });

  final String formId;
  final PublicLanguage language;
  final String heading;
  final String intro;
  final TextStyle headingStyle;
  final TextStyle bodyStyle;
  final Color accent;
  final bool interactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = FormStrings.of(language);
    final form = ref.watch(publicWebsiteFormProvider(formId));
    final body = form.when(
      skipLoadingOnRefresh: false,
      loading: () => Semantics(
        key: const Key('website-form-loading'),
        label: strings.loading,
        child: const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5))),
      ),
      error: (_, _) => Column(
        key: const Key('website-form-load-error'),
        children: [
          Text(strings.loadFailed, style: bodyStyle),
          TextButton(key: const Key('website-form-retry'), onPressed: () => ref.invalidate(publicWebsiteFormProvider(formId)), child: Text(strings.retry)),
        ],
      ),
      data: (form) => form == null
          ? (interactive
              ? const SizedBox.shrink(key: Key('website-form-unavailable'))
              : Container(
                  key: const Key('website-form-inactive-note'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(12)),
                  child: const Text('This form isn’t active (or was deleted), so visitors don’t see this block. Activate it in Settings → Website forms, or choose another.'),
                ))
          : PublicWebsiteFormView(form: form, language: language, interactive: interactive, accent: accent, bodyStyle: bodyStyle),
    );
    final hidden = interactive && form.valueOrNull == null && !form.isLoading && !form.hasError;
    return Column(
      key: Key('website-form-block-$formId'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hidden && heading.isNotEmpty) ...[Text(heading, style: headingStyle), const SizedBox(height: 12)],
        if (!hidden && intro.isNotEmpty) ...[Text(intro, style: bodyStyle), const SizedBox(height: 20)],
        body,
      ],
    );
  }
}

/// A form for visitors (or, with [interactive] false, a preview that sends
/// nothing): its cover image, title and description, then each question
/// and content block in order (section headings, text, images, dividers),
/// Send, then the success message and reference. Answers are checked here
/// for messages only; the submission service checks them again against
/// the stored form.
///
/// Images come from [media] (by id), or — when null — from the published
/// website images ([publishedWebsiteMediaProvider]); an image that isn't
/// there (hidden, consent withdrawn, deleted) is left out, and the form
/// still works.
///
/// The form builder's canvas uses it too: with [onSelect], each item (and
/// the header, as null) is selectable, [selectedId] is outlined, and
/// nothing can be typed in.
///
/// One submission key per filled-in form: a double click, or Send again
/// after a lost connection, can't store two submissions. Sending is
/// through [formSubmissionGatewayProvider].
///
/// Send is offered only while the school accepts submissions
/// ([publicSubmissionStatusProvider], live: switched off while the form is
/// open, it closes). Until the setting has loaded, Send is disabled; if it
/// can't be loaded, the form is closed. The submission service checks the
/// setting again right before writing; if Firestore refuses the write, the
/// visitor is told it couldn't be saved (not that submissions are closed).
class PublicWebsiteFormView extends ConsumerStatefulWidget {
  const PublicWebsiteFormView({
    super.key,
    required this.form,
    required this.language,
    this.interactive = true,
    this.accent = PublicColors.forest,
    this.bodyStyle = PublicText.body,
    this.media,
    this.showHeader = true,
    this.selectedId,
    this.onSelect,
  });

  final PublicWebsiteForm form;
  final PublicLanguage language;
  final bool interactive;
  final Color accent;
  final TextStyle bodyStyle;
  final Map<String, WebsiteMedia>? media;

  /// The cover image, title and description above the questions.
  final bool showHeader;
  final String? selectedId;
  final ValueChanged<String?>? onSelect;

  @override
  ConsumerState<PublicWebsiteFormView> createState() => _PublicWebsiteFormViewState();
}

class _PublicWebsiteFormViewState extends ConsumerState<PublicWebsiteFormView> {
  final Map<String, Object?> _answers = {};
  final Map<String, TextEditingController> _dates = {};
  final Map<String, FocusNode> _focus = {};
  Map<String, FormAnswerError> _errors = {};

  /// A multi-step form's current step (an index into [_steps], or
  /// [_steps].length for the review).
  int _step = 0;

  /// The error summary is shown (after Send or Next found problems).
  bool _summary = false;
  String _key = FormIds.submissionKey();
  bool _sending = false;
  String? _message;
  FormSubmissionReceipt? _receipt;

  /// The service refused a submission as closed before the setting's
  /// change reached this page.
  bool _refusedClosed = false;

  FormStrings get _strings => FormStrings.of(widget.language);

  /// A form visitors could send (not the editor's preview or canvas).
  bool get _live => widget.interactive && !_selecting;
  bool get _selecting => widget.onSelect != null;

  AsyncValue<PublicSubmissionStatus> get _status => ref.watch(publicSubmissionStatusProvider);

  /// A live form that can't be sent: the school's submissions are off, not
  /// loaded yet or unreadable.
  bool get _closed => _live && (_refusedClosed || !(_status.valueOrNull?.open ?? false));

  /// What a closed form tells visitors: the school's own message when it
  /// has written one, otherwise the website's wording. Nothing while the
  /// setting is still loading.
  String? get _closedNotice {
    if (!_closed) return null;
    final status = _status;
    if (status.isLoading && !status.hasValue && !_refusedClosed) return null;
    final custom = status.valueOrNull?.closedMessage ?? '';
    return custom.isNotEmpty ? custom : _strings.failure(FormSubmissionErrorCode.unavailable);
  }

  static const _compact = {FormFieldType.shortText, FormFieldType.email, FormFieldType.phone, FormFieldType.date, FormFieldType.number};

  @override
  void initState() {
    super.initState();
    // Default answers, filled in as if typed (and sent unless changed).
    for (final f in widget.form.fields) {
      final value = f.defaultValue;
      if (value == null || value.trim().isEmpty || !f.takesDefault) continue;
      _answers[f.id] = value;
      if (f.type == FormFieldType.date) _dates[f.id] = TextEditingController(text: value);
    }
  }

  @override
  void dispose() {
    for (final c in _dates.values) {
      c.dispose();
    }
    for (final n in _focus.values) {
      n.dispose();
    }
    super.dispose();
  }

  FocusNode _focusOf(String id) => _focus.putIfAbsent(id, () => FocusNode(debugLabel: 'form-$id'));

  /// The form's steps: one, unless it is a multi-step form, then split at
  /// its page breaks (steps with nothing in them are skipped). Each with
  /// its title (a page break's) and items.
  List<({String title, List<FormItem> items})> get _steps {
    final form = widget.form;
    if (!form.multiStep || _selecting) return [(title: '', items: [for (final i in form.items) if (!_isBreak(i)) i])];
    final steps = <({String title, List<FormItem> items})>[(title: '', items: <FormItem>[])];
    for (final item in form.items) {
      if (_isBreak(item)) {
        steps.add((title: (item as FormContentBlock).title.resolve(widget.language).trim(), items: <FormItem>[]));
      } else {
        steps.last.items.add(item);
      }
    }
    return [for (final s in steps) if (s.items.isNotEmpty) s];
  }

  static bool _isBreak(FormItem item) => item is FormContentBlock && item.type == FormBlockType.pageBreak;

  bool get _reviewing => widget.form.multiStep && widget.form.reviewStep && !_selecting && _step >= _steps.length;

  /// [fields]' answers checked (only theirs, so a step is checked alone).
  ({Map<String, Object> values, Map<String, FormAnswerError> errors}) _check(List<WebsiteFormField> fields) =>
      validateFormAnswers(fields, {for (final f in fields) if (_answers.containsKey(f.id)) f.id: _answers[f.id]});

  /// Shows [errors] and moves to the first: its step, then its question.
  void _showErrors(Map<String, FormAnswerError> errors) {
    final steps = _steps;
    final first = widget.form.fields.where((f) => errors.containsKey(f.id)).firstOrNull;
    setState(() {
      _errors = errors;
      _summary = true;
      _message = _strings.fixErrors;
      if (first != null) {
        final at = steps.indexWhere((s) => s.items.any((i) => i.id == first.id));
        if (at >= 0) _step = at;
      }
    });
    if (first != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final node = _focus[first.id];
        node?.requestFocus();
        final ctx = node?.context;
        if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, alignment: 0.2, duration: const Duration(milliseconds: 200));
      });
    }
  }

  void _next() {
    final steps = _steps;
    final fields = steps[_step].items.whereType<WebsiteFormField>().toList();
    final checked = _check(fields);
    if (checked.errors.isNotEmpty) return _showErrors(checked.errors);
    setState(() {
      _step++;
      _summary = false;
      _message = null;
    });
  }

  void _previous() => setState(() {
        _step = math.max(0, _step - 1);
        _summary = false;
      });

  Future<void> _send() async {
    if (_sending || _receipt != null) return;
    final checked = validateFormAnswers(widget.form.fields, _answers);
    if (checked.errors.isNotEmpty) return _showErrors(checked.errors);
    setState(() {
      _errors = const {};
      _summary = false;
      _message = null;
    });
    if (!widget.interactive) {
      setState(() => _message = _strings.preview);
      return;
    }
    setState(() => _sending = true);
    try {
      final receipt = await ref.read(formSubmissionGatewayProvider).submit(
            FormSubmissionRequest(formId: widget.form.id, answers: checked.values, submissionKey: _key, formVersion: widget.form.version),
          );
      if (mounted) setState(() => _receipt = receipt);
    } on FormSubmissionException catch (e) {
      if (mounted) {
        if (e.fieldErrors.isNotEmpty) _showErrors(e.fieldErrors);
        setState(() {
          _errors = e.fieldErrors;
          // Closed meanwhile: said by the closed notice, not twice.
          _refusedClosed = e.code == FormSubmissionErrorCode.unavailable;
          _message = _refusedClosed ? null : _strings.failure(e.code);
          // Refused as it is: a corrected form is a new submission.
          if (e.code == FormSubmissionErrorCode.invalid) _key = FormIds.submissionKey();
        });
      }
    } catch (_) {
      // The same key, so sending again can't store it twice.
      if (mounted) setState(() => _message = _strings.failure(FormSubmissionErrorCode.failed));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _set(String id, Object? value) => setState(() {
        _answers[id] = value;
        if (_errors.remove(id) != null && _errors.isEmpty) {
          _message = null;
          _summary = false;
        }
      });

  Map<String, WebsiteMedia> get _media =>
      widget.media ?? {for (final m in ref.watch(publishedWebsiteMediaProvider).valueOrNull ?? const <WebsiteMedia>[]) m.id: m};

  @override
  Widget build(BuildContext context) {
    // A newer setting replaces what a refused submission said.
    if (_live) {
      ref.listen(publicSubmissionStatusProvider, (previous, next) {
        if (_refusedClosed && next.valueOrNull?.revision != previous?.valueOrNull?.revision) setState(() => _refusedClosed = false);
      });
    }
    final form = widget.form;
    final strings = _strings;
    final media = _media;
    if (_receipt case final receipt?) {
      return Container(
        key: const Key('website-form-success'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: widget.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline, color: widget.accent),
              const SizedBox(height: 8),
              if (form.completionTitle.resolve(widget.language).trim() case final title when title.isNotEmpty) ...[
                Semantics(header: true, child: Text(title, key: const Key('website-form-completion-title'), style: PublicText.title)),
                const SizedBox(height: 6),
              ],
              Text(form.successMessage.resolve(widget.language), style: widget.bodyStyle),
              const SizedBox(height: 8),
              SelectableText(strings.reference(receipt.reference), key: const Key('website-form-reference'), style: widget.bodyStyle.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }
    final steps = _steps;
    final multi = form.multiStep && !_selecting && (steps.length > 1 || form.reviewStep);
    final step = _step.clamp(0, steps.length);
    final last = step >= steps.length - 1;
    final review = _reviewing;
    final items = _selecting ? form.items : (review ? const <FormItem>[] : steps[math.min(step, steps.length - 1)].items);
    final total = steps.length + (form.reviewStep ? 1 : 0);
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 640;
      final rows = _rows(items, wide: wide);
      Widget cell(FormItem item) => _selectable(item.id, item is WebsiteFormField ? _field(context, item) : _content(item as FormContentBlock, media));
      final invalid = [for (final f in form.fields) if (_errors.containsKey(f.id) && items.any((i) => i.id == f.id)) f];
      return FocusTraversalGroup(
        child: Column(
          key: Key('website-form-${form.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showHeader && (step == 0 || _selecting)) _selectable(null, _header(form, media)),
            if (multi) _progress(steps, step, total, review),
            if (form.fields.any((f) => f.required) && !review)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_strings.requiredNote, key: const Key('website-form-required-note'), style: widget.bodyStyle.copyWith(fontSize: 13)),
              ),
            if (_summary && invalid.isNotEmpty) _errorSummary(invalid),
            if (review) _review(steps),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: row.length == 1 && row.single.$2 >= 1
                    ? cell(row.single.$1)
                    : Row(
                        key: Key('website-form-row-${row.first.$1.id}'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (j, (item, share)) in row.indexed) ...[
                            if (j > 0) const SizedBox(width: 16),
                            Expanded(flex: (share * 600).round(), child: cell(item)),
                          ],
                          if (row.fold<double>(0, (sum, c) => sum + c.$2) case final used when used < 0.999) ...[
                            const SizedBox(width: 16),
                            Spacer(flex: ((1 - used) * 600).round()),
                          ],
                        ],
                      ),
              ),
            // Closed (switched off): said up front, and Send is disabled,
            // instead of failing when pressed. The editor preview never
            // sends, so it isn't "closed".
            if (_closedNotice case final notice?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  key: const Key('website-form-closed'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 20, color: Color(0xFF8A6A33)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(notice, style: widget.bodyStyle.copyWith(color: const Color(0xFF6B4F1D)))),
                    ],
                  ),
                ),
              ),
            if (_message case final m?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(m, key: const Key('website-form-message'), style: widget.bodyStyle.copyWith(color: m == strings.preview ? null : const Color(0xFFB3261E))),
                ),
              ),
            IgnorePointer(
              ignoring: _selecting,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (multi && step > 0)
                    OutlinedButton.icon(
                      key: const Key('website-form-previous'),
                      onPressed: _sending ? null : _previous,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(strings.previous),
                      style: OutlinedButton.styleFrom(foregroundColor: widget.accent, minimumSize: const Size(120, 48)),
                    ),
                  if (multi && !review && !(last && !form.reviewStep))
                    FilledButton(
                      key: const Key('website-form-next'),
                      onPressed: _next,
                      style: FilledButton.styleFrom(backgroundColor: widget.accent, minimumSize: const Size(140, 48)),
                      child: Text(last ? strings.review : strings.next),
                    )
                  else
                    FilledButton(
                      key: const Key('website-form-submit'),
                      onPressed: _sending || _closed ? null : _send,
                      style: FilledButton.styleFrom(backgroundColor: widget.accent, minimumSize: const Size(140, 48)),
                      child: Text(_sending ? strings.sending : strings.send),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  /// [items] in rows, each with its share of the row: content and
  /// full-width questions alone; questions with a width share a row while
  /// they fit; others (automatic) as before: short questions two to a row.
  /// On narrower screens, one per row.
  List<List<(FormItem, double)>> _rows(List<FormItem> items, {required bool wide}) {
    final rows = <List<(FormItem, double)>>[];
    var explicit = false;
    for (final item in items) {
      final field = item is WebsiteFormField ? item : null;
      final share = field?.widthFraction;
      final last = rows.isEmpty ? null : rows.last;
      final used = last?.fold<double>(0, (sum, c) => sum + c.$2) ?? 1;
      if (!wide || field == null) {
        rows.add([(item, 1)]);
        explicit = false;
      } else if (share != null) {
        if (explicit && last != null && used + share <= 1.001) {
          last.add((item, share));
        } else {
          rows.add([(item, share)]);
        }
        explicit = share < 1;
      } else if (_compact.contains(field.type) &&
          !explicit &&
          last != null &&
          last.length == 1 &&
          last.single.$1 is WebsiteFormField &&
          (last.single.$1 as WebsiteFormField).widthFraction == null &&
          _compact.contains((last.single.$1 as WebsiteFormField).type) &&
          last.single.$2 == 1) {
        rows[rows.length - 1] = [(last.single.$1, 0.5), (item, 0.5)];
      } else {
        rows.add([(item, 1)]);
        explicit = false;
      }
    }
    // An automatic short question alone keeps the whole row, as before.
    return rows;
  }

  Widget _progress(List<({String title, List<FormItem> items})> steps, int step, int total, bool review) {
    final n = math.min(step + 1, total);
    final title = review ? _strings.review : steps[step].title;
    return Padding(
      key: const Key('website-form-progress'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: '${_strings.step(n, total)}${title.isEmpty ? '' : ': $title'}',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${_strings.step(n, total)}${title.isEmpty ? '' : ' · $title'}', key: const Key('website-form-step'), style: widget.bodyStyle.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: n / total, minHeight: 6, color: widget.accent, backgroundColor: widget.accent.withValues(alpha: 0.15)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What to fix, each a link to its question.
  Widget _errorSummary(List<WebsiteFormField> invalid) {
    const red = Color(0xFFB3261E);
    return Container(
      key: const Key('website-form-error-summary'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(10), border: Border.all(color: red.withValues(alpha: 0.4))),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_strings.errorCount(invalid.length), style: widget.bodyStyle.copyWith(fontWeight: FontWeight.w600, color: red)),
            for (final f in invalid)
              TextButton(
                key: Key('website-form-error-link-${f.id}'),
                style: TextButton.styleFrom(foregroundColor: red, padding: const EdgeInsets.symmetric(vertical: 4), alignment: Alignment.centerLeft),
                onPressed: () {
                  final node = _focus[f.id];
                  node?.requestFocus();
                  if (node?.context case final ctx? when ctx.mounted) Scrollable.ensureVisible(ctx, alignment: 0.2);
                },
                child: Text('${f.label.resolve(widget.language)}: ${_errorText(f)}', textAlign: TextAlign.start),
              ),
          ],
        ),
      ),
    );
  }

  String _errorText(WebsiteFormField f) {
    final custom = f.errorMessage.resolve(widget.language);
    final e = _errors[f.id];
    return e == null ? '' : (custom.isNotEmpty ? custom : _strings.error(e));
  }

  /// A multi-step form's last step: every answer, by step, to change.
  Widget _review(List<({String title, List<FormItem> items})> steps) {
    String shown(WebsiteFormField f) {
      final v = _answers[f.id];
      if (v == null || (v is String && v.trim().isEmpty)) return _strings.notAnswered;
      if (f.type == FormFieldType.checkbox) return v == true ? _strings.yes : _strings.no;
      if (f.type?.hasOptions ?? false) {
        final option = f.options.where((o) => o.id == v).firstOrNull;
        return option?.label.resolve(widget.language) ?? _strings.notAnswered;
      }
      return v.toString().trim();
    }

    return Column(
      key: const Key('website-form-review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(_strings.review, style: PublicText.title)),
        const SizedBox(height: 12),
        for (final (i, s) in steps.indexed)
          for (final f in s.items.whereType<WebsiteFormField>())
            if (f.type != FormFieldType.attachment)
              Padding(
                key: Key('website-form-review-${f.id}'),
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.label.resolve(widget.language), style: widget.bodyStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                          Text(shown(f), style: widget.bodyStyle),
                        ],
                      ),
                    ),
                    TextButton(
                      key: Key('website-form-review-edit-${f.id}'),
                      onPressed: () => setState(() => _step = i),
                      child: Text(_strings.edit, semanticsLabel: '${_strings.edit}: ${f.label.resolve(widget.language)}'),
                    ),
                  ],
                ),
              ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// On the builder's canvas: selectable and outlined; elsewhere as is.
  Widget _selectable(String? id, Widget child) {
    if (!_selecting) return child;
    final selected = widget.selectedId == id;
    final item = id == null ? null : widget.form.items.where((i) => i.id == id).firstOrNull;
    final hidden = item is WebsiteFormField ? item.hidden : (item is FormContentBlock && item.hidden);
    return GestureDetector(
      key: Key(id == null ? 'form-canvas-header' : 'form-canvas-item-$id'),
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelect!(id),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? widget.accent : Colors.transparent, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: !hidden
            ? AbsorbPointer(child: child)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(key: Key('form-canvas-hidden-$id'), children: const [
                    Icon(Icons.visibility_off_outlined, size: 16, color: Color(0xFF6E6E73)),
                    SizedBox(width: 4),
                    Text('Hidden from visitors', style: TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
                  ]),
                  Opacity(opacity: 0.45, child: AbsorbPointer(child: child)),
                ],
              ),
      ),
    );
  }

  Widget _missingImage(String what) => Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(12)),
        child: Text('$what isn’t available to visitors', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8A6A33))),
      );

  Widget _header(PublicWebsiteForm form, Map<String, WebsiteMedia> media) {
    final cover = form.coverMediaId == null ? null : media[form.coverMediaId];
    final title = form.title.resolve(widget.language);
    final description = form.description.resolve(widget.language);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cover != null) ...[
            PublicWebsiteImage(
              key: const Key('website-form-cover'),
              media: cover,
              aspectRatio: 16 / 7,
              borderRadius: 16,
              semanticLabel: cover.alt.resolve(widget.language),
            ),
            const SizedBox(height: 16),
          ] else if (_selecting && form.coverMediaId != null) ...[
            KeyedSubtree(key: const Key('website-form-cover-missing'), child: _missingImage('The cover image')),
            const SizedBox(height: 16),
          ],
          if (title.isNotEmpty) Semantics(header: true, child: Text(title, key: const Key('website-form-title'), style: PublicText.heading)),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(description, key: const Key('website-form-description'), style: widget.bodyStyle),
          ],
        ],
      ),
    );
  }

  Widget _content(FormContentBlock block, Map<String, WebsiteMedia> media) {
    final title = block.title.resolve(widget.language);
    final body = block.body.resolve(widget.language);
    final key = Key('website-form-content-${block.id}');
    switch (block.type) {
      case FormBlockType.heading:
        return Padding(
          key: key,
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(title, style: PublicText.title)),
              if (body.isNotEmpty) ...[const SizedBox(height: 4), Text(body, style: widget.bodyStyle)],
            ],
          ),
        );
      case FormBlockType.text:
        return Text(body, key: key, style: widget.bodyStyle);
      case FormBlockType.image:
        final image = media[block.mediaId];
        if (image == null) return _selecting ? KeyedSubtree(key: key, child: _missingImage('This image')) : SizedBox.shrink(key: key);
        return Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PublicWebsiteImage(media: image, aspectRatio: 16 / 9, borderRadius: 12, semanticLabel: image.alt.resolve(widget.language)),
            if (body.isNotEmpty) ...[const SizedBox(height: 6), Text(body, style: widget.bodyStyle.copyWith(fontSize: 14))],
          ],
        );
      case FormBlockType.divider:
        return Divider(key: key, height: 16, color: PublicColors.line);
      case FormBlockType.pageBreak:
        // Steps are made from page breaks; only the builder's canvas shows
        // where they are.
        if (!_selecting) return SizedBox.shrink(key: key);
        final step = 1 + widget.form.items.takeWhile((i) => i.id != block.id).where(_isBreak).length + 1;
        return Row(
          key: key,
          children: [
            const Expanded(child: Divider(color: Color(0xFF8A6A33))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                widget.form.multiStep ? 'Page break · step $step${title.isEmpty ? '' : ': $title'}' : 'Page break (no effect: the form is on one page)',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A6A33), fontWeight: FontWeight.w600),
              ),
            ),
            const Expanded(child: Divider(color: Color(0xFF8A6A33))),
          ],
        );
      case null:
        return SizedBox.shrink(key: key);
    }
  }

  Widget _field(BuildContext context, WebsiteFormField f) {
    final strings = _strings;
    final optional = !f.required && f.type != FormFieldType.checkbox && f.type != FormFieldType.attachment;
    final label = '${f.label.resolve(widget.language)}${optional ? ' (${strings.optional})' : ''}';
    final custom = f.errorMessage.resolve(widget.language);
    final error = _errors[f.id] == null ? null : (custom.isNotEmpty ? custom : strings.error(_errors[f.id]!));
    final hint = f.placeholder.resolve(widget.language);
    final help = f.helpText.resolve(widget.language);
    final locked = _sending || _selecting;
    InputDecoration deco({String? hintText, Widget? suffix}) => InputDecoration(
          labelText: '$label${f.required ? ' *' : ''}',
          hintText: hintText ?? (hint.isEmpty ? null : hint),
          helperText: help.isEmpty ? null : help,
          helperMaxLines: 4,
          errorText: error,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
          suffixIcon: suffix,
        );
    final key = Key('website-form-field-${f.id}');
    switch (f.type!) {
      case FormFieldType.shortText:
      case FormFieldType.email:
      case FormFieldType.phone:
      case FormFieldType.longText:
      case FormFieldType.number:
        final long = f.type == FormFieldType.longText;
        final rows = f.visibleRows;
        final textual = long || f.type == FormFieldType.shortText;
        return TextFormField(
          key: key,
          focusNode: _focusOf(f.id),
          // Kept when a step is left and come back to, or an answer is
          // refused.
          initialValue: _answers[f.id] as String?,
          enabled: !_sending,
          readOnly: _selecting,
          decoration: deco(),
          minLines: long ? rows : 1,
          maxLines: long ? (f.resize == 'fixed' ? rows : math.max(rows, FormFieldLimits.growTo)) : 1,
          maxLength: long || f.maxLength != null || (textual && f.showsCounter) ? f.maxAnswerLength : null,
          // The counter stays beside an error message; read as a sentence.
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => !f.showsCounter || maxLength == null
              ? null
              : Text('$currentLength / $maxLength', key: Key('website-form-counter-${f.id}'), semanticsLabel: _strings.characters(currentLength, maxLength), style: const TextStyle(fontSize: 12)),
          keyboardType: switch (f.type) {
            FormFieldType.email => TextInputType.emailAddress,
            FormFieldType.phone => TextInputType.phone,
            FormFieldType.longText => TextInputType.multiline,
            FormFieldType.number => const TextInputType.numberWithOptions(decimal: true, signed: true),
            _ => TextInputType.text,
          },
          autofillHints: switch (f.type) {
            FormFieldType.email => const [AutofillHints.email],
            FormFieldType.phone => const [AutofillHints.telephoneNumber],
            _ => null,
          },
          onChanged: (v) => _set(f.id, v),
        );
      case FormFieldType.date:
        final controller = _dates.putIfAbsent(f.id, TextEditingController.new);
        return TextFormField(
          key: key,
          controller: controller,
          enabled: !_sending,
          readOnly: _selecting,
          keyboardType: TextInputType.datetime,
          focusNode: _focusOf(f.id),
          decoration: deco(
            hintText: strings.dateHint,
            suffix: IconButton(
              key: Key('website-form-date-pick-${f.id}'),
              tooltip: strings.pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              onPressed: locked
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final first = (f.minDate == null ? null : parseFormDate(f.minDate!)) ?? DateTime(1900);
                      final last = (f.maxDate == null ? null : parseFormDate(f.maxDate!)) ?? DateTime(now.year + 10);
                      final initial = parseFormDate(controller.text) ?? (now.isBefore(first) ? first : (now.isAfter(last) ? last : now));
                      final picked = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);
                      if (picked == null) return;
                      final text = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                      controller.text = text;
                      _set(f.id, text);
                    },
            ),
          ),
          onChanged: (v) => _set(f.id, v),
        );
      case FormFieldType.dropdown:
        return DropdownButtonFormField<String>(
          key: key,
          focusNode: _focusOf(f.id),
          isExpanded: true,
          initialValue: _answers[f.id] as String?,
          decoration: deco(hintText: strings.choose),
          items: [for (final o in f.options) DropdownMenuItem(value: o.id, child: Text(o.label.resolve(widget.language), overflow: TextOverflow.ellipsis))],
          onChanged: locked ? null : (v) => _set(f.id, v),
        );
      case FormFieldType.radio:
        return InputDecorator(
          key: key,
          decoration: deco().copyWith(hintText: null, border: InputBorder.none, contentPadding: EdgeInsets.zero),
          child: RadioGroup<String>(
            groupValue: _answers[f.id] as String?,
            onChanged: (v) => locked ? null : _set(f.id, v),
            child: Column(
              children: [
                for (final (j, o) in f.options.indexed)
                  RadioListTile<String>(
                    key: Key('website-form-option-${f.id}-${o.id}'),
                    focusNode: j == 0 ? _focusOf(f.id) : null,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: o.id,
                    title: Text(o.label.resolve(widget.language)),
                  ),
              ],
            ),
          ),
        );
      case FormFieldType.checkbox:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              key: key,
              focusNode: _focusOf(f.id),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _answers[f.id] == true,
              title: Text('$label${f.required ? ' *' : ''}', style: widget.bodyStyle),
              subtitle: help.isEmpty ? null : Text(help, style: widget.bodyStyle.copyWith(fontSize: 13)),
              onChanged: locked ? null : (v) => _set(f.id, v ?? false),
            ),
            if (error != null) Text(error, key: Key('website-form-error-${f.id}'), style: const TextStyle(color: Color(0xFFB3261E), fontSize: 12)),
          ],
        );
      case FormFieldType.attachment:
        // Disabled until a secure upload path exists: nothing is uploaded,
        // and the field is never required meanwhile.
        final types = f.allowedFileTypes.map((t) => t.toUpperCase()).join(', ');
        return InputDecorator(
          key: Key('website-form-attachment-${f.id}'),
          decoration: InputDecoration(labelText: f.label.resolve(widget.language), helperText: help.isEmpty ? null : help, helperMaxLines: 4, border: const OutlineInputBorder(), enabled: false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.upload_file_outlined), label: Text(strings.upload)),
              const SizedBox(height: 6),
              Text(strings.uploadLimits(types, f.maxFileSizeMb, f.maxFiles), style: widget.bodyStyle.copyWith(fontSize: 13)),
              if (!FormAttachments.publicUploadsEnabled)
                Text(strings.uploadsUnavailable, key: Key('website-form-attachment-note-${f.id}'), style: widget.bodyStyle.copyWith(fontSize: 13, color: const Color(0xFF8A6A33))),
            ],
          ),
        );
    }
  }
}

/// How long text grows in the form.
class FormFieldLimits {
  /// A growing long text answer box reaches this many rows before it
  /// scrolls (or its own rows, if more).
  static const growTo = 10;
}
