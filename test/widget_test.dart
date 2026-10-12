import 'package:flutter_test/flutter_test.dart';
import 'package:mindtrack_pro/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MindTrackApp());
    expect(find.byType(MindTrackApp), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
  });
}
