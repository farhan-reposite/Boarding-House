import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/utils/format.dart';
import '../../data/models.dart';

/// Builds tenant-facing invoices. Texts are in Indonesian because tenants
/// read them; edit the strings below if you want something different.
/// (PDF text is kept ASCII-only because the built-in PDF font has no
/// full Unicode support.)
class InvoiceService {
  InvoiceService._();

  static String number(ChargeView v) {
    final d = v.charge.dueDate;
    final month = d.month.toString().padLeft(2, '0');
    return 'INV-${d.year}$month-${v.charge.id.toString().padLeft(4, '0')}';
  }

  /// Short message for WhatsApp (used as chat text or as caption for the PDF).
  static String message(ChargeView v, KostProfile profile) {
    final c = v.charge;
    final b = StringBuffer();
    b.writeln('Halo ${v.tenantName},');
    final period = '${fmtDateId(c.dueDate)} - ${fmtDateId(c.periodEnd)}';
    if (c.remaining == 0) {
      b.writeln(
          'Terima kasih, pembayaran sewa kamar ${v.roomName} periode $period sudah kami terima (lunas).');
    } else {
      if (isOverdue(c.dueDate)) {
        b.writeln(
            'Ini pengingat bahwa tagihan sewa kamar ${v.roomName} periode $period sudah melewati jatuh tempo.');
      } else {
        b.writeln('Berikut tagihan sewa kamar ${v.roomName} periode $period.');
      }
      b.writeln('Sisa tagihan: ${rp(c.remaining)}');
      b.writeln('Jatuh tempo: ${fmtDateId(c.dueDate)}');
      final info = profile.paymentInfo.trim();
      if (info.isNotEmpty) {
        b.writeln();
        b.writeln('Pembayaran ke:');
        b.writeln(info);
      }
      b.writeln();
      b.writeln('Mohon konfirmasi setelah melakukan pembayaran. Terima kasih.');
    }
    if (profile.name.trim().isNotEmpty) {
      b.writeln();
      b.write('- ${profile.name.trim()}');
    }
    return b.toString().trimRight();
  }

  static Future<Uint8List> buildPdf(ChargeView v, KostProfile profile) async {
    final c = v.charge;
    final paid = c.remaining == 0;
    final kostName = profile.name.trim().isEmpty ? 'Kost' : profile.name.trim();
    final period = '${fmtDateId(c.dueDate)} - ${fmtDateId(c.periodEnd)}';

    pw.Widget cell(String text, {bool bold = false, bool right = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(
          text,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    pw.Widget totalRow(String label, String value, {bool bold = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.SizedBox(
              width: 110,
              child: pw.Text(label,
                  style: pw.TextStyle(
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ),
            pw.SizedBox(
              width: 100,
              child: pw.Text(value,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ),
          ],
        ),
      );
    }

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(kostName,
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('INVOICE',
                        style: pw.TextStyle(
                            fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    pw.Text(number(v)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(),
            pw.SizedBox(height: 6),
            pw.Text('Kepada: ${v.tenantName}'),
            pw.Text('Kamar: ${v.roomName}'),
            pw.Text('Jatuh tempo: ${fmtDateId(c.dueDate)}'),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1.4),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    cell('Deskripsi', bold: true),
                    cell('Jumlah', bold: true, right: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    cell('Sewa kamar ${v.roomName}\nPeriode: $period'),
                    cell(rp(c.amount), right: true),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            totalRow('Total', rp(c.amount)),
            totalRow('Sudah dibayar', rp(c.paidAmount)),
            totalRow('Sisa tagihan', rp(c.remaining), bold: true),
            pw.SizedBox(height: 10),
            pw.Text(
              paid ? 'LUNAS' : 'BELUM LUNAS',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: paid ? PdfColors.green800 : PdfColors.red800,
              ),
            ),
            if (!paid && profile.paymentInfo.trim().isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text('Pembayaran ke:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(profile.paymentInfo.trim()),
            ],
            pw.Spacer(),
            pw.Text('Terima kasih.',
                style: const pw.TextStyle(color: PdfColors.grey700)),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// Builds the PDF and opens the Android share sheet (WhatsApp, Drive, ...).
  static Future<void> sharePdf(ChargeView v, KostProfile profile) async {
    final bytes = await buildPdf(v, profile);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${number(v)}.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        text: message(v, profile),
        subject: 'Invoice ${number(v)}',
      ),
    );
  }

  /// Builds one PDF per invoice and shares them all in a single share sheet.
  static Future<void> shareMany(
      List<ChargeView> views, KostProfile profile) async {
    final dir = await getTemporaryDirectory();
    final files = <XFile>[];
    for (final v in views) {
      final bytes = await buildPdf(v, profile);
      final file = File(p.join(dir.path, '${number(v)}.pdf'));
      await file.writeAsBytes(bytes, flush: true);
      files.add(XFile(file.path, mimeType: 'application/pdf'));
    }
    await SharePlus.instance.share(
      ShareParams(files: files, subject: 'Invoices / receipts'),
    );
  }
}
