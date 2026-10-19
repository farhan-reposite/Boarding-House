import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import '../../core/icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models.dart';
import '../utils/date_helpers.dart';
import '../utils/format.dart';
import '../utils/photo_store.dart';
import '../i18n/app_language.dart';

// ------------------------------------------------------------ status pills

class StatusColors {
  const StatusColors(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

/// Semantic tones used everywhere for quick scanning:
/// success = paid / healthy, info = vacant / not yet due, warning = expiring
/// or partial, danger = overdue, neutral = inactive.
enum Tone { success, info, warning, danger, neutral }

/// Soft background + text color pair, readable in both light and dark mode.
StatusColors toneColors(BuildContext context, Tone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (tone) {
    Tone.success => dark
        ? const StatusColors(Color(0xFF1B4A3B), Color(0xFFA5DDB5))
        : const StatusColors(Color(0xFFE0EEE2), Color(0xFF1D5A3A)),
    Tone.info => dark
        ? const StatusColors(Color(0xFF16385A), Color(0xFFA9CCF5))
        : const StatusColors(Color(0xFFDFEAF5), Color(0xFF24527A)),
    Tone.warning => dark
        ? const StatusColors(Color(0xFF4A3A00), Color(0xFFFFD25C))
        : const StatusColors(Color(0xFFFFF0C2), Color(0xFF7A5400)),
    Tone.danger => dark
        ? const StatusColors(Color(0xFF5C1F1A), Color(0xFFFFB0A8))
        : const StatusColors(Color(0xFFFBE3DF), Color(0xFFB3261E)),
    Tone.neutral => dark
        ? const StatusColors(Color(0xFF244A3D), Color(0xFFC5D6CC))
        : const StatusColors(Color(0xFFE7ECE5), Color(0xFF4A5A51)),
  };
}

/// Strong solid color for tile edges, dots and icons.
Color toneAccent(Tone tone) => switch (tone) {
      Tone.success => const Color(0xFF3E9A62),
      Tone.info => const Color(0xFF3F86D6),
      Tone.warning => const Color(0xFFFFBA00),
      Tone.danger => const Color(0xFFD9453A),
      Tone.neutral => const Color(0xFF8A9A91),
    };

Tone roomStatusTone(RoomStatus s) => switch (s) {
      RoomStatus.available => Tone.info,
      RoomStatus.occupied => Tone.success,
      RoomStatus.reserved => Tone.info,
      RoomStatus.maintenance => Tone.warning,
    };

Tone paymentStatusTone(PaymentStatus s) => switch (s) {
      PaymentStatus.paid => Tone.success,
      PaymentStatus.partial => Tone.warning,
      PaymentStatus.unpaid => Tone.info,
      PaymentStatus.overdue => Tone.danger,
    };

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.colors});
  final String label;
  final StatusColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class RoomStatusPill extends StatelessWidget {
  const RoomStatusPill(this.status, {super.key});
  final RoomStatus status;

  @override
  Widget build(BuildContext context) => Pill(
      label: status.label,
      colors: toneColors(context, roomStatusTone(status)));
}

class PaymentStatusPill extends StatelessWidget {
  const PaymentStatusPill(this.status, {super.key});
  final PaymentStatus status;

  @override
  Widget build(BuildContext context) => Pill(
      label: status.label,
      colors: toneColors(context, paymentStatusTone(status)));
}

// ------------------------------------------------------------ layout bits

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: TextStyle(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ photos

class PhotoThumb extends StatelessWidget {
  const PhotoThumb({
    super.key,
    required this.name,
    this.size = 72,
    this.radius = 8,
    this.onTap,
    this.placeholderIcon = Ph.image,
  });
  final String? name;
  final double size;
  final double radius;
  final VoidCallback? onTap;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      child: Icon(placeholderIcon, color: scheme.outline),
    );
    final Widget content = name == null
        ? placeholder
        : Image.file(
            PhotoStore.file(name!),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: 400,
            errorBuilder: (context, error, stack) => placeholder,
          );
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}

/// Bottom sheet: camera or gallery. Returns the stored file name.
Future<String?> pickPhotoSheet(BuildContext context) async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return PhotoStore.pick(ImageSource.gallery);
  }
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Ph.camera),
            title: Text(tr('Take a photo')),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Ph.images),
            title: Text(tr('Choose from gallery')),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  return PhotoStore.pick(source);
}

void openPhoto(BuildContext context, String name) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PhotoViewerScreen(name: name)),
  );
}

class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(PhotoStore.file(name)),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- inputs

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.clearable = false,
    this.enabled = true,
    this.errorText,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool clearable;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: enabled
            ? () async {
                final first = firstDate ?? DateTime(2015);
                final last = lastDate ?? DateTime(2100);
                var initial = value ?? todayDate();
                if (initial.isBefore(first)) initial = first;
                if (initial.isAfter(last)) initial = last;
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: first,
                  lastDate: last,
                );
                if (picked != null) onChanged(dateOnly(picked));
              }
            : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            enabled: enabled,
            suffixIcon: clearable && value != null && enabled
                ? IconButton(
                    icon: const Icon(Ph.x),
                    onPressed: () => onChanged(null),
                  )
                : const Icon(Ph.calendarBlank),
          ),
          child: Text(value == null ? tr('Not set') : fmtDate(value)),
        ),
      ),
    );
  }
}

Widget appTextField({
  required TextEditingController controller,
  required String label,
  TextInputType? type,
  int maxLines = 1,
  String? Function(String?)? validator,
  TextCapitalization capitalization = TextCapitalization.sentences,
  ValueChanged<String>? onChanged,
  String? helper,
  IconData? icon,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      keyboardType: type,
      maxLines: maxLines,
      textCapitalization: capitalization,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: icon == null ? null : Icon(icon),
        // Multi-line fields look better with the icon riding the top of the
        // box rather than centered in the whole (taller) field.
        alignLabelWithHint: maxLines > 1,
      ),
    ),
  );
}

Widget moneyField({
  required TextEditingController controller,
  required String label,
  String? Function(String?)? validator,
  ValueChanged<String>? onChanged,
  bool enabled = true,
  String? helper,
  String? errorText,
  IconData? icon,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'Rp ',
        prefixIcon: icon == null ? null : Icon(icon),
        helperText: helper,
        errorText: errorText,
      ),
    ),
  );
}

// ------------------------------------------------------------------ dialogs

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel ?? tr('Confirm')),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

void snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// ------------------------------------------------------------ async helper

extension AsyncUi<T> on AsyncValue<T> {
  /// Loading spinner / error text / data. Keeps showing old data while
  /// reloading so lists don't flicker after every edit.
  Widget ui({required Widget Function(T value) data}) {
    return when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${tr('Something went wrong:')}\n$e', textAlign: TextAlign.center),
        ),
      ),
      data: data,
    );
  }
}
