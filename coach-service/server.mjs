import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { mkdirSync, openSync, closeSync, unlinkSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { Store, Coach, check, text, addMaterial, recordAttempt, updatePreferences } from './core.mjs';
import { makeGenerator, makeNotifier } from './providers.mjs';

function authorized(header, token) {
  const actual = Buffer.from(header || ''), expected = Buffer.from(`Bearer ${token}`);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
export async function readBody(req) {
  const chunks = [];
  let bytes = 0;
  for await (const chunk of req) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    bytes += buffer.length;
    check(bytes <= 100000, '请求过大', 413);
    chunks.push(buffer);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw Object.assign(new Error('JSON 格式无效'), { status: 400 }); }
}
export function createServer(coach, token) {
  check(typeof token === 'string' && token.length >= 32, 'COACH_TOKEN must contain at least 32 characters');
  return http.createServer(async (req, res) => {
    const reply = (status, body) => {
      res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
      res.end(JSON.stringify(body));
    };
    if (!authorized(req.headers.authorization, token)) { reply(401, { error: '教练服务凭据无效' }); return; }
    try {
      const path = new URL(req.url, 'http://localhost').pathname;
      if (req.method === 'GET' && path === '/v1/coach') {
        reply(200, await coach.store.serial(() => coach.snapshot())); return;
      }
      check(req.method === 'POST', '接口不存在', 404);
      const body = await readBody(req);
      if (path === '/v1/questions') { reply(200, await coach.ask(body)); return; }
      const snapshot = await coach.store.serial(() => {
        const s = coach.store.data;
        const now = coach.clock();
        if (path === '/v1/preferences') {
          check(body.revision === (s.preferencesRevision ?? 0), '其他设备已更新教学安排，请刷新后重试', 409);
          updatePreferences(s, body.preferences);
        } else if (path === '/v1/materials') {
          addMaterial(s, body, now);
        } else if (path === '/v1/attempts') {
          recordAttempt(s, body, now);
        } else if (path === '/v1/progress') {
          const lesson = s.lessons.find(l => l.id === body.lessonId && !l.completedAt);
          check(lesson, '本课已完成，请刷新', 409);
          check(body.revision === (s.draft?.revision ?? 0), '其他设备已更新草稿，请保留本地文字并刷新查看', 409);
          check(typeof body.answer === 'string' && body.answer.length <= 8000 && typeof body.revealed === 'boolean', '草稿无效');
          s.draft = { lessonId: lesson.id, answer: body.answer, revealed: body.revealed || (s.draft?.lessonId === lesson.id && s.draft.revealed), revision: (s.draft?.revision ?? 0) + 1 };
        } else if (path === '/v1/defer') {
          const lesson = s.lessons.find(l => l.id === body.lessonId && !l.completedAt);
          check(lesson, '本课已完成，请刷新', 409);
          // Skip without creating a failed attempt; keep the material eligible for a later lesson.
          lesson.completedAt = now.toISOString(); lesson.deferred = true;
          const material = s.materials.find(m => m.id === lesson.materialId);
          material.dueAt = new Date(now.getTime() + 86400000).toISOString();
        } else if (path === '/v1/devices') {
          const id = text(body.id, 100);
          check(typeof body.token === 'string' && /^[a-f0-9]{32,256}$/.test(body.token), '设备 token 无效');
          s.devices = s.devices.filter(d => d.id !== id && d.token !== body.token);
          check(s.devices.length < 8, '设备数量已达上限');
          s.devices.push({ id, token: body.token });
        } else if (path === '/v1/devices/remove') {
          s.devices = s.devices.filter(d => d.id !== body.id);
        } else if (path === '/v1/reset') {
          check(body.revision === s.revision && body.confirm === 'delete-coach-data', '请刷新并确认清除教练记录', 409);
          s.devicesEpoch = (s.devicesEpoch ?? 0) + 1;
          s.preferencesRevision = (s.preferencesRevision ?? 0) + 1;
          s.preferences.enabled = false; s.materials = []; s.lessons = []; s.attempts = []; s.devices = []; s.deliveries = []; s.lastError = null; s.draft = null; s.discussions = [];
          // Quota remains: deleting teaching data must not reset the daily spending guard.
        } else { check(false, '接口不存在', 404); }
        coach.store.save(); return coach.snapshot();
      });
      reply(200, snapshot);
    } catch (error) { reply(error.status || 500, { error: error.status ? error.message : '服务暂时不可用，请稍后重试' }); }
  });
}
export function start(env = process.env) {
  const file = resolve(env.COACH_DATA_FILE || './data/coach.json');
  mkdirSync(dirname(file), { recursive: true, mode: 0o700 });
  const lock = file + '.lock';
  // One process / one volume only. Recover after a crash in the same PID namespace.
  // In a restarted single-instance container PID may be reused by this process.
  try {
    const previousPID = Number(readFileSync(lock, 'utf8'));
    let alive = Number.isInteger(previousPID) && previousPID > 0;
    if (alive && previousPID !== process.pid) {
      try { process.kill(previousPID, 0); } catch (error) { if (error.code === 'ESRCH') alive = false; }
    } else if (previousPID === process.pid) { alive = false; }
    if (alive) throw new Error('Another process owns the coach data file');
    unlinkSync(lock);
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const fd = openSync(lock, 'wx', 0o600); writeFileSync(fd, String(process.pid)); closeSync(fd);
  let server, timer;
  try {
    const store = new Store(file), generate = makeGenerator(env), notify = makeNotifier(env);
    const coach = new Coach(store, { generate, notify, capabilities: { generator: !!generate, push: !!notify } });
    server = createServer(coach, env.COACH_TOKEN);
    let ticking = false;
    const tick = async () => {
      if (ticking) return;
      ticking = true;
      try { await coach.tick(); } catch { console.error('Coach persistence/scheduler error; inspect service health.'); }
      finally { ticking = false; }
    };
    timer = setInterval(tick, 60000);
    server.listen(Number(env.PORT || 9220), env.HOST || '127.0.0.1', tick);
    const stop = () => {
      clearInterval(timer);
      server.close(() => { unlinkSync(lock); process.exit(0); });
    };
    process.on('SIGTERM', stop); process.on('SIGINT', stop);
    console.log('Coach service started; no credentials or lesson content are logged.');
  } catch (error) {
    clearInterval(timer); server?.close(); unlinkSync(lock); throw error;
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) start();
