import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Store, Coach, addMaterial, recordAttempt, defaults, updatePreferences, DAY } from './core.mjs';
import { createServer, readBody } from './server.mjs';

const fen = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r';
const material = { id: 'chapter-1-node-1', title: '教材第一节', locator: '棋书 / 第一节 / 节点1', fen, note: '先观察对方威胁，再考虑自己的计划。', objective: '解释双方计划' };
const start = new Date('2026-10-26T11:05:00Z');
function fixture(t, generator) {
  const dir = mkdtempSync(join(tmpdir(), 'xq-coach-')); t.after(() => rmSync(dir, { recursive: true, force: true }));
  const file = join(dir, 'state.json'), store = new Store(file);
  let now = start, calls = 0, pushes = 0;
  store.data.preferences.enabled = true;
  addMaterial(store.data, material, now);
  store.data.devices.push({ id: 'phone', token: 'a'.repeat(64) });
  const generate = async ctx => { calls++; return generator ? generator(ctx) : { sourceId: ctx.material.id, title: '看看双方计划', question: '你会先观察什么？', hint: '看看对方的威胁', explanation: '原笔记建议先观察威胁，具体变化尚未核验。' }; };
  const coach = new Coach(store, { generate, notify: async () => { pushes++; return { ok: true }; }, clock: () => now, capabilities: { generator: true, push: true } });
  return { store, coach, file, generate, now: value => { now = value; }, counts: () => ({ calls, pushes }) };
}

test('autonomous tick prepares, persists and deduplicates across restart and concurrent ticks', async t => {
  const f = fixture(t);
  await Promise.all([f.coach.tick(), f.coach.tick(), f.coach.tick()]);
  assert.deepEqual(f.counts(), { calls: 1, pushes: 1 });
  const restored = new Store(f.file);
  const restarted = new Coach(restored, { generate: f.generate, notify: async () => assert.fail('duplicate push'), clock: () => start });
  await restarted.tick();
  assert.equal(restored.data.lessons.length, 1);
  assert.equal(restored.data.deliveries[0].status, 'accepted-by-apns');
});

test('pause and quiet hours suppress both preparation and notifications', async t => {
  const f = fixture(t);
  f.now(new Date('2026-10-26T15:00:00Z')); await f.coach.tick();
  f.now(start); f.store.data.preferences.enabled = false; await f.coach.tick();
  assert.deepEqual(f.counts(), { calls: 0, pushes: 0 });
});

test('nonresponse never adds failures; next day follows up on same prepared lesson', async t => {
  const f = fixture(t); await f.coach.tick();
  const id = f.store.data.lessons[0].id;
  f.now(new Date(start.getTime() + DAY)); await f.coach.tick();
  assert.deepEqual(f.counts(), { calls: 1, pushes: 2 });
  assert.equal(f.store.data.lessons[0].id, id);
  assert.equal(f.store.data.attempts.length, 0);
  assert.equal(f.store.data.materials[0].successes, 0);
});

test('self-report adjusts repeated reviews, revealed answers never count as independent', async t => {
  const f = fixture(t); await f.coach.tick();
  let now = start;
  for (let i = 0; i < 3; i++) {
    const lesson = f.coach.snapshot().activeLesson;
    recordAttempt(f.store.data, { id: `a-${i}`, lessonId: lesson.id, answer: '先看对方威胁', rating: 'independent', revealed: false }, now);
    const interval = f.store.data.materials[0].intervalDays;
    assert.equal(interval, [1, 3, 6][i]);
    now = new Date(now.getTime() + interval * DAY); f.now(now); await f.coach.tick();
  }
  const lesson = f.coach.snapshot().activeLesson;
  recordAttempt(f.store.data, { id: 'revealed', lessonId: lesson.id, answer: '看过提示才理解', rating: 'independent', revealed: true }, now);
  assert.equal(f.store.data.attempts.at(-1).rating, 'prompted');
  assert.equal(f.store.data.materials[0].intervalDays, 3);
  assert.equal(f.store.data.materials[0].successes, 0);
});

test('idempotent submission and competing devices cannot grade the same lesson twice', async t => {
  const f = fixture(t); await f.coach.tick();
  const input = { id: 'one', lessonId: f.coach.snapshot().activeLesson.id, answer: '自己的想法', rating: 'uncertain', revealed: false };
  recordAttempt(f.store.data, input, start); recordAttempt(f.store.data, input, start);
  assert.equal(f.store.data.attempts.length, 1);
  assert.throws(() => recordAttempt(f.store.data, { ...input, id: 'two' }, start), /本课已完成/);
});

test('failed generation has durable bounded retries, and wrong sources are rejected', async t => {
  const f = fixture(t, async () => ({ sourceId: 'made-up' }));
  for (let i = 0; i < 8; i++) { f.now(new Date(start.getTime() + i * 5 * 60000)); await f.coach.tick(); }
  assert.equal(f.counts().calls, 3); assert.equal(f.counts().pushes, 0);
  assert.equal(new Store(f.file).data.budget['2026-10-26'].calls, 3);
  assert.equal(f.store.data.lessons.length, 0);
  assert.equal(f.store.data.attempts.length, 0);
});

test('failed/ambiguous push is not silently treated as delivered and is not repeated', async t => {
  const f = fixture(t); f.coach.notify = async () => { throw new Error('timeout'); };
  await f.coach.tick(); await f.coach.tick();
  assert.equal(f.store.data.deliveries.length, 1);
  assert.equal(f.store.data.deliveries[0].status, 'unknown');
});

test('material snapshots are immutable; invalid input and corrupt disk fail closed', t => {
  const f = fixture(t);
  addMaterial(f.store.data, { ...material, note: 'different' }, start);
  assert.equal(f.store.data.materials[0].note, material.note);
  assert.throws(() => addMaterial(f.store.data, { ...material, id: 'other', fen: 'bad' }, start));
  assert.throws(() => updatePreferences(f.store.data, { ...f.store.data.preferences, timeZone: 'bad' }));
  writeFileSync(f.file, 'corrupt'); assert.throws(() => new Store(f.file));
});

test('HTTP authentication, revisions, cross-device draft, reset and lesson continuation', async t => {
  const f = fixture(t); await f.coach.tick();
  const server = createServer(f.coach, 's'.repeat(40));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const url = `http://127.0.0.1:${server.address().port}`;
  const request = (path, body, auth = true) => fetch(url + path, { method: body ? 'POST' : 'GET', headers: auth ? { Authorization: `Bearer ${'s'.repeat(40)}`, 'Content-Type': 'application/json' } : {}, body: body ? JSON.stringify(body) : undefined });
  assert.equal((await request('/v1/coach', null, false)).status, 401);
  let snapshot = await (await request('/v1/coach')).json();
  assert.ok(snapshot.activeLesson); assert.equal(snapshot.devices, undefined);
  const progress = { lessonId: snapshot.activeLesson.id, answer: '我的草稿', revealed: true, revision: 0 };
  assert.equal((await request('/v1/progress', progress)).status, 200);
  assert.equal((await request('/v1/progress', progress)).status, 409);
  snapshot = await (await request('/v1/coach')).json();
  assert.equal(snapshot.draft.answer, '我的草稿');
  assert.equal((await request('/v1/preferences', { revision: -1, preferences: snapshot.preferences })).status, 409);
  const prefVersion = snapshot.preferencesRevision;
  // Draft and notification writes changed global revision, but not the teaching settings version.
  assert.notEqual(snapshot.revision, prefVersion);
  const preferenceBody = { revision: prefVersion, preferences: { ...snapshot.preferences, goal: '新的学习目标' } };
  let response = await request('/v1/preferences', preferenceBody);
  assert.equal(response.status, 200);
  const updated = await response.json();
  assert.equal(updated.preferencesRevision, prefVersion + 1);
  assert.equal((await request('/v1/preferences', preferenceBody)).status, 409);

  const attempt = { id: 'device-two', lessonId: snapshot.activeLesson.id, answer: '另一设备完成', revealed: false, rating: 'independent' };
  snapshot = await (await request('/v1/attempts', attempt)).json();
  assert.equal(snapshot.activeLesson, null);
  assert.equal(snapshot.attempts[0].rating, 'prompted');
  snapshot = await (await request('/v1/reset', { revision: snapshot.revision, confirm: 'delete-coach-data' })).json();
  assert.equal(snapshot.preferences.enabled, false); assert.equal(snapshot.materials.length, 0);
});

test('follow-up discussion persists, preserves source and shares model quota', async t => {
  const f = fixture(t); await f.coach.tick();
  const input = { id: 'question-1', lessonId: f.coach.snapshot().activeLesson.id, question: '这里为什么要先观察对手？' };
  await f.coach.ask(input); await f.coach.ask(input);
  assert.equal(f.store.data.discussions.length, 1);
  assert.equal(new Store(f.file).data.discussions[0].question, input.question);
  assert.equal(f.counts().calls, 2);
  await f.coach.ask({ ...input, id: 'question-2' });
  await assert.rejects(f.coach.ask({ ...input, id: 'question-3' }), /额度/);
  assert.equal(f.store.data.attempts.length, 0);
});

test('review never prepares a second lesson on the same local day', async t => {
  const f = fixture(t); await f.coach.tick();
  const lessonId = f.coach.snapshot().activeLesson.id;
  recordAttempt(f.store.data, { id: 'answer', lessonId, answer: '我的思路', rating: 'again', revealed: false }, start);
  addMaterial(f.store.data, { ...material, id: 'another-source' }, start);
  await f.coach.tick();
  assert.equal(f.counts().calls, 1);
});

test('disk failure stops subsequent work instead of exposing unpersisted progress', async t => {
  const f = fixture(t);
  // A directory at the temp-file path forces an atomic save failure without touching real data.
  const { mkdirSync } = await import('node:fs');
  mkdirSync(f.file + '.tmp');
  await assert.rejects(f.coach.tick());
  await assert.rejects(f.store.serial(() => f.coach.snapshot()), /Persistence failed/);
  assert.equal(f.counts().calls, 0);
});

test('slow preparation does not push after the contact window', async t => {
  const f = fixture(t, async ctx => {
    f.now(new Date('2026-10-26T12:01:00Z'));
    return { sourceId: ctx.material.id, title: '课程', question: '你的思路？', hint: '先观察', explanation: '原笔记的解释还需核验。' };
  });
  await f.coach.tick();
  assert.equal(f.store.data.lessons.length, 1);
  assert.equal(f.counts().pushes, 0);
});


test('UTF-8 Chinese notes survive byte-split request chunks', async () => {
  const expected = { note: '先观察对方威胁，再考虑自己的计划。' };
  const bytes = Buffer.from(JSON.stringify(expected));
  async function* split() { for (const byte of bytes) yield Buffer.from([byte]); }
  assert.deepEqual(await readBody(split()), expected);
  async function* oversized() { yield Buffer.alloc(100001); }
  await assert.rejects(readBody(oversized()), error => error.status === 413);
});

test('follow-ups leave one call for due proactive preparation', async t => {
  const f = fixture(t); await f.coach.tick();
  const oldLesson = f.coach.snapshot().activeLesson;
  recordAttempt(f.store.data, { id: 'done', lessonId: oldLesson.id, answer: '我的思路', rating: 'independent', revealed: false }, start);
  f.now(new Date(start.getTime() + DAY));
  await f.coach.ask({ id: 'follow1', lessonId: oldLesson.id, question: '为什么？' });
  await f.coach.ask({ id: 'follow2', lessonId: oldLesson.id, question: '再解释一下？' });
  await assert.rejects(f.coach.ask({ id: 'follow3', lessonId: oldLesson.id, question: '还有呢？' }), /备课保留/);
  await f.coach.tick();
  assert.equal(f.store.data.lessons.length, 2);
});

test('exhausted preparation quota is visible rather than silently skipped', async t => {
  const f = fixture(t);
  f.store.data.budget['2026-10-26'] = { calls: 3 };
  await f.coach.tick();
  assert.match(f.coach.snapshot().lastError, /额度已用完/);
  assert.equal(f.store.data.attempts.length, 0);
});

test('APNs provider token is reused and refreshed before expiry', async () => {
  const { generateKeyPairSync, verify } = await import('node:crypto');
  const { makeProviderToken } = await import('./providers.mjs');
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  let now = Date.now();
  const token = makeProviderToken({ key: privateKey, keyID: 'test-key', teamID: 'test-team', clock: () => now });
  const first = token();
  now += 30 * 60000;
  assert.equal(token(), first);
  now += 16 * 60000;
  const second = token(); assert.notEqual(second, first);
  const [header, payload, signature] = second.split('.');
  assert.equal(verify('sha256', Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')), true);
  assert.equal(JSON.parse(Buffer.from(payload, 'base64url')).iat, Math.floor(now / 1000));
});


test('existing lesson and elapsed contact window do not reserve unusable quota', async t => {
  const f = fixture(t); await f.coach.tick();
  f.store.data.preferences.maxDailyCalls = 1;
  const lessonId = f.coach.snapshot().activeLesson.id;
  f.now(new Date(start.getTime() + DAY));
  await f.coach.ask({ id: 'old-active', lessonId, question: '继续昨天的问题' });
  recordAttempt(f.store.data, { id: 'finish', lessonId, answer: '我的想法', rating: 'again', revealed: false }, new Date(start.getTime() + DAY));
  f.now(new Date(start.getTime() + 2 * DAY + 2 * 3600000));
  await f.coach.ask({ id: 'after-hours', lessonId, question: '今晚再回顾一下' });
  assert.equal(f.store.data.discussions.length, 2);
});
