import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/common.dart';

class EducationScreen extends StatefulWidget {
  const EducationScreen({super.key});

  @override
  State<EducationScreen> createState() =>
      _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  static const _topics = [
    (
      'Eczema',
      'Dry, itchy, inflamed skin can have many causes. Gentle moisturizers and avoiding personal triggers may help.',
      Icons.water_drop_outlined,
      Color(0xffe3f2ee),
      Color(0xff397a6c),
    ),
    (
      'Psoriasis',
      'Psoriasis is a long-term inflammatory condition. A clinician can assess symptoms and discuss treatment.',
      Icons.layers_outlined,
      Color(0xffeee9fa),
      Color(0xff7058a6),
    ),
    (
      'Acne',
      'Acne is common and varies from person to person. Avoid harsh scrubbing and seek care for persistent or painful acne.',
      Icons.face_retouching_natural_outlined,
      Color(0xffffeee3),
      Color(0xffad6743),
    ),
    (
      'Dry skin',
      'Dryness can be affected by weather, bathing, and products. Persistent cracking or discomfort may need medical advice.',
      Icons.spa_outlined,
      Color(0xffe4edf9),
      Color(0xff4775a5),
    ),
    (
      'Sun safety',
      'Use shade, protective clothing, and broad-spectrum sunscreen. Check your skin and ask a clinician about changes.',
      Icons.wb_sunny_outlined,
      Color(0xfffff3cf),
      Color(0xff997221),
    ),
  ];

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredTopics = _topics.where((topic) {
      final content =
          '${topic.$1} ${topic.$2}'.toLowerCase();
      return content.contains(_query.trim().toLowerCase());
    }).toList();

    return Scaffold(
      appBar:
          AppBar(title: const Text('Skin learning hub')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 180,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/sun_safety.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xd9103433),
                          Color(0x8c103433),
                          Color(0x06103433),
                        ],
                        stops: [0, .58, 1],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 245,
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Learn at your own pace',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 23,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Simple guides for everyday skin health.',
                              style: TextStyle(
                                color: Colors.white,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const NoticeBanner(),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (value) =>
                setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search skin topics',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          SectionTitle(
            _query.isEmpty
                ? 'Explore topics'
                : 'Search results',
            action: '${filteredTopics.length} topics',
          ),
          const SizedBox(height: 8),
          if (filteredTopics.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No topics match that search. Try another word.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          for (final topic in filteredTopics)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: topic.$4,
                  child: Icon(topic.$3, color: topic.$5),
                ),
                title: Text(
                  topic.$1,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('General information'),
                childrenPadding: const EdgeInsets.fromLTRB(
                    18, 0, 18, 18),
                children: [
                  Text(topic.$2,
                      style: const TextStyle(height: 1.45)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Card(
            color: Theme.of(context)
                .colorScheme
                .errorContainer,
            child: ListTile(
              leading: const Icon(
                  Icons.health_and_safety_outlined),
              title: const Text(
                'When to get urgent help',
                style:
                    TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Learn what symptoms need prompt medical attention.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/emergency'),
            ),
          ),
        ],
      ),
    );
  }
}
