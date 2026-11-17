import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/common.dart';

class EducationScreen extends StatefulWidget {
  const EducationScreen({super.key, this.initialTopic});

  final String? initialTopic;

  @override
  State<EducationScreen> createState() =>
      _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  static const _topics = [
    _EducationTopic(
      title: 'Eczema',
      summary:
          'Atopic eczema commonly causes itchy, dry skin. Its appearance can vary across skin tones.',
      details: [
        'Areas may look dry, cracked, scaly, thickened, blistered, or lighter or darker than nearby skin.',
        'Soaps, detergents, heat, fabrics, and other triggers can worsen symptoms for some people; triggers differ.',
        'Moisturizing treatments can help manage dryness. A clinician or pharmacist can advise about care and treatment.',
      ],
      sources: [
        _EducationSource(
          'NHS: Atopic eczema',
          'https://www.nhs.uk/conditions/atopic-eczema/',
        ),
      ],
      icon: Icons.water_drop_outlined,
      backgroundColor: Color(0xffe3f2ee),
      foregroundColor: Color(0xff397a6c),
    ),
    _EducationTopic(
      title: 'Psoriasis',
      summary:
          'Psoriasis is a long-term skin condition that can cause dry, flaky, itchy, or painful patches.',
      details: [
        'Patches may look different from person to person and may appear on several parts of the body.',
        'A photo cannot confirm psoriasis or distinguish it reliably from other skin conditions.',
        'A healthcare professional can assess symptoms and discuss suitable treatment options.',
      ],
      sources: [
        _EducationSource(
          'NHS: Psoriasis',
          'https://www.nhs.uk/conditions/psoriasis/',
        ),
      ],
      icon: Icons.layers_outlined,
      backgroundColor: Color(0xffeee9fa),
      foregroundColor: Color(0xff7058a6),
    ),
    _EducationTopic(
      title: 'Acne',
      summary:
          'Acne can cause spots, oily skin, and sometimes deep or painful lumps. It often affects the face, chest, or back.',
      details: [
        'Gentle cleansing is preferable to harsh scrubbing, which can irritate skin.',
        'Picking or squeezing spots can increase irritation and scarring.',
        'Ask a pharmacist or clinician for advice if acne is persistent, painful, scarring, or affecting wellbeing.',
      ],
      sources: [
        _EducationSource(
          'NHS: Acne',
          'https://www.nhs.uk/conditions/acne/',
        ),
      ],
      icon: Icons.face_retouching_natural_outlined,
      backgroundColor: Color(0xffffeee3),
      foregroundColor: Color(0xffad6743),
    ),
    _EducationTopic(
      title: 'Dry skin and moisturizers',
      summary:
          'Dryness can be affected by washing, weather, and products. Moisturizers are also called emollients.',
      details: [
        'Some everyday soaps and shower gels can dry skin or worsen an existing dry-skin condition.',
        'Emollients help keep moisture in the skin; a pharmacist or clinician can help choose a suitable product.',
        'Get advice if dryness is persistent, painful, cracked, widespread, or interfering with sleep.',
      ],
      sources: [
        _EducationSource(
          'NHS: Emollients',
          'https://www.nhs.uk/tests-and-treatments/emollients/',
        ),
      ],
      icon: Icons.spa_outlined,
      backgroundColor: Color(0xffe4edf9),
      foregroundColor: Color(0xff4775a5),
    ),
    _EducationTopic(
      title: 'Sun protection',
      summary:
          'Shade, sun-protective clothing, and sunscreen can reduce ultraviolet exposure.',
      details: [
        'When outdoors, seek shade and use clothing, a wide-brimmed hat, and sunglasses when practical.',
        'The American Academy of Dermatology recommends broad-spectrum, water-resistant SPF 30 or higher on exposed skin.',
        'Reapply sunscreen about every two hours outdoors, and after swimming or sweating, following the product label.',
        'Sun protection is useful for every skin tone.',
      ],
      sources: [
        _EducationSource(
          'American Academy of Dermatology: Practice safe sun',
          'https://www.aad.org/public/everyday-care/sun-protection/shade-clothing-sunscreen/practice-safe-sun',
        ),
      ],
      icon: Icons.wb_sunny_outlined,
      backgroundColor: Color(0xfffff3cf),
      foregroundColor: Color(0xff997221),
    ),
    _EducationTopic(
      title: 'How to check your skin',
      summary:
          'A regular look over your skin can help you notice a new or changing spot to discuss with a healthcare professional.',
      details: [
        'Use a full-length mirror and a hand mirror to check hard-to-see areas, including your back and scalp.',
        'Remember areas that may be missed, such as palms, soles, between toes, and around or under nails.',
        'Notice spots that look different from others, or that change, itch, or bleed. A self-check does not diagnose a condition.',
      ],
      sources: [
        _EducationSource(
          'American Academy of Dermatology: Skin self-exam',
          'https://www.aad.org/public/diseases/skin-cancer/check-skin',
        ),
      ],
      icon: Icons.search_outlined,
      backgroundColor: Color(0xffe8f0f4),
      foregroundColor: Color(0xff3c7188),
    ),
    _EducationTopic(
      title: 'The ABCDE signs to learn about',
      summary:
          'Dermatologists use ABCDE as one memory aid for features of a spot that should be assessed.',
      details: [
        'A — Asymmetry: one half looks unlike the other.',
        'B — Border: the edge is irregular or poorly defined.',
        'C — Color: there is a mix of colors in one spot.',
        'D — Diameter: melanoma can be larger than 6 mm when diagnosed, but can also be smaller.',
        'E — Evolving: the spot is changing in size, shape, or color, or looks different from your other spots.',
        'These signs are not a diagnosis. New, changing, itching, or bleeding spots should be discussed with a healthcare professional.',
      ],
      sources: [
        _EducationSource(
          'American Academy of Dermatology: ABCDE signs',
          'https://www.aad.org/public/diseases/skin-cancer/types/common/melanoma/symptoms',
        ),
      ],
      icon: Icons.remove_red_eye_outlined,
      backgroundColor: Color(0xffffe9e6),
      foregroundColor: Color(0xffa34f45),
    ),
    _EducationTopic(
      title: 'Contact dermatitis',
      summary:
          'Contact dermatitis is skin irritation or inflammation after contact with an irritant or an allergen.',
      details: [
        'It can cause itchy, dry, cracked, or blistered areas where the skin was exposed.',
        'If you notice a possible link to a product or substance, record what it was and when symptoms appeared.',
        'A pharmacist, GP, or dermatologist can help assess the cause and suitable next steps.',
      ],
      sources: [
        _EducationSource(
          'NHS: Contact dermatitis',
          'https://www.nhs.uk/conditions/contact-dermatitis/',
        ),
      ],
      icon: Icons.touch_app_outlined,
      backgroundColor: Color(0xfff4e9f0),
      foregroundColor: Color(0xff89516f),
    ),
    _EducationTopic(
      title: 'Ringworm and fungal skin infections',
      summary:
          'Ringworm is a fungal infection, not a worm. Its rash may be ring-shaped, but it can look different across body sites and skin tones.',
      details: [
        'A rash may be itchy, dry, swollen, or scaly. Appearance alone cannot confirm the cause.',
        'Fungal infections can spread through close contact or shared items such as towels and combs.',
        'A pharmacist can advise about suspected ringworm. Scalp involvement or a weakened immune system needs professional advice.',
      ],
      sources: [
        _EducationSource(
          'NHS: Ringworm',
          'https://www.nhs.uk/conditions/ringworm/',
        ),
      ],
      icon: Icons.circle_outlined,
      backgroundColor: Color(0xffedf0df),
      foregroundColor: Color(0xff657241),
    ),
    _EducationTopic(
      title: 'Skin changes across skin tones',
      summary:
          'The same condition can look different on different people. Redness may be less obvious on brown or black skin.',
      details: [
        'Inflammation may also appear darker, lighter, purple, or gray compared with nearby skin.',
        'Notice changes in warmth, swelling, pain, texture, or spread as well as color.',
        'A photo or an AI score may miss changes. Seek professional assessment when a spot is new, changing, or concerning.',
      ],
      sources: [
        _EducationSource(
          'NHS: Atopic eczema',
          'https://www.nhs.uk/conditions/atopic-eczema/',
        ),
        _EducationSource(
          'NHS: Cellulitis',
          'https://www.nhs.uk/conditions/cellulitis/',
        ),
      ],
      icon: Icons.palette_outlined,
      backgroundColor: Color(0xfff0e9df),
      foregroundColor: Color(0xff795f43),
    ),
    _EducationTopic(
      title: 'Preparing for an appointment',
      summary:
          'A few notes can help you explain what has changed when speaking with a healthcare professional.',
      details: [
        'Write down when you first noticed the area and whether its size, shape, color, or symptoms have changed.',
        'Note itch, pain, swelling, possible exposures, and any products or medicines used.',
        'Bring questions and mention any personal concerns. Do not delay care while collecting photos or using this app.',
      ],
      sources: [
        _EducationSource(
          'American Academy of Dermatology: Skin self-exam',
          'https://www.aad.org/public/diseases/skin-cancer/check-skin',
        ),
      ],
      icon: Icons.assignment_outlined,
      backgroundColor: Color(0xffe9edf7),
      foregroundColor: Color(0xff5a6692),
    ),
  ];

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _query = widget.initialTopic ?? '';
    _searchController.text = _query;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openSource(_EducationSource source) async {
    final didOpen = await launchUrl(
      Uri.parse(source.url),
      mode: LaunchMode.externalApplication,
    );
    if (!didOpen && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not open this source.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredTopics = _topics.where((topic) {
      final content =
          '${topic.title} ${topic.summary} ${topic.details.join(' ')}'
              .toLowerCase();
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
                initiallyExpanded:
                    widget.initialTopic == topic.title,
                leading: CircleAvatar(
                  backgroundColor: topic.backgroundColor,
                  child: Icon(
                    topic.icon,
                    color: topic.foregroundColor,
                  ),
                ),
                title: Text(
                  topic.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  topic.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(
                    18, 0, 18, 18),
                children: [
                  for (final detail in topic.details)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding:
                                EdgeInsets.only(top: 7),
                            child:
                                Icon(Icons.circle, size: 6),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              detail,
                              style: const TextStyle(
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Trusted reading',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge,
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 0,
                    children: [
                      for (final source in topic.sources)
                        TextButton.icon(
                          onPressed: () =>
                              _openSource(source),
                          icon: const Icon(
                            Icons.open_in_new,
                            size: 16,
                          ),
                          label: Text(source.label),
                        ),
                    ],
                  ),
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

class _EducationTopic {
  const _EducationTopic({
    required this.title,
    required this.summary,
    required this.details,
    required this.sources,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String title;
  final String summary;
  final List<String> details;
  final List<_EducationSource> sources;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
}

class _EducationSource {
  const _EducationSource(this.label, this.url);

  final String label;
  final String url;
}
