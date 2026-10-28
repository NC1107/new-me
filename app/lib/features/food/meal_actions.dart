import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/log_actions.dart';
import '../../theme/tokens.dart';
import '../../util/client_op_id.dart';
import '../../util/errors.dart';
import '../../util/format.dart';

/// Deletes a meal and offers an Undo that logs it again. A failure says why and offers no Undo.
/// [onUndone] runs after an Undo brought the meal back, for a list that holds its own copy.
Future<void> deleteMealWithUndo(
  ScaffoldMessengerState messenger,
  LogActions actions,
  MealLog meal, {
  VoidCallback? onUndone,
}) async {
  HapticFeedback.mediumImpact();
  try {
    await actions.delete(meal);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(errorCopy(e))));
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Deleted ${meal.name}'),
        // An action makes a snack bar stay until tapped; Undo is offered for a while only.
        persist: false,
        duration: kUndoWindow,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await actions.create(meal.toDraft(newClientOpId()));
              onUndone?.call();
            } on ApiException catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(errorCopy(e))));
            }
          },
        ),
      ),
    );
}

/// Whether the server would still take a change to this meal: its day is today, or yesterday
/// while [backdateUntil] has not passed. Without Today loaded the server decides.
bool mealIsEditable({
  required MealLog meal,
  required String? localToday,
  required DateTime? backdateUntil,
  required DateTime now,
}) {
  if (localToday == null) return true;
  if (meal.localDate == localToday) return true;
  return backdateUntil != null &&
      now.isBefore(backdateUntil) &&
      meal.localDate == previousDate(localToday);
}
