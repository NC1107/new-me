import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/me/goals_page.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'habit_fixtures.dart';
import 'test_support.dart';

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('Goals lists every habit and the way to add one', (tester) async {
    final app = TestApp(tester, habitsServer(), surfaceHeight: 4000);
    await app.pump(const GoalsPage());
    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('Brush teeth'), findsOneWidget);
    expect(find.text('Add a habit'), findsNothing);
    expect(find.text('ADD A HABIT'), findsOneWidget);
  });

  testWidgets('Me has no Habits row of its own', (tester) async {
    final app = TestApp(tester, habitsServer());
    await app.pump(const MeScreen());
    expect(find.text('Habits'), findsNothing);
  });
}
