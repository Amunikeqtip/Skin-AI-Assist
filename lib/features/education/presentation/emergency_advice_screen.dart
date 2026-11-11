import 'package:flutter/material.dart';

class EmergencyAdviceScreen extends StatelessWidget {
  const EmergencyAdviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
          title:
              const Text('Urgent skin and allergy advice')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: colors.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Icon(Icons.emergency,
                      color: colors.error, size: 34),
                  const SizedBox(height: 12),
                  Text(
                    'Get emergency help now',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                          color: colors.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Call your local emergency number or go to emergency care if someone is struggling to breathe, has sudden swelling of the lips, mouth, tongue, or throat, faints, becomes very confused, or cannot be woken.',
                    style: TextStyle(
                        color: colors.onErrorContainer),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _AdviceCard(
            icon: Icons.local_hospital_outlined,
            title: 'Seek urgent medical advice',
            body:
                'Get prompt medical help for rapidly spreading skin changes, worsening pain or swelling, a high temperature, or feeling very unwell. Do not wait for an app assessment.',
          ),
          const SizedBox(height: 16),
          _AdviceCard(
            icon: Icons.medication_outlined,
            title:
                'If you have a prescribed emergency plan',
            body:
                'Follow the instructions given to you by your healthcare professional. If you have a prescribed adrenaline auto-injector and think you are having a severe allergic reaction, use it as directed and seek emergency help.',
          ),
          const SizedBox(height: 16),
          const _AdviceCard(
            icon: Icons.info_outline,
            title: 'This app cannot assess emergencies',
            body:
                'SkinAI Assist does not diagnose or decide how urgent your symptoms are. If you are worried or symptoms are getting worse, contact a healthcare professional or local emergency service.',
          ),
          const SizedBox(height: 20),
          Text(
            'Guidance reviewed from NHS information on anaphylaxis and cellulitis: nhs.uk/conditions/anaphylaxis/ and nhs.uk/conditions/cellulitis/. Emergency numbers and services vary by location.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color:
                    Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }
}
