import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('Me lists Habits with the count and opens the list', (tester) async {
    final app = TestApp(tester, habitsServer());
    await app.pump(const MeScreen());
    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('4 habits'), findsOneWidget);
    await app.tap(find.text('Habits'));
    expect(find.text('Marked off from Today in one tap.'), findsOneWidget);
    expect(find.text('Brush teeth'), findsOneWidget);
  });

  testWidgets('a single habit reads singular', (tester) async {
    final app = TestApp(tester, habitsServer(all: [allHabits().first]));
    await app.pump(const MeScreen());
    expect(find.text('1 habit'), findsOneWidget);
  });
}
