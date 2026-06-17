import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ContextAwareExhibitionApp());
}

class ContextAwareExhibitionApp extends StatelessWidget {
  const ContextAwareExhibitionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Context Music Exhibition',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ExhibitionColors.background,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: ExhibitionColors.mint,
          secondary: ExhibitionColors.sun,
          tertiary: ExhibitionColors.sky,
          surface: ExhibitionColors.surface,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: ExhibitionColors.mint,
          thumbColor: ExhibitionColors.mint,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
        ),
      ),
      home: const ExhibitionShell(),
    );
  }
}

class ExhibitionColors {
  static const background = Color(0xFF0B0F12);
  static const surface = Color(0xFF151C20);
  static const panel = Color(0xFF1B2529);
  static const mint = Color(0xFF62D3C4);
  static const sun = Color(0xFFF4C76A);
  static const sky = Color(0xFF8CB7F2);
  static const coral = Color(0xFFFF8E7A);
}

class ExhibitionShell extends StatefulWidget {
  const ExhibitionShell({super.key});

  @override
  State<ExhibitionShell> createState() => _ExhibitionShellState();
}

class _ExhibitionShellState extends State<ExhibitionShell> {
  GeoPoint? _selectedPoint;

  @override
  Widget build(BuildContext context) {
    final point = _selectedPoint;
    if (point == null) {
      return LocationSelectionPage(
        onStart: (value) => setState(() => _selectedPoint = value),
      );
    }

    return ExhibitionDashboard(
      initialPoint: point,
      onChangeLocation: () => setState(() => _selectedPoint = null),
    );
  }
}

class LocationSelectionPage extends StatefulWidget {
  const LocationSelectionPage({super.key, required this.onStart});

  final ValueChanged<GeoPoint> onStart;

  @override
  State<LocationSelectionPage> createState() => _LocationSelectionPageState();
}

class _LocationSelectionPageState extends State<LocationSelectionPage> {
  final _mapController = MapController();
  final _latController = TextEditingController(text: '51.50740');
  final _lonController = TextEditingController(text: '-0.12780');
  GeoPoint _point = const GeoPoint(
    latitude: 51.5074,
    longitude: -0.1278,
    label: 'London / exhibition demo',
  );

  @override
  void dispose() {
    _mapController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  void _setPoint(GeoPoint point) {
    setState(() {
      _point = point;
      _latController.text = point.latitude.toStringAsFixed(5);
      _lonController.text = point.longitude.toStringAsFixed(5);
    });
    _mapController.move(LatLng(point.latitude, point.longitude), 13);
  }

  void _applyTypedCoordinates() {
    final lat = double.tryParse(_latController.text.trim());
    final lon = double.tryParse(_lonController.text.trim());
    if (lat == null || lon == null) return;
    _setPoint(GeoPoint(latitude: lat, longitude: lon, label: 'Typed point'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Expanded(
                flex: 7,
                child: _MapSelector(
                  controller: _mapController,
                  point: _point,
                  onPointSelected: (latLng) => _setPoint(
                    GeoPoint(
                      latitude: latLng.latitude,
                      longitude: latLng.longitude,
                      label: 'Selected point',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 390,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Context Music Exhibition',
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            const _SoftText(
                              'Tap or drag the OpenStreetMap view, then start the exhibition from the selected coordinates.',
                            ),
                            const SizedBox(height: 24),
                            _CoordinateField(
                              label: 'Latitude',
                              controller: _latController,
                              onSubmitted: (_) => _applyTypedCoordinates(),
                            ),
                            const SizedBox(height: 12),
                            _CoordinateField(
                              label: 'Longitude',
                              controller: _lonController,
                              onSubmitted: (_) => _applyTypedCoordinates(),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _applyTypedCoordinates,
                              icon: const Icon(Icons.edit_location_alt),
                              label: const Text('Use typed coordinates'),
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _PresetChip(
                                  label: 'London',
                                  onPressed: () => _setPoint(
                                    const GeoPoint(
                                      latitude: 51.5074,
                                      longitude: -0.1278,
                                      label: 'London',
                                    ),
                                  ),
                                ),
                                _PresetChip(
                                  label: 'Lake District',
                                  onPressed: () => _setPoint(
                                    const GeoPoint(
                                      latitude: 54.4609,
                                      longitude: -3.0886,
                                      label: 'Lake District',
                                    ),
                                  ),
                                ),
                                _PresetChip(
                                  label: 'Brighton coast',
                                  onPressed: () => _setPoint(
                                    const GeoPoint(
                                      latitude: 50.8225,
                                      longitude: -0.1372,
                                      label: 'Brighton coast',
                                    ),
                                  ),
                                ),
                                _PresetChip(
                                  label: 'Peak District',
                                  onPressed: () => _setPoint(
                                    const GeoPoint(
                                      latitude: 53.3498,
                                      longitude: -1.8330,
                                      label: 'Peak District',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _SelectedPointPanel(point: _point),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => widget.onStart(_point),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start exhibition'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExhibitionDashboard extends StatefulWidget {
  const ExhibitionDashboard({
    super.key,
    required this.initialPoint,
    required this.onChangeLocation,
  });

  final GeoPoint initialPoint;
  final VoidCallback onChangeLocation;

  @override
  State<ExhibitionDashboard> createState() => _ExhibitionDashboardState();
}

class _ExhibitionDashboardState extends State<ExhibitionDashboard> {
  final _musicLibrary = MusicLibrary();
  final _contextService = ContextDetectionService();
  final _recommender = MusicRecommender();
  final _bleService = CadenceBleService();
  final _player = AudioPlayer();

  List<MusicTrack> _tracks = [];
  late GeoPoint _point;
  EnvironmentContext _context = EnvironmentContext.mock('urban');
  Recommendation? _recommendation;
  BleDeviceReading? _bleReading;
  String _contextStatus = 'Preparing location context';
  String _bleStatus = 'Tap to connect CadenceMic';
  String _playerStatus = 'Ready';
  bool _loadingContext = false;
  bool _bleBusy = false;
  bool _bleConnected = false;
  bool _isPlaying = false;
  String? _playingTrackId;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  double _deviceBpm = 86;
  double _ambientVolume = 55;

  @override
  void initState() {
    super.initState();
    _point = widget.initialPoint;
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _playingTrackId = null;
          _playerStatus = 'Completed';
        }
      });
    });
    _bootExhibition();
  }

  Future<void> _bootExhibition() async {
    await _loadLibrary();
    await _detectContextFromSelectedPoint();
  }

  Future<void> _loadLibrary() async {
    final tracks = await _musicLibrary.loadSampleTracks();
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _updateRecommendationState();
    });
  }

  Future<void> _detectContextFromSelectedPoint() async {
    setState(() {
      _loadingContext = true;
      _contextStatus = 'Reading nearby map features';
    });

    try {
      final context = await _contextService.detectNearbyContext(_point);
      if (!mounted) return;
      setState(() {
        _context = context;
        _contextStatus = 'Live context from OpenStreetMap';
        _updateRecommendationState();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _context = EnvironmentContext.mock('urban');
        _contextStatus = 'Using fallback context';
        _updateRecommendationState();
      });
    } finally {
      if (mounted) {
        setState(() => _loadingContext = false);
      }
    }
  }

  void _updateRecommendationState() {
    _recommendation = _recommender.recommend(
      context: _context,
      bpm: _deviceBpm.round(),
      tracks: _tracks,
    );
  }

  void _setDemoInput({double? bpm, double? ambient}) {
    setState(() {
      if (bpm != null) _deviceBpm = bpm;
      if (ambient != null) _ambientVolume = ambient;
      _updateRecommendationState();
    });
    _syncPlayerVolume();
  }

  Future<void> _connectBleDevice() async {
    setState(() {
      _bleBusy = true;
      _bleStatus = 'Scanning for CadenceMic';
    });

    try {
      await _bleService.connect(
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _bleStatus = status);
        },
        onDisconnected: () {
          if (!mounted) return;
          setState(() {
            _bleConnected = false;
            _bleStatus = 'CadenceMic disconnected';
          });
        },
        onReading: (reading) {
          if (!mounted) return;
          setState(() {
            _bleReading = reading;
            _bleConnected = true;
            _bleStatus = 'CadenceMic live';
            if (reading.bpm > 0) _deviceBpm = reading.bpm.toDouble();
            _ambientVolume = reading.ambient.clamp(0, 100);
            _updateRecommendationState();
          });
          _syncPlayerVolume();
        },
      );
      if (!mounted) return;
      setState(() => _bleConnected = true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _bleStatus = 'BLE unavailable';
        _bleConnected = false;
      });
    } finally {
      if (mounted) {
        setState(() => _bleBusy = false);
      }
    }
  }

  Future<void> _disconnectBleDevice() async {
    setState(() {
      _bleBusy = true;
      _bleStatus = 'Disconnecting';
    });
    await _bleService.disconnect();
    if (!mounted) return;
    setState(() {
      _bleBusy = false;
      _bleConnected = false;
      _bleStatus = 'Tap to connect CadenceMic';
    });
  }

  Future<void> _playRecommendation() async {
    final recommendation = _recommendation;
    if (recommendation == null) return;

    setState(() => _playerStatus = 'Loading stream');
    try {
      await _player.setVolume(VolumeMapper.fromAmbient(_ambientVolume));
      await _player.setUrl(recommendation.track.audioUrl);
      await _player.play();
      if (!mounted) return;
      setState(() {
        _playingTrackId = recommendation.track.id;
        _playerStatus = 'Playing';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _playingTrackId = null;
        _playerStatus = 'Stream unavailable';
      });
    }
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _playingTrackId = null;
      _playerStatus = 'Stopped';
    });
  }

  Future<void> _syncPlayerVolume() async {
    await _player.setVolume(VolumeMapper.fromAmbient(_ambientVolume));
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
    final recommendation = _recommendation;
    final outputVolume = VolumeMapper.fromAmbient(_ambientVolume);
    final isCurrentTrackPlaying =
        _isPlaying && _playingTrackId == recommendation?.track.id;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _TopBar(
                  point: _point,
                  status: _contextStatus,
                  loading: _loadingContext,
                  onRefresh: _detectContextFromSelectedPoint,
                  onChangeLocation: widget.onChangeLocation,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 10,
                        child: _ContextStage(
                          contextData: _context,
                          recommendation: recommendation,
                          bpm: _deviceBpm.round(),
                          ambient: _ambientVolume,
                          outputVolume: outputVolume,
                          isPlaying: isCurrentTrackPlaying,
                          playerStatus: _playerStatus,
                          onPlay: _playRecommendation,
                          onStop: _stopPlayback,
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 360,
                        child: _ControlRail(
                          bleStatus: _bleStatus,
                          reading: _bleReading,
                          connected: _bleConnected,
                          busy: _bleBusy,
                          bpm: _deviceBpm,
                          ambient: _ambientVolume,
                          onConnect: _connectBleDevice,
                          onDisconnect: _disconnectBleDevice,
                          onBpmChanged: (value) => _setDemoInput(bpm: value),
                          onAmbientChanged: (value) =>
                              _setDemoInput(ambient: value),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;
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
            'Matched ${matched.isEmpty ? context.primary : matched.join(', ')} with target ${targetRange.min}-${targetRange.max} bpm.',
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

    onStatus('Connecting to CadenceMic');
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 15),
    );

    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        onDisconnected();
      }
    });

    onStatus('Reading sensor stream');
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
      final raw = utf8.decode(value, allowMalformed: true).trim();
      if (raw.isEmpty) return;
      onReading(BleDeviceReading.fromJsonText(raw));
    });
    await characteristic.setNotifyValue(true);
  }

  Future<BluetoothDevice> _findCadenceMic(ValueChanged<String> onStatus) async {
    onStatus('Scanning for CadenceMic');
    final completer = Completer<BluetoothDevice>();
    late StreamSubscription<List<ScanResult>> scanSubscription;

    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final device = result.device;
        final name = _deviceName(device).toLowerCase();
        if (name.contains('cadencemic') ||
            result.advertisementData.serviceUuids.contains(serviceUuid)) {
          if (!completer.isCompleted) completer.complete(device);
        }
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [serviceUuid],
      timeout: const Duration(seconds: 8),
    );

    try {
      return await completer.future.timeout(
        const Duration(seconds: 9),
        onTimeout: () => throw Exception('CadenceMic not found'),
      );
    } finally {
      await FlutterBluePlus.stopScan();
      await scanSubscription.cancel();
    }
  }

  Future<void> disconnect() async {
    await _valueSubscription?.cancel();
    await _connectionSubscription?.cancel();
    final device = _device;
    _device = null;
    if (device != null) {
      await device.disconnect();
    }
  }

  void dispose() {
    disconnect();
  }

  String _deviceName(BluetoothDevice device) {
    if (device.platformName.isNotEmpty) return device.platformName;
    if (device.advName.isNotEmpty) return device.advName;
    return device.remoteId.str;
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
      'ContextAwareMusicDissertation/1.0 (Flutter Android exhibition app)';

  static const _overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.openstreetmap.ru/api/interpreter',
  ];

  Future<EnvironmentContext> detectNearbyContext(GeoPoint point) async {
    final radiusMeters = 700;
    final query = '''
[out:json][timeout:25];
(
  nwr(around:$radiusMeters,${point.latitude},${point.longitude})["natural"];
  nwr(around:$radiusMeters,${point.latitude},${point.longitude})["landuse"];
  nwr(around:$radiusMeters,${point.latitude},${point.longitude})["waterway"];
  nwr(around:$radiusMeters,${point.latitude},${point.longitude})["leisure"];
  nwr(around:$radiusMeters,${point.latitude},${point.longitude})["building"];
  nwr(around:$radiusMeters,${point.latitude},${point.longitude})["highway"];
  nwr(around:$radiusMeters,${point.latitude},${point.longitude})["amenity"];
  nwr(around:$radiusMeters,${point.latitude},${point.longitude})["place"];
  nwr(around:$radiusMeters,${point.latitude},${point.longitude})["tourism"];
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
    throw Exception('Overpass HTTP ${status ?? 'unknown'}');
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
      if (_roadWeight(highway) > 0) {
        add('road', _roadWeight(highway));
        if (_isMajorRoad(highway)) add('urban', 0.25);
      }
      if (building != null) add('urban', 1.1);
      if (amenity != null) add('urban', 1.0);
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

class _MapSelector extends StatelessWidget {
  const _MapSelector({
    required this.controller,
    required this.point,
    required this.onPointSelected,
  });

  final MapController controller;
  final GeoPoint point;
  final ValueChanged<LatLng> onPointSelected;

  @override
  Widget build(BuildContext context) {
    final selected = LatLng(point.latitude, point.longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: ExhibitionColors.surface,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Stack(
          children: [
            FlutterMap(
              mapController: controller,
              options: MapOptions(
                initialCenter: selected,
                initialZoom: 13,
                minZoom: 3,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onTap: (_, latLng) => onPointSelected(latLng),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'app_exhibition',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: selected,
                      width: 56,
                      height: 56,
                      child: const Icon(
                        Icons.location_on,
                        color: ExhibitionColors.coral,
                        size: 48,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 18,
              bottom: 18,
              child: _GlassLabel(
                icon: Icons.touch_app,
                text: 'Tap the real map to select the exhibition GPS point',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.point,
    required this.status,
    required this.loading,
    required this.onRefresh,
    required this.onChangeLocation,
  });

  final GeoPoint point;
  final String status;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onChangeLocation;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Context Music Exhibition',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: 4),
              _SoftText(
                '${point.label}  ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}  ·  $status',
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Refresh context',
          onPressed: loading ? null : onRefresh,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'Change location',
          onPressed: onChangeLocation,
          icon: const Icon(Icons.map),
        ),
      ],
    );
  }
}

class _ContextStage extends StatelessWidget {
  const _ContextStage({
    required this.contextData,
    required this.recommendation,
    required this.bpm,
    required this.ambient,
    required this.outputVolume,
    required this.isPlaying,
    required this.playerStatus,
    required this.onPlay,
    required this.onStop,
  });

  final EnvironmentContext contextData;
  final Recommendation? recommendation;
  final int bpm;
  final double ambient;
  final double outputVolume;
  final bool isPlaying;
  final String playerStatus;
  final Future<void> Function() onPlay;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final rec = recommendation;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: ExhibitionColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ContextTitle(primary: contextData.primary),
              ),
              _MetricBlock(
                icon: Icons.favorite,
                label: 'BPM',
                value: '$bpm',
                color: ExhibitionColors.coral,
              ),
              const SizedBox(width: 12),
              _MetricBlock(
                icon: Icons.graphic_eq,
                label: 'Ambient',
                value: '${ambient.round()}',
                color: ExhibitionColors.sky,
              ),
              const SizedBox(width: 12),
              _MetricBlock(
                icon: Icons.volume_up,
                label: 'Output',
                value: '${(outputVolume * 100).round()}%',
                color: ExhibitionColors.sun,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final keyword in contextData.musicKeywords.take(6))
                _KeywordChip(keyword),
            ],
          ),
          const SizedBox(height: 22),
          Expanded(
            child: rec == null
                ? const Center(child: CircularProgressIndicator())
                : _RecommendationShowcase(
                    recommendation: rec,
                    isPlaying: isPlaying,
                    playerStatus: playerStatus,
                    onPlay: onPlay,
                    onStop: onStop,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContextTitle extends StatelessWidget {
  const _ContextTitle({required this.primary});

  final String primary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SoftText('Detected context'),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _labelForContext(primary),
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
          ),
        ),
      ],
    );
  }
}

class _RecommendationShowcase extends StatelessWidget {
  const _RecommendationShowcase({
    required this.recommendation,
    required this.isPlaying,
    required this.playerStatus,
    required this.onPlay,
    required this.onStop,
  });

  final Recommendation recommendation;
  final bool isPlaying;
  final String playerStatus;
  final Future<void> Function() onPlay;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SoftText('Recommended music'),
                const SizedBox(height: 10),
                Text(
                  recommendation.track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  recommendation.track.artist,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: isPlaying ? onStop : onPlay,
                      icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                      label: Text(isPlaying ? 'Stop' : 'Play'),
                    ),
                    const SizedBox(width: 14),
                    _StatusBadge(
                      icon: isPlaying ? Icons.equalizer : Icons.stream,
                      text: playerStatus,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 4,
          child: Column(
            children: [
              _MatchMeter(
                label: 'Context match',
                value: recommendation.keywordScore,
                color: ExhibitionColors.mint,
              ),
              const SizedBox(height: 12),
              _MatchMeter(
                label: 'BPM match',
                value: recommendation.bpmScore,
                color: ExhibitionColors.coral,
              ),
              const SizedBox(height: 12),
              _TrackFact(
                icon: Icons.speed,
                label: 'Track BPM',
                value: '${recommendation.track.bpm}',
              ),
              const SizedBox(height: 12),
              _TrackFact(
                icon: Icons.tune,
                label: 'Target range',
                value:
                    '${recommendation.targetBpmRange.min}-${recommendation.targetBpmRange.max}',
              ),
              const SizedBox(height: 12),
              _TrackFact(
                icon: Icons.auto_awesome,
                label: 'Why this track',
                value: recommendation.reason,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ControlRail extends StatelessWidget {
  const _ControlRail({
    required this.bleStatus,
    required this.reading,
    required this.connected,
    required this.busy,
    required this.bpm,
    required this.ambient,
    required this.onConnect,
    required this.onDisconnect,
    required this.onBpmChanged,
    required this.onAmbientChanged,
  });

  final String bleStatus;
  final BleDeviceReading? reading;
  final bool connected;
  final bool busy;
  final double bpm;
  final double ambient;
  final Future<void> Function() onConnect;
  final Future<void> Function() onDisconnect;
  final ValueChanged<double> onBpmChanged;
  final ValueChanged<double> onAmbientChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ExhibitionColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                connected ? Icons.bluetooth_connected : Icons.bluetooth,
                color: connected
                    ? ExhibitionColors.mint
                    : Colors.white.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CadenceMic',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: connected ? 'Disconnect BLE' : 'Connect BLE',
                onPressed: busy
                    ? null
                    : connected
                        ? onDisconnect
                        : onConnect,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(connected ? Icons.link_off : Icons.link),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SoftText(bleStatus),
          const SizedBox(height: 18),
          _LiveValue(
            label: 'BPM',
            value: bpm.round().toString(),
            icon: Icons.favorite,
            color: ExhibitionColors.coral,
          ),
          Slider(
            value: bpm,
            min: 50,
            max: 160,
            divisions: 110,
            label: '${bpm.round()} bpm',
            onChanged: onBpmChanged,
          ),
          const SizedBox(height: 10),
          _LiveValue(
            label: 'Ambient',
            value: ambient.round().toString(),
            icon: Icons.graphic_eq,
            color: ExhibitionColors.sky,
          ),
          Slider(
            value: ambient,
            min: 0,
            max: 100,
            divisions: 100,
            label: ambient.round().toString(),
            onChanged: onAmbientChanged,
          ),
          const Spacer(),
          if (reading != null)
            _ReadingPanel(reading: reading!)
          else
            const _SoftText(
              'Manual controls stay available when the physical device is not connected.',
            ),
        ],
      ),
    );
  }
}

class _SelectedPointPanel extends StatelessWidget {
  const _SelectedPointPanel({required this.point});

  final GeoPoint point;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ExhibitionColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: ExhibitionColors.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${point.label}\n${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordinateField extends StatelessWidget {
  const _CoordinateField({
    required this.label,
    required this.controller,
    required this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.place, size: 18),
      onPressed: onPressed,
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          _SoftText(label),
        ],
      ),
    );
  }
}

class _MatchMeter extends StatelessWidget {
  const _MatchMeter({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final percent = (value.clamp(0, 1) * 100).round();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text('$percent%'),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: value.clamp(0, 1),
              color: color,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackFact extends StatelessWidget {
  const _TrackFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: ExhibitionColors.mint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SoftText(label),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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

class _LiveValue extends StatelessWidget {
  const _LiveValue({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Text(label),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

class _ReadingPanel extends StatelessWidget {
  const _ReadingPanel({required this.reading});

  final BleDeviceReading reading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SoftText('Live sensor reading'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusBadge(icon: Icons.favorite, text: '${reading.bpm} bpm'),
              _StatusBadge(
                icon: Icons.graphic_eq,
                text: reading.ambient.toStringAsFixed(1),
              ),
              _StatusBadge(
                icon: reading.step ? Icons.directions_walk : Icons.pause,
                text: reading.step ? 'Step' : 'Still',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeywordChip extends StatelessWidget {
  const _KeywordChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ExhibitionColors.mint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ExhibitionColors.mint.withValues(alpha: 0.30)),
      ),
      child: Text(label),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.icon, required this.text});

  final IconData icon;
  final String text;

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
          Text(text),
        ],
      ),
    );
  }
}

class _GlassLabel extends StatelessWidget {
  const _GlassLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }
}

class _SoftText extends StatelessWidget {
  const _SoftText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
    );
  }
}

String _labelForContext(String context) {
  return switch (context) {
    'forest_mountain' => 'Forest / Mountain',
    'water' => 'Waterfront',
    'park' => 'Park',
    'urban' => 'Urban',
    'road' => 'Road',
    _ => context,
  };
}
