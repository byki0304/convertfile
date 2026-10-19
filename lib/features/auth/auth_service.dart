import 'package:firebase_auth/firebase_auth.dart';

import '../../shared/app_text.dart';

class AuthService {
  AuthService._();

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static Future<void> _persist(bool keep) => _auth.setPersistence(keep ? Persistence.LOCAL : Persistence.SESSION);

  static Future<void> signIn(String email, String password, {required bool keep}) async {
    await _persist(keep);
    await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  static Future<void> signUp(String email, String password, {required bool keep}) async {
    await _persist(keep);
    await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
  }

  static Future<void> google({required bool keep}) async {
    await _persist(keep);
    await _auth.signInWithPopup(GoogleAuthProvider());
  }

  static Future<void> guest({required bool keep}) async {
    await _persist(keep);
    await _auth.signInAnonymously();
  }

  static Future<void> resetPassword(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  /// Links the anonymous account to Google; the uid and its data stay the same.
  static Future<void> linkGoogle() async {
    await _auth.currentUser!.linkWithPopup(GoogleAuthProvider());
  }

  static Future<void> changePassword(String current, String next) async {
    final user = _auth.currentUser!;
    final cred = EmailAuthProvider.credential(email: user.email!, password: current);
    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(next);
  }

  static Future<void> signOut() => _auth.signOut();
}

/// Returns null for silent cases (popup closed by the user).
String? authErrorMessage(AppText t, Object e, {bool phone = false}) {
  final code = e is FirebaseAuthException ? e.code : '';
  switch (code) {
    case 'popup-closed-by-user':
    case 'cancelled-popup-request':
      return null;
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
    case 'invalid-email':
    case 'invalid-login-credentials':
      return phone
          ? t.s('휴대폰번호 또는 비밀번호가 맞지 않습니다.', 'Phone number or password is incorrect.', '携帯電話番号またはパスワードが正しくありません。')
          : t.s('이메일 또는 비밀번호가 맞지 않습니다.', 'Email or password is incorrect.', 'メールアドレスまたはパスワードが正しくありません。');
    case 'too-many-requests':
      return t.s('요청이 많습니다. 잠시 후 다시 시도해 주세요.', 'Too many requests. Please try again later.', 'リクエストが多すぎます。しばらくしてから再度お試しください。');
    case 'operation-not-allowed':
    case 'admin-restricted-operation':
      return t.s('이 로그인 방법이 아직 활성화되지 않았습니다.', 'This sign-in method is not enabled yet.', 'このログイン方法はまだ有効になっていません。');
    case 'email-already-in-use':
      return phone
          ? t.s('이미 가입된 휴대폰번호입니다.', 'This phone number is already registered.', 'この携帯電話番号はすでに登録されています。')
          : t.s('이미 가입된 이메일입니다.', 'This email is already registered.', 'このメールアドレスはすでに登録されています。');
    case 'credential-already-in-use':
      return t.s(
        '이 Google 계정은 이미 다른 계정에 연결되어 있습니다.',
        'This Google account is already linked to another account.',
        'このGoogleアカウントはすでに別のアカウントに連携されています。',
      );
    case 'weak-password':
      return passwordRuleText(t);
    default:
      return t.s('연결을 확인한 뒤 다시 시도해 주세요.', 'Check your connection and try again.', '接続を確認してから再度お試しください。');
  }
}

String passwordRuleText(AppText t) =>
    t.s('비밀번호는 영문과 숫자를 포함해 8자 이상이어야 합니다.', 'Use at least 8 characters with letters and numbers.', 'パスワードは英字と数字を含む8文字以上にしてください。');
