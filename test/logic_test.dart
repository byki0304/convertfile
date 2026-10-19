import 'dart:ui';

import 'package:convertfile/shared/api.dart';
import 'package:convertfile/shared/file_rules.dart';
import 'package:convertfile/shared/logic/business_calc.dart';
import 'package:convertfile/shared/logic/calc_engine.dart';
import 'package:convertfile/shared/logic/frame.dart';
import 'package:convertfile/shared/logic/pdf_logic.dart';
import 'package:convertfile/shared/phone_login.dart';
import 'package:convertfile/shared/app_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('frame', () {
    test('portrait when width <= height', () {
      expect(frameOf(const Size(390, 844)), AppFrame.phonePortrait);
      expect(frameOf(const Size(800, 800)), AppFrame.phonePortrait);
    });
    test('phone landscape when short or narrow', () {
      expect(frameOf(const Size(844, 390)), AppFrame.phoneLandscape);
      expect(frameOf(const Size(819, 700)), AppFrame.phoneLandscape);
    });
    test('desktop otherwise', () {
      expect(frameOf(const Size(1280, 800)), AppFrame.desktop);
      expect(frameOf(const Size(820, 600)), AppFrame.desktop);
    });
    test('popup position is kept inside the area', () {
      expect(clampInside(const Offset(-20, 900), const Size(260, 380), const Size(1000, 700)), const Offset(0, 320));
      expect(clampInside(const Offset(16, 16), const Size(260, 380), const Size(1000, 700)), const Offset(16, 16));
    });
  });

  group('format table', () {
    test('accepts listed inputs', () {
      expect(checkFormat(TargetFormat.pdf, 'hwp'), RuleResult.ok);
      expect(checkFormat(TargetFormat.pptx, 'xlsx'), RuleResult.ok);
      expect(checkFormat(TargetFormat.md, 'hwt'), RuleResult.ok);
    });
    test('rejects unknown or macro files', () {
      expect(checkFormat(TargetFormat.pdf, 'docm'), RuleResult.unsupported);
      expect(checkFormat(TargetFormat.txt, 'png'), RuleResult.unsupported);
      expect(checkFormat(TargetFormat.pdf, 'pdf'), RuleResult.sameFormat);
    });
    test('same format by family', () {
      expect(checkFormat(TargetFormat.docx, 'doc'), RuleResult.sameFormat);
      expect(checkFormat(TargetFormat.hwpx, 'hwp'), RuleResult.sameFormat);
      expect(checkFormat(TargetFormat.hwpx, 'hwt'), RuleResult.sameFormat);
      expect(checkFormat(TargetFormat.xlsx, 'xls'), RuleResult.sameFormat);
    });
    test('modes and AI need', () {
      expect(modeOf(TargetFormat.pdf, 'docx'), ConvertMode.layout);
      expect(modeOf(TargetFormat.docx, 'hwp'), ConvertMode.layout);
      expect(modeOf(TargetFormat.docx, 'pptx'), ConvertMode.content);
      expect(modeOf(TargetFormat.xlsx, 'md'), ConvertMode.table);
      expect(needsAi(TargetFormat.md, 'pdf'), isTrue);
      expect(needsAi(TargetFormat.pptx, 'xlsx'), isFalse);
      expect(needsAi(TargetFormat.pptx, 'docx'), isTrue);
      expect(needsAi(TargetFormat.pdf, 'docx'), isFalse);
    });
    test('output name keeps the original name', () {
      expect(outputNameOf('보고서.v2.hwp', TargetFormat.pdf), '보고서.v2.pdf');
    });
  });

  group('limits', () {
    test('file size boundaries', () {
      expect(Limits.fileBytes(false), 1073741824);
      expect(Limits.fileBytes(true), 104857600);
      expect(Limits.aiCalls(false), 200);
      expect(Limits.aiCalls(true), 30);
    });
    test('pdf tool totals and 300MB warning', () {
      expect(checkPdfToolSize(300 * 1024 * 1024, guest: false), PdfSizeCheck.ok);
      expect(checkPdfToolSize(300 * 1024 * 1024 + 1, guest: false), PdfSizeCheck.warn);
      expect(checkPdfToolSize(1073741824, guest: false), PdfSizeCheck.warn);
      expect(checkPdfToolSize(1073741825, guest: false), PdfSizeCheck.tooLarge);
      expect(checkPdfToolSize(104857600, guest: true), PdfSizeCheck.ok);
      expect(checkPdfToolSize(104857601, guest: true), PdfSizeCheck.tooLarge);
    });
  });

  group('calculator', () {
    const c = CalcEngine();
    test('arithmetic and precedence', () {
      expect(c.evaluate('1+2×3'), 7);
      expect(c.evaluate('(1+2)×3'), 9);
      expect(c.evaluate('10÷4'), 2.5);
      expect(c.evaluate('-3+5'), 2);
      expect(c.evaluate('50%'), 0.5);
    });
    test('divide by zero', () {
      expect(() => c.evaluate('1÷0'), throwsA(isA<CalcException>()));
    });
    test('scientific functions', () {
      expect(c.evaluate('sin(30)'), closeTo(0.5, 1e-9));
      expect(c.evaluate('cos(90)'), 0);
      expect(const CalcEngine(degrees: false).evaluate('sin(π÷2)'), closeTo(1, 1e-9));
      expect(c.evaluate('log(1000)'), closeTo(3, 1e-9));
      expect(c.evaluate('ln(e)'), closeTo(1, 1e-9));
      expect(c.evaluate('√(16)'), 4);
      expect(c.evaluate('2^10'), 1024);
      expect(c.evaluate('2π'), closeTo(6.283185307, 1e-6));
      expect(() => c.evaluate('tan(90)'), throwsA(isA<CalcException>()));
      expect(() => c.evaluate('log(0)'), throwsA(isA<CalcException>()));
    });
    test('formatting', () {
      expect(CalcEngine.format(3), '3');
      expect(CalcEngine.format(0.1 + 0.2), '0.3');
    });
  });

  group('business', () {
    test('VAT both ways', () {
      final a = vatFromSupply(10000);
      expect([a.supply, a.vat, a.total], [10000, 1000, 11000]);
      final b = vatFromTotal(11000);
      expect([b.supply, b.vat, b.total], [10000, 1000, 11000]);
    });
    test('discount and margin', () {
      expect(discountedPrice(20000, 15), 17000);
      expect(marginRate(7000, 10000), closeTo(30, 1e-9));
      expect(markupRate(8000, 10000), closeTo(25, 1e-9));
      expect(marginRate(1, 0), isNull);
    });
    test('business days', () {
      expect(businessDays(DateTime(2026, 10, 19), DateTime(2026, 10, 25)), 5);
      expect(businessDays(DateTime(2026, 10, 25), DateTime(2026, 10, 19)), 5);
      expect(businessDays(DateTime(2026, 10, 24), DateTime(2026, 10, 25)), 0);
      expect(businessDays(DateTime(2026, 10, 1), DateTime(2026, 10, 31)), 22);
      expect(daysBetween(DateTime(2026, 1, 1), DateTime(2026, 12, 31)), 364);
    });
  });

  group('pdf logic', () {
    test('merge slots grow 5 to 20 and keep order', () {
      final m = MergeSlots<String>();
      expect(m.visible, 5);
      final left = m.addAll(List.generate(22, (i) => 'f$i'));
      expect(m.visible, 20);
      expect(left, 2);
      expect(m.filled.first, 'f0');
      m.move(0, 2);
      expect(m.filled.take(3), ['f1', 'f2', 'f0']);
      m.removeAt(0);
      expect(m.filled.first, 'f2');
    });
    test('edit move, delete, selected order, undo', () {
      final e = PdfEditModel(5);
      e.move(0, 4);
      expect(e.pages, [1, 2, 3, 4, 0]);
      e.toggle(0);
      e.toggle(2);
      expect(e.selectedInOrder, [2, 0]);
      e.deleteSelected();
      expect(e.pages, [1, 3, 4]);
      e.undo();
      expect(e.pages, [1, 2, 3, 4, 0]);
      e.undo();
      expect(e.pages, [0, 1, 2, 3, 4]);
      expect(e.canUndo, isFalse);
    });
    test('merged file name', () {
      expect(mergedFileName(DateTime(2026, 10, 19, 9, 5)), 'merged_20261019_0905.pdf');
    });
  });

  group('phone login', () {
    test('builds the synthetic email', () {
      expect(phoneDigits('+82', '010-1234-5678'), '821012345678');
      expect(phoneDigits('+81', '90-1234-5678'), '819012345678');
      expect(phoneDigits('+82', 'abc'), isNull);
      expect(phoneEmail('821012345678'), '821012345678@phone.convertfile-9b293.firebaseapp.com');
      expect(phoneFromEmail('821012345678@phone.convertfile-9b293.firebaseapp.com'), '+821012345678');
      expect(defaultCountryCode(AppLang.ja), '+81');
      expect(defaultCountryCode(AppLang.en), '+82');
    });
    test('password rule', () {
      expect(isValidPassword('abcd1234'), isTrue);
      expect(isValidPassword('abcdefgh'), isFalse);
      expect(isValidPassword('a1'), isFalse);
    });
  });

  group('expiry', () {
    test('168h expiry hides rows', () {
      final now = DateTime(2026, 10, 19, 12);
      final c = Conversion('x', {'expireAt': now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch});
      expect(c.expiredAt(now), isTrue);
      final d = Conversion('y', {'expireAt': now.add(const Duration(hours: 167, minutes: 30)).millisecondsSinceEpoch});
      expect(d.expiredAt(now), isFalse);
      expect(d.hoursLeft(now), 168);
    });
    test('seoul day boundary', () {
      expect(seoulDay(DateTime.utc(2026, 10, 18, 14, 59)), '20261018');
      expect(seoulDay(DateTime.utc(2026, 10, 18, 15, 0)), '20261019');
    });
  });
}
