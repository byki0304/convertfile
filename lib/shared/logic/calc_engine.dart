import 'dart:math' as math;

class CalcException implements Exception {
  const CalcException(this.code);

  final String code;

  @override
  String toString() => 'CalcException($code)';
}

/// Expression evaluator for the basic and scientific calculators.
/// Supports + - × ÷ ^ %, parentheses, unary minus, π, e, and sin cos tan log ln √.
class CalcEngine {
  const CalcEngine({this.degrees = true});

  final bool degrees;

  static const functions = {'sin', 'cos', 'tan', 'log', 'ln', '√'};

  double evaluate(String expression) {
    final tokens = _tokenize(expression);
    if (tokens.isEmpty) throw const CalcException('empty');
    final p = _Parser(tokens, this);
    final v = p.parseExpression();
    if (!p.done) throw const CalcException('syntax');
    if (v.isNaN || v.isInfinite) throw const CalcException('math');
    return v;
  }

  List<String> _tokenize(String src) {
    final out = <String>[];
    var i = 0;
    final s = src.replaceAll(' ', '').replaceAll('*', '×').replaceAll('/', '÷').replaceAll('sqrt', '√').replaceAll('pi', 'π');
    while (i < s.length) {
      final c = s[i];
      if (RegExp(r'[0-9.]').hasMatch(c)) {
        final start = i;
        while (i < s.length && RegExp(r'[0-9.]').hasMatch(s[i])) {
          i++;
        }
        final n = s.substring(start, i);
        if ('.'.allMatches(n).length > 1) throw const CalcException('syntax');
        out.add(n);
        continue;
      }
      if ('+-×÷^()%πe√'.contains(c)) {
        out.add(c);
        i++;
        continue;
      }
      final word = RegExp(r'^(sin|cos|tan|log|ln)').firstMatch(s.substring(i));
      if (word != null) {
        out.add(word.group(0)!);
        i += word.group(0)!.length;
        continue;
      }
      throw const CalcException('syntax');
    }
    return out;
  }

  double applyFunction(String f, double x) {
    double rad(double v) => degrees ? v * math.pi / 180 : v;
    double clean(double v) => v.abs() < 1e-12 ? 0 : v;
    switch (f) {
      case 'sin':
        return clean(math.sin(rad(x)));
      case 'cos':
        return clean(math.cos(rad(x)));
      case 'tan':
        final c = math.cos(rad(x));
        if (c.abs() < 1e-12) throw const CalcException('math');
        return clean(math.sin(rad(x)) / c);
      case 'log':
        if (x <= 0) throw const CalcException('math');
        return math.log(x) / math.ln10;
      case 'ln':
        if (x <= 0) throw const CalcException('math');
        return math.log(x);
      case '√':
        if (x < 0) throw const CalcException('math');
        return math.sqrt(x);
    }
    throw const CalcException('syntax');
  }

  static String format(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    var s = v.toStringAsPrecision(12);
    if (s.contains('e')) return s;
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }
}

class _Parser {
  _Parser(this.t, this.engine);

  final List<String> t;
  final CalcEngine engine;
  int i = 0;

  bool get done => i >= t.length;
  String? get peek => done ? null : t[i];

  double parseExpression() {
    var v = parseTerm();
    while (peek == '+' || peek == '-') {
      final op = t[i++];
      final r = parseTerm();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double parseTerm() {
    var v = parseFactor();
    while (true) {
      final p = peek;
      if (p == '×' || p == '÷') {
        i++;
        final r = parseFactor();
        if (p == '÷') {
          if (r == 0) throw const CalcException('divide-by-zero');
          v = v / r;
        } else {
          v = v * r;
        }
      } else if (p != null && (p == '(' || p == 'π' || p == 'e' || CalcEngine.functions.contains(p))) {
        v = v * parseFactor();
      } else {
        return v;
      }
    }
  }

  double parseFactor() {
    final base = parseUnary();
    if (peek == '^') {
      i++;
      final exp = parseFactor();
      final r = math.pow(base, exp).toDouble();
      if (r.isNaN) throw const CalcException('math');
      return r;
    }
    return base;
  }

  double parseUnary() {
    if (peek == '-') {
      i++;
      return -parseUnary();
    }
    if (peek == '+') {
      i++;
      return parseUnary();
    }
    return parsePostfix();
  }

  double parsePostfix() {
    var v = parsePrimary();
    while (peek == '%') {
      i++;
      v = v / 100;
    }
    return v;
  }

  double parsePrimary() {
    final p = peek;
    if (p == null) throw const CalcException('syntax');
    if (p == '(') {
      i++;
      final v = parseExpression();
      if (peek == ')') i++;
      return v;
    }
    if (p == 'π') {
      i++;
      return math.pi;
    }
    if (p == 'e') {
      i++;
      return math.e;
    }
    if (CalcEngine.functions.contains(p)) {
      i++;
      return engine.applyFunction(p, parseUnary());
    }
    final n = double.tryParse(p);
    if (n == null) throw const CalcException('syntax');
    i++;
    return n;
  }
}
