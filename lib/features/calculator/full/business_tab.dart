import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/app_text.dart';
import '../../../shared/logic/business_calc.dart';
import '../../../shared/state.dart';
import '../../../shared/widgets.dart';

class BusinessTab extends ConsumerStatefulWidget {
  const BusinessTab({super.key});

  @override
  ConsumerState<BusinessTab> createState() => _BusinessTabState();
}

class _BusinessTabState extends ConsumerState<BusinessTab> {
  final _amount = TextEditingController();
  bool _fromSupply = true;
  final _price = TextEditingController();
  final _rate = TextEditingController();
  final _cost = TextEditingController();
  final _sell = TextEditingController();
  DateTime? _from;
  DateTime? _to;

  @override
  void dispose() {
    for (final c in [_amount, _price, _rate, _cost, _sell]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim());

  Widget _field(TextEditingController c, String label) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: InputDecoration(labelText: label, isDense: true),
    onChanged: (_) => setState(() {}),
  );

  Widget _result(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final won = t.s('원', ' KRW', 'ウォン');
    String money(num v) => '${t.number(v)}$won';
    String pct(double? v) => v == null ? '-' : '${t.number(v, decimals: 1)}%';

    final amount = _num(_amount);
    final vat = amount == null ? null : (_fromSupply ? vatFromSupply(amount.round()) : vatFromTotal(amount.round()));
    final price = _num(_price);
    final rate = _num(_rate);
    final cost = _num(_cost);
    final sell = _num(_sell);
    final df = MaterialLocalizations.of(context);

    final cards = [
      PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(t.s('부가세', 'VAT', '付加価値税')),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(t.s('공급가 → 합계', 'Supply → Total', '供給価額 → 合計'))),
                ButtonSegment(value: false, label: Text(t.s('합계 → 공급가', 'Total → Supply', '合計 → 供給価額'))),
              ],
              selected: {_fromSupply},
              onSelectionChanged: (s) => setState(() => _fromSupply = s.first),
            ),
            const SizedBox(height: 10),
            _field(_amount, _fromSupply ? t.s('공급가', 'Supply amount', '供給価額') : t.s('합계', 'Total', '合計')),
            if (vat != null) ...[
              _result(t.s('공급가', 'Supply amount', '供給価額'), money(vat.supply)),
              _result(t.s('부가세(10%)', 'VAT (10%)', '付加価値税(10%)'), money(vat.vat)),
              _result(t.s('합계', 'Total', '合計'), money(vat.total)),
            ],
          ],
        ),
      ),
      PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(t.s('할인율', 'Discount', '割引率')),
            _field(_price, t.s('정가', 'Price', '定価')),
            const SizedBox(height: 8),
            _field(_rate, t.s('할인율(%)', 'Discount (%)', '割引率(%)')),
            if (price != null && rate != null) ...[
              _result(t.s('할인 금액', 'Discount amount', '割引額'), t.number(price - discountedPrice(price, rate), decimals: 0)),
              _result(t.s('판매가', 'Sale price', '販売価格'), t.number(discountedPrice(price, rate), decimals: 0)),
            ],
            const SizedBox(height: 16),
            SectionTitle(t.s('마진율', 'Margin', 'マージン率')),
            _field(_cost, t.s('원가', 'Cost', '原価')),
            const SizedBox(height: 8),
            _field(_sell, t.s('판매가', 'Sale price', '販売価格')),
            if (cost != null && sell != null) ...[
              _result(t.s('이익', 'Profit', '利益'), t.number(sell - cost)),
              _result(t.s('마진율(판매가 기준)', 'Margin (on price)', 'マージン率(販売価格基準)'), pct(marginRate(cost, sell))),
              _result(t.s('이익률(원가 기준)', 'Markup (on cost)', '利益率(原価基準)'), pct(markupRate(cost, sell))),
            ],
          ],
        ),
      ),
      PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(t.s('날짜 계산', 'Dates', '日付計算')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _pickDate(true),
                  child: Text('${t.s('시작일', 'Start', '開始日')}: ${_from == null ? '-' : df.formatMediumDate(_from!)}'),
                ),
                OutlinedButton(
                  onPressed: () => _pickDate(false),
                  child: Text('${t.s('종료일', 'End', '終了日')}: ${_to == null ? '-' : df.formatMediumDate(_to!)}'),
                ),
              ],
            ),
            if (_from != null && _to != null) ...[
              _result(t.s('날짜 차이', 'Days between', '日数差'), _days(t, daysBetween(_from!, _to!))),
              _result(t.s('영업일 수(주말 제외)', 'Business days (excl. weekends)', '営業日数(週末除く)'), _days(t, businessDays(_from!, _to!))),
            ],
          ],
        ),
      ),
    ];
    return PageBody(
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 600 ? 2 : 1);
          final w = (c.maxWidth - (cols - 1) * 16) / cols;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [for (final card in cards) SizedBox(width: w, child: card)],
          );
        },
      ),
    );
  }

  String _days(AppText t, int n) => t.s('${t.number(n)}일', '${t.number(n)} days', '${t.number(n)}日');
}
