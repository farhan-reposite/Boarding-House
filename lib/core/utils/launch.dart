import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/common.dart';
import 'format.dart';
import '../i18n/app_language.dart';

Future<void> callNumber(BuildContext context, String phone) async {
  if (phone.trim().isEmpty) {
    snack(context, tr('No phone number saved.'));
    return;
  }
  try {
    final ok = await launchUrl(Uri(scheme: 'tel', path: phone.trim()));
    if (!ok && context.mounted) snack(context, tr('Could not open the dialer.'));
  } catch (_) {
    if (context.mounted) snack(context, tr('Could not open the dialer.'));
  }
}

/// Opens a WhatsApp chat with [phone] (optionally with a prefilled [text]).
Future<void> openWhatsApp(BuildContext context, String phone,
    [String text = '']) async {
  final number = normalizePhone(phone);
  if (number.isEmpty) {
    snack(context, tr('No phone number saved.'));
    return;
  }
  final query = text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}';
  try {
    final ok = await launchUrl(
      Uri.parse('https://wa.me/$number$query'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) snack(context, tr('Could not open WhatsApp.'));
  } catch (_) {
    if (context.mounted) snack(context, tr('Could not open WhatsApp.'));
  }
}
