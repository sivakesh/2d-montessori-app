import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../auth/providers/auth_provider.dart';
import '../data/school_settings_service.dart';
import '../models/school_settings_model.dart';
import '../providers/school_identity_provider.dart';
import 'access_restricted_view.dart';

/// The School Settings form (Settings -> School). Pushed from
/// AdminSettingsScreen rather than re-wrapped in AdminLayout again — the
/// same "plain Scaffold with its own AppBar/back button" shape every other
/// drill-down-from-an-admin-list screen in this app already uses.
class SchoolSettingsScreen extends StatelessWidget {
  const SchoolSettingsScreen({super.key, this.service});

  final SchoolSettingsService? service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('School Settings')),
      body: _SchoolSettingsBody(service: service),
    );
  }
}

class _SchoolSettingsBody extends ConsumerStatefulWidget {
  const _SchoolSettingsBody({this.service});

  final SchoolSettingsService? service;

  @override
  ConsumerState<_SchoolSettingsBody> createState() => _SchoolSettingsBodyState();
}

class _SchoolSettingsBodyState extends ConsumerState<_SchoolSettingsBody> {
  late final _service = widget.service ?? SchoolSettingsService();
  final _formKey = GlobalKey<FormState>();

  late final _nameController = TextEditingController();
  late final _addressController = TextEditingController();
  late final _phoneController = TextEditingController();
  late final _emailController = TextEditingController();
  late final _websiteController = TextEditingController();
  late final _descriptionController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _removingLogo = false;
  String _currentLogoUrl = '';
  PlatformFile? _pickedLogoFile;

  String get _role => (ref.read(currentUserProvider)?.role ?? '').toLowerCase();

  /// build()-only: ref.watch() cannot be called from initState()/_load()
  /// (which runs during initState), so the initial load below uses
  /// ref.read() via [_role] instead — this getter exists solely for the
  /// widget tree's own access-gating in [build].
  bool get _isAdmin => (ref.watch(currentUserProvider)?.role ?? '').toLowerCase() == 'admin';

  // Rebuilds the Identity Preview live as the admin types — it only
  // depends on name/phone/email, so only those three get a listener rather
  // than every controller in the form.
  void _repaintLivePreview() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_repaintLivePreview);
    _phoneController.addListener(_repaintLivePreview);
    _emailController.addListener(_repaintLivePreview);
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_role != 'admin') {
      setState(() => _loading = false);
      return;
    }
    try {
      final settings = await _service.getSettings(schoolId: kDefaultSchoolId, requesterRole: _role);
      if (!mounted) return;
      _nameController.text = settings?.name ?? '';
      _addressController.text = settings?.address ?? '';
      _phoneController.text = settings?.phone ?? '';
      _emailController.text = settings?.email ?? '';
      _websiteController.text = settings?.website ?? '';
      _descriptionController.text = settings?.description ?? '';
      _currentLogoUrl = settings?.logoUrl ?? '';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickLogo() async {
    final file = await _service.pickLogoFile();
    if (file == null || file.bytes == null) return;
    setState(() => _pickedLogoFile = file);
  }

  Future<void> _removeLogo() async {
    if (_pickedLogoFile != null) {
      // Nothing has been uploaded yet for this pick — just discard it
      // locally, no Storage/Firestore interaction needed.
      setState(() => _pickedLogoFile = null);
      return;
    }
    if (_currentLogoUrl.isEmpty) return;

    final user = ref.read(currentUserProvider);
    setState(() => _removingLogo = true);
    try {
      await _service.removeLogo(
        schoolId: kDefaultSchoolId,
        requesterRole: _role,
        logoUrl: _currentLogoUrl,
        updatedBy: user?.id ?? '',
        updatedByName: user?.name ?? '',
      );
      if (!mounted) return;
      setState(() => _currentLogoUrl = '');
      // The sidebar's logo is this same saved value — refresh it so
      // "Remove" is reflected there immediately, not just in this form.
      ref.invalidate(schoolIdentityProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo removed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove logo: $e')),
      );
    } finally {
      if (mounted) setState(() => _removingLogo = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider);
    setState(() => _saving = true);
    try {
      String? newLogoUrl;
      if (_pickedLogoFile != null) {
        newLogoUrl = await _service.uploadLogo(
          schoolId: kDefaultSchoolId,
          requesterRole: _role,
          file: _pickedLogoFile!,
          previousLogoUrl: _currentLogoUrl.isNotEmpty ? _currentLogoUrl : null,
        );
      }

      await _service.saveSettings(
        schoolId: kDefaultSchoolId,
        requesterRole: _role,
        name: _nameController.text,
        logoUrl: newLogoUrl,
        address: _addressController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        website: _websiteController.text,
        description: _descriptionController.text,
        updatedBy: user?.id ?? '',
        updatedByName: user?.name ?? '',
      );

      if (!mounted) return;
      setState(() {
        if (newLogoUrl != null) _currentLogoUrl = newLogoUrl;
        _pickedLogoFile = null;
      });
      // AppSidebar/AdminSidebar both watch this same provider — refresh it
      // so the saved name/logo shows up there without an app restart.
      ref.invalidate(schoolIdentityProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('School settings saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save school settings: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) return const AccessRestrictedView();
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                // Caps the form's width on very wide desktop screens — an
                // unconstrained Wrap left huge unused gutters either side
                // of narrow single-column fields at e.g. 1440px.
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityPreviewCard(
                      name: _nameController.text,
                      phone: _phoneController.text,
                      email: _emailController.text,
                      logoUrl: _currentLogoUrl,
                      pickedFile: _pickedLogoFile,
                    ),
                    const SizedBox(height: 20),
                    _SettingsSectionCard(
                      icon: Icons.school_outlined,
                      title: 'School Identity',
                      subtitle: 'How this school is identified across the app',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LogoSection(
                            logoUrl: _currentLogoUrl,
                            pickedFile: _pickedLogoFile,
                            busy: _saving || _removingLogo,
                            onPick: _pickLogo,
                            onRemove: _removeLogo,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(labelText: 'School Name *'),
                            validator: SchoolSettingsValidation.validateName,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SettingsSectionCard(
                      icon: Icons.contact_phone_outlined,
                      title: 'Contact Information',
                      subtitle: 'Optional — how parents and staff can reach the school',
                      child: _ContactFields(
                        phoneController: _phoneController,
                        emailController: _emailController,
                        websiteController: _websiteController,
                        addressController: _addressController,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SettingsSectionCard(
                      icon: Icons.info_outline,
                      title: 'About the School',
                      subtitle: 'Optional — a short description of the school',
                      child: TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A titled card grouping one part of the form — the shared shape "School
/// Identity"/"Contact Information"/"About the School" all use, matching
/// this app's existing card styling (AppColors.card, AppSizes' web border
/// radius) rather than introducing a new one.
class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.borderRadiusWeb),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Phone/Email/Website in a responsive row (3 columns wide, 1 narrow) plus
/// a full-width multi-line Address below — its own LayoutBuilder so the
/// column math is based on this card's actual content width, not the
/// whole screen's.
class _ContactFields extends StatelessWidget {
  const _ContactFields({
    required this.phoneController,
    required this.emailController,
    required this.websiteController,
    required this.addressController,
  });

  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController websiteController;
  final TextEditingController addressController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final columns = constraints.maxWidth >= 640 ? 3 : (constraints.maxWidth >= 420 ? 2 : 1);
        final fieldWidth = columns == 1
            ? double.infinity
            : (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: SchoolSettingsValidation.validateEmail,
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: TextFormField(
                    controller: websiteController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Website'),
                    validator: SchoolSettingsValidation.validateWebsite,
                  ),
                ),
              ],
            ),
            const SizedBox(height: spacing),
            TextFormField(
              controller: addressController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
          ],
        );
      },
    );
  }
}

/// Compact "Identity Preview" card at the top of the form — a live view of
/// what AppSidebar/AdminSidebar will show once saved, using the *current
/// form state* (including an unsaved pick/edit), not only the last-saved
/// value, so the admin can see what they're about to publish before
/// hitting Save.
class _IdentityPreviewCard extends StatelessWidget {
  const _IdentityPreviewCard({
    required this.name,
    required this.phone,
    required this.email,
    required this.logoUrl,
    required this.pickedFile,
  });

  final String name;
  final String phone;
  final String email;
  final String logoUrl;
  final PlatformFile? pickedFile;

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isEmpty ? 'Untitled School' : name.trim();
    final contactBits = [phone.trim(), email.trim()].where((s) => s.isNotEmpty).join('  •  ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSizes.borderRadiusWeb),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          _LogoThumb(logoUrl: logoUrl, pickedFile: pickedFile, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'IDENTITY PREVIEW',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
                ),
                if (contactBits.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    contactBits,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The logo thumbnail rendering rules shared by [_LogoSection] (the bigger
/// editable preview) and [_IdentityPreviewCard] (the small live preview):
/// an unsaved local pick wins, then the saved Storage URL, then a neutral
/// placeholder icon — never a broken-image glyph.
class _LogoThumb extends StatelessWidget {
  const _LogoThumb({required this.logoUrl, required this.pickedFile, required this.size});

  final String logoUrl;
  final PlatformFile? pickedFile;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: pickedFile != null
          ? Image.memory(
              pickedFile!.bytes!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.broken_image_outlined,
                color: AppColors.textSecondary,
                size: size * 0.4,
              ),
            )
          : logoUrl.isNotEmpty
              ? Image.network(
                  logoUrl,
                  fit: BoxFit.cover,
                  // A broken/unreachable logo URL falls back to the
                  // placeholder icon rather than a broken-image glyph.
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textSecondary,
                    size: size * 0.4,
                  ),
                )
              : Icon(Icons.school_outlined, color: AppColors.textSecondary, size: size * 0.4),
    );
  }
}

class _LogoSection extends StatelessWidget {
  const _LogoSection({
    required this.logoUrl,
    required this.pickedFile,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final String logoUrl;
  final PlatformFile? pickedFile;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  bool get _hasLogo => pickedFile != null || logoUrl.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _LogoThumb(logoUrl: logoUrl, pickedFile: pickedFile, size: 84),
        const SizedBox(width: 16),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onPick,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: Text(_hasLogo ? 'Replace Logo' : 'Upload Logo'),
              ),
              if (_hasLogo)
                TextButton.icon(
                  onPressed: busy ? null : onRemove,
                  icon: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: const Text('Remove', style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
