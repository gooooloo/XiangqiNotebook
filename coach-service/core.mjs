import { randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync, renameSync, mkdirSync, openSync, closeSync, fsyncSync } from 'node:fs';
import { dirname } from 'node:path';

export class RequestError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}
export function check(condition, message, status = 400) {
  if (!condition) throw new RequestError(message, status);
}
export function text(value, max = 4000) {
  check(typeof value === 'string' && value.trim().length > 0 && value.length <= max, '文字为空或过长');
  return value.trim();
}
export const DAY = 86400000;
export const defaults = () => ({
  version: 1, revision: 0, preferencesRevision: 0,
  preferences: { enabled: false, goal: '理解教材中的思路，并能独立运用', timeZone: 'Asia/Shanghai', hour: 19, dailyMinutes: 10, maxDailyCalls: 3 },
  materials: [], lessons: [], attempts: [], discussions: [], devices: [], devicesEpoch: 0, budget: {}, deliveries: [], lastError: null
});

// Single writer. A second process must not share this volume (see server lock).
export class Store {
  constructor(file) {
    this.file = file;
    try { this.data = JSON.parse(readFileSync(file, 'utf8')); }
    catch (error) { if (error.code !== 'ENOENT') throw error; this.data = defaults(); }
    check(this.data.version === 1, 'Unsupported coach data version');
    this.tail = Promise.resolve();
  }
  save() {
    try {
    this.data.revision++;
    mkdirSync(dirname(this.file), { recursive: true, mode: 0o700 });
    const tmp = this.file + '.tmp';
    writeFileSync(tmp, JSON.stringify(this.data), { mode: 0o600 });
    const fd = openSync(tmp, 'r'); fsyncSync(fd); closeSync(fd);
    renameSync(tmp, this.file);
    const dir = openSync(dirname(this.file), 'r'); fsyncSync(dir); closeSync(dir);
    } catch (error) { this.failed = true; throw error; }
  }
  serial(work) {
    const result = this.tail.then(() => {
      if (this.failed) throw new Error('Persistence failed; restart after repairing storage');
      return work();
    });
    this.tail = result.catch(() => {});
    return result;
  }
}
export function localClock(now, timeZone) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hourCycle: 'h23' }).formatToParts(now);
  const p = Object.fromEntries(parts.map(x => [x.type, x.value]));
  return { day: `${p.year}-${p.month}-${p.day}`, hour: Number(p.hour) };
}
export function updatePreferences(state, input) {
  check(typeof input.enabled === 'boolean', '需要明确是否启用教练');
  text(input.goal, 500); text(input.timeZone, 80);
  try { localClock(new Date(), input.timeZone); } catch { throw new RequestError('时区无效'); }
  check(Number.isInteger(input.hour) && input.hour >= 0 && input.hour <= 23, '联系时间无效');
  check(Number.isInteger(input.dailyMinutes) && input.dailyMinutes >= 3 && input.dailyMinutes <= 30, '每日学习时长应为 3–30 分钟');
  check(Number.isInteger(input.maxDailyCalls) && input.maxDailyCalls >= 1 && input.maxDailyCalls <= 10, '每日备课次数应为 1–10');
  state.preferencesRevision = (state.preferencesRevision ?? 0) + 1;
  state.preferences = { enabled: input.enabled, goal: input.goal.trim(), timeZone: input.timeZone, hour: input.hour, dailyMinutes: input.dailyMinutes, maxDailyCalls: input.maxDailyCalls };
}
export function validFen(fen) {
  if (typeof fen !== 'string') return false;
  const [board, turn] = fen.split(' ');
  if (!['r', 'w', 'b'].includes(turn) || board.split('/').length !== 10) return false;
  return board.split('/').every(row => /^[rnbakcpheRNBAKCPHE1-9]+$/.test(row) && [...row].reduce((n, c) => n + (/\d/.test(c) ? Number(c) : 1), 0) === 9)
    && (board.match(/k/g) || []).length === 1 && (board.match(/K/g) || []).length === 1;
}
export function addMaterial(state, input, now) {
  const id = text(input.id, 120);
  const existing = state.materials.find(m => m.id === id);
  if (existing) return existing; // Immutable source snapshot; retries don't replace student notes.
  check(state.materials.length < 200, '首版最多保留 200 个教学局面');
  check(validFen(input.fen), '教材局面格式不合法');
  const material = {
    id, title: text(input.title, 200), locator: text(input.locator, 500), fen: input.fen,
    note: text(input.note, 8000), objective: text(input.objective, 500),
    sourceKind: 'student-note', createdAt: now.toISOString(), intervalDays: 0,
    dueAt: now.toISOString(), successes: 0,
    // Syntax validation is NOT chess legality, engine verification, or explanation verification.
    evidence: { source: 'student-note', fenSyntaxChecked: true, rulesVerified: false, engineVerified: false, explanationVerified: false }
  };
  state.materials.push(material);
  return material;
}
export function activeLesson(state) { return state.lessons.find(l => !l.completedAt); }
export function chooseMaterial(state, now) {
  return state.materials.filter(m => Date.parse(m.dueAt) <= now.getTime())
    .sort((a, b) => Date.parse(a.dueAt) - Date.parse(b.dueAt) || a.id.localeCompare(b.id))[0];
}
export function recordAttempt(state, input, now) {
  const id = text(input.id, 120);
  if (state.attempts.some(a => a.id === id)) return;
  const lesson = state.lessons.find(l => l.id === input.lessonId);
  check(lesson && !lesson.completedAt, '本课已完成或不存在，请刷新课堂', 409);
  check(['independent', 'prompted', 'again', 'uncertain'].includes(input.rating), '无效的复习反馈');
  const answer = text(input.answer, 8000);
  check(typeof input.revealed === 'boolean', '需要记录是否查看讲解');
  const material = state.materials.find(m => m.id === lesson.materialId);
  // A revealed explanation cannot count as independent recall. Self-report is never a mastery verdict.
  const revealed = input.revealed || (state.draft?.lessonId === lesson.id && state.draft.revealed) || false;
  const rating = revealed && input.rating === 'independent' ? 'prompted' : input.rating;
  if (rating === 'independent') {
    material.successes++;
    material.intervalDays = material.successes === 1 ? 1 : Math.min(60, Math.max(3, material.intervalDays * 2));
  } else if (rating === 'prompted') {
    material.successes = 0; material.intervalDays = Math.max(1, Math.min(3, Math.floor(material.intervalDays / 2)));
  } else if (rating === 'again') {
    material.successes = 0; material.intervalDays = 1;
  } else {
    // Uncertainty isn't failure. Preserve success history; check again soon.
    material.intervalDays = Math.max(1, Math.min(3, material.intervalDays || 1));
  }
  material.dueAt = new Date(now.getTime() + material.intervalDays * DAY).toISOString();
  lesson.completedAt = now.toISOString();
  state.attempts.push({ id, lessonId: lesson.id, materialId: material.id, answer, rating, revealed, basis: 'student-self-report', kind: 'retention', createdAt: now.toISOString() });
}

export class Coach {
  constructor(store, { generate, notify, clock = () => new Date(), capabilities = {} }) {
    this.store = store; this.generate = generate; this.notify = notify; this.clock = clock; this.capabilities = capabilities;
  }
  snapshot() {
    const s = this.store.data;
    return { revision: s.revision, preferencesRevision: s.preferencesRevision ?? 0, preferences: s.preferences, materials: s.materials, lessons: s.lessons.slice(-40), attempts: s.attempts.slice(-100),
      activeLesson: activeLesson(s) ?? null, devicesEpoch: s.devicesEpoch ?? 0, draft: s.draft ?? null, lastError: s.lastError, capabilities: this.capabilities,
      discussions: (s.discussions ?? []).slice(-100), deliveryStatus: s.deliveries.at(-1)?.status ?? 'none' };
  }
  async ask(input) {
    return this.store.serial(async () => {
      const s = this.store.data, now = this.clock();
      const id = text(input.id, 120), question = text(input.question, 3000);
      s.discussions ??= [];
      if (s.discussions.some(d => d.id === id)) return this.snapshot();
      const lesson = s.lessons.find(l => l.id === input.lessonId);
      check(lesson, '课程不存在', 404);
      check(this.generate, '服务尚未配置模型', 503);
      const { day, hour } = localClock(now, s.preferences.timeZone);
      const budget = s.budget[day] ??= { calls: 0, lastCallAt: null };
      const needsPreparation = s.preferences.enabled && !activeLesson(s) && hour <= s.preferences.hour && chooseMaterial(s, now)
        && !s.lessons.some(l => localClock(new Date(l.createdAt), s.preferences.timeZone).day === day);
      const reserve = needsPreparation ? 1 : 0;
      check(budget.calls < s.preferences.maxDailyCalls - reserve,
        reserve ? '今日剩余额度已为主动备课保留，问题可先记在草稿中' : '今日模型请求额度已用完，问题可先记在草稿中', 429);
      budget.calls++; this.store.save();
      const material = s.materials.find(m => m.id === lesson.materialId);
      try {
        const result = await this.generate({ material, preferences: s.preferences,
          attempts: s.attempts.filter(a => a.materialId === material.id).slice(-8),
          question, previousExplanation: lesson.content.explanation,
          discussion: s.discussions.filter(d => d.lessonId === lesson.id).slice(-6) });
        const content = validateLesson(result, material);
        s.discussions.push({ id, lessonId: lesson.id, question, answer: content.explanation, createdAt: now.toISOString(), provenance: 'ai-explanation-unverified' });
        this.store.save(); return this.snapshot();
      } catch { throw new RequestError('教练暂时无法回答，问题仍保留在输入框中', 503); }
    });
  }
  async tick() {
    return this.store.serial(async () => {
      const s = this.store.data, now = this.clock(), p = s.preferences;
      if (!p.enabled) return;
      const { day, hour } = localClock(now, p.timeZone);
      // One-hour agreed contact window. No catch-up notification at night after downtime.
      if (hour !== p.hour) return;
      let lesson = activeLesson(s);
      if (!lesson) {
        // At most one lesson per local day, independent of clients and restarts.
        if (s.lessons.some(l => localClock(new Date(l.createdAt), p.timeZone).day === day)) return;
        const material = chooseMaterial(s, now);
        if (!material || !this.generate) return;
        const budget = s.budget[day] ??= { calls: 0, lastCallAt: null };
        if (budget.calls >= p.maxDailyCalls) {
          const message = '今日模型请求额度已用完，备课将顺延至下次联系时段；未计为学习失败。';
          if (s.lastError !== message) { s.lastError = message; this.store.save(); }
          return;
        }
        if (budget.lastCallAt && now - Date.parse(budget.lastCallAt) < 15 * 60000) return;
        budget.calls++; budget.lastCallAt = now.toISOString();
        this.store.save(); // Reserve quota before external call, including crashes and failures.
        try {
          const result = await this.generate({ material, preferences: p, attempts: s.attempts.filter(a => a.materialId === material.id).slice(-8) });
          const content = validateLesson(result, material);
          lesson = { id: randomUUID(), materialId: material.id, createdAt: now.toISOString(), completedAt: null,
            reason: material.intervalDays ? '根据上次自评安排复习；先回忆，再看讲解。' : '从你选定的教材笔记开始，先了解你的思路。',
            content, minutes: p.dailyMinutes, provenance: 'ai-explanation-unverified', model: result.model ?? 'unknown' };
          s.lessons.push(lesson); s.lastError = null; this.store.save();
        } catch {
          s.lastError = '备课失败，稍后会在约定时间内重试；未计为学习失败。'; this.store.save(); return;
        }
      }
      // A slow model response may finish after the agreed contact window.
      const deliveryClock = localClock(this.clock(), p.timeZone);
      if (deliveryClock.day !== day || deliveryClock.hour !== p.hour) return;
      if (!this.notify || !s.devices.length) return;
      // Reserve each delivery before sending: at-most-once attempt, avoiding duplicate alerts after crash.
      // No automatic retry after ambiguous APNs outcome; the prepared lesson remains in the inbox.
      for (const device of [...s.devices]) {
        const key = `${day}:${device.id}`;
        if (s.deliveries.some(d => d.key === key)) continue;
        const delivery = { key, lessonId: lesson.id, status: 'attempting', at: now.toISOString() };
        s.deliveries.push(delivery); this.store.save();
        try {
          const result = await this.notify(device, lesson);
          delivery.status = result.ok ? 'accepted-by-apns' : 'failed';
          if (result.removeDevice) s.devices = s.devices.filter(d => d.id !== device.id);
        } catch { delivery.status = 'unknown'; }
        this.store.save();
      }
    });
  }
}
export function validateLesson(result, material) {
  check(result && typeof result === 'object', '备课结果无效');
  check(result.sourceId === material.id, '备课引用了其他材料');
  return { sourceId: material.id, title: text(result.title, 200), question: text(result.question, 1500),
    explanation: text(result.explanation, 6000), hint: text(result.hint, 1000) };
}
