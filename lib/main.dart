import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'app.dart';
import 'core/services/firebase_services.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SkinAiBootstrap()));
}

class SkinAiBootstrap extends StatefulWidget {
  const SkinAiBootstrap({super.key});

  @override
  State<SkinAiBootstrap> createState() =>
      _SkinAiBootstrapState();
}

class _SkinAiBootstrapState extends State<SkinAiBootstrap> {
  bool _ready = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeStorage();
  }

  Future<void> _initializeStorage() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Hive.initFlutter();
      if (!Hive.isBoxOpen('preferences')) {
        await Hive.openBox('preferences');
      }

      const secureStorage = FlutterSecureStorage();
      var encodedKey =
          await secureStorage.read(key: 'scan_box_key');
      if (encodedKey == null) {
        final random = Random.secure();
        encodedKey = base64UrlEncode(
          List<int>.generate(
              32, (_) => random.nextInt(256)),
        );
        await secureStorage.write(
            key: 'scan_box_key', value: encodedKey);
      }

      final cipher = HiveAesCipher(
        base64Url.decode(base64Url.normalize(encodedKey)),
      );
      if (!Hive.isBoxOpen('scans')) {
        await Hive.openBox('scans',
            encryptionCipher: cipher);
      }
      if (!Hive.isBoxOpen('profile')) {
        await Hive.openBox('profile',
            encryptionCipher: cipher);
      }

      var firebaseReady = false;
      try {
        firebaseReady = await FirebaseSetup.initialize();
      } catch (_) {
        firebaseReady = false;
      }
      FirebaseAuthService.instance.markReady(firebaseReady);
      if (firebaseReady) {
        unawaited(FirebaseCloudStore.instance
            .syncLocalData()
            .catchError((_) {}));
      }

      if (!mounted) return;
      setState(() {
        _ready = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'SkinAI Assist could not prepare its secure local storage. Check device storage and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const SkinAiApp();

    return MaterialApp(
      title: 'SkinAI Assist',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/skinai_logo.png',
                    width: 220,
                    height: 220,
                    fit: BoxFit.contain,
                    semanticLabel: 'SkinAI Assist logo',
                  ),
                  const SizedBox(height: 24),
                  if (_loading) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text(
                        'Preparing secure offline storage…'),
                  ] else ...[
                    Text(
                      _error ?? 'Startup could not finish.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _initializeStorage,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
