import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ContextAwareMusicApp());
}

class ContextAwareMusicApp extends StatelessWidget {
  const ContextAwareMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF101416);
    const surface = Color(0xFF1A2023);
    const accent = Color(0xFF58C4B8);
    const warm = Color(0xFFE8B45B);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Context Aware Music',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          surface: surface,
          primary: accent,
          secondary: warm,
          tertiary: Color(0xFF8FB8E8),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFF283238)),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: accent,
          thumbColor: accent,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _musicLibrary = MusicLibrary();
  final _contextService = ContextDetectionService();
  final _recommender = MusicRecommender();

  List<MusicTrack> _tracks = [];
  EnvironmentContext _context = EnvironmentContext.mock('forest');
  Recommendation? _recommendation;
  Position? _position;
  String? _status;
  bool _loadingContext = false;

  double _deviceBpm = 86;
  double _ambientVolume = 55;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final tracks = await _musicLibrary.loadSampleTracks();
    setState(() {
      _tracks = tracks;
      _recommendation = _recommender.recommend(
        context: _context,
        bpm: _deviceBpm.round(),
        tracks: tracks,
      );
    });
  }

  Future<void> _detectContextFromLocation() async {
    setState(() {
      _loadingContext = true;
      _status = 'Requesting location and querying Overpass API...';
    });

    try {
      final position = await _contextService.currentPosition();
      final context = await _contextService.detectNearbyContext(position);
      setState(() {
        _position = position;
        _context = context;
        _recommendation = _recommender.recommend(
          context: context,
          bpm: _deviceBpm.round(),
          tracks: _tracks,
        );
        _status = 'Context updated from GPS and OpenStreetMap.';
      });
    } catch (error) {
      setState(() {
        _status = 'Could not use GPS/Overpass: $error';
      });
    } finally {
      setState(() {
        _loadingContext = false;
      });
    }
  }

  void _useMockContext(String context) {
    setState(() {
      _context = EnvironmentContext.mock(context);
      _recommendation = _recommender.recommend(
        context: _context,
        bpm: _deviceBpm.round(),
        tracks: _tracks,
      );
      _status = 'Using mock context: $context';
    });
  }

  void _updateRecommendation() {
    setState(() {
      _recommendation = _recommender.recommend(
        context: _context,
        bpm: _deviceBpm.round(),
        tracks: _tracks,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final outputVolume = VolumeMapper.fromAmbient(_ambientVolume);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Context Aware Music'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Detect location context',
            onPressed: _loadingContext ? null : _detectContextFromLocation,
            icon: _loadingContext
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeroPanel(
              contextLabel: _context.primary,
              bpm: _deviceBpm.round(),
              outputVolume: outputVolume,
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Environment',
              icon: Icons.public,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in const [
                        'forest',
                        'ocean',
                        'river',
                        'city',
                        'park',
                        'road',
                      ])
                        ChoiceChip(
                          label: Text(item),
                          selected: _context.primary == item,
                          onSelected: (_) => _useMockContext(item),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: 'Music prompts',
                    value: _context.musicKeywords.join(', '),
                  ),
                  if (_position != null)
                    _InfoRow(
                      label: 'GPS',
                      value:
                          '${_position!.latitude.toStringAsFixed(5)}, ${_position!.longitude.toStringAsFixed(5)}',
                    ),
                  if (_status != null) _MutedText(_status!),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Device Input',
              icon: Icons.sensors,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LabeledSlider(
                    label: 'BPM from physical device',
                    value: _deviceBpm,
                    min: 50,
                    max: 160,
                    divisions: 110,
                    displayValue: '${_deviceBpm.round()} bpm',
                    onChanged: (value) {
                      _deviceBpm = value;
                      _updateRecommendation();
                    },
                  ),
                  const SizedBox(height: 10),
                  _LabeledSlider(
                    label: 'Ambient volume from device',
                    value: _ambientVolume,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    displayValue:
                        '${_ambientVolume.round()} -> output ${(outputVolume * 100).round()}%',
                    onChanged: (value) {
                      setState(() {
                        _ambientVolume = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _RecommendationPanel(recommendation: _recommendation),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Sample Library',
              icon: Icons.library_music,
              child: Column(
                children: [
                  for (final track in _tracks)
                    _TrackTile(
                      track: track,
                      selected: track.id == _recommendation?.track.id,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.bpm,
    required this.environmentTags,
    required this.musicTags,
    required this.audioPath,
  });

  final String id;
  final String title;
  final String artist;
  final int bpm;
  final List<String> environmentTags;
  final List<String> musicTags;
  final String audioPath;

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      bpm: json['bpm'] as int,
      environmentTags: List<String>.from(json['environmentTags'] as List),
      musicTags: List<String>.from(json['musicTags'] as List),
      audioPath: json['audioPath'] as String,
    );
  }
}

class MusicLibrary {
  Future<List<MusicTrack>> loadSampleTracks() async {
    final raw = await rootBundle.loadString(
      'assets/data/sample_music_library.json',
    );
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((item) => MusicTrack.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

class EnvironmentContext {
  const EnvironmentContext({
    required this.primary,
    required this.musicKeywords,
    required this.scores,
  });

  final String primary;
  final List<String> musicKeywords;
  final Map<String, double> scores;

  factory EnvironmentContext.mock(String primary) {
    return EnvironmentContext(
      primary: primary,
      musicKeywords: ContextVocabulary.musicKeywords(primary),
      scores: {primary: 1},
    );
  }
}

class Recommendation {
  const Recommendation({
    required this.track,
    required this.score,
    required this.keywordScore,
    required this.bpmScore,
    required this.reason,
    required this.targetBpmRange,
  });

  final MusicTrack track;
  final double score;
  final double keywordScore;
  final double bpmScore;
  final String reason;
  final IntRange targetBpmRange;
}

class IntRange {
  const IntRange(this.min, this.max);

  final int min;
  final int max;
}

class MusicRecommender {
  Recommendation? recommend({
    required EnvironmentContext context,
    required int bpm,
    required List<MusicTrack> tracks,
  }) {
    if (tracks.isEmpty) return null;

    final targetRange = _rangeForBpm(bpm);
    final ranked = tracks.map((track) {
      final environmentScore = _environmentScore(context, track);
      final bpmScore = _bpmScore(track.bpm, targetRange);
      final score = environmentScore * 0.72 + bpmScore * 0.28;
      final matched = track.environmentTags
          .where((tag) => context.musicKeywords.contains(tag))
          .toList();

      return Recommendation(
        track: track,
        score: score,
        keywordScore: environmentScore,
        bpmScore: bpmScore,
        targetBpmRange: targetRange,
        reason:
            'Matched ${matched.isEmpty ? context.primary : matched.join(', ')}; track BPM ${track.bpm} vs target ${targetRange.min}-${targetRange.max}.',
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final top = ranked.take(3).where((item) => item.score > 0).toList();
    if (top.isEmpty) return ranked.first;
    return top[Random().nextInt(top.length)];
  }

  IntRange _rangeForBpm(int bpm) {
    if (bpm < 70) return const IntRange(50, 80);
    if (bpm < 100) return const IntRange(70, 105);
    if (bpm < 130) return const IntRange(95, 135);
    return const IntRange(120, 160);
  }

  double _environmentScore(EnvironmentContext context, MusicTrack track) {
    final keywords = context.musicKeywords.toSet();
    final tags = {...track.environmentTags, ...track.musicTags};
    final matches = tags.where(keywords.contains).length;
    final directContextBonus = track.environmentTags.contains(context.primary)
        ? 0.45
        : 0;
    return min(1, directContextBonus + matches / max(1, keywords.length));
  }

  double _bpmScore(int trackBpm, IntRange range) {
    if (trackBpm >= range.min && trackBpm <= range.max) return 1;
    final distance = trackBpm < range.min
        ? range.min - trackBpm
        : trackBpm - range.max;
    return max(0, 1 - distance / 45);
  }
}

class VolumeMapper {
  static double fromAmbient(double ambientVolume) {
    return (0.3 + (ambientVolume / 100) * 0.5).clamp(0.3, 0.8);
  }
}

class ContextVocabulary {
  static List<String> musicKeywords(String context) {
    return switch (context) {
      'forest' => ['forest', 'park', 'nature', 'ambient', 'acoustic', 'calm'],
      'ocean' => ['ocean', 'river', 'sea', 'open', 'chill', 'atmospheric'],
      'river' => ['river', 'ocean', 'flowing', 'piano', 'soft', 'calm'],
      'city' => ['city', 'road', 'urban', 'electronic', 'rhythmic'],
      'park' => ['park', 'forest', 'green', 'light', 'happy', 'acoustic'],
      'road' => ['road', 'city', 'rhythmic', 'energetic', 'electronic'],
      _ => [context],
    };
  }
}

class ContextDetectionService {
  Future<Position> currentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location service is disabled');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  Future<EnvironmentContext> detectNearbyContext(Position position) async {
    final query = '''
[out:json][timeout:25];
(
  nwr(around:800,${position.latitude},${position.longitude})["natural"];
  nwr(around:800,${position.latitude},${position.longitude})["landuse"];
  nwr(around:800,${position.latitude},${position.longitude})["waterway"];
  nwr(around:800,${position.latitude},${position.longitude})["leisure"];
  nwr(around:800,${position.latitude},${position.longitude})["building"];
  nwr(around:800,${position.latitude},${position.longitude})["highway"];
  nwr(around:800,${position.latitude},${position.longitude})["amenity"];
);
out tags center 80;
''';

    final response = await http.post(
      Uri.parse('https://overpass-api.de/api/interpreter'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'data': query},
    );
    if (response.statusCode != 200) {
      throw Exception('Overpass returned HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = (data['elements'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final scores = _scoreElements(elements);
    if (scores.isEmpty) return EnvironmentContext.mock('city');

    final primary = scores.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    return EnvironmentContext(
      primary: primary,
      musicKeywords: ContextVocabulary.musicKeywords(primary),
      scores: scores,
    );
  }

  Map<String, double> _scoreElements(List<Map<String, dynamic>> elements) {
    final scores = <String, double>{};

    void add(String key, double value) {
      scores[key] = (scores[key] ?? 0) + value;
    }

    for (final element in elements) {
      final tags = (element['tags'] as Map<String, dynamic>? ?? {});
      final natural = tags['natural'];
      final landuse = tags['landuse'];
      final waterway = tags['waterway'];
      final leisure = tags['leisure'];

      if (natural == 'wood' || landuse == 'forest') add('forest', 3);
      if (natural == 'water' || waterway != null) add('river', 2.5);
      if (natural == 'coastline' || natural == 'beach') add('ocean', 4);
      if (leisure == 'park' || landuse == 'grass') add('park', 2.5);
      if (tags.containsKey('building') || tags.containsKey('amenity')) {
        add('city', 1.3);
      }
      if (tags.containsKey('highway')) add('road', 1.6);
    }

    return scores;
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.contextLabel,
    required this.bpm,
    required this.outputVolume,
  });

  final String contextLabel;
  final int bpm;
  final double outputVolume;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF182225),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF314249)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            contextLabel.toUpperCase(),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetricPill(icon: Icons.favorite, label: '$bpm bpm'),
              const SizedBox(width: 8),
              _MetricPill(
                icon: Icons.volume_up,
                label: '${(outputVolume * 100).round()}% output',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _RecommendationPanel extends StatelessWidget {
  const _RecommendationPanel({required this.recommendation});

  final Recommendation? recommendation;

  @override
  Widget build(BuildContext context) {
    final rec = recommendation;
    if (rec == null) {
      return const _SectionCard(
        title: 'Recommendation',
        icon: Icons.queue_music,
        child: _MutedText('Loading sample music library...'),
      );
    }

    return _SectionCard(
      title: 'Recommendation',
      icon: Icons.queue_music,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rec.track.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
          ),
          const SizedBox(height: 4),
          _MutedText('${rec.track.artist} • ${rec.track.bpm} bpm'),
          const SizedBox(height: 12),
          _ScoreBar(label: 'Environment match', value: rec.keywordScore),
          const SizedBox(height: 8),
          _ScoreBar(label: 'BPM match', value: rec.bpmScore),
          const SizedBox(height: 12),
          _InfoRow(label: 'Reason', value: rec.reason),
          _InfoRow(label: 'Tags', value: rec.track.environmentTags.join(', ')),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, required this.selected});

  final MusicTrack track;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.play_circle_fill : Icons.music_note,
        color: selected ? Theme.of(context).colorScheme.secondary : null,
      ),
      title: Text(track.title),
      subtitle: Text('${track.environmentTags.join(', ')} • ${track.bpm} bpm'),
      trailing: selected ? const Text('selected') : null,
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text(label)),
            const SizedBox(width: 12),
            Text(displayValue),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: displayValue,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 142, child: Text(label)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: value.clamp(0, 1),
              backgroundColor: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 38,
          child: Text('${(value * 100).round()}%'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
    );
  }
}
