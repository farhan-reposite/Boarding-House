import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup_service.dart';
import '../../core/utils/date_helpers.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/kost_logo.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../providers.dart';
import '../../core/i18n/app_language.dart';
import '../../core/tutorial/tutorial.dart';
import '../dashboard/insights.dart';
import '../payments/export_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _paymentInfo = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await ref.read(repoProvider).getProfile();
    if (!mounted) return;
    _name.text = profile.name;
    _paymentInfo.text = profile.paymentInfo;
  }

  @override
  void dispose() {
    _name.dispose();
    _paymentInfo.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    await ref.read(repoProvider).saveProfile(KostProfile(
          name: _name.text.trim(),
          paymentInfo: _paymentInfo.text.trim(),
        ));
    notifyChanged(ref);
    if (mounted) snack(context, tr('Saved.'));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on KostException catch (e) {
      if (mounted) snack(context, e.message);
    } catch (e) {
      if (mounted) snack(context, tr('Something went wrong: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    if (!mounted) return;

    final ok = await confirmDialog(
      context,
      title: tr('Restore this backup?'),
      message:
          tr('ALL current data (rooms, tenants, payments, photos) will be replaced by the contents of the backup. This cannot be undone.'),
      confirmLabel: tr('Replace everything'),
      destructive: true,
    );
    if (!ok) return;

    await _run(() async {
      await BackupService.restoreBackup(File(path));
      notifyChanged(ref);
      await _loadProfile();
      if (mounted) snack(context, tr('Backup restored.'));
    });
  }

  Future<void> _backupNow() => _run(() async {
        await BackupService.shareBackup();
        notifyChanged(ref);
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(languageProvider);
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 56,
        leading: const Padding(
          padding: EdgeInsets.all(12),
          child: KostLogo(size: 28),
        ),
        title: Text(tr('Settings')),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _BackupAlert(onTap: _busy ? null : _backupNow),
          ),
          SectionCard(
            title: tr('Kost profile'),
            children: [
              const SizedBox(height: 4),
              appTextField(
                controller: _name,
                label: tr('Kost name'),
                icon: Ph.storefront,
                capitalization: TextCapitalization.words,
                helper: tr('Shown on invoices'),
              ),
              appTextField(
                controller: _paymentInfo,
                label: tr('Payment instructions'),
                icon: Ph.bank,
                maxLines: 3,
                helper: tr('e.g. BCA 1234567890 a/n Your Name. Shown on invoices and WhatsApp messages.'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saveProfile,
                  child: Text(tr('Save')),
                ),
              ),
            ],
          ),
          SectionCard(
            title: tr('Appearance'),
            children: [
              Text(
                tr('Choose how Kost Manager looks on this phone.'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(tr('System')),
                    icon: Icon(Ph.circleHalf),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(tr('Light')),
                    icon: Icon(Ph.sun),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(tr('Dark')),
                    icon: Icon(Ph.moon),
                  ),
                ],
                selected: {themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) async {
                  final mode = selection.first;
                  ref.read(themeModeProvider.notifier).state = mode;
                  await ref
                      .read(repoProvider)
                      .setThemeModeSetting(themeModeToSetting(mode));
                },
              ),
            ],
          ),
          SectionCard(
            title: tr('Language'),
            children: [
              Text(
                tr('Choose the language used in the app.'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              SegmentedButton<AppLanguage>(
                segments: [
                  for (final l in AppLanguage.values)
                    ButtonSegment(value: l, label: Text(l.nativeName)),
                ],
                selected: {language},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    changeLanguage(ref, selection.first),
              ),
            ],
          ),
          SectionCard(
            title: tr('Tutorial'),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Ph.arrowUUpLeft),
                title: Text(tr('Replay the tutorial')),
                subtitle: Text(
                    tr('Quick setup, adding a room and assigning a tenant')),
                onTap: () => startTutorial(ref),
              ),
            ],
          ),
          SectionCard(
            title: tr('Backup & export'),
            children: [
              Text(
                tr('All data is stored only on this phone. Make a backup regularly and keep it in Google Drive or send it to yourself.'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Ph.cloudArrowUp),
                title: Text(tr('Create backup')),
                subtitle: Text(tr('Database + all photos, as one .zip file')),
                enabled: !_busy,
                onTap: _backupNow,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Ph.clockCounterClockwise),
                title: Text(tr('Restore from backup')),
                subtitle: Text(tr('Replaces all current data')),
                enabled: !_busy,
                onTap: _restore,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Ph.table),
                title: Text(tr('Export payments')),
                subtitle: Text(tr('Excel or PDF, by month, year or all')),
                enabled: !_busy,
                onTap: () => showExportSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// Backup status: green when recent, yellow after a week, red when never.
/// Tap to create a backup now.
class _BackupAlert extends ConsumerWidget {
  const _BackupAlert({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lastBackupProvider);
    final last = async.valueOrNull;
    if (async.isLoading && last == null) return const SizedBox.shrink();

    final days = last == null ? null : todayDate().difference(last).inDays;
    final tone = days == null
        ? Tone.danger
        : days > 7
            ? Tone.warning
            : Tone.success;
    final text = days == null
        ? tr('No backup yet. Your data exists only on this device.')
        : days == 0
            ? tr('Backed up today')
            : tr(days == 1 ? 'Last backup {n} day ago' : 'Last backup {n} days ago',
                {'n': days});
    final colors = toneColors(context, tone);

    return Material(
      color: colors.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(tone == Tone.success ? Ph.cloudCheck : Ph.cloudSlash,
                  size: 20, color: colors.fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.fg)),
              ),
              if (tone != Tone.success)
                Text(tr('Back up'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.fg)),
            ],
          ),
        ),
      ),
    );
  }
}
