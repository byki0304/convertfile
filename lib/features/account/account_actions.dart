import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/app_text.dart';
import '../../shared/phone_login.dart';
import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../ai_home/ai_home_state.dart';
import '../auth/auth_service.dart';
import '../pdf_edit/pdf_edit_page.dart';
import '../pdf_merge/pdf_merge_page.dart';

bool isGoogleUser(User? u) => u?.providerData.any((p) => p.providerId == 'google.com') ?? false;

/// Google name → phone number → email local part → 게스트.
String displayNameOf(AppText t, User? u) {
  if (u == null || u.isAnonymous) return t.guest;
  final name = u.displayName;
  if (name != null && name.trim().isNotEmpty) return name;
  final phone = phoneFromEmail(u.email);
  if (phone != null) return phone;
  final email = u.email;
  if (email != null && email.contains('@')) return email.split('@').first;
  return t.guest;
}

/// Email or phone number; 게스트 for guests.
String accountIdOf(AppText t, User? u) {
  if (u == null || u.isAnonymous) return t.guest;
  return phoneFromEmail(u.email) ?? u.email ?? '-';
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.radius = 18});

  final User? user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = user?.photoURL;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.ink, width: 1.4),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.accent,
        foregroundImage: photo != null ? NetworkImage(photo) : null,
        child: Icon(Icons.person, size: radius * 1.1, color: AppColors.ink),
      ),
    );
  }
}

void resetSessionState(WidgetRef ref) {
  ref.read(navProvider.notifier).leaveGuard = null;
  for (final p in [
    navProvider,
    basicCalcProvider,
    sciCalcProvider,
    calcHandoffProvider,
    convertHandoffProvider,
    pdfHandoffProvider,
    backupModeProvider,
    aiDraftProvider,
    mergeStateProvider,
    editStateProvider,
  ]) {
    ref.invalidate(p);
  }
}

Future<void> logoutFlow(BuildContext context, WidgetRef ref) async {
  final t = ref.read(textProvider);
  final user = FirebaseAuth.instance.currentUser;
  if (user != null && user.isAnonymous) {
    final ok = await confirmDialog(
      context,
      t,
      t.s(
        '게스트로 로그아웃하면 이 기록으로 다시 들어올 수 없습니다. 먼저 Google 계정을 연결하면 기록이 유지됩니다.',
        'If you log out as a guest, you cannot return to these records. Link a Google account first to keep them.',
        'ゲストでログアウトすると、この記録には戻れません。先にGoogleアカウントを連携すると記録が保持されます。',
      ),
      confirmLabel: t.logout,
      danger: true,
    );
    if (!ok) return;
  }
  resetSessionState(ref);
  await AuthService.signOut();
}
