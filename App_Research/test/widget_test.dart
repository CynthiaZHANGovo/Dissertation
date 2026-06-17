import 'package:flutter_test/flutter_test.dart';

import 'package:app_research/main.dart';

void main() {
  testWidgets('loads the context aware music dashboard', (tester) async {
    await tester.pumpWidget(const ContextAwareMusicApp());
    await tester.pumpAndSettle();

    expect(find.text('Context Aware Music'), findsWidgets);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Device Input'), findsOneWidget);
    expect(find.text('FOREST_MOUNTAIN'), findsOneWidget);
  });
}
