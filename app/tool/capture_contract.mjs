// Records the real server responses that test/contract_test.dart parses.
//
// Run against a freshly reset local stack (docker compose down -v, up -d):
//   node tool/capture_contract.mjs http://127.0.0.1:8080 dev-key-0123456789 [http://127.0.0.1:8081]
// The optional third URL is a server started with NEWME_MIN_CLIENT_VERSION above 0.1.0, used for
// the 426 body. Tokens and invite codes are replaced by placeholders of the same shape.
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const [base = 'http://127.0.0.1:8080', appKey = 'dev-key-0123456789', oldBase] = process.argv.slice(2);
const outDir =
  process.env.CONTRACT_OUT ?? join(dirname(fileURLToPath(import.meta.url)), '..', 'test', 'contract');
const timezone = 'America/New_York';

function scrub(value) {
  return JSON.parse(
    JSON.stringify(value, (key, v) => {
      if (key === 'token' && typeof v === 'string') return 'T'.repeat(v.length);
      if (key === 'code' && typeof v === 'string' && /^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$/.test(v)) {
        return 'ABCD-EFGH-JKLM-NPQR';
      }
      return v;
    }),
  );
}

async function save(name, method, path, request, res, body) {
  const exchange = { method, path, status: res.status, request: scrub(request), body: scrub(body) };
  await writeFile(join(outDir, `${name}.json`), JSON.stringify(exchange, null, 2) + '\n');
}

async function call(name, method, path, { body, token, key = appKey, version = '0.1.0', url = base } = {}) {
  const headers = { 'X-App-Key': key, 'X-Client-Version': version };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(url + path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  const parsed = text ? JSON.parse(text) : {};
  if (name) await save(name, method, path, body ?? null, res, parsed);
  return { status: res.status, body: parsed };
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const ok = (r, ...statuses) => {
  if (!statuses.includes(r.status)) throw new Error(`unexpected ${r.status}: ${JSON.stringify(r.body)}`);
  return r.body;
};

await mkdir(outDir, { recursive: true });

ok(await call('server_info_fresh', 'GET', '/api/server-info'), 200);
const admin = ok(
  await call('join_first', 'POST', '/api/join', { body: { name: 'Nick', color: 'green', timezone } }),
  201,
);
ok(await call('server_info', 'GET', '/api/server-info'), 200);
ok(await call('invite_check_invalid', 'POST', '/api/invites/check', { body: { code: 'AAAA-BBBB-CCCC-DDDD' } }), 200);

const invite = ok(await call('invite', 'POST', '/api/invites', { token: admin.token }), 201);
ok(await call('invite_check_valid', 'POST', '/api/invites/check', { body: { code: invite.code } }), 200);
const member = ok(
  await call('join_member', 'POST', '/api/join', {
    body: { code: invite.code, name: 'Sam', color: 'violet', timezone },
  }),
  201,
);

const second = ok(await call(null, 'POST', '/api/invites', { token: admin.token }), 201);
await sleep(13000);
const repaired = ok(
  await call('join_repair', 'POST', '/api/join', {
    body: { code: second.code, userId: member.user.id },
  }),
  201,
);

const token = admin.token;
ok(await call('me', 'GET', '/api/me', { token }), 200);
ok(await call('today_fresh', 'GET', '/api/today', { token }), 200);
ok(
  await call('me_patched', 'PATCH', '/api/me', {
    token,
    body: {
      targets: { kcal: 2200, protein: 150, carbs: 220, fat: 70 },
      questTemplates: [{ key: 'pushups', target: 40 }, { key: 'yoga', enabled: true, target: 15 }],
    },
  }),
  200,
);

// Together: a reward of one point is reached by the first log below, so one run records the
// active, the early-claim and the reached shapes.
ok(await call('rewards_empty', 'GET', '/api/rewards', { token }), 200);
const reward = ok(
  await call('reward_created', 'POST', '/api/rewards', { token, body: { name: 'Pizza night', target: 1 } }),
  201,
);
ok(await call('reward_active', 'POST', '/api/rewards', { token: repaired.token, body: { name: 'Again', target: 50 } }), 409);
ok(await call('reward_claim_early', 'POST', `/api/rewards/${reward.reward.id}/claim`, { token }), 409);
ok(await call('rewards_active', 'GET', '/api/rewards', { token }), 200);
ok(
  await call('cheer_created', 'POST', '/api/cheers', {
    token: repaired.token,
    body: { to: admin.user.id, kind: 'fire' },
  }),
  201,
);
ok(
  await call('cheer_repeat', 'POST', '/api/cheers', {
    token: repaired.token,
    body: { to: admin.user.id, kind: 'fire' },
  }),
  200,
);
ok(await call('cheer_invalid', 'POST', '/api/cheers', { token, body: { to: admin.user.id, kind: 'fire' } }), 422);
ok(
  await call('push_put', 'PUT', '/api/devices/me/push', { token, body: { token: 'ab12'.repeat(16) } }),
  204,
);
ok(await call('push_delete', 'DELETE', '/api/devices/me/push', { token }), 204);

const op = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
ok(
  await call('log_pushups', 'POST', '/api/logs', {
    token,
    body: { clientOpId: op(1), kind: 'activity', type: 'pushups', unit: 'reps', quantity: 45 },
  }),
  201,
);
ok(
  await call('log_reading', 'POST', '/api/logs', {
    token,
    body: { clientOpId: op(2), kind: 'activity', type: 'reading', unit: 'pages', quantity: 12 },
  }),
  201,
);
// Yoga is switched on by the join-day PATCH above, and logging it carries the day past the
// streak line so the counted path is recorded too.
ok(
  await call('log_yoga', 'POST', '/api/logs', {
    token,
    body: { clientOpId: op(20), kind: 'activity', type: 'yoga', unit: 'minutes', quantity: 15 },
  }),
  201,
);
const meal = ok(
  await call('log_meal', 'POST', '/api/logs', {
    token,
    body: {
      clientOpId: op(3), kind: 'meal', name: 'Chicken bowl', kcal: 650,
      protein: 42.5, carbs: 60, fat: 18, fiber: 7,
    },
  }),
  201,
);
ok(
  await call('log_meal_replay', 'POST', '/api/logs', {
    token,
    body: {
      clientOpId: op(3), kind: 'meal', name: 'Chicken bowl', kcal: 650,
      protein: 42.5, carbs: 60, fat: 18, fiber: 7,
    },
  }),
  200,
);
ok(
  await call('log_closed', 'POST', '/api/logs', {
    token,
    body: { clientOpId: op(4), kind: 'activity', type: 'pushups', unit: 'reps', quantity: 5, date: '2020-01-01' },
  }),
  422,
);
const extra = ok(
  await call(null, 'POST', '/api/logs', {
    token,
    body: { clientOpId: op(5), kind: 'meal', name: 'Oats', kcal: 300, protein: 10, carbs: 50, fat: 6, fiber: 8 },
  }),
  201,
);
ok(await call('logs', 'GET', `/api/logs?date=${meal.log.localDate}`, { token }), 200);
ok(await call('meals_recent', 'GET', '/api/meals/recent?limit=20', { token }), 200);
ok(await call('log_deleted', 'DELETE', `/api/logs/${extra.log.id}`, { token }), 200);

const now = new Date(Date.now() - 60_000).toISOString();
const today = meal.log.localDate;
ok(
  await call('health_daily', 'PUT', '/api/health/daily', {
    token,
    body: {
      items: [
        { date: today, metric: 'steps', value: 6200, source: 'healthkit', measuredAt: now },
        { date: today, metric: 'active_energy', value: 410, source: 'healthkit', measuredAt: now },
        { date: today, metric: 'exercise_minutes', value: 24, source: 'healthkit', measuredAt: now },
        { date: today, metric: 'sleep_minutes', value: 432, source: 'healthkit', measuredAt: now },
        { date: today, metric: 'resting_hr', value: 58, source: 'healthkit', measuredAt: now },
        { date: today, metric: 'weight_kg', value: 82.4, source: 'healthkit', measuredAt: now },
        { date: today, metric: 'body_fat_pct', value: 18.2, source: 'healthkit', measuredAt: now },
        { date: today, metric: 'vo2max', value: 41.5, source: 'healthkit', measuredAt: now },
      ],
    },
  }),
  200,
);
ok(
  await call('health_daily_closed', 'PUT', '/api/health/daily', {
    token,
    body: { items: [{ date: '2020-01-01', metric: 'steps', value: 10, source: 'healthkit', measuredAt: now }] },
  }),
  422,
);
ok(await call('health_trends', 'GET', '/api/health/trends?metric=weight_kg&days=30', { token }), 200);
ok(await call('today', 'GET', '/api/today', { token }), 200);
ok(await call('board', 'GET', '/api/board', { token }), 200);
ok(await call('rewards_reached', 'GET', '/api/rewards', { token }), 200);
ok(await call('reward_claimed', 'POST', `/api/rewards/${reward.reward.id}/claim`, { token }), 200);

ok(await call('error_bad_app_key', 'GET', '/api/server-info', { key: 'wrong-key' }), 403);
ok(await call('error_unauthorized', 'GET', '/api/me', { token: 'not-a-token' }), 401);
ok(await call('error_invalid_json', 'PATCH', '/api/me', { token, body: { kcalTarget: 2000 } }), 400);
if (oldBase) ok(await call('error_update_required', 'GET', '/api/me', { token, url: oldBase }), 426);

console.log(`captured into ${outDir}`);
