# Open questions before the design is final

Consolidated from the feasibility sweep (see `feasibility-digest.md`) and deduplicated.
Decisions already made on 2026-10-26 and not re-asked here: Flutter app, Go + Postgres backend in Docker, Claude API allowed from the server, iOS builds on cloud CI reusing the check-in TestFlight secrets, TestFlight internal testing only.

Questions marked (check on phone) need someone to open Settings or the Health app.

## A. People, schedules, fairness

1. Nadia's fixed weekly commitments: work hours, commute, which days and hours are horse days, and how physical they are (riding only, or mucking and lifting). Does the horse schedule change week to week?
2. Would she do a 20-second weekly "this week looks normal / busy / horse-heavy" check-in so her targets scale, with that input visible to you?
3. How competitive is each of you, honestly? Head-to-head as the main loop, or cooperative-first (household streak, shared quests) with a light weekly duel?
4. Should raw leaderboards (most pushups, most miles) be visible at all, even as a non-scoring bragging tab?
5. What does "fair" mean to you both: percent of your own target, capacity scaling by free time, or separate leagues per category?
6. Rewards you would actually care about: date-night fund, weekly winner picks the weekend meal or movie, a bigger quarterly reward? Who controls payout?
7. Self-reported items (teeth, creatine, Huel, cooked at home, reading minutes): pure honor system, or a partner "flag this" step?
8. When does a day end: midnight or 04:00? Grace windows: creatine and Huel count until noon? Fixed AM/PM windows for teeth?

## B. Devices and data sources

9. (check on scale) Renpho model or HVIN on the sticker underneath, and is it Bluetooth-only or Wi-Fi?
10. Do you each have your own Renpho Health account and profile, and has auto-recognition assigned weigh-ins correctly so far?
11. (check on phone) Health > Sources on both phones: is Renpho writing weight, body fat %, lean body mass and BMI? Only weight and body fat % are guaranteed.
12. Do you both wear the Apple Watch to bed every night? When does each of you charge it?
13. (check on phone) Are both phones on iOS 26.x? AlarmKit and medication dose events need it.
14. Toothbrushes: Oral-B, Sonicare, Oclean, Quip, or plain? Only some apps write brushing events to Health.
15. Is "data fresh by next morning plus whenever the app opens" enough, or do you want near-real-time partner comparisons during the day? Near-real-time means a Swift background sync shim in v1.
16. Do you want a watchOS companion app (one-tap creatine and teeth, start today's planned workout, see the plan on the wrist), or is iPhone plus normal Watch workouts flowing into Health enough? A Watch app changes signing and the build.

## C. Workouts and running

17. Dumbbells: adjustable or fixed pairs, which weights? Does Nadia use a different set?
18. Apartment gym equipment: rack, barbell, cables, machines, treadmill brand?
19. Per person: lifting history, can you each run 20 minutes continuously today, injuries or limits (knees, shoulders, fingers)?
20. Per person: how many training days per week, and realistic session length on workdays versus off days?
21. Climbing: how often, bouldering or lead, hangboard or campus use?
22. Nadia: strength training too, or yoga plus running as her base? How should yoga sessions be built: her own routines, videos, studio classes?
23. Does riding count as a workout, as external load for recovery, or not at all?
24. Pushup and pull-up counts are not in HealthKit. Manual rep logging per set, periodic max-rep tests, or both?
25. Should the plan be pushed to the Watch (WorkoutKit) or logged in the app and imported from Health?

## D. Food

26. Calorie depth: calories and protein only, or full macros, fiber, sodium, micronutrients?
27. Goals per person: cut, maintain, build? Are you fine with scoring rewarding logging and home cooking but never lower calories?
28. Is "cooked at home" scored per person or per household dinner? What counts as eating out (coffee, lunch at work, groceries delivered)?
29. How is "no DoorDash / no eating out" recorded: honor-system tap, partner confirm, something else?
30. Recipes and meal planning: a Mealie container in the stack, recipes in the app's own tables, or no recipes in v1? Do you want a weekly meal plan and grocery list?
31. Where do you shop and what is a typical pantry? This drives a 30 to 50 barcode hit-rate test before building scanning.
32. Do restaurant or chain meals need nutrition lookup, or is a quick-add estimate fine?

## E. Reading and audiobooks

33. Where does each of you read or listen today: Audiobookshelf, Audible, Libby, Apple Books, Kindle, paper? Roughly what share is audiobooks?
34. Would you move audiobooks into Audiobookshelf (it is already at books.npc-server.top) so progress is automatic, or must listening stay in Audible or Libby?
35. Do either of you use Hardcover, StoryGraph or Goodreads already?
36. Points by minutes, pages or percent, or finished books? Should ebook and paper minutes count equal to audiobook minutes? Daily cap?
37. Comfortable creating a couple of Shortcuts personal automations on each phone (app opened or closed sends a ping), or should the app avoid any manual iOS setup?

## F. Screen time, alarm, math

38. Screen time cannot be read by an app. Is a daily or weekly screenshot of Settings > Screen Time (OCR extracts the number) acceptable as the baseline?
39. Should I request the Family Controls entitlement from Apple in parallel, accepting that approval may take weeks or be refused for a private app, to upgrade to automatic coarse buckets later?
40. Reward lower total time, or only specific categories (social, video)?
41. The "did not type the password for more time" idea is not detectable. Drop it, or replace it with something else?
42. Apple always lets you stop an alarm. Is "alarm rings, then the app prompts a math check-in that earns points" acceptable instead of a hard math-to-dismiss alarm? Or keep your current alarm clock?
43. Should math problems also be a standalone daily habit (difficulty, scoring), or only the wake-up check?

## G. Health, bloodwork, supplements, sleep

44. Which lab or health system do you each use (Quest, Labcorp, Kaiser or another Epic system)? Is it connected under Health > Health Records?
45. Any medications, other supplements, kidney, iron or thyroid conditions, or pregnancy plans that should suppress supplement nudges?
46. Are you comfortable sending lab PDFs to the Claude API for extraction, or should that stay local or manual?
47. Sleep targets: wake windows for workdays and free days per person. Do Nadia's early horse mornings count as workdays?
48. Headline sleep metric: a nightly "slept well" streak, or a weekly consistency score?

## H. Platform and operations

49. Apple Developer account: individual or organization, and are you the Account Holder (needed to add Nadia as an internal tester and to create API keys)?
50. Will the GitHub repo be public or private? It affects free macOS CI minutes.
51. Is the server reachable from the public internet at a `*.npc-server.top` host, or only on LAN or Tailscale? Phones need to reach it away from home.
52. If public, is a one-time pairing passphrase acceptable despite "no auth", so a random scanner cannot post data as you?
53. Do you want a web dashboard for big before-and-after charts? Read-only, or also an admin for scoring rules and targets?
54. The year goal: what is it, which day-one baseline metrics (weight, body fat, 1-mile time, max pushups, resting HR, VO2max, screen-time average), and does the year start now or on 2027-01-01?
55. To-do list: shared, personal, or both? Points per task, partner-assigned tasks?
56. Where should nightly Postgres backups go, and how long should raw samples be kept (forever is cheap at this scale)?
57. TestFlight builds expire after 90 days. A monthly scheduled CI build with an alert if it fails is my default. Acceptable, or prefer ad hoc provisioning as the primary path?
