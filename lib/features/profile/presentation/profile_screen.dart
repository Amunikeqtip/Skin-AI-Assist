import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() =>
      _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String age = 'Prefer not to say',
      gender = 'Prefer not to say',
      skin = 'Not sure';
  @override
  Widget build(BuildContext c) => Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const CircleAvatar(
                radius: 38,
                child:
                    Icon(Icons.person_outline, size: 38)),
            const SizedBox(height: 20),
            TextField(
                decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    prefixIcon:
                        Icon(Icons.person_outline))),
            const SizedBox(height: 16),
            _select(
                'Age range',
                age,
                [
                  'Prefer not to say',
                  'Under 18',
                  '18–24',
                  '25–34',
                  '35–44',
                  '45–54',
                  '55–64',
                  '65+'
                ],
                (v) => setState(() => age = v)),
            const SizedBox(height: 16),
            _select(
                'Gender (optional)',
                gender,
                [
                  'Prefer not to say',
                  'Woman',
                  'Man',
                  'Non-binary',
                  'Self describe'
                ],
                (v) => setState(() => gender = v)),
            const SizedBox(height: 16),
            _select(
                'Skin type',
                skin,
                [
                  'Not sure',
                  'Dry',
                  'Oily',
                  'Combination',
                  'Sensitive',
                  'Normal'
                ],
                (v) => setState(() => skin = v)),
            const SizedBox(height: 22),
            const Text(
                'Profile details are optional and stored locally on this device.')
          ]));
}

Widget _select(String label, String value,
        List<String> items, ValueChanged<String> change) =>
    DropdownButtonFormField(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: items
            .map((s) =>
                DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: (v) {
          if (v != null) change(v);
        });
