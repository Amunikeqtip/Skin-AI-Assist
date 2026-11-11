import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../../core/providers/scan_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() =>
      _ProfileScreenState();
}

class _ProfileScreenState
    extends ConsumerState<ProfileScreen> {
  static const _defaultAge = 'Prefer not to say';
  static const _defaultGender = 'Prefer not to say';
  static const _defaultSkin = 'Not sure';

  final _nameController = TextEditingController();
  late String age = _defaultAge;
  late String gender = _defaultGender;
  late String skin = _defaultSkin;

  Box get _profileBox => Hive.box('profile');

  @override
  void initState() {
    super.initState();
    final stored = _profileBox.get('details');
    if (stored is! Map) return;

    _nameController.text = stored['name'] as String? ?? '';
    age = stored['age'] as String? ?? _defaultAge;
    gender = stored['gender'] as String? ?? _defaultGender;
    skin = stored['skin'] as String? ?? _defaultSkin;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    await _profileBox.put('details', {
      'name': _nameController.text.trim(),
      'age': age,
      'gender': gender,
      'skin': skin,
    });
  }

  Future<void> _clearProfile() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear profile details?'),
        content: const Text(
          'This removes your saved name, age range, gender, and skin type from this device. It does not delete visit history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear details'),
          ),
        ],
      ),
    );

    if (shouldClear != true) return;

    await _profileBox.delete('details');
    if (!mounted) return;

    setState(() {
      _nameController.clear();
      age = _defaultAge;
      gender = _defaultGender;
      skin = _defaultSkin;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Profile details cleared.')),
    );
  }

  Future<void> _clearAllLocalData() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all local data?'),
        content: const Text(
          'This permanently removes saved visits, questionnaire answers, profile details, and your disclaimer acceptance from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all data'),
          ),
        ],
      ),
    );

    if (shouldClear != true || !mounted) return;

    try {
      await Hive.box('scans').clear();
      await _profileBox.clear();
      await Hive.box('preferences').delete('accepted');
      ref.invalidate(scanHistoryProvider);

      if (!mounted) return;
      setState(() {
        _nameController.clear();
        age = _defaultAge;
        gender = _defaultGender;
        skin = _defaultSkin;
      });
      context.go('/disclaimer');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Could not clear all local data. Please try again.'),
        ),
      );
    }
  }

  void _changeValue(String field, String value) {
    setState(() {
      switch (field) {
        case 'age':
          age = value;
        case 'gender':
          gender = value;
        case 'skin':
          skin = value;
      }
    });
    _saveProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 38,
            child: Icon(Icons.person_outline, size: 38),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            onChanged: (_) => _saveProfile(),
            decoration: const InputDecoration(
              labelText: 'Name (optional)',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          _select(
            label: 'Age range',
            value: age,
            items: const [
              _defaultAge,
              'Under 18',
              '18–24',
              '25–34',
              '35–44',
              '45–54',
              '55–64',
              '65+',
            ],
            onChanged: (value) =>
                _changeValue('age', value),
          ),
          const SizedBox(height: 16),
          _select(
            label: 'Gender (optional)',
            value: gender,
            items: const [
              _defaultGender,
              'Woman',
              'Man',
              'Non-binary',
              'Self describe',
            ],
            onChanged: (value) =>
                _changeValue('gender', value),
          ),
          const SizedBox(height: 16),
          _select(
            label: 'Skin type',
            value: skin,
            items: const [
              _defaultSkin,
              'Dry',
              'Oily',
              'Combination',
              'Sensitive',
              'Normal',
            ],
            onChanged: (value) =>
                _changeValue('skin', value),
          ),
          const SizedBox(height: 18),
          const Text(
            'Profile details are optional, encrypted, and stored on this device.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _clearProfile,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear profile details'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _clearAllLocalData,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Clear all local data'),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _select({
  required String label,
  required String value,
  required List<String> items,
  required ValueChanged<String> onChanged,
}) {
  return DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: items
        .map((item) => DropdownMenuItem(
            value: item, child: Text(item)))
        .toList(),
    onChanged: (newValue) {
      if (newValue != null) onChanged(newValue);
    },
  );
}
