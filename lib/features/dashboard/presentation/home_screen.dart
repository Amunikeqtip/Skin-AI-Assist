import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Image.asset(
                      'assets/images/skinai_logo.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text('SkinAI Assist',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    fontWeight:
                                        FontWeight.bold)),
                        const Text(
                            'Your skin health companion'),
                      ],
                    ),
                  ),
                  IconButton(
                      onPressed: () =>
                          context.go('/profile'),
                      icon:
                          const Icon(Icons.person_outline)),
                ],
              ),
              const SizedBox(height: 20),
              const NoticeBanner(),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    Color(0xff1976d2),
                    Color(0xff42a5f5)
                  ]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'A little care goes a long way',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        'Check in with your skin and learn what to watch for.',
                        style:
                            TextStyle(color: Colors.white)),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => context.go('/scan'),
                      icon: const Icon(
                          Icons.camera_alt_outlined),
                      label: const Text('Start a new scan'),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor:
                              const Color(0xff145da0)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SectionTitle('Quick actions'),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics:
                    const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  _Action(Icons.history, 'Scan history',
                      () => context.go('/history')),
                  _Action(
                      Icons.menu_book_outlined,
                      'Learn about skin',
                      () => context.go('/learn')),
                  _Action(
                      Icons.health_and_safety_outlined,
                      'When to get help',
                      () => context.go('/learn')),
                  _Action(
                      Icons.person_outline,
                      'Your profile',
                      () => context.go('/profile')),
                ],
              ),
              const SizedBox(height: 24),
              SectionTitle('Recent activity',
                  action: 'See all',
                  onTap: () => context.go('/history')),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                      child: Icon(Icons.spa_outlined)),
                  title: const Text('Your scan history'),
                  subtitle: const Text(
                      'Your saved screenings appear here'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/history'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'If you have a rapidly changing, bleeding, painful, or concerning skin issue, contact a healthcare professional.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      );
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon,
                    color: Theme.of(context)
                        .colorScheme
                        .primary,
                    size: 27),
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
}
