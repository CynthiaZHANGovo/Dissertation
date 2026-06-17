import 'package:flutter_test/flutter_test.dart';

import 'package:app_exhibition/main.dart';

void main() {
  testWidgets('loads the exhibition location selector', (tester) async {
    await tester.pumpWidget(const ContextAwareExhibitionApp());
    await tester.pumpAndSettle();

    expect(find.text('Context Music Exhibition'), findsOneWidget);
    expect(find.text('Start exhibition'), findsOneWidget);
    expect(find.text('Latitude'), findsOneWidget);
  });
}
