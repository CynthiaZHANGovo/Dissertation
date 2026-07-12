import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_exhibition/main.dart';

void main() {
  testWidgets('loads the In Tune location selector', (tester) async {
    await tester.pumpWidget(const ContextAwareExhibitionApp());
    await tester.pumpAndSettle();

    expect(find.text('In Tune'), findsOneWidget);
    expect(find.text('Continue to In Tune'), findsOneWidget);
    expect(find.text('Latitude'), findsOneWidget);
    expect(find.text('UCL East'), findsWidgets);
    expect(find.text('Hyde Park'), findsOneWidget);
    expect(find.text('London Bridge / Thames'), findsOneWidget);
    expect(find.text('A40 Westway'), findsOneWidget);
    expect(find.text('Epping Forest'), findsOneWidget);
    expect(find.text('Start exhibition'), findsNothing);
  });

  testWidgets('dashboard fits a compact landscape tablet', (tester) async {
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ContextAwareExhibitionApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to In Tune'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Reading location...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Reading location...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('In Tune'), findsOneWidget);
    expect(find.text('Detected context'), findsOneWidget);
    expect(find.text('CadenceMic'), findsOneWidget);
    expect(find.text('Urban'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('keeps output volume safe for raw BLE ambient values', () {
    expect(VolumeMapper.fromAmbient(-50), 0.10);
    expect(VolumeMapper.fromAmbient(1000), closeTo(0.80, 0.000001));
    expect(VolumeMapper.fromAmbient(double.nan), inInclusiveRange(0.10, 0.80));
  });

  testWidgets('inactivity guard resets and fires after one minute', (
    tester,
  ) async {
    var timeoutCount = 0;
    final guard = InactivityGuard(
      duration: const Duration(minutes: 1),
      onTimeout: () => timeoutCount += 1,
    );

    guard.arm();
    await tester.pump(const Duration(seconds: 59));
    expect(timeoutCount, 0);

    guard.arm();
    await tester.pump(const Duration(seconds: 59));
    expect(timeoutCount, 0);

    await tester.pump(const Duration(seconds: 1));
    expect(timeoutCount, 1);
    guard.dispose();
  });

  group('context fallback selection', () {
    test('curated London presets resolve to their intended contexts', () async {
      final service = ContextDetectionService();
      const presets = <GeoPoint>[
        GeoPoint(
          latitude: 51.5381,
          longitude: -0.0106,
          label: 'UCL East',
          curatedContext: 'urban',
        ),
        GeoPoint(
          latitude: 51.5110,
          longitude: -0.1680,
          label: 'Hyde Park',
          curatedContext: 'park',
        ),
        GeoPoint(
          latitude: 51.5075,
          longitude: -0.0855,
          label: 'London Bridge / Thames',
          curatedContext: 'water',
        ),
        GeoPoint(
          latitude: 51.519649,
          longitude: -0.189106,
          label: 'A40 Westway',
          curatedContext: 'road',
        ),
        GeoPoint(
          latitude: 51.6573673,
          longitude: 0.0621929,
          label: 'Epping Forest',
          curatedContext: 'forest_mountain',
        ),
      ];

      final contexts = <String>[];
      for (final preset in presets) {
        contexts.add((await service.detectNearbyContext(preset)).primary);
      }

      expect(contexts, ['urban', 'park', 'water', 'road', 'forest_mountain']);
    });

    test('uses urban when no other context has strong evidence', () {
      expect(ContextSelector.primaryFromScores({'urban': 100}), 'urban');
      expect(
        ContextSelector.primaryFromScores({'urban': 100, 'road': 1.2}),
        'urban',
      );
      expect(
        ContextSelector.primaryFromScores({
          'urban': 100,
          'forest_mountain': 2.2,
        }),
        'urban',
      );
    });

    test('clear environmental evidence takes priority over urban', () {
      expect(
        ContextSelector.primaryFromScores({'urban': 100, 'park': 2.8}),
        'park',
      );
      expect(
        ContextSelector.primaryFromScores({'urban': 100, 'water': 3.0}),
        'water',
      );
      expect(
        ContextSelector.primaryFromScores({
          'urban': 100,
          'forest_mountain': 3.5,
        }),
        'forest_mountain',
      );
      expect(
        ContextSelector.primaryFromScores({'urban': 100, 'road': 3.5}),
        'road',
      );
    });

    test('uses park, forest, water, road, urban priority order', () {
      const allContexts = {
        'urban': 100.0,
        'road': 4.0,
        'water': 3.0,
        'forest_mountain': 3.5,
        'park': 2.8,
      };
      expect(ContextSelector.primaryFromScores(allContexts), 'park');

      expect(
        ContextSelector.primaryFromScores({...allContexts, 'park': 0}),
        'forest_mountain',
      );
      expect(
        ContextSelector.primaryFromScores({
          ...allContexts,
          'park': 0,
          'forest_mountain': 0,
        }),
        'water',
      );
      expect(
        ContextSelector.primaryFromScores({
          ...allContexts,
          'park': 0,
          'forest_mountain': 0,
          'water': 0,
        }),
        'road',
      );
      expect(ContextSelector.primaryFromScores(const {'urban': 100}), 'urban');
    });

    test('OSM water=river is scored as water', () {
      final elements = <Map<String, dynamic>>[
        ...List.generate(
          20,
          (_) => <String, dynamic>{
            'tags': <String, dynamic>{'building': 'yes'},
          },
        ),
        <String, dynamic>{
          'tags': <String, dynamic>{'water': 'river'},
        },
      ];
      final scores = ContextDetectionService().scoreElements(elements);

      expect(scores['water'], 3);
      expect(ContextSelector.primaryFromScores(scores), 'water');
    });
  });

  group('battery runtime estimate', () {
    test('parses the compact firmware payload', () {
      final reading = BleDeviceReading.fromJsonText(
        '{"bpm":164,"ambient":31,"battery":55,"voltage":3.93}',
      );

      expect(reading.batteryPercent, 55);
      expect(reading.voltage, 3.93);
      expect(reading.current, 0);
      expect(reading.step, isFalse);
    });

    test('formats remaining time from the calibrated full runtime', () {
      expect(DeviceRuntimeEstimator.formatRemaining(55), '2h 55m');
      expect(DeviceRuntimeEstimator.formatApproximate(55), 'About 3 hours');
      expect(DeviceRuntimeEstimator.formatRemaining(null), '--');
      expect(DeviceRuntimeEstimator.formatApproximate(null), '--');
    });

    test('ignores an implausible battery jump', () {
      const stable = BleDeviceReading(
        bpm: 86,
        ambient: 55,
        current: 0,
        step: false,
        raw: '{}',
        batteryPercent: 60,
        voltage: 3.95,
      );
      const spike = BleDeviceReading(
        bpm: 86,
        ambient: 55,
        current: 0,
        step: false,
        raw: '{}',
        batteryPercent: 20,
        voltage: 3.40,
      );
      final filter = BatteryReadingFilter();

      filter.accept(stable);
      final result = filter.accept(spike);

      expect(result.percent, 60);
      expect(result.voltage, 3.95);
    });
  });

  test('track details hide placeholder artist and use database tags', () {
    const track = MusicTrack(
      id: 'sample',
      title: 'Sample',
      artist: 'Streaming Sample',
      bpm: 90,
      environmentTags: ['water'],
      musicTags: ['chill', 'flowing', 'calm'],
      audioUrl: 'https://example.com/audio.mp3',
    );

    expect(track.displayDetails, 'chill · flowing · calm');
    expect(track.displayDetails, isNot(contains('Streaming Sample')));
  });
}
