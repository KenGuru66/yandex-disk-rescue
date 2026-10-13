// Перенос безлимита Яндекс Диска (/photounlim) в обычную папку через внутренний API веб-клиента.
// Все запросы выполняются внутри открытой вкладки disk.yandex.ru (cookies и TLS браузера).
//   node yd.js list  <state_dir>                      — собрать список /photounlim/* (только чтение)
//   node yd.js move  <state_dir> <limit> [batch]      — перенести до <limit> файлов пачками (batch ≤ 40)
// Переменные: YD_DEST — папка на Диске (по умолчанию «Безлимит», создайте её заранее),
//             YD_CDP — адрес отладки Chrome (http://127.0.0.1:9222), PLAYWRIGHT_CORE — путь к модулю.
// Повторный move продолжит с места остановки: успешные переносы помнятся в <state_dir>/moved.jsonl.
const { chromium } = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');
const fs = require('fs');
const path = require('path');

const [cmd, STATE, LIMIT_RAW, BATCH_RAW] = process.argv.slice(2);
const DST_DIR = '/disk/' + (process.env.YD_DEST || 'Безлимит').replace(/^\/+|\/+$/g, '') + '/';
const LIST_FILE = path.join(STATE, 'unlim_list.json');
const DONE_FILE = path.join(STATE, 'moved.jsonl');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const jitter = (a, b) => a + Math.random() * (b - a);
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

class Stop extends Error {}

async function getPage() {
  const browser = await chromium.connectOverCDP(process.env.YD_CDP || 'http://127.0.0.1:9222');
  const page = browser.contexts()[0].pages().find((p) => p.url().startsWith('https://disk.yandex.ru/'));
  if (!page) throw new Stop('нет вкладки disk.yandex.ru — войдите в аккаунт в окне Chrome');
  return { browser, page };
}

async function readSk(page) {
  const sk = await page.evaluate(() => {
    const m = document.documentElement.innerHTML.match(/"sk":"([^"]+)"/);
    return m ? m[1] : null;
  });
  if (!sk) throw new Stop('sk не найден на странице — обновите вкладку Диска');
  return sk;
}

function makeApi(page, uid) {
  let sk = null;
  return async function call(method, requestParams) {
    if (!sk) sk = await readSk(page);
    for (let attempt = 0; attempt < 5; attempt++) {
      const body = { sk, connection_id: `${uid}${Date.now()}`, apiMethod: method };
      if (requestParams !== undefined) body.requestParams = requestParams;
      const r = await page.evaluate(async ({ method, body }) => {
        const resp = await fetch(`/models-v2?m=${method}`, {
          method: 'POST', credentials: 'include',
          headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
          body: JSON.stringify(body),
        });
        return { status: resp.status, text: await resp.text() };
      }, { method, body });
      let data = null;
      try { data = JSON.parse(r.text); } catch { /* не JSON */ }
      if (data && data.type === 'captcha') throw new Stop('Яндекс показал капчу — пройдите её в окне Chrome и перезапустите');
      if (data && data.error && data.error.code === 'CKEY') { sk = await readSk(page); continue; }
      if (r.status === 429 || r.status >= 500) { const w = 15000 * (attempt + 1); log(`HTTP ${r.status} на ${method}, пауза ${w / 1000}s`); await sleep(w); continue; }
      if (r.status !== 200 || data === null) throw new Stop(`${method}: HTTP ${r.status}: ${r.text.slice(0, 300)}`);
      return data;
    }
    throw new Stop(`${method}: исчерпаны повторы`);
  };
}

async function list(call) {
  const init = await call('intapi/photo-init-snapshot');
  const snap = await call('intapi/photo-get-snapshot', { id: init.photoslice_id, locale: 'ru' });
  const clusters = snap.items.filter((c) => c.albums && c.albums.photounlim > 0);
  const expected = clusters.reduce((s, c) => s + c.albums.photounlim, 0);
  log(`кластеров всего ${snap.items.length}, с безлимитом ${clusters.length}, файлов безлимита по счётчикам: ${expected}`);
  const items = new Set();
  const CHUNK = 50;
  for (let i = 0; i < clusters.length; i += CHUNK) {
    const chunk = clusters.slice(i, i + CHUNK);
    const req = {};
    chunk.forEach((c) => { req[c.id] = { range: [0, c.size - 1] }; });
    const res = await call('intapi/photo-get-clusters-with-resources',
      { photosliceId: init.photoslice_id, clusters: req, hideScreenshots: false });
    for (const c of res.clusters.fetched || []) for (const it of c.items) if (it.id.startsWith('/photounlim/')) items.add(it.id);
    if ((i / CHUNK) % 10 === 0) log(`  обработано кластеров ${Math.min(i + CHUNK, clusters.length)}/${clusters.length}, файлов ${items.size}`);
    await sleep(jitter(300, 800));
  }
  const arr = [...items].sort();
  fs.writeFileSync(LIST_FILE, JSON.stringify({ at: new Date().toISOString(), expected, items: arr }, null, 0));
  log(`собрано ${arr.length} путей (ожидалось ${expected}) → ${LIST_FILE}`);
}

async function move(call, limit, batch) {
  const { items } = JSON.parse(fs.readFileSync(LIST_FILE, 'utf8'));
  const done = new Set(fs.existsSync(DONE_FILE)
    ? fs.readFileSync(DONE_FILE, 'utf8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l)).filter((r) => r.ok).map((r) => r.src)
    : []);
  const todo = items.filter((s) => !done.has(s)).slice(0, limit);
  log(`в списке ${items.length}, уже перенесено ${done.size}, в этом запуске ${todo.length}, пачка ${batch}`);
  let ok = 0, failed = 0;
  for (let i = 0; i < todo.length; i += batch) {
    const ops = todo.slice(i, i + batch).map((src) => ({ src, dst: DST_DIR + src.slice('/photounlim/'.length), force: 0 }));
    const started = await call('mpfs/bulk-async-move', { operations: ops });
    const pending = new Map();
    started.forEach((s, k) => {
      if (s && s.oid) pending.set(s.oid, ops[k].src);
      else { failed++; fs.appendFileSync(DONE_FILE, JSON.stringify({ src: ops[k].src, ok: false, err: s }) + '\n'); }
    });
    for (let waited = 0; pending.size && waited < 300000; waited += 2000) {
      await sleep(2000);
      const st = await call('mpfs/bulk-operation-status', { oids: [...pending.keys()] });
      for (const [oid, src] of [...pending]) {
        const s = st[oid];
        if (!s || s.status === 'WAITING' || s.status === 'EXECUTING') continue;
        const good = s.status === 'DONE';
        good ? ok++ : failed++;
        fs.appendFileSync(DONE_FILE, JSON.stringify({ src, ok: good, err: good ? undefined : s }) + '\n');
        pending.delete(oid);
      }
    }
    if (pending.size) throw new Stop(`операции не завершились за 5 минут: ${pending.size}`);
    log(`пачка ${i / batch + 1}: перенесено всего ${ok}, ошибок ${failed}`);
    if (failed > 20 && failed > ok * 0.05) throw new Stop(`слишком много ошибок: ${failed}`);
    await sleep(jitter(2000, 5000));
  }
  log(`готово: перенесено ${ok}, ошибок ${failed}`);
}

(async () => {
  fs.mkdirSync(STATE, { recursive: true });
  const { browser, page } = await getPage();
  try {
    const uid = await page.evaluate(() => (document.documentElement.innerHTML.match(/"uid":"?(\d+)/) || [])[1]);
    const call = makeApi(page, uid || '');
    if (cmd === 'list') await list(call);
    else if (cmd === 'move') await move(call, Number(LIMIT_RAW || 10), Math.min(Number(BATCH_RAW || 40), 40));
    else throw new Stop(`неизвестная команда ${cmd}`);
  } catch (e) {
    console.error(e instanceof Stop ? `СТОП: ${e.message}` : e);
    process.exitCode = 1;
  } finally {
    process.exit(process.exitCode || 0); // browser.close() не зовём: он может закрыть сам Chrome с сессией
  }
})();
