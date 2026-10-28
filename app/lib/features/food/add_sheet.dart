import 'package:flutter/material.dart';

import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/choice_card.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import '../log/log_kind.dart';
import '../log/log_sheet.dart';
import '../me/food_edit_page.dart';

/// Asks whether a meal is being logged or a food saved, so the Food tab has one add button.
Future<void> showAddFoodSheet(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const AddFoodSheet());

class AddFoodSheet extends StatelessWidget {
  const AddFoodSheet({super.key});

  @override
  Widget build(BuildContext context) {
    // The sheet closes first, so what opens next sits on the tab and not on top of the sheet.
    void then(void Function(BuildContext context) open) {
      final navigator = Navigator.of(context);
      navigator.pop();
      open(navigator.context);
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text('What are you adding?', style: AppText.title),
            ),
            const SizedBox(height: 16),
            ChoiceCard(
              icon: Icons.restaurant_rounded,
              iconPalette: questPalette('meals_logged'),
              title: 'Meal',
              subtitle: 'Log what you ate',
              onTap: () => then((c) => showLogSheet(c, kind: LogKind.meal, focusSearch: true)),
            ),
            const SizedBox(height: 10),
            ChoiceCard(
              icon: Icons.bookmark_add_rounded,
              iconPalette: questPalette('meals_logged'),
              title: 'Food',
              subtitle: 'Save a food with its exact numbers',
              onTap: () => then((c) => pushPage(c, const FoodEditPage())),
            ),
          ],
        ),
      ),
    );
  }
}
