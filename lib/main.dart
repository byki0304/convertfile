import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/auth/login_page.dart';
import 'firebase_options.dart';
import 'pages/app_shell.dart';
import 'shared/app_text.dart';
import 'shared/state.dart';
import 'shared/theme.dart';
import 'shared/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseStorage.instance.setMaxUploadRetryTime(const Duration(hours: 2));
  await pdfrxFlutterInitialize();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(overrides: [prefsProvider.overrideWithValue(prefs)], child: const ConvertFileApp()));
}

class ConvertFileApp extends ConsumerWidget {
  const ConvertFileApp({super.key, this.home});

  /// Tests inject a home widget instead of the auth gate.
  final Widget? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final reading = ref.watch(readingProvider);
    return MaterialApp(
      title: 'ConvertFile',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(lang, reading),
      locale: Locale(lang.code),
      supportedLocales: [for (final l in AppLang.values) Locale(l.code)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => ReadingScale(settings: reading, child: child!),
      home: home ?? const AuthGate(),
    );
  }
}

/// Applies the 5-step text size to every screen. Line spacing is applied through the theme.
class ReadingScale extends StatelessWidget {
  const ReadingScale({super.key, required this.settings, required this.child});

  final ReadingSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(settings.fontFactor)),
      child: child,
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    return user.when(
      data: (u) => u == null ? const LoginPage() : const AppShell(),
      loading: () => const Scaffold(
        body: GridBackground(child: Center(child: AppLogo(size: 56))),
      ),
      error: (_, _) => const LoginPage(),
    );
  }
}
