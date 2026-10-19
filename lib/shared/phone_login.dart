import 'app_text.dart';
import '../firebase_options.dart';

String defaultCountryCode(AppLang lang) => lang == AppLang.ja ? '+81' : '+82';

String phonePlaceholder(AppLang lang) => lang == AppLang.ja ? '90-1234-5678' : '10-1234-5678';

/// E.164 digits without '+', or null when the number is not valid.
String? phoneDigits(String countryCode, String local) {
  final cc = countryCode.replaceAll(RegExp(r'[^0-9]'), '');
  var n = local.replaceAll(RegExp(r'[\s\-().]'), '');
  if (cc.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(n)) return null;
  n = n.replaceFirst(RegExp(r'^0+'), '');
  final digits = '$cc$n';
  if (n.length < 7 || digits.length > 15) return null;
  return digits;
}

/// Phone accounts sign in with email/password under this synthetic address. It is never shown or mailed.
String phoneEmail(String digits, {String projectId = DefaultFirebaseOptions.projectId}) => '$digits@phone.$projectId.firebaseapp.com';

bool isPhoneEmail(String? email) => email != null && email.contains('@phone.') && email.endsWith('.firebaseapp.com');

/// Displays a phone account's number as +{digits}.
String? phoneFromEmail(String? email) => isPhoneEmail(email) ? '+${email!.split('@').first}' : null;

bool isValidEmail(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

/// 8+ characters with letters and digits.
bool isValidPassword(String v) => v.length >= 8 && RegExp(r'[A-Za-z]').hasMatch(v) && RegExp(r'[0-9]').hasMatch(v);
