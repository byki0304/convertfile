import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/app_text.dart';
import '../../shared/phone_login.dart';
import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'auth_service.dart';

enum _Mode { choose, email, phone }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  _Mode _mode = _Mode.choose;
  bool _signUp = false;
  bool _keep = true;
  bool _busy = false;
  bool _showPw = false;
  String? _error;
  String? _info;
  String? _country;
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {bool phone = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(ref.read(textProvider), e, phone: phone));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final t = ref.read(textProvider);
    final lang = ref.read(langProvider);
    final phone = _mode == _Mode.phone;
    String email;
    if (phone) {
      final digits = phoneDigits(_country ?? defaultCountryCode(lang), _id.text);
      if (digits == null) {
        return setState(() => _error = t.s('휴대폰번호를 확인해 주세요.', 'Check the phone number.', '携帯電話番号を確認してください。'));
      }
      email = phoneEmail(digits);
    } else {
      if (!isValidEmail(_id.text)) {
        return setState(() => _error = t.s('이메일 형식이 올바르지 않습니다.', 'The email format is invalid.', 'メールアドレスの形式が正しくありません。'));
      }
      email = _id.text.trim();
    }
    if (_signUp) {
      if (!isValidPassword(_pw.text)) return setState(() => _error = passwordRuleText(t));
      if (_pw.text != _pw2.text) {
        return setState(() => _error = t.s('비밀번호가 서로 다릅니다.', 'The passwords do not match.', 'パスワードが一致しません。'));
      }
      await _run(() => AuthService.signUp(email, _pw.text, keep: _keep), phone: phone);
    } else {
      await _run(() => AuthService.signIn(email, _pw.text, keep: _keep), phone: phone);
    }
  }

  Future<void> _reset() async {
    final t = ref.read(textProvider);
    if (!isValidEmail(_id.text)) {
      return setState(() => _error = t.s('이메일 형식이 올바르지 않습니다.', 'The email format is invalid.', 'メールアドレスの形式が正しくありません。'));
    }
    await _run(() async {
      await AuthService.resetPassword(_id.text);
      if (mounted) {
        setState(() => _info = t.s('비밀번호 재설정 메일을 보냈습니다.', 'A password reset email has been sent.', 'パスワード再設定メールを送信しました。'));
      }
    });
  }

  void _open(_Mode m, {bool signUp = false}) => setState(() {
    _mode = m;
    _signUp = signUp;
    _error = null;
    _info = null;
    _pw.clear();
    _pw2.clear();
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final lang = ref.watch(langProvider);
    return Scaffold(
      body: GridBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: PaperCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      label: 'ConvertFile',
                      header: true,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: 724 / 440,
                          child: Image.asset(
                            'assets/brand/hero.jpg',
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                            errorBuilder: (_, _, _) => const Center(child: AppLogo(size: 48)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t.tagline,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.sub),
                    ),
                    const SizedBox(height: 20),
                    if (_mode == _Mode.choose) ..._chooser(t) else ..._form(t, lang),
                    if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: AppColors.danger))],
                    if (_info != null) ...[const SizedBox(height: 12), Text(_info!, style: const TextStyle(color: AppColors.ok))],
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _keep,
                      onChanged: (v) => setState(() => _keep = v ?? true),
                      title: Text(t.s('로그인 상태 유지', 'Keep me signed in', 'ログイン状態を保持')),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        for (final l in AppLang.values)
                          ChoiceChip(label: Text(l.label), selected: lang == l, onSelected: (_) => ref.read(langProvider.notifier).set(l)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _chooser(AppText t) {
    Widget btn(String label, IconData icon, VoidCallback? onTap, {bool primary = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: primary
          ? FilledButton.icon(onPressed: _busy ? null : onTap, icon: Icon(icon), label: Text(label))
          : OutlinedButton.icon(onPressed: _busy ? null : onTap, icon: Icon(icon), label: Text(label)),
    );
    return [
      btn(t.s('이메일 로그인', 'Log in with email', 'メールでログイン'), Icons.mail_outline, () => _open(_Mode.email), primary: true),
      btn(t.s('휴대폰번호 로그인', 'Log in with phone number', '携帯電話番号でログイン'), Icons.phone_iphone, () => _open(_Mode.phone)),
      btn(
        t.s('Google로 로그인', 'Log in with Google', 'Googleでログイン'),
        Icons.account_circle_outlined,
        () => _run(() => AuthService.google(keep: _keep)),
      ),
      btn(t.s('게스트로 시작', 'Start as guest', 'ゲストで始める'), Icons.person_outline, () => _run(() => AuthService.guest(keep: _keep))),
      TextButton(
        onPressed: _busy ? null : () => _open(_Mode.email, signUp: true),
        child: Text(t.s('처음이면 신규가입', 'New here? Sign up', '初めての方は新規登録')),
      ),
      if (_busy) const LinearProgressIndicator(),
    ];
  }

  List<Widget> _form(AppText t, AppLang lang) {
    final phone = _mode == _Mode.phone;
    final title = _signUp
        ? (phone ? t.s('휴대폰번호 가입', 'Sign up with phone number', '携帯電話番号で登録') : t.s('이메일 가입', 'Sign up with email', 'メールで登録'))
        : (phone ? t.s('휴대폰번호 로그인', 'Log in with phone number', '携帯電話番号でログイン') : t.s('이메일 로그인', 'Log in with email', 'メールでログイン'));
    final pwLabel = t.s('비밀번호', 'Password', 'パスワード');
    return [
      Row(
        children: [
          IconButton(tooltip: t.s('뒤로', 'Back', '戻る'), onPressed: () => _open(_Mode.choose), icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (phone)
        Row(
          children: [
            DropdownButton<String>(
              value: _country ?? defaultCountryCode(lang),
              items: const [
                DropdownMenuItem(value: '+82', child: Text('+82')),
                DropdownMenuItem(value: '+81', child: Text('+81')),
                DropdownMenuItem(value: '+1', child: Text('+1')),
              ],
              onChanged: (v) => setState(() => _country = v),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _id,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t.s('휴대폰번호', 'Phone number', '携帯電話番号'), hintText: phonePlaceholder(lang)),
              ),
            ),
          ],
        )
      else
        TextField(
          controller: _id,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(labelText: t.s('이메일', 'Email', 'メールアドレス'), hintText: 'example@email.com'),
        ),
      const SizedBox(height: 10),
      TextField(
        controller: _pw,
        obscureText: !_showPw,
        onSubmitted: _signUp ? null : (_) => _submit(),
        decoration: InputDecoration(
          labelText: pwLabel,
          suffixIcon: IconButton(
            tooltip: t.s('비밀번호 보기', 'Show password', 'パスワードを表示'),
            icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showPw = !_showPw),
          ),
        ),
      ),
      if (_signUp) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _pw2,
          obscureText: !_showPw,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: t.s('비밀번호 확인', 'Confirm password', 'パスワード確認')),
        ),
        const SizedBox(height: 4),
        Text(passwordRuleText(t), style: const TextStyle(color: AppColors.sub, fontSize: 12)),
      ],
      const SizedBox(height: 14),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(_signUp ? t.s('가입하기', 'Sign up', '登録する') : t.s('로그인', 'Log in', 'ログイン')),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => setState(() => _signUp = !_signUp),
            child: Text(_signUp ? t.s('로그인으로', 'Back to log in', 'ログインへ') : t.s('신규가입', 'Sign up', '新規登録')),
          ),
          if (!phone && !_signUp) TextButton(onPressed: _busy ? null : _reset, child: Text(t.s('비밀번호 찾기', 'Forgot password', 'パスワードを忘れた'))),
        ],
      ),
    ];
  }
}
