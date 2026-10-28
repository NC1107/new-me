import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'habit_models.dart';
import 'models.dart';

/// Sent on every request as X-Client-Version and shown in Me. Release builds pass the tagged
/// version; the default mirrors pubspec for local and web builds, which a test enforces.
const kClientVersion = String.fromEnvironment('NEWME_CLIENT_VERSION', defaultValue: '0.1.0');

/// Shared secret baked in at build time with --dart-define=NEWME_APP_KEY=...
const String kAppKey = String.fromEnvironment('NEWME_APP_KEY');

enum ApiErrorKind {
  /// 403 bad_app_key: this build is not accepted. Never a sign-out.
  badAppKey,

  /// 426: the server requires a newer client.
  updateRequired,

  /// 422 date_closed: the entry's day is no longer open.
  dateClosed,

  /// No response at all, or a 5xx. Never a sign-out.
  offline,

  /// A reachable host that does not speak the New Me API.
  wrongServer,

  /// Any other rejection, carrying the server's own message.
  other,
}

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.kind = ApiErrorKind.other,
    this.statusCode,
    this.code,
    this.minClientVersion,
    this.body = const {},
  });

  const ApiException.badAppKey({int? statusCode})
    : this(
        'This build is not accepted by the server',
        kind: ApiErrorKind.badAppKey,
        statusCode: statusCode,
        code: 'bad_app_key',
      );

  const ApiException.updateRequired({String? minClientVersion})
    : this(
        'Update required',
        kind: ApiErrorKind.updateRequired,
        statusCode: 426,
        code: 'update_required',
        minClientVersion: minClientVersion,
      );

  const ApiException.dateClosed({String message = 'That day is closed'})
    : this(message, kind: ApiErrorKind.dateClosed, statusCode: 422, code: 'date_closed');

  const ApiException.offline({int? statusCode, String message = 'Offline', String? code})
    : this(message, kind: ApiErrorKind.offline, statusCode: statusCode, code: code);

  const ApiException.wrongServer() : this('Not a New Me server', kind: ApiErrorKind.wrongServer);

  factory ApiException.fromDio(DioException e) {
    final response = e.response;
    // Before the format check: a proxy page labelled as JSON fails to parse, yet is a restart.
    if (isProxyError(response)) {
      return ApiException.offline(
        statusCode: response!.statusCode,
        message: 'New Me is updating. Try again in a moment.',
        code: 'unavailable',
      );
    }
    if (e.error is FormatException) {
      return const ApiException('Unexpected response from the server');
    }
    if (response == null) return const ApiException.offline();

    final status = response.statusCode;
    final data = response.data;
    final body = data is Map<String, dynamic> ? data : const <String, dynamic>{};

    final code = body['code'] as String?;
    final serverMessage = body['error'] as String?;

    if (status == 403 && code == 'bad_app_key') return ApiException.badAppKey(statusCode: status);
    if (status == 426) {
      return ApiException.updateRequired(minClientVersion: body['minClientVersion'] as String?);
    }
    if (status == 422 && code == 'date_closed') {
      return ApiException.dateClosed(message: serverMessage ?? 'That day is closed');
    }
    if (status != null && status >= 500) {
      return ApiException.offline(
        statusCode: status,
        message: serverMessage ?? 'Server error',
        code: code,
      );
    }
    return ApiException(
      serverMessage ?? e.message ?? 'Request failed',
      statusCode: status,
      code: code,
      body: body,
    );
  }

  final String message;
  final ApiErrorKind kind;
  final int? statusCode;

  /// The server's machine-readable error code, such as `date_closed`.
  final String? code;

  /// On a 426, the oldest client version the server still accepts.
  final String? minClientVersion;

  /// The whole error body, for errors that carry details such as a rejected plan's violations.
  final Map<String, dynamic> body;

  @override
  String toString() => 'ApiException($kind, $statusCode): $message';
}

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// True for an answer from the proxy in front of the server rather than the server itself: a
/// 404, 502, 503 or 504 without the server's JSON error envelope, which is what a restart looks
/// like while the new container comes up.
bool isProxyError(Response<dynamic>? response) {
  final status = response?.statusCode;
  if (status == null || !const {404, 502, 503, 504}.contains(status)) return false;
  final data = response!.data;
  return data is! Map || data['error'] is! String;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    String? token,
    void Function()? onUnauthorized,
    void Function()? onUpdateRequired,
    HttpClientAdapter? adapter,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: const Duration(seconds: 15),
           sendTimeout: const Duration(seconds: 15),
           receiveTimeout: const Duration(seconds: 15),
           headers: {
             'X-App-Key': kAppKey,
             'X-Client-Version': kClientVersion,
             if (token != null) 'Authorization': 'Bearer $token',
           },
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) async {
          final status = e.response?.statusCode;
          // Only a rejected token means the session is dead; a 401 without one is a login error.
          if (status == 401 && token != null) onUnauthorized?.call();
          if (status == 426) onUpdateRequired?.call();
          // A restart answers from the proxy for a second or two; idempotent requests try once
          // more, so a deploy mid-tap goes unnoticed.
          final options = e.requestOptions;
          if (isProxyError(e.response) &&
              options.method != 'POST' &&
              options.extra[_kRetried] != true) {
            await Future<void>.delayed(retryDelay);
            options.extra[_kRetried] = true;
            try {
              return handler.resolve(await _dio.fetch<dynamic>(options));
            } on DioException catch (again) {
              return handler.next(again);
            }
          }
          handler.next(e);
        },
      ),
    );
  }

  static const _kRetried = 'newme.retried';

  /// How long a request waits before its one retry after a proxy error. Tests shorten it.
  static Duration retryDelay = const Duration(milliseconds: 1500);

  final Dio _dio;

  Future<T> _send<T>(
    Future<Response<dynamic>> Function() request,
    T Function(dynamic) parse,
  ) async {
    try {
      final response = await request();
      return parse(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on TypeError {
      throw const ApiException('Unexpected response from the server');
    } on FormatException {
      throw const ApiException('Unexpected response from the server');
    }
  }

  Future<ServerInfo> serverInfo() async {
    try {
      return await _send(() => _dio.get<dynamic>('/api/server-info'), (data) {
        if (data is! Map<String, dynamic> || data['initialized'] is! bool) {
          throw const ApiException.wrongServer();
        }
        return ServerInfo.fromJson(data);
      });
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.other) throw const ApiException.wrongServer();
      rethrow;
    }
  }

  Future<InviteCheck> checkInvite(String code) => _send(
    () => _dio.post<dynamic>('/api/invites/check', data: {'code': code}),
    (data) => InviteCheck.fromJson(data as Json),
  );

  Future<JoinResult> join(JoinRequest request) => _send(
    () => _dio.post<dynamic>('/api/join', data: request.toJson()),
    (data) => JoinResult.fromJson(data as Json),
  );

  Future<void> deleteDevice() => _send(() => _dio.delete<dynamic>('/api/devices/me'), (_) {});

  Future<Me> me() => _send(() => _dio.get<dynamic>('/api/me'), (data) => Me.fromJson(data as Json));

  Future<Me> patchMe(MePatch patch) => _send(
    () => _dio.patch<dynamic>('/api/me', data: patch.toJson()),
    (data) => Me.fromJson(data as Json),
  );

  Future<TargetsReport> targets() =>
      _send(() => _dio.get<dynamic>('/api/targets'), TargetsReport.parse);

  /// Sets the chosen targets from tomorrow, all or nothing; answers with the refreshed profile
  /// and the keys that were applied. Throws a 422 for a key that cannot be applied.
  Future<({Me me, List<String> applied})> applyTargets(List<String> keys) => _send(
    () => _dio.post<dynamic>('/api/targets/apply', data: {'keys': keys}),
    (data) => (me: Me.fromJson(data as Json), applied: parseApplied(data)),
  );

  /// Records a push-up max test: one set to near failure. [date] is YYYY-MM-DD and defaults to
  /// today on the server; a second test on the same day replaces the first.
  Future<PushupMaxResult> recordPushupMax({required int reps, String? date}) => _send(
    () => _dio.post<dynamic>('/api/pushups/max', data: {'reps': reps, 'date': ?date}),
    PushupMaxResult.parse,
  );

  /// Signs in to Audiobookshelf through the server, which keeps the session and never the
  /// password. Throws an [ApiException] with code `abs_login_failed` for bad credentials.
  Future<AudiobookshelfLink> linkAudiobookshelf({
    required String username,
    required String password,
  }) => _send(
    () => _dio.put<dynamic>(
      '/api/me/audiobookshelf',
      data: {'username': username, 'password': password},
    ),
    (data) => AudiobookshelfLink.fromJson(data as Json),
  );

  Future<void> unlinkAudiobookshelf() =>
      _send(() => _dio.delete<dynamic>('/api/me/audiobookshelf'), (_) {});

  /// Reads Audiobookshelf for the caller now. The server answers at most once a minute with fresh
  /// data and otherwise with the stored state. Throws codes `abs_disabled` and `abs_not_linked`.
  Future<ListeningSync> syncAudiobookshelf() => _send(
    () => _dio.post<dynamic>('/api/me/audiobookshelf/sync'),
    (data) => ListeningSync.fromJson(data as Json),
  );

  Future<Today> today({String? date}) => _send(
    () => _dio.get<dynamic>('/api/today', queryParameters: {'date': ?date}),
    (data) => Today.fromJson(data as Json),
  );

  Future<List<Habit>> habits() => _send(
    () => _dio.get<dynamic>('/api/habits'),
    (data) => HabitList.fromJson(data as Json).habits,
  );

  Future<Habit> createHabit(HabitDraft draft) => _send(
    () => _dio.post<dynamic>('/api/habits', data: draft.toJson()),
    (data) => Habit.fromJson((data as Json)['habit'] as Json),
  );

  Future<Habit> patchHabit(int id, Json patch) => _send(
    () => _dio.patch<dynamic>('/api/habits/$id', data: patch),
    (data) => Habit.fromJson((data as Json)['habit'] as Json),
  );

  Future<HabitProposals> habitProposals() => _send(
    () => _dio.get<dynamic>('/api/habits/proposals'),
    (data) => HabitProposals.fromJson(data as Json),
  );

  /// Approves or declines the partner's pending change to their habit [id].
  Future<void> answerHabitProposal(int id, {required bool approve}) =>
      _send(() => _dio.post<dynamic>('/api/habits/$id/${approve ? 'approve' : 'decline'}'), (_) {});

  Future<void> deleteHabit(int id) => _send(() => _dio.delete<dynamic>('/api/habits/$id'), (_) {});

  /// [ids] must list every habit once; the answer is the list in its new order.
  Future<List<Habit>> orderHabits(List<int> ids) => _send(
    () => _dio.put<dynamic>('/api/habits/order', data: {'ids': ids}),
    (data) => HabitList.fromJson(data as Json).habits,
  );

  /// Sets one slot done or undone. Idempotent, so a retry is harmless.
  Future<HabitMarkResult> markHabitSlot(
    int id,
    String date, {
    required int slot,
    required bool done,
  }) => _putMark(id, date, {'slot': slot, 'done': done});

  /// Sets a count habit's total for the day.
  Future<HabitMarkResult> markHabitCount(int id, String date, int count) =>
      _putMark(id, date, {'count': count});

  Future<HabitMarkResult> _putMark(int id, String date, Json body) => _send(
    () => _dio.put<dynamic>('/api/habits/$id/marks/$date', data: body),
    (data) => HabitMarkResult.fromJson(data as Json),
  );

  /// Marks [from] to [to] (inclusive, today to 14 days ahead, at most 14 days) as away. Throws
  /// code `away_overlap` (409) when it meets an existing span.
  Future<AwayCreated> createAway({required String from, required String to, String note = ''}) =>
      _send(
        () => _dio.post<dynamic>('/api/away', data: {'from': from, 'to': to, 'note': note}),
        AwayCreated.parse,
      );

  Future<void> deleteAway(int id) => _send(() => _dio.delete<dynamic>('/api/away/$id'), (_) {});

  /// Spends one of the caller's freezes on the partner's missed [date]. Throws codes
  /// `cover_closed` and `no_freeze` (422).
  Future<Freezes> coverStreak(String date) => _send(
    () => _dio.post<dynamic>('/api/streak/cover', data: {'date': date}),
    (data) => Freezes.parse((data as Json)['freezes']),
  );

  Future<Progress> progress({int window = 30}) => _send(
    () => _dio.get<dynamic>('/api/progress', queryParameters: {'window': window}),
    Progress.parse,
  );

  /// [month] is YYYY-MM; null asks for the last completed month.
  Future<Lookback> lookback({String? month}) => _send(
    () => _dio.get<dynamic>('/api/lookback', queryParameters: {'month': ?month}),
    Lookback.parse,
  );

  /// The exercise catalog with the caller's custom exercises, best sets and max tests.
  Future<ExerciseCatalog> exercises() =>
      _send(() => _dio.get<dynamic>('/api/exercises'), ExerciseCatalog.parse);

  /// One how-to photo, fetched with the app key and token the server requires. [path] is an
  /// exercise's imageUrls entry.
  Future<Uint8List> exerciseImage(String path) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Adds a custom exercise for the caller only.
  Future<Exercise> createExercise({
    required String name,
    required List<String> primaryMuscles,
    required Measure measure,
    required LoadKind load,
    List<String> equipment = const [],
  }) => _send(
    () => _dio.post<dynamic>(
      '/api/exercises',
      data: {
        'name': name,
        'primaryMuscles': primaryMuscles,
        'secondaryMuscles': <String>[],
        'measure': measure.name,
        'load': load.name,
        'equipment': equipment,
      },
    ),
    (data) =>
        Exercise.tryParse((data as Json)['exercise']) ??
        (throw const FormatException('no exercise')),
  );

  /// Deletes a custom exercise; its logged sets stay.
  Future<void> deleteExercise(String key) =>
      _send(() => _dio.delete<dynamic>('/api/exercises/$key'), (_) {});

  /// Records a max test (one set to near failure) for any exercise.
  Future<void> recordMaxTest(String exercise, {int? reps, int? seconds}) => _send(
    () => _dio.post<dynamic>(
      '/api/exercises/$exercise/max',
      data: {'reps': ?reps, 'seconds': ?seconds},
    ),
    (_) {},
  );

  /// Logs a set once per op id and answers with the set and the rescored day.
  Future<SetResult> logSet(SetDraft draft) =>
      _send(() => _dio.post<dynamic>('/api/sets', data: draft.toJson()), SetResult.parse);

  Future<SetResult> deleteSet(int id) =>
      _send(() => _dio.delete<dynamic>('/api/sets/$id'), SetResult.parse);

  /// Live sets of the last [days] days, oldest first, optionally of one exercise.
  Future<List<ExerciseSet>> sets({String? exercise, int days = 90}) => _send(
    () => _dio.get<dynamic>('/api/sets', queryParameters: {'exercise': ?exercise, 'days': days}),
    (data) => [
      for (final s in ((data as Json)['sets'] as List? ?? const [])) ?ExerciseSet.tryParse(s),
    ],
  );

  /// The training profile, or null before the first save.
  Future<TrainingProfile?> trainingProfile() => _send(
    () => _dio.get<dynamic>('/api/training/profile'),
    (data) => TrainingProfile.tryParse((data as Json)['profile']),
  );

  Future<TrainingProfile> saveTrainingProfile(TrainingProfile profile) => _send(
    () => _dio.put<dynamic>('/api/training/profile', data: profile.toJson()),
    (data) => TrainingProfile.tryParse((data as Json)['profile']) ?? profile,
  );

  /// Plan design asks Claude once or twice, so it gets far longer than the default timeout.
  static final _planOptions = Options(
    sendTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 120),
  );

  /// Designs a plan. A plan that broke the rules twice is a 422 `plan_invalid` whose
  /// [ApiException.body] carries the violations.
  Future<TrainingPlan> generatePlan({int? weeks}) => _send(
    () => _dio.post<dynamic>('/api/training/plan', data: {'weeks': ?weeks}, options: _planOptions),
    _planFrom,
  );

  Future<TrainingPlan> changePlan(PlanChange change, {String detail = ''}) => _send(
    () => _dio.post<dynamic>(
      '/api/training/plan/change',
      data: {'kind': change.wire, 'detail': detail},
      options: _planOptions,
    ),
    _planFrom,
  );

  Future<void> endPlan() => _send(() => _dio.delete<dynamic>('/api/training/plan'), (_) {});

  static TrainingPlan _planFrom(dynamic data) {
    final plan = TrainingPlan.tryParse((data as Json)['plan']);
    if (plan == null) throw const FormatException('no plan');
    return plan;
  }

  Future<TrainingToday> trainingToday() =>
      _send(() => _dio.get<dynamic>('/api/training/today'), TrainingToday.parse);

  /// Chooses the full session for today instead of the eased one; the choice sticks for the day.
  Future<TrainingToday> takeFullSession() =>
      _send(() => _dio.post<dynamic>('/api/training/today/full'), TrainingToday.parse);

  /// Completes a session; the rescored day has the strength quest done by the session.
  Future<DayDetail> completeSession(int id) => _send(
    () => _dio.post<dynamic>('/api/training/sessions/$id/complete'),
    (data) => DayDetail.fromJson((data as Json)['day'] as Json),
  );

  Future<TrainingProgress> trainingProgress() =>
      _send(() => _dio.get<dynamic>('/api/training/progress'), TrainingProgress.parse);

  Future<List<Milestone>> milestones() => _send(
    () => _dio.get<dynamic>('/api/milestones'),
    (data) => parseMilestones((data as Json)['milestones']),
  );

  Future<Board> board() =>
      _send(() => _dio.get<dynamic>('/api/board'), (data) => Board.fromJson(data as Json));

  Future<List<LogEntry>> logs({required String date}) => _send(
    () => _dio.get<dynamic>('/api/logs', queryParameters: {'date': date}),
    (data) => [for (final j in (data as Json)['logs'] as List) LogEntry.fromJson(j as Json)],
  );

  Future<LogResult> createLog(LogDraft draft) => _send(
    () => _dio.post<dynamic>('/api/logs', data: draft.toJson()),
    (data) => LogResult.fromJson(data as Json),
  );

  Future<LogDeleteResult> deleteLog(LogEntry entry) => _send(
    () => _dio.delete<dynamic>('/api/logs/${entry.id}'),
    (data) => LogDeleteResult.fromJson(data as Json),
  );

  Future<List<RecentMeal>> recentMeals({int limit = 20}) => _send(
    () => _dio.get<dynamic>('/api/meals/recent', queryParameters: {'limit': limit}),
    (data) => [for (final j in (data as Json)['meals'] as List) RecentMeal.fromJson(j as Json)],
  );

  /// Works a meal out from a sentence. Nothing is stored or logged. Throws codes
  /// `estimate_disabled`, `rate_limited` and `estimate_unavailable`.
  Future<MealBreakdown> estimateMeal({required String text}) => _send(
    () => _dio.post<dynamic>(
      '/api/meals/estimate',
      data: {'text': text},
      options: Options(
        sendTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 60),
      ),
    ),
    (data) => MealBreakdown.fromJson(data as Json),
  );

  /// Searches the household food library; [remote] also searches USDA and Open Food Facts.
  Future<FoodSearch> foods({String q = '', bool remote = false}) => _send(
    () => _dio.get<dynamic>(
      '/api/foods',
      queryParameters: {if (q.isNotEmpty) 'q': q, if (remote) 'remote': 1},
      options: Options(receiveTimeout: const Duration(seconds: 20)),
    ),
    (data) => FoodSearch.fromJson(data as Json),
  );

  /// Saves a food. A database food that is already saved comes back as the saved copy.
  Future<SavedFood> createFood(SavedFood food) => _send(
    () => _dio.post<dynamic>('/api/foods', data: food.toJson()),
    (data) => SavedFood.fromJson(data as Json),
  );

  Future<SavedFood> updateFood(int id, SavedFood food) => _send(
    () => _dio.patch<dynamic>(
      '/api/foods/$id',
      data: food.toJson()
        ..remove('source')
        ..remove('sourceId'),
    ),
    (data) => SavedFood.fromJson(data as Json),
  );

  Future<void> deleteFood(int id) => _send(() => _dio.delete<dynamic>('/api/foods/$id'), (_) {});

  /// Counts a use of a saved food, which ranks it higher in search.
  Future<void> useFood(int id) => _send(() => _dio.post<dynamic>('/api/foods/$id/use'), (_) {});

  Future<Recap> recap({String? week}) => _send(
    () => _dio.get<dynamic>('/api/recap', queryParameters: {'week': ?week}),
    (data) => Recap.fromJson(data as Json),
  );

  Future<GoalProposals> goalProposals() => _send(
    () => _dio.get<dynamic>('/api/goals/proposals'),
    (data) => GoalProposals.fromJson(data as Json),
  );

  /// Applies the proposal like a goal edit and answers with the refreshed profile.
  Future<Me> acceptGoalProposal(String key) => _send(
    () => _dio.post<dynamic>('/api/goals/proposals/$key/accept'),
    (data) => Me.fromJson(data as Json),
  );

  Future<void> dismissGoalProposal(String key) =>
      _send(() => _dio.post<dynamic>('/api/goals/proposals/$key/dismiss'), (_) {});

  /// Stores past days' readings where the server has none, without rescoring; answers with how
  /// many were new.
  Future<int> putHealthHistory(List<HealthItem> items) => _send(
    () => _dio.put<dynamic>(
      '/api/health/history',
      data: {
        'items': [for (final i in items) i.toJson()],
      },
    ),
    (data) => ((data as Json)['stored'] as num?)?.toInt() ?? 0,
  );

  Future<HealthDailyResult> putHealthDaily(List<HealthItem> items) => _send(
    () => _dio.put<dynamic>(
      '/api/health/daily',
      data: {
        'items': [for (final i in items) i.toJson()],
      },
    ),
    (data) => HealthDailyResult.fromJson(data as Json),
  );

  /// At most 100 items per request; the caller chunks.
  Future<int> putHealthWorkouts(List<WorkoutUpload> items) => _send(
    () => _dio.put<dynamic>(
      '/api/health/workouts',
      data: {
        'items': [for (final i in items) i.toJson()],
      },
    ),
    (data) => _int((data as Json)['saved']),
  );

  Future<WorkoutList> workouts({int days = 30}) => _send(
    () => _dio.get<dynamic>('/api/workouts', queryParameters: {'days': days}),
    (data) => WorkoutList.fromJson(data as Json),
  );

  Future<int> putHealthSleep(List<SleepNightUpload> nights) => _send(
    () => _dio.put<dynamic>(
      '/api/health/sleep',
      data: {
        'nights': [for (final n in nights) n.toJson()],
      },
    ),
    (data) => _int((data as Json)['saved']),
  );

  Future<Insights> insights() =>
      _send(() => _dio.get<dynamic>('/api/insights'), (data) => Insights.fromJson(data as Json));

  Future<HealthTrend> healthTrends(String metric, int days) => _send(
    () =>
        _dio.get<dynamic>('/api/health/trends', queryParameters: {'metric': metric, 'days': days}),
    (data) => HealthTrend.fromJson(data as Json),
  );

  /// Answers the stored cheer for both a first send (201) and a repeat (200).
  Future<Cheer> sendCheer({required int to, required CheerKind kind}) => _send(
    () => _dio.post<dynamic>('/api/cheers', data: {'to': to, 'kind': kind.name}),
    (data) => Cheer.tryParse((data as Json)['cheer']) ?? (throw const FormatException('cheer')),
  );

  Future<RewardList> rewards() =>
      _send(() => _dio.get<dynamic>('/api/rewards'), (data) => RewardList.fromJson(data as Json));

  Reward _reward(Object? data) =>
      Reward.tryParse((data as Json)['reward']) ?? (throw const FormatException('reward'));

  /// Proposes a reward priced in gems. The partner approves it; alone it is approved at once.
  Future<Reward> createReward({required String name, required int price}) => _send(
    () => _dio.post<dynamic>('/api/rewards', data: {'name': name, 'price': price}),
    _reward,
  );

  /// Edits a reward. A new price on an approved reward is proposed again.
  Future<Reward> patchReward(int id, {String? name, int? price}) => _send(
    () => _dio.patch<dynamic>('/api/rewards/$id', data: {'name': ?name, 'price': ?price}),
    _reward,
  );

  /// Withdraws my pending or declined proposal.
  Future<void> withdrawReward(int id) =>
      _send(() => _dio.delete<dynamic>('/api/rewards/$id'), (_) {});

  Future<Reward> answerReward(int id, {required bool approve}) => _send(
    () => _dio.post<dynamic>('/api/rewards/$id/${approve ? 'approve' : 'decline'}'),
    _reward,
  );

  Future<Reward> cancelReward(int id) =>
      _send(() => _dio.post<dynamic>('/api/rewards/$id/cancel'), _reward);

  Future<Reward> focusReward(int id) =>
      _send(() => _dio.post<dynamic>('/api/rewards/$id/focus'), _reward);

  /// Spends the price from the bank. Throws code `reward_not_reached` (409) while the bank
  /// does not cover it; a repeat answers the claimed reward without spending again.
  Future<Reward> claimReward(int id) =>
      _send(() => _dio.post<dynamic>('/api/rewards/$id/claim'), _reward);

  Future<void> putPushToken(String token) =>
      _send(() => _dio.put<dynamic>('/api/devices/me/push', data: {'token': token}), (_) {});

  Future<void> deletePushToken() =>
      _send(() => _dio.delete<dynamic>('/api/devices/me/push'), (_) {});

  Future<Invite> createInvite() =>
      _send(() => _dio.post<dynamic>('/api/invites'), (data) => Invite.fromJson(data as Json));
}
