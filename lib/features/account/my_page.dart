import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/api.dart';
import '../../shared/app_text.dart';
import '../../shared/errors.dart';
import '../../shared/file_rules.dart';
import '../../shared/phone_login.dart';
import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/auth_service.dart';
import '../convert/conversion_list.dart';
import 'account_actions.dart';

class MyPage extends ConsumerStatefulWidget {
  const MyPage({super.key});

  @override
  ConsumerState<MyPage> createState() => _MyPageState();
}

class _MyPageState extends ConsumerState<MyPage> {
  Map<String, dynamic>? _db;
  bool _dbBusy = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDb());
  }

  Future<void> _loadDb() async {
    setState(() => _dbBusy = true);
    try {
      final r = await Api.call('dbStatus');
      if (mounted) setState(() => _db = r);
    } catch (_) {
      if (mounted) setState(() => _db = null);
    } finally {
      if (mounted) setState(() => _dbBusy = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _dbBusy = true);
    try {
      await Api.call('syncBackup');
    } catch (_) {
      if (mounted) showSnack(context, genericError(ref.read(textProvider)));
    }
    await _loadDb();
  }

  Future<void> _linkGoogle() async {
    final t = ref.read(textProvider);
    setState(() => _busy = true);
    try {
      await AuthService.linkGoogle();
      if (mounted) showSnack(context, t.s('Google 계정을 연결했습니다.', 'Google account linked.', 'Googleアカウントを連携しました。'));
    } catch (e) {
      final m = authErrorMessage(t, e);
      if (m != null && mounted) showSnack(context, m);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetTurns() async {
    final t = ref.read(textProvider);
    final ok = await confirmDialog(
      context,
      t,
      t.s('AI 대화 기록을 모두 지웁니다.', 'All AI chat history will be deleted.', 'AI会話履歴をすべて削除します。'),
      confirmLabel: t.delete,
      danger: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await Api.call('deleteByIds', {'allTurns': true});
      if (mounted) showSnack(context, t.s('AI 대화 기록을 지웠습니다.', 'AI chat history deleted.', 'AI会話履歴を削除しました。'));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, errorMessage(t, e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    final t = ref.read(textProvider);
    final ok = await confirmDialog(
      context,
      t,
      t.s(
        '계정과 변환 기록, 업로드·결과 파일, AI 대화, 사용량 기록을 삭제합니다. 이 기기의 계산 기록도 지워지고, 언어와 글자 설정만 남습니다.',
        'Your account, conversion history, uploaded and result files, AI chats and usage records will be deleted. Calculator history on this device is also erased; only language and text settings remain.',
        'アカウント、変換履歴、アップロード・結果ファイル、AI会話、使用量の記録を削除します。この端末の計算履歴も消え、言語と文字の設定のみ残ります。',
      ),
      confirmLabel: t.s('탈퇴', 'Delete account', '退会'),
      danger: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await Api.call('withdraw');
      ref.read(calcHistoryProvider.notifier).clearAll();
      resetSessionState(ref);
      await AuthService.signOut();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, errorMessage(t, e.code));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final user = ref.watch(authUserProvider).value;
    final guest = user?.isAnonymous ?? true;
    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _profile(t, user, guest),
          const SizedBox(height: 16),
          _UsageCard(guest: guest),
          const SizedBox(height: 16),
          ConversionList(emptyText: t.s('최근 7일 동안 변환한 파일이 없습니다.', 'No conversions in the last 7 days.', '最近7日間に変換したファイルはありません。')),
          const SizedBox(height: 16),
          const _SettingsCard(),
          const SizedBox(height: 16),
          _services(t),
          const SizedBox(height: 16),
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (guest)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _linkGoogle,
                      icon: const Icon(Icons.link),
                      label: Text(t.s('Google 계정 연결', 'Link Google account', 'Googleアカウント連携')),
                    ),
                  ),
                OutlinedButton(
                  onPressed: _busy ? null : _resetTurns,
                  child: Text(t.s('AI 대화 기록 초기화', 'Reset AI chat history', 'AI会話履歴を初期化')),
                ),
                const SizedBox(height: 10),
                Text(t.aiNotice, style: const TextStyle(color: AppColors.sub, fontSize: 12)),
                const SizedBox(height: 10),
                FilledButton(onPressed: _busy ? null : () => logoutFlow(context, ref), child: Text(t.logout)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _withdraw,
                    child: Text(t.s('탈퇴', 'Delete account', '退会'), style: const TextStyle(color: AppColors.danger)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profile(AppText t, User? user, bool guest) {
    final google = isGoogleUser(user);
    final passwordAccount = !guest && user?.email != null && (user?.providerData.any((p) => p.providerId == 'password') ?? false);
    return PaperCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(user: user, radius: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayNameOf(t, user), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                Text('ID: ${accountIdOf(t, user)}', style: const TextStyle(color: AppColors.sub)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    if (google) _pill(t.s('Google 연결됨', 'Google linked', 'Google連携済み'), AppColors.ok),
                    if (guest) _pill(t.guest, AppColors.sub),
                  ],
                ),
                if (!guest) ...[
                  const SizedBox(height: 8),
                  if (passwordAccount)
                    Row(
                      children: [
                        Text('${t.s('비밀번호', 'Password', 'パスワード')}  ••••••••'),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => _PasswordDialog(phone: isPhoneEmail(user?.email)),
                          ),
                          child: Text(t.s('비밀번호 변경', 'Change password', 'パスワード変更')),
                        ),
                      ],
                    )
                  else if (google)
                    Text(
                      t.s(
                        'Google 계정으로 로그인 중입니다. 비밀번호는 Google에서 관리합니다.',
                        'You are signed in with Google. Your password is managed by Google.',
                        'Googleアカウントでログイン中です。パスワードはGoogleで管理されます。',
                      ),
                      style: const TextStyle(color: AppColors.sub),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
    child: Text(
      label,
      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

  Widget _services(AppText t) {
    final db = _db;
    final last = db?['lastMirroredAt'] is num ? DateTime.fromMillisecondsSinceEpoch((db!['lastMirroredAt'] as num).toInt()) : null;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            t.s('연동 서비스', 'Connected services', '連携サービス'),
            trailing: IconButton(tooltip: t.refresh, onPressed: _dbBusy ? null : _loadDb, icon: const Icon(Icons.refresh)),
          ),
          if (_dbBusy) const LinearProgressIndicator(),
          Text(
            'Firebase · ${t.s('주 DB', 'Primary DB', '主DB')} ${db == null ? '-' : t.number(db['primaryCount'] as num)}${t.s('건', '', '件')}',
          ),
          Text(
            'Google Cloud · ${t.s('보조 DB', 'Backup DB', '補助DB')} ${db == null ? '-' : t.number(db['backupCount'] as num)}${t.s('건', '', '件')}',
          ),
          Text(
            '${t.s('마지막 복제', 'Last mirrored', '最終複製')}: ${last == null ? '-' : t.dateTime(last)}',
            style: const TextStyle(color: AppColors.sub),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: _dbBusy ? null : _sync, child: Text(t.s('보조 DB 동기화', 'Sync backup DB', '補助DBを同期'))),
          ),
        ],
      ),
    );
  }
}

class _UsageCard extends ConsumerWidget {
  const _UsageCard({required this.guest});

  final bool guest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    final uid = ref.watch(uidProvider);
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder(
      stream: Api.usage(uid, seoulDay(DateTime.now())).snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data();
        final bytes = (d?['bytes'] as num?)?.toInt() ?? 0;
        final ai = (d?['aiCalls'] as num?)?.toInt() ?? 0;
        final limit = Limits.dailyBytes(guest);
        final aiLimit = Limits.aiCalls(guest);
        return PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(t.s('오늘 사용량', "Today's usage", '本日の使用量')),
              Text('${t.size(bytes)} / ${t.limitLabel(limit)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: (bytes / limit).clamp(0, 1).toDouble(), minHeight: 8),
              const SizedBox(height: 10),
              Text(
                'AI ${t.number(ai)} / ${t.s('$aiLimit회', '$aiLimit', '$aiLimit回')}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: (ai / aiLimit).clamp(0, 1).toDouble(), minHeight: 8, color: AppColors.accent),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsCard extends ConsumerWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    final lang = ref.watch(langProvider);
    final reading = ref.watch(readingProvider);
    Widget steps(String label, int value, ValueChanged<int> onChanged) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (var i = 1; i <= 5; i++) ChoiceChip(label: Text('$i'), selected: value == i, onSelected: (_) => onChanged(i))],
        ),
      ],
    );
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(t.s('설정', 'Settings', '設定')),
          Text(t.language, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (final l in AppLang.values)
                ChoiceChip(label: Text(l.label), selected: lang == l, onSelected: (_) => ref.read(langProvider.notifier).set(l)),
            ],
          ),
          const SizedBox(height: 12),
          steps(t.fontSize, reading.fontLevel, ref.read(readingProvider.notifier).setFont),
          const SizedBox(height: 12),
          steps(t.lineSpacing, reading.lineLevel, ref.read(readingProvider.notifier).setLine),
        ],
      ),
    );
  }
}

class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog({required this.phone});

  final bool phone;

  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final _cur = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _cur.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = ref.read(textProvider);
    if (!isValidPassword(_next.text)) return setState(() => _error = passwordRuleText(t));
    if (_next.text != _confirm.text) {
      return setState(() => _error = t.s('비밀번호가 서로 다릅니다.', 'The passwords do not match.', 'パスワードが一致しません。'));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.changePassword(_cur.text, _next.text);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, t.s('비밀번호를 변경했습니다.', 'Password changed.', 'パスワードを変更しました。'));
    } on FirebaseAuthException catch (e) {
      final wrong = const {'wrong-password', 'invalid-credential', 'invalid-login-credentials'}.contains(e.code);
      setState(
        () =>
            _error = wrong ? t.s('현재 비밀번호가 맞지 않습니다.', 'The current password is incorrect.', '現在のパスワードが正しくありません。') : authErrorMessage(t, e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    return AlertDialog(
      title: Text(t.s('비밀번호 변경', 'Change password', 'パスワード変更')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _cur,
              obscureText: true,
              decoration: InputDecoration(labelText: t.s('현재 비밀번호', 'Current password', '現在のパスワード')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _next,
              obscureText: true,
              decoration: InputDecoration(labelText: t.s('새 비밀번호', 'New password', '新しいパスワード')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: InputDecoration(labelText: t.s('비밀번호 확인', 'Confirm password', 'パスワード確認')),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(t.confirm)),
      ],
    );
  }
}
