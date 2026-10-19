import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/api.dart';
import '../../../shared/state.dart';
import '../../../shared/theme.dart';
import '../../../shared/widgets.dart';

const fxCurrencies = ['USD', 'EUR', 'JPY', 'CNY', 'GBP', 'HKD', 'SGD', 'AUD'];

/// JPY is shown per 100 yen.
int fxUnit(String c) => c == 'JPY' ? 100 : 1;

class FxRates {
  const FxRates(this.krwPerUnit, this.fetchedAt);

  final Map<String, double> krwPerUnit;
  final DateTime fetchedAt;
}

class FxNotifier extends AsyncNotifier<FxRates?> {
  @override
  Future<FxRates?> build() async => null;

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final r = await Api.call('getExchangeRates');
      final rates = Map<String, dynamic>.from(r['rates'] as Map);
      return FxRates({
        for (final e in rates.entries) e.key: (e.value as num).toDouble(),
      }, DateTime.fromMillisecondsSinceEpoch((r['fetchedAt'] as num).toInt()));
    });
  }
}

final fxProvider = AsyncNotifierProvider<FxNotifier, FxRates?>(FxNotifier.new);

class FxTab extends ConsumerStatefulWidget {
  const FxTab({super.key});

  @override
  ConsumerState<FxTab> createState() => _FxTabState();
}

class _FxTabState extends ConsumerState<FxTab> {
  String _currency = 'USD';
  final _foreign = TextEditingController();
  final _krw = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final h = ref.read(calcHandoffProvider);
      if (h != null && h.tab == CalcTab.fx) {
        if (h.currency != null && fxCurrencies.contains(h.currency)) setState(() => _currency = h.currency!);
        final amount = RegExp(r'[0-9]+(\.[0-9]+)?').firstMatch(h.input.replaceAll(',', ''))?.group(0);
        if (amount != null) _foreign.text = amount;
        ref.read(calcHandoffProvider.notifier).set(null);
      }
      if (ref.read(fxProvider).value == null) await ref.read(fxProvider.notifier).load();
      _fromForeign();
    });
  }

  @override
  void dispose() {
    _foreign.dispose();
    _krw.dispose();
    super.dispose();
  }

  double? get _rate => ref.read(fxProvider).value?.krwPerUnit[_currency];

  void _fromForeign() {
    final v = double.tryParse(_foreign.text.replaceAll(',', ''));
    final r = _rate;
    if (v == null || r == null) return;
    _krw.text = (v * r).toStringAsFixed(0);
    setState(() {});
  }

  void _fromKrw() {
    final v = double.tryParse(_krw.text.replaceAll(',', ''));
    final r = _rate;
    if (v == null || r == null || r == 0) return;
    _foreign.text = (v / r).toStringAsFixed(2);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final fx = ref.watch(fxProvider);
    final rates = fx.value;
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle(
                  t.s('환율 환산', 'Currency converter', '為替換算'),
                  trailing: IconButton(
                    tooltip: t.refresh,
                    onPressed: fx.isLoading ? null : () => ref.read(fxProvider.notifier).load().then((_) => _fromForeign()),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                if (fx.hasError)
                  Text(
                    t.s(
                      '환율을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
                      'Could not load exchange rates. Please try again later.',
                      '為替レートを読み込めませんでした。しばらくしてから再度お試しください。',
                    ),
                    style: const TextStyle(color: AppColors.danger),
                  ),
                if (fx.isLoading) const LinearProgressIndicator(),
                if (rates != null) ...[
                  Text('${t.s('기준 시각', 'As of', '基準時刻')}: ${t.dateTime(rates.fetchedAt)}', style: const TextStyle(color: AppColors.sub)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      DropdownButton<String>(
                        value: _currency,
                        items: [for (final c in fxCurrencies) DropdownMenuItem(value: c, child: Text(c))],
                        onChanged: (v) {
                          setState(() => _currency = v!);
                          _fromForeign();
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _foreign,
                          inputFormatters: digits,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: _currency, isDense: true),
                          onChanged: (_) => _fromForeign(),
                        ),
                      ),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Icon(Icons.swap_vert)),
                  TextField(
                    controller: _krw,
                    inputFormatters: digits,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'KRW', isDense: true),
                    onChanged: (_) => _fromKrw(),
                  ),
                ],
              ],
            ),
          ),
          if (rates != null) ...[
            const SizedBox(height: 16),
            PaperCard(
              child: Column(
                children: [
                  for (final c in fxCurrencies)
                    if (rates.krwPerUnit[c] != null)
                      ListTile(
                        dense: true,
                        title: Text('${fxUnit(c)} $c'),
                        trailing: Text(
                          '${t.number(rates.krwPerUnit[c]! * fxUnit(c), decimals: 2)} KRW',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
