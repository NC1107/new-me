# v18: shared household habits

Nick asked for habits that belong to both people, like doing the laundry or cleaning the apartment.
A shared habit (a chore) is one list both people see, that either person marks done.

## What it is

A chore has a name, an icon from the habit icon set, and a schedule.
The schedule is one of four kinds.

- `daily`: due every day until it is done that day.
- `weekdays`: due on chosen weekdays (ISO, Monday 1).
- `weekly`: due seven days after it was last done.
- `every_n`: due N days after it was last done, N from 2 to 365.

A chore that was never done is due from the day it was created, in the creator's time zone.
A chore that is done late is counted from the day it was actually done, so a skipped week does not pile up a backlog.
A `daily` chore is never overdue, it is simply due today until done.
A `weekdays` chore becomes overdue when its scheduled day passes without a mark.

Either person can create, edit, delete and mark done.
Deleting asks for confirmation in the app, and removes the chore for both people.
Gems already earned from a deleted chore stay, because they sit on days that may be finalized.

## Due and overdue are per viewer

The server stores when a chore was done as an instant and the doer's local day.
Every response computes the state for the person asking, in their own zone and their own today.
`state` is `overdue`, `today` or `upcoming`, `dueOn` is the date, and `daysFromToday` is negative when overdue.
`doneToday` is true when anyone did it on the viewer's today, and `doneByMe` when the viewer did.
The rules are pure functions in `server/internal/score/shared_habits.go` (`SharedDue`), table-tested without a database.

## Credit

The person who marks a chore done earns `score.SharedHabitGems`, which is 25, the worth a personal habit gets when it is created without one.
The gems are written as a row in `shared_habit_marks` with the doer's local day.
Scoring adds them to the day's bonus points, next to the weekly challenge award.
Bonus points never enter the percent, the counted flag or the quest maximum, so a chore cannot change either person's daily percent or streak.
They do count toward the gem total, the shared bank and rewards.

A chore marked done on someone's day is paid once.
A second tap that day, by either person, changes nothing and pays nothing, so a stale screen or a double tap cannot earn twice.
Marking a chore early, before it is due, is allowed and paid.
Nothing stops someone marking a weekly chore every day for gems.
That is a trust call between two people who live together, and the rule can be tightened later if it is ever used that way.

Undo removes the caller's own latest mark of a chore, only while that mark is still the chore's latest one and its day is still writable.
That is the same window as every other write (today, or yesterday until the grace hour passes).
Undo deletes the row, so the gems leave with it.

## Push

When a person marks a chore done, the partner gets a push, kind `shared_habit`, titled "Nick did Do the laundry".
It goes through `together.Service.Notify`, so quiet hours, away days and the held-push queue apply like every other partner push.
It follows the partner-done switch in Me, notifications.
A repeat tap that pays nothing sends nothing, and undo sends nothing.

## API

All routes need the app key and a device token.

| Route | What it does |
| --- | --- |
| `GET /api/shared-habits` | The list for the caller, overdue first, then due today, then upcoming by date. |
| `POST /api/shared-habits` | Create from `name`, `icon` and `schedule`. At most 40 live chores. |
| `PATCH /api/shared-habits/{id}` | Change any of name, icon, schedule. |
| `DELETE /api/shared-habits/{id}` | Remove for both people. |
| `POST /api/shared-habits/{id}/done` | Mark done by the caller. Answers the chore and `gemsEarned`, 0 when it was already done that day. |
| `DELETE /api/shared-habits/{id}/done` | Undo the caller's own latest mark. |

`schedule` is `{"kind": "weekly"}`, `{"kind": "weekdays", "weekdays": [1, 3, 5]}` or `{"kind": "every_n", "everyDays": 3}`.
Five household icons were added to the icon set (`local_laundry_service`, `cleaning_services`, `delete`, `shopping_cart`, `home`), which personal habits can use too.

## Data

Migration `0030_v18_shared_habits.sql` adds two tables.

- `shared_habits`: the chore, its schedule, `start_on`, `created_by`, soft delete.
- `shared_habit_marks`: one row per time it was done, with the doer, their local day, the instant and the gems.

## App

- Us has a Home section below the two people and above the weekly challenge.
  Due chores come first (labelled "Due now" when there are upcoming ones too), then "Coming up".
  Each row shows the icon, the due state in amber when overdue, the schedule and who did it last and how long ago, and a round check.
  The check marks it done, and tapping it again undoes your own mark.
  If the partner did it today the check is filled and cannot be undone by you.
  Tapping the row opens the sheet to edit or delete.
- The sheet has quick-add templates (laundry, dishes, clean the bathroom, vacuum, take out the trash, change the sheets, groceries, water the plants), a name, the icon grid with household icons first, and the schedule.
- Today's habit strip shows chores that are due, or were done today, as chips with a small people badge.
  A tap marks the chore done, and a second tap undoes your own mark.
  The "x of y" count in the strip header counts personal habits only.
- Pull to refresh on Us reloads the list.

## Not in scope

- Assigning a chore to one person or alternating who does it.
- Chore reminders on the phone before the due day.
- Separate notification switch for chores.
- Streaks or stats for chores.
