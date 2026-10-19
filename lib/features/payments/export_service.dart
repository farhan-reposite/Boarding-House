import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/i18n/app_language.dart';
import '../../core/utils/date_helpers.dart';
import '../../core/utils/format.dart';
import '../../data/models.dart';

enum ExportScope { month, year, all }

enum ExportFormat { xlsx, pdf }

/// Which invoices to export. Invoices are matched by their due date
/// (the start of the billing period).
class ExportPeriod {
  ExportPeriod._(this.scope, this.from, this.to);

  factory ExportPeriod.month(int year, int month) => ExportPeriod._(
        ExportScope.month,
        DateTime(year, month, 1),
        DateTime(year, month + 1, 1),
      );

  factory ExportPeriod.year(int year) => ExportPeriod._(
        ExportScope.year,
        DateTime(year, 1, 1),
        DateTime(year + 1, 1, 1),
      );

  factory ExportPeriod.all() => ExportPeriod._(ExportScope.all, null, null);

  final ExportScope scope;
  final DateTime? from;

  /// Exclusive upper bound.
  final DateTime? to;

  bool contains(DateTime d) =>
      (from == null || !d.isBefore(from!)) && (to == null || d.isBefore(to!));

  String get label {
    switch (scope) {
      case ExportScope.month:
        return DateFormat('MMMM yyyy', AppLang.current.dateLocale).format(from!);
      case ExportScope.year:
        return '${from!.year}';
      case ExportScope.all:
        return tr('All periods');
    }
  }

  String get fileSlug {
    switch (scope) {
      case ExportScope.month:
        return '${from!.year}-${from!.month.toString().padLeft(2, '0')}';
      case ExportScope.year:
        return '${from!.year}';
      case ExportScope.all:
        return 'all';
    }
  }
}

class ExportSummary {
  const ExportSummary({
    required this.count,
    required this.paidCount,
    required this.billed,
    required this.collected,
    required this.outstanding,
  });

  final int count;
  final int paidCount;
  final int billed;
  final int collected;
  final int outstanding;
}

/// Builds the payments report as a styled Excel workbook or a PDF and
/// opens the share sheet.
class ExportService {
  ExportService._();

  // ----------------------------------------------------------------- data

  static List<ChargeView> filter(List<ChargeView> all, ExportPeriod period) {
    final list = all.where((v) => period.contains(v.charge.dueDate)).toList();
    list.sort((a, b) {
      final c = a.charge.dueDate.compareTo(b.charge.dueDate);
      return c != 0 ? c : naturalCompare(a.roomName, b.roomName);
    });
    return list;
  }

  static ExportSummary summarize(List<ChargeView> rows) {
    var billed = 0;
    var collected = 0;
    var outstanding = 0;
    var paid = 0;
    for (final v in rows) {
      billed += v.charge.amount;
      collected += v.charge.paidAmount;
      outstanding += v.charge.remaining;
      if (v.charge.remaining == 0) paid++;
    }
    return ExportSummary(
      count: rows.length,
      paidCount: paid,
      billed: billed,
      collected: collected,
      outstanding: outstanding,
    );
  }

  static Future<void> exportAndShare({
    required List<ChargeView> all,
    required ExportPeriod period,
    required ExportFormat format,
    required String kostName,
  }) async {
    final rows = filter(all, period);
    final tmp = await getTemporaryDirectory();
    final base = 'kost_payments_${period.fileSlug}';

    final File file;
    final String mime;
    if (format == ExportFormat.xlsx) {
      file = File(p.join(tmp.path, '$base.xlsx'));
      await file.writeAsBytes(buildXlsx(rows, period, kostName), flush: true);
      mime =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    } else {
      file = File(p.join(tmp.path, '$base.pdf'));
      await file.writeAsBytes(await buildPdf(rows, period, kostName),
          flush: true);
      mime = 'application/pdf';
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mime)],
        subject: 'Kost payments ${period.label}',
      ),
    );
  }

  // ----------------------------------------------------------------- xlsx

  static const _lastCol = 10; // A..J
  static const _letters = 'ABCDEFGHIJ';

  static String _esc(String s) => s
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static int _serial(DateTime d) => DateTime.utc(d.year, d.month, d.day)
      .difference(DateTime.utc(1899, 12, 30))
      .inDays;

  static String _str(String ref, String text, int style) =>
      '<c r="$ref" s="$style" t="inlineStr"><is>'
      '<t xml:space="preserve">${_esc(text)}</t></is></c>';

  static String _num(String ref, num v, int style) =>
      '<c r="$ref" s="$style"><v>$v</v></c>';

  static String _blank(String ref, int style) => '<c r="$ref" s="$style"/>';

  static String _formula(String ref, String f, num cached, int style) =>
      '<c r="$ref" s="$style"><f>$f</f><v>$cached</v></c>';

  /// One `<row>`. [cells] maps a 0-based column to its XML; missing columns
  /// are filled with an empty cell in [fillStyle] so merged ranges and
  /// backgrounds render fully.
  static String _row(int r, Map<int, String> cells,
      {double? height, int fillStyle = 0}) {
    final b = StringBuffer();
    b.write(height == null
        ? '<row r="$r">'
        : '<row r="$r" ht="$height" customHeight="1">');
    for (var c = 0; c < _lastCol; c++) {
      b.write(cells[c] ?? _blank('${_letters[c]}$r', fillStyle));
    }
    b.write('</row>');
    return b.toString();
  }

  // Style indexes (see _stylesXml).
  static const _sTitle = 1;
  static const _sSubtitle = 2;
  static const _sHeader = 3;
  static const _sText = 4;
  static const _sTextZebra = 5;
  static const _sMoney = 6;
  static const _sMoneyZebra = 7;
  static const _sDate = 8;
  static const _sDateZebra = 9;
  static const _sPaid = 10;
  static const _sPartial = 11;
  static const _sUnpaid = 12;
  static const _sOverdue = 13;
  static const _sTotalLabel = 14;
  static const _sTotalMoney = 15;
  static const _sKpiLabel = 16;
  static const _sKpiMoney = 17;
  static const _sKpiCount = 18;
  static const _sCenter = 19;
  static const _sCenterZebra = 20;

  static String _xf({
    int num = 0,
    int font = 0,
    int fill = 0,
    int border = 0,
    String h = 'left',
    int indent = 0,
    bool wrap = false,
  }) =>
      '<xf numFmtId="$num" fontId="$font" fillId="$fill" borderId="$border" '
      'xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" '
      'applyBorder="1" applyAlignment="1">'
      '<alignment horizontal="$h" vertical="center"'
      '${indent > 0 ? ' indent="$indent"' : ''}'
      '${wrap ? ' wrapText="1"' : ''}/></xf>';

  static String _font(
          {bool bold = false, int size = 11, String color = '10241C'}) =>
      '<font>${bold ? '<b/>' : ''}<sz val="$size"/>'
      '<color rgb="FF$color"/><name val="Calibri"/><family val="2"/></font>';

  static String _fill(String color) =>
      '<fill><patternFill patternType="solid"><fgColor rgb="FF$color"/>'
      '<bgColor indexed="64"/></patternFill></fill>';

  static String _stylesXml() {
    final fonts = [
      _font(), // 0 default
      _font(bold: true, size: 20, color: '0C3B2E'), // 1 title
      _font(size: 10, color: '55665D'), // 2 subtitle
      _font(bold: true, color: 'FFFFFF'), // 3 header
      _font(bold: true), // 4 bold
      _font(size: 9, color: '55665D'), // 5 kpi label
      _font(bold: true, size: 15, color: '0C3B2E'), // 6 kpi value
      _font(bold: true, size: 10, color: '1D5A3A'), // 7 paid
      _font(bold: true, size: 10, color: '7A5400'), // 8 partial
      _font(bold: true, size: 10, color: '24527A'), // 9 unpaid
      _font(bold: true, size: 10, color: 'B3261E'), // 10 overdue
    ];
    final fills = [
      '<fill><patternFill patternType="none"/></fill>', // 0
      '<fill><patternFill patternType="gray125"/></fill>', // 1
      _fill('0C3B2E'), // 2 forest
      _fill('F2F5F0'), // 3 zebra / kpi
      _fill('E0EEE2'), // 4 paid
      _fill('FFF0C2'), // 5 partial
      _fill('DFEAF5'), // 6 unpaid
      _fill('FBE3DF'), // 7 overdue
      _fill('E5EBE3'), // 8 total
    ];
    const borders = [
      '<border><left/><right/><top/><bottom/><diagonal/></border>',
      '<border><left/><right/><top/>'
          '<bottom style="thin"><color rgb="FFD7DFD8"/></bottom><diagonal/></border>',
    ];
    final xfs = [
      _xf(), // 0
      _xf(font: 1), // 1 title
      _xf(font: 2), // 2 subtitle
      _xf(font: 3, fill: 2, h: 'center', wrap: true), // 3 header
      _xf(border: 1, indent: 1), // 4 text
      _xf(fill: 3, border: 1, indent: 1), // 5 text zebra
      _xf(num: 164, border: 1, h: 'right', indent: 1), // 6 money
      _xf(num: 164, fill: 3, border: 1, h: 'right', indent: 1), // 7
      _xf(num: 165, border: 1, h: 'center'), // 8 date
      _xf(num: 165, fill: 3, border: 1, h: 'center'), // 9
      _xf(font: 7, fill: 4, border: 1, h: 'center'), // 10 paid
      _xf(font: 8, fill: 5, border: 1, h: 'center'), // 11 partial
      _xf(font: 9, fill: 6, border: 1, h: 'center'), // 12 unpaid
      _xf(font: 10, fill: 7, border: 1, h: 'center'), // 13 overdue
      _xf(font: 4, fill: 8, indent: 1), // 14 total label
      _xf(num: 164, font: 4, fill: 8, h: 'right', indent: 1), // 15 total money
      _xf(font: 5, fill: 3, indent: 1), // 16 kpi label
      _xf(num: 164, font: 6, fill: 3, indent: 1), // 17 kpi money
      _xf(font: 6, fill: 3, indent: 1), // 18 kpi count
      _xf(border: 1, h: 'center'), // 19 center
      _xf(fill: 3, border: 1, h: 'center'), // 20 center zebra
    ];

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<numFmts count="2">'
        '<numFmt numFmtId="164" formatCode="&quot;Rp&quot;\\ #,##0"/>'
        '<numFmt numFmtId="165" formatCode="dd\\ mmm\\ yyyy"/>'
        '</numFmts>'
        '<fonts count="${fonts.length}">${fonts.join()}</fonts>'
        '<fills count="${fills.length}">${fills.join()}</fills>'
        '<borders count="${borders.length}">${borders.join()}</borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="${xfs.length}">${xfs.join()}</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>';
  }

  static int _statusStyle(PaymentStatus s) => switch (s) {
        PaymentStatus.paid => _sPaid,
        PaymentStatus.partial => _sPartial,
        PaymentStatus.unpaid => _sUnpaid,
        PaymentStatus.overdue => _sOverdue,
      };

  static Uint8List buildXlsx(
      List<ChargeView> rows, ExportPeriod period, String kostName) {
    final today = todayDate();
    final sum = summarize(rows);
    final sheetName = _esc(tr('Payments'));
    final name = kostName.trim().isEmpty ? 'Kost Manager' : kostName.trim();

    final data = StringBuffer();
    final merges = <String>[];

    // 1: title, 2: subtitle
    data.write(_row(1, {0: _str('A1', '$name - ${tr('Payments report')}', _sTitle)},
        height: 34));
    merges.add('A1:J1');
    data.write(_row(
        2,
        {
          0: _str(
              'A2',
              '${tr('Period')}: ${period.label}   |   '
                  '${tr('Generated on {date}', {'date': fmtDate(today)})}',
              _sSubtitle)
        },
        height: 18));
    merges.add('A2:J2');
    data.write(_row(3, {}, height: 8));

    // 4-5: KPI strip
    data.write(_row(
        4,
        {
          0: _str('A4', tr('Billed'), _sKpiLabel),
          3: _str('D4', tr('Collected'), _sKpiLabel),
          6: _str('G4', tr('Outstanding'), _sKpiLabel),
          8: _str('I4', tr('Invoices'), _sKpiLabel),
        },
        height: 18,
        fillStyle: _sKpiLabel));
    data.write(_row(
        5,
        {
          0: _num('A5', sum.billed, _sKpiMoney),
          3: _num('D5', sum.collected, _sKpiMoney),
          6: _num('G5', sum.outstanding, _sKpiMoney),
          8: _str('I5', '${sum.paidCount} / ${sum.count} ${tr('paid')}',
              _sKpiCount),
        },
        height: 28,
        fillStyle: _sKpiCount));
    merges.addAll(['A4:C4', 'D4:F4', 'G4:H4', 'I4:J4']);
    merges.addAll(['A5:C5', 'D5:F5', 'G5:H5', 'I5:J5']);
    data.write(_row(6, {}, height: 10));

    // 7: header
    final headers = [
      tr('No.'),
      tr('Tenant'),
      tr('Room'),
      tr('Due date'),
      tr('Period end'),
      tr('Amount'),
      tr('Paid'),
      tr('Remaining'),
      tr('Last payment'),
      tr('Status'),
    ];
    data.write(_row(
        7,
        {
          for (var c = 0; c < headers.length; c++)
            c: _str('${_letters[c]}7', headers[c], _sHeader),
        },
        height: 26));

    // data rows from 8
    const first = 8;
    for (var i = 0; i < rows.length; i++) {
      final r = first + i;
      final v = rows[i];
      final c = v.charge;
      final z = i.isOdd;
      data.write(_row(
          r,
          {
            0: _num('A$r', i + 1, z ? _sCenterZebra : _sCenter),
            1: _str('B$r', v.tenantName, z ? _sTextZebra : _sText),
            2: _str('C$r', v.roomName, z ? _sTextZebra : _sText),
            3: _num('D$r', _serial(c.dueDate), z ? _sDateZebra : _sDate),
            4: _num('E$r', _serial(c.periodEnd), z ? _sDateZebra : _sDate),
            5: _num('F$r', c.amount, z ? _sMoneyZebra : _sMoney),
            6: _num('G$r', c.paidAmount, z ? _sMoneyZebra : _sMoney),
            7: _num('H$r', c.remaining, z ? _sMoneyZebra : _sMoney),
            8: c.paidDate == null
                ? _blank('I$r', z ? _sDateZebra : _sDate)
                : _num('I$r', _serial(c.paidDate!), z ? _sDateZebra : _sDate),
            9: _str('J$r', c.statusOn(today).label,
                _statusStyle(c.statusOn(today))),
          },
          height: 21));
    }

    final last = first + rows.length - 1;
    final total = last + 1;
    if (rows.isNotEmpty) {
      data.write(_row(
          total,
          {
            0: _str('A$total', tr('Total'), _sTotalLabel),
            5: _formula('F$total', 'SUM(F$first:F$last)', sum.billed, _sTotalMoney),
            6: _formula(
                'G$total', 'SUM(G$first:G$last)', sum.collected, _sTotalMoney),
            7: _formula('H$total', 'SUM(H$first:H$last)', sum.outstanding,
                _sTotalMoney),
          },
          height: 24,
          fillStyle: _sTotalLabel));
      merges.add('A$total:E$total');
    }

    final lastRow = rows.isEmpty ? 7 : total;
    const widths = [6.0, 28.0, 10.0, 14.0, 14.0, 17.0, 17.0, 17.0, 15.0, 13.0];
    final cols = StringBuffer('<cols>');
    for (var i = 0; i < widths.length; i++) {
      cols.write(
          '<col min="${i + 1}" max="${i + 1}" width="${widths[i]}" customWidth="1"/>');
    }
    cols.write('</cols>');

    final sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
        '<dimension ref="A1:J$lastRow"/>'
        '<sheetViews><sheetView showGridLines="0" workbookViewId="0">'
        '<pane ySplit="7" topLeftCell="A8" activePane="bottomLeft" state="frozen"/>'
        '<selection pane="bottomLeft" activeCell="A8" sqref="A8"/>'
        '</sheetView></sheetViews>'
        '<sheetFormatPr defaultRowHeight="18"/>'
        '$cols'
        '<sheetData>$data</sheetData>'
        '${rows.isEmpty ? '' : '<autoFilter ref="A7:J$last"/>'}'
        '<mergeCells count="${merges.length}">'
        '${merges.map((m) => '<mergeCell ref="$m"/>').join()}'
        '</mergeCells>'
        '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>'
        '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>'
        '</worksheet>';

    const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>';

    const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>';

    final workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="$sheetName" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>';

    const workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>';

    final archive = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add('[Content_Types].xml', contentTypes);
    add('_rels/.rels', rootRels);
    add('xl/workbook.xml', workbook);
    add('xl/_rels/workbook.xml.rels', workbookRels);
    add('xl/styles.xml', _stylesXml());
    add('xl/worksheets/sheet1.xml', sheet);

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  // ------------------------------------------------------------------ pdf

  /// The built-in PDF font only knows basic Latin, so other characters are
  /// replaced to avoid missing-glyph boxes.
  static String _ascii(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

  static Future<Uint8List> buildPdf(
      List<ChargeView> rows, ExportPeriod period, String kostName) async {
    final today = todayDate();
    final sum = summarize(rows);
    final name = _ascii(kostName.trim().isEmpty ? 'Kost Manager' : kostName.trim());

    final forest = PdfColor.fromHex('#0C3B2E');
    final gold = PdfColor.fromHex('#FFBA00');
    final zebra = PdfColor.fromHex('#F2F5F0');
    final totalBg = PdfColor.fromHex('#E5EBE3');
    final line = PdfColor.fromHex('#D7DFD8');
    final muted = PdfColor.fromHex('#55665D');
    final ink = PdfColor.fromHex('#10241C');

    (PdfColor, PdfColor) statusColors(PaymentStatus s) => switch (s) {
          PaymentStatus.paid => (
              PdfColor.fromHex('#E0EEE2'),
              PdfColor.fromHex('#1D5A3A')
            ),
          PaymentStatus.partial => (
              PdfColor.fromHex('#FFF0C2'),
              PdfColor.fromHex('#7A5400')
            ),
          PaymentStatus.unpaid => (
              PdfColor.fromHex('#DFEAF5'),
              PdfColor.fromHex('#24527A')
            ),
          PaymentStatus.overdue => (
              PdfColor.fromHex('#FBE3DF'),
              PdfColor.fromHex('#B3261E')
            ),
        };

    pw.Widget cell(String text,
        {pw.TextAlign align = pw.TextAlign.left,
        bool bold = false,
        PdfColor? color}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(
          _ascii(text),
          textAlign: align,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? ink,
          ),
        ),
      );
    }

    pw.Widget statusCell(PaymentStatus s) {
      final (bg, fg) = statusColors(s);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: pw.BoxDecoration(
              color: bg,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              _ascii(s.label),
              style: pw.TextStyle(
                  fontSize: 8, fontWeight: pw.FontWeight.bold, color: fg),
            ),
          ),
        ),
      );
    }

    pw.Widget kpi(String label, String value) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 8),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: zebra,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: line, width: 0.6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_ascii(label),
                    style: pw.TextStyle(fontSize: 8.5, color: muted)),
                pw.SizedBox(height: 3),
                pw.Text(_ascii(value),
                    style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: forest)),
              ],
            ),
          ),
        );

    final headers = [
      tr('No.'),
      tr('Tenant'),
      tr('Room'),
      tr('Due date'),
      tr('Period end'),
      tr('Amount'),
      tr('Paid'),
      tr('Remaining'),
      tr('Last payment'),
      tr('Status'),
    ];

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: forest),
        children: [
          for (var i = 0; i < headers.length; i++)
            cell(headers[i],
                bold: true,
                color: PdfColors.white,
                align: (i >= 5 && i <= 7)
                    ? pw.TextAlign.right
                    : (i == 0 || i == 3 || i == 4 || i == 8 || i == 9)
                        ? pw.TextAlign.center
                        : pw.TextAlign.left),
        ],
      ),
      for (var i = 0; i < rows.length; i++)
        pw.TableRow(
          decoration: i.isOdd ? pw.BoxDecoration(color: zebra) : null,
          children: [
            cell('${i + 1}', align: pw.TextAlign.center),
            cell(rows[i].tenantName),
            cell(rows[i].roomName),
            cell(fmtDate(rows[i].charge.dueDate), align: pw.TextAlign.center),
            cell(fmtDate(rows[i].charge.periodEnd), align: pw.TextAlign.center),
            cell(rp(rows[i].charge.amount), align: pw.TextAlign.right),
            cell(rp(rows[i].charge.paidAmount), align: pw.TextAlign.right),
            cell(rp(rows[i].charge.remaining), align: pw.TextAlign.right),
            cell(fmtDate(rows[i].charge.paidDate), align: pw.TextAlign.center),
            statusCell(rows[i].charge.statusOn(today)),
          ],
        ),
      if (rows.isNotEmpty)
        pw.TableRow(
          decoration: pw.BoxDecoration(color: totalBg),
          children: [
            cell(''),
            cell(tr('Total'), bold: true),
            cell(''),
            cell(''),
            cell(''),
            cell(rp(sum.billed), align: pw.TextAlign.right, bold: true),
            cell(rp(sum.collected), align: pw.TextAlign.right, bold: true),
            cell(rp(sum.outstanding), align: pw.TextAlign.right, bold: true),
            cell(''),
            cell(''),
          ],
        ),
    ];

    final doc = pw.Document(title: 'Kost payments ${period.label}');
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _ascii('$name  |  ${tr('Payments report')}'),
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
            pw.Text(
              '${ctx.pageNumber} / ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: pw.BoxDecoration(
              color: forest,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(name,
                        style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white)),
                    pw.SizedBox(height: 3),
                    pw.Text(_ascii(tr('Payments report')),
                        style: pw.TextStyle(fontSize: 11, color: gold)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(_ascii(period.label),
                        style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white)),
                    pw.SizedBox(height: 3),
                    pw.Text(
                        _ascii(tr('Generated on {date}',
                            {'date': fmtDate(today)})),
                        style:
                            pw.TextStyle(fontSize: 9, color: PdfColors.grey300)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              kpi(tr('Billed'), rp(sum.billed)),
              kpi(tr('Collected'), rp(sum.collected)),
              kpi(tr('Outstanding'), rp(sum.outstanding)),
              kpi(tr('Invoices'),
                  '${sum.paidCount} / ${sum.count} ${tr('paid')}'),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: line, width: 0.5),
              bottom: pw.BorderSide(color: line, width: 0.5),
            ),
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: pw.FlexColumnWidth(0.5),
              1: pw.FlexColumnWidth(2.6),
              2: pw.FlexColumnWidth(1.0),
              3: pw.FlexColumnWidth(1.5),
              4: pw.FlexColumnWidth(1.5),
              5: pw.FlexColumnWidth(1.7),
              6: pw.FlexColumnWidth(1.7),
              7: pw.FlexColumnWidth(1.7),
              8: pw.FlexColumnWidth(1.5),
              9: pw.FlexColumnWidth(1.2),
            },
            children: tableRows,
          ),
        ],
      ),
    );
    return doc.save();
  }
}
