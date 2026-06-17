import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

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
  final _bleService = CadenceBleService();
  final _player = AudioPlayer();

  List<MusicTrack> _tracks = [];
  EnvironmentContext _context = EnvironmentContext.mock('forest_mountain');
  Recommendation? _recommendation;
  BleDeviceReading? _bleReading;
  Position? _position;
  String? _status;
  String _bleStatus = 'Disconnected';
  bool _loadingContext = false;
  bool _bleBusy = false;
  bool _bleConnected = false;
  bool _isPlaying = false;
  String? _playingTrackId;
  String _playerStatus = 'Ready to stream';
  StreamSubscription<PlayerState>? _playerStateSubscription;

  double _deviceBpm = 86;
  double _ambientVolume = 55;

  @override
  void initState() {
    super.initState();
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _playingTrackId = null;
          _playerStatus = 'Playback completed';
        }
      });
    });
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
        _status = 'GPS/Overpass failed: ${ErrorText.short(error)}';
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

  Future<void> _playRecommendation() async {
    final recommendation = _recommendation;
    if (recommendation == null) return;

    setState(() {
      _playerStatus = 'Loading stream...';
    });

    try {
      await _player.setVolume(VolumeMapper.fromAmbient(_ambientVolume));
      await _player.setUrl(recommendation.track.audioUrl);
      await _player.play();
      setState(() {
        _playingTrackId = recommendation.track.id;
        _playerStatus = 'Streaming ${recommendation.track.title}';
      });
    } catch (error) {
      setState(() {
        _playingTrackId = null;
        _playerStatus = 'Playback failed: ${ErrorText.short(error)}';
      });
    }
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    setState(() {
      _playingTrackId = null;
      _playerStatus = 'Playback stopped';
    });
  }

  Future<void> _syncPlayerVolume() async {
    await _player.setVolume(VolumeMapper.fromAmbient(_ambientVolume));
  }

  Future<void> _connectBleDevice() async {
    setState(() {
      _bleBusy = true;
      _bleStatus = 'Scanning for CadenceMic...';
    });

    try {
      await _bleService.connect(
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            _bleStatus = status;
          });
        },
        onDisconnected: () {
          if (!mounted) return;
          setState(() {
            _bleConnected = false;
            _bleStatus = 'Disconnected';
          });
        },
        onReading: (reading) {
          if (!mounted) return;
          setState(() {
            _bleReading = reading;
            _bleConnected = true;
            _bleStatus = 'Connected to CadenceMic';
            if (reading.bpm > 0) _deviceBpm = reading.bpm.toDouble();
            _ambientVolume = reading.ambient.clamp(0, 100);
            _recommendation = _recommender.recommend(
              context: _context,
              bpm: _deviceBpm.round(),
              tracks: _tracks,
            );
          });
          _syncPlayerVolume();
        },
      );
      setState(() {
        _bleConnected = true;
      });
    } catch (error) {
      setState(() {
        _bleStatus = ErrorText.short(error);
        _bleConnected = false;
      });
    } finally {
      setState(() {
        _bleBusy = false;
      });
    }
  }

  Future<void> _disconnectBleDevice() async {
    setState(() {
      _bleBusy = true;
      _bleStatus = 'Disconnecting...';
    });
    await _bleService.disconnect();
    setState(() {
      _bleBusy = false;
      _bleConnected = false;
      _bleStatus = 'Disconnected';
    });
  }

  @override
  void dispose() {
    _bleService.dispose();
    _playerStateSubscription?.cancel();
    _player.dispose();
    super.dispose();
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
                        'forest_mountain',
                        'water',
                        'park',
                        'urban',
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
                  _BleStatusPanel(
                    status: _bleStatus,
                    reading: _bleReading,
                    connected: _bleConnected,
                    busy: _bleBusy,
                    onConnect: _connectBleDevice,
                    onDisconnect: _disconnectBleDevice,
                  ),
                  const SizedBox(height: 14),
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
                      _syncPlayerVolume();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _RecommendationPanel(
              recommendation: _recommendation,
              isPlaying: _isPlaying &&
                  _playingTrackId == _recommendation?.track.id,
              playerStatus: _playerStatus,
              onPlay: _playRecommendation,
              onStop: _stopPlayback,
            ),
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
    required this.audioUrl,
  });

  final String id;
  final String title;
  final String artist;
  final int bpm;
  final List<String> environmentTags;
  final List<String> musicTags;
  final String audioUrl;

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      bpm: json['bpm'] as int,
      environmentTags: List<String>.from(json['environmentTags'] as List),
      musicTags: List<String>.from(json['musicTags'] as List),
      audioUrl: (json['audioUrl'] ?? json['audioPath']) as String,
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

class BleDeviceReading {
  const BleDeviceReading({
    required this.bpm,
    required this.ambient,
    required this.current,
    required this.step,
    required this.raw,
  });

  final int bpm;
  final double ambient;
  final double current;
  final bool step;
  final String raw;

  factory BleDeviceReading.fromJsonText(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return BleDeviceReading(
      bpm: (data['bpm'] as num? ?? 0).round(),
      ambient: (data['ambient'] as num? ?? 0).toDouble(),
      current: (data['current'] as num? ?? 0).toDouble(),
      step: (data['step'] as num? ?? 0) == 1,
      raw: raw,
    );
  }
}

class CadenceBleService {
  static final Guid serviceUuid = Guid(
    '12345678-1234-1234-1234-1234567890ab',
  );
  static final Guid characteristicUuid = Guid(
    'abcdefab-1234-5678-1234-abcdefabcdef',
  );

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  Future<void> connect({
    required ValueChanged<String> onStatus,
    required ValueChanged<BleDeviceReading> onReading,
    required VoidCallback onDisconnected,
  }) async {
    await disconnect();

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      throw Exception('Bluetooth is not on');
    }

    final device = await _findCadenceMic(onStatus);
    _device = device;

    onStatus('Connecting to ${_deviceName(device)}...');
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 15),
    );

    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        onDisconnected();
      }
    });

    onStatus('Discovering BLE services...');
    final services = await device.discoverServices();
    final service = services.firstWhere(
      (item) => item.serviceUuid == serviceUuid,
      orElse: () => throw Exception('CadenceMic service not found'),
    );
    final characteristic = service.characteristics.firstWhere(
      (item) => item.characteristicUuid == characteristicUuid,
      orElse: () => throw Exception('CadenceMic data characteristic not found'),
    );

    _valueSubscription = characteristic.onValueReceived.listen((value) {
      final raw = utf8.decode(value).trim();
      if (raw.isEmpty) return;
      onReading(BleDeviceReading.fromJsonText(raw));
    });

    await characteristic.setNotifyValue(true);
    onStatus('Connected to CadenceMic');

    try {
      final value = await characteristic.read();
      if (value.isNotEmpty) {
        final raw = utf8.decode(value).trim();
        onReading(BleDeviceReading.fromJsonText(raw));
      }
    } catch (_) {
      // Notify is the primary data path; read is only a best-effort initial value.
    }
  }

  Future<BluetoothDevice> _findCadenceMic(ValueChanged<String> onStatus) async {
    BluetoothDevice? found;
    StreamSubscription<List<ScanResult>>? scanSubscription;

    Future<BluetoothDevice?> runScan({
      required String label,
      List<Guid> withServices = const [],
      List<String> withNames = const [],
    }) async {
      found = null;
      onStatus(label);
      scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
        for (final result in results) {
          final device = result.device;
          final names = {
            device.platformName,
            device.advName,
            result.advertisementData.advName,
          };
          if (names.contains('CadenceMic') ||
              result.advertisementData.serviceUuids.contains(serviceUuid)) {
            found = device;
            FlutterBluePlus.stopScan();
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(
        withServices: withServices,
        withNames: withNames,
        timeout: const Duration(seconds: 8),
        androidUsesFineLocation: true,
      );
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
      await scanSubscription?.cancel();
      scanSubscription = null;
      return found;
    }

    final byService = await runScan(
      label: 'Scanning for CadenceMic service...',
      withServices: [serviceUuid],
    );
    if (byService != null) return byService;

    final byName = await runScan(
      label: 'Scanning for CadenceMic name...',
      withNames: const ['CadenceMic'],
    );
    if (byName != null) return byName;

    throw Exception('CadenceMic not found. Check power and advertising.');
  }

  Future<void> disconnect() async {
    await _valueSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _valueSubscription = null;
    _connectionSubscription = null;

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  Future<void> dispose() => disconnect();

  String _deviceName(BluetoothDevice device) {
    return device.platformName.isNotEmpty
        ? device.platformName
        : device.advName.isNotEmpty
            ? device.advName
            : device.remoteId.str;
  }
}

class ContextVocabulary {
  static List<String> musicKeywords(String context) {
    return switch (context) {
      'forest_mountain' => [
          'forest_mountain',
          'forest',
          'mountain',
          'nature',
          'ambient',
          'calm',
        ],
      'water' => ['water', 'flowing', 'open', 'chill', 'piano', 'calm'],
      'park' => ['park', 'green', 'light', 'happy', 'acoustic'],
      'urban' => ['urban', 'road', 'city', 'electronic', 'rhythmic'],
      'road' => ['road', 'highway', 'travel', 'driving', 'energetic'],
      _ => [context],
    };
  }
}

class ContextDetectionService {
  static const _userAgent =
      'ContextAwareMusicDissertation/1.0 (Flutter Android student research app)';

  static const _overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.openstreetmap.ru/api/interpreter',
  ];

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
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        forceLocationManager: true,
      ),
    );
  }

  Future<EnvironmentContext> detectNearbyContext(Position position) async {
    final radiusMeters = 700;
    final query = '''
[out:json][timeout:25];
(
  nwr(around:$radiusMeters,${position.latitude},${position.longitude})["natural"];
  nwr(around:$radiusMeters,${position.latitude},${position.longitude})["landuse"];
  nwr(around:$radiusMeters,${position.latitude},${position.longitude})["waterway"];
  nwr(around:$radiusMeters,${position.latitude},${position.longitude})["leisure"];
  nwr(around:$radiusMeters,${position.latitude},${position.longitude})["building"];
  nwr(around:$radiusMeters,${position.latitude},${position.longitude})["highway"];
  nwr(around:$radiusMeters,${position.latitude},${position.longitude})["amenity"];
  nwr(around:$radiusMeters,${position.latitude},${position.longitude})["place"];
  nwr(around:$radiusMeters,${position.latitude},${position.longitude})["tourism"];
);
out tags 120;
''';

    final response = await _queryOverpass(query);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = (data['elements'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final scores = _scoreElements(elements);
    if (scores.isEmpty) return EnvironmentContext.mock('urban');

    final primary = scores.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
    return EnvironmentContext(
      primary: primary,
      musicKeywords: ContextVocabulary.musicKeywords(primary),
      scores: scores,
    );
  }

  Future<http.Response> _queryOverpass(String query) async {
    http.Response? lastResponse;

    for (final endpoint in _overpassEndpoints) {
      try {
        final response = await http
            .post(
              Uri.parse(endpoint),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
                'User-Agent': _userAgent,
              },
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode == 200) return response;
        lastResponse = response;
      } catch (_) {
        continue;
      }
    }

    final status = lastResponse?.statusCode;
    final body = lastResponse?.body.trim();
    final normalizedBody = body?.replaceAll(RegExp(r'\s+'), ' ');
    final detail = normalizedBody == null || normalizedBody.isEmpty
        ? ''
        : ': ${normalizedBody.substring(0, min(120, normalizedBody.length))}';
    if (status == 429) {
      throw Exception(
        'Overpass rate limit. Wait briefly and try again, or switch network.',
      );
    }
    throw Exception('Overpass HTTP ${status ?? 'unknown'}$detail');
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
      final amenity = tags['amenity'];
      final building = tags['building'];
      final highway = tags['highway'];
      final place = tags['place'];
      final tourism = tags['tourism'];

      if (natural == 'wood' ||
          natural == 'tree_row' ||
          natural == 'scrub' ||
          natural == 'heath' ||
          natural == 'peak' ||
          natural == 'ridge' ||
          natural == 'cliff' ||
          natural == 'bare_rock' ||
          natural == 'scree' ||
          natural == 'fell' ||
          landuse == 'forest' ||
          landuse == 'orchard' ||
          tourism == 'viewpoint') {
        add('forest_mountain', _forestMountainWeight(natural, landuse));
      }
      if (natural == 'water' ||
          natural == 'coastline' ||
          natural == 'beach' ||
          waterway != null ||
          landuse == 'reservoir' ||
          landuse == 'basin') {
        add('water', 3);
      }
      if (leisure == 'park' ||
          leisure == 'garden' ||
          leisure == 'nature_reserve' ||
          landuse == 'grass' ||
          landuse == 'recreation_ground') {
        add('park', 2.8);
      }
      if (_isRoadContext(highway)) {
        add('road', _roadWeight(highway));
        if (_isMajorRoad(highway)) add('urban', 0.25);
      }
      if (building != null) {
        add('urban', 1.1);
      }
      if (amenity != null) {
        add('urban', 1.0);
      }
      if (place == 'city' ||
          place == 'town' ||
          place == 'suburb' ||
          place == 'neighbourhood') {
        add('urban', 2);
      }
    }

    return scores;
  }

  double _forestMountainWeight(dynamic natural, dynamic landuse) {
    if (natural == 'peak' ||
        natural == 'ridge' ||
        natural == 'cliff' ||
        natural == 'bare_rock' ||
        natural == 'scree' ||
        natural == 'fell') {
      return 4.2;
    }
    if (natural == 'wood' || landuse == 'forest') return 3.5;
    return 2.2;
  }

  bool _isRoadContext(dynamic highway) {
    return _roadWeight(highway) > 0;
  }

  bool _isMajorRoad(dynamic highway) {
    return highway == 'motorway' ||
        highway == 'trunk' ||
        highway == 'primary' ||
        highway == 'secondary' ||
        highway == 'tertiary';
  }

  double _roadWeight(dynamic highway) {
    return switch (highway) {
      'motorway' || 'trunk' => 4.0,
      'primary' => 3.5,
      'secondary' => 3.0,
      'tertiary' => 2.2,
      'cycleway' || 'pedestrian' => 1.4,
      'footway' || 'path' || 'steps' => 1.2,
      'residential' || 'service' || 'living_street' => 0.7,
      _ => 0,
    };
  }
}

class ErrorText {
  static String short(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.length <= 120) return text;
    return '${text.substring(0, 117)}...';
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
  const _RecommendationPanel({
    required this.recommendation,
    required this.isPlaying,
    required this.playerStatus,
    required this.onPlay,
    required this.onStop,
  });

  final Recommendation? recommendation;
  final bool isPlaying;
  final String playerStatus;
  final Future<void> Function() onPlay;
  final Future<void> Function() onStop;

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
          _InfoRow(label: 'Stream', value: rec.track.audioUrl),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: isPlaying ? onStop : onPlay,
                icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                label: Text(isPlaying ? 'Stop' : 'Play stream'),
              ),
              const SizedBox(width: 12),
              Expanded(child: _MutedText(playerStatus)),
            ],
          ),
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

class _BleStatusPanel extends StatelessWidget {
  const _BleStatusPanel({
    required this.status,
    required this.reading,
    required this.connected,
    required this.busy,
    required this.onConnect,
    required this.onDisconnect,
  });

  final String status;
  final BleDeviceReading? reading;
  final bool connected;
  final bool busy;
  final Future<void> Function() onConnect;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final reading = this.reading;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                connected ? Icons.bluetooth_connected : Icons.bluetooth,
                color: connected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white.withValues(alpha: 0.68),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CadenceMic BLE',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : connected
                        ? onDisconnect
                        : onConnect,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(connected ? Icons.link_off : Icons.link),
                label: Text(connected ? 'Disconnect' : 'Connect'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MutedText(status),
          if (reading != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricPill(icon: Icons.favorite, label: '${reading.bpm} bpm'),
                _MetricPill(
                  icon: Icons.volume_up,
                  label: 'ambient ${reading.ambient.toStringAsFixed(1)}',
                ),
                _MetricPill(
                  icon: Icons.graphic_eq,
                  label: 'current ${reading.current.toStringAsFixed(1)}',
                ),
                _MetricPill(
                  icon: reading.step ? Icons.directions_walk : Icons.pause,
                  label: reading.step ? 'step' : 'no step',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _MutedText(reading.raw),
          ],
        ],
      ),
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
