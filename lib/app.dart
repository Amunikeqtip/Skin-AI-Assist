import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/presentation/home_screen.dart';
import 'features/education/presentation/education_screen.dart';
import 'features/history/presentation/history_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/scan/presentation/scan_flow.dart';

class SkinAiApp extends StatelessWidget {
  const SkinAiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'SkinAI Assist',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        routerConfig: _router,
      );
}

final _router = GoRouter(
  initialLocation: Hive.box('preferences')
          .get('accepted', defaultValue: false)
      ? '/'
      : '/disclaimer',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(
          location: state.matchedLocation, child: child),
      routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => const HomeScreen()),
        GoRoute(
            path: '/scan',
            builder: (_, __) => const ScanFlow()),
        GoRoute(
            path: '/history',
            builder: (_, __) => const HistoryScreen()),
        GoRoute(
            path: '/learn',
            builder: (_, __) => const EducationScreen()),
        GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfileScreen()),
      ],
    ),
    GoRoute(
        path: '/disclaimer',
        builder: (_, __) => const DisclaimerScreen()),
    GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen()),
  ],
);

class AppShell extends StatelessWidget {
  const AppShell(
      {super.key,
      required this.child,
      required this.location});
  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context) {
    const paths = [
      '/',
      '/scan',
      '/history',
      '/learn',
      '/profile'
    ];
    final selectedIndex =
        paths.indexOf(location).clamp(0, paths.length - 1);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) =>
            context.go(paths[index]),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.center_focus_weak),
              label: 'Scan'),
          NavigationDestination(
              icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              label: 'Learn'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Profile'),
        ],
      ),
    );
  }
}

class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/images/skinai_logo.png',
                    width: 100, height: 100),
                const SizedBox(height: 24),
                Text('Important notice',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium),
                const SizedBox(height: 16),
                const Text(
                    'SkinAI Assist does not provide medical diagnoses. Results are generated using machine learning and may be inaccurate. Always consult a qualified healthcare professional for medical advice.'),
                const SizedBox(height: 24),
                const Text(
                    'Your photos stay on this device. This educational screening aid cannot replace professional care.'),
                const SizedBox(height: 30),
                FilledButton(
                  onPressed: () {
                    Hive.box('preferences')
                        .put('accepted', true);
                    context.go('/onboarding');
                  },
                  child: const Text('Accept and continue'),
                ),
              ],
            ),
          ),
        ),
      );
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() =>
      _OnboardingScreenState();
}

class _OnboardingScreenState
    extends State<OnboardingScreen> {
  int page = 0;
  final pages = [
    (
      'Take a clear photo',
      'Use steady hands and bright, even light.',
      Icons.camera_alt_outlined
    ),
    (
      'Let AI analyse',
      'On-device screening helps you learn about common skin concerns.',
      Icons.auto_awesome_outlined
    ),
    (
      'Receive guidance',
      'Explore educational information and know when to seek professional care.',
      Icons.health_and_safety_outlined
    ),
  ];

  void finish() => context.go('/');

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: finish,
                      child: const Text('Skip')),
                ),
                const Spacer(),
                Icon(pages[page].$3,
                    size: 100, color: AppTheme.blue),
                const SizedBox(height: 30),
                Text(pages[page].$1,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(pages[page].$2,
                    textAlign: TextAlign.center),
                const Spacer(),
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: List.generate(
                    pages.length,
                    (index) => Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index == page
                            ? AppTheme.blue
                            : Colors.grey.shade300,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () {
                    if (page < pages.length - 1) {
                      setState(() => page++);
                    } else {
                      finish();
                    }
                  },
                  child: Text(page == pages.length - 1
                      ? 'Get started'
                      : 'Next'),
                ),
              ],
            ),
          ),
        ),
      );
}
