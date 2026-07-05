import 'package:flutter_test/flutter_test.dart';

import 'package:app_research/main.dart';

void main() {
  test('volume mapping always stays in a safe range', () {
    expect(VolumeMapper.fromAmbient(-100), 0.3);
    expect(VolumeMapper.fromAmbient(1000), 0.8);
    expect(VolumeMapper.fromAmbient(double.nan), 0.55);
  });

  test('sensor filter ignores invalid and missing readings', () {
    final filter = SensorInputFilter();
    final result = filter.accept(
      const BleDeviceReading(
        bpm: 0,
        ambient: 999,
        current: 0,
        step: false,
        raw: '{}',
      ),
      currentBpm: 86,
      currentAmbient: 55,
    );

    expect(result.bpmAccepted, isFalse);
    expect(result.ambientAccepted, isFalse);
    expect(result.bpm, 86);
    expect(result.ambient, 55);
  });

  test('sensor filter limits sudden valid changes', () {
    final filter = SensorInputFilter();
    final result = filter.accept(
      const BleDeviceReading(
        bpm: 180,
        ambient: 100,
        current: 100,
        step: true,
        raw: '{}',
      ),
      currentBpm: 86,
      currentAmbient: 55,
    );

    expect(result.bpm, closeTo(88.4, 0.01));
    expect(result.ambient, closeTo(55.8, 0.01));
  });

  test('parses battery telemetry and estimates remaining runtime', () {
    final reading = BleDeviceReading.fromJsonText(
      '{"bpm":164,"ambient":31,"battery":55,"voltage":3.93}',
    );

    expect(reading.batteryPercent, 55);
    expect(reading.batteryVoltage, 3.93);
    final remaining = BatteryRuntimeEstimator.remaining(reading.batteryPercent);
    expect(remaining, const Duration(minutes: 175));
    expect(
      BatteryRuntimeEstimator.approximateLabel(remaining!),
      'Around 2–3 h left',
    );
  });

  test('ignores invalid startup battery telemetry', () {
    final reading = BleDeviceReading.fromJsonText(
      '{"bpm":0,"ambient":0,"battery":0,"voltage":0}',
    );

    expect(reading.batteryPercent, isNull);
    expect(reading.batteryVoltage, isNull);
  });

  test('Overpass tag mapping resists dense urban feature counts', () {
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

  test('context conflicts use park, forest, water, road, urban order', () {
    const scores = {
      'urban': 100.0,
      'road': 4.0,
      'water': 3.0,
      'forest_mountain': 3.5,
      'park': 2.8,
    };

    expect(ContextSelector.primaryFromScores(scores), 'park');
    expect(
      ContextSelector.primaryFromScores({...scores, 'park': 0}),
      'forest_mountain',
    );
    expect(
      ContextSelector.primaryFromScores({
        ...scores,
        'park': 0,
        'forest_mountain': 0,
      }),
      'water',
    );
  });

  testWidgets('loads the context aware music dashboard', (tester) async {
    await tester.pumpWidget(const ContextAwareMusicApp());
    await tester.pumpAndSettle();

    expect(find.text('Context Aware Music'), findsWidgets);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Device Input'), findsOneWidget);
    expect(find.text('FOREST_MOUNTAIN'), findsOneWidget);
  });
}
