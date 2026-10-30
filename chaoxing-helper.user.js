// ==UserScript==
// @name         学习通页面增强（章节统计 + 一键继续）
// @namespace    mochi.cx
// @version      1.3.0
// @description  学习通课程页的独立增强脚本：统计已完成/未完成章节与剩余任务点，一键跳到下一个未完成章节。不包含任何第三方脚本代码。
// @author       Mochi
// @match        *://*.chaoxing.com/*
// @grant        unsafeWindow
// @grant        GM_getValue
// @grant        GM_setValue
// @run-at       document-idle
// @noframes
// ==/UserScript==

(function () {
  'use strict';

  const HOST_ID = 'mochi-cx-helper';
  const POS_KEY = 'panel-pos-v1';
  if (document.getElementById(HOST_ID)) return;

  const host = document.createElement('div');
  host.id = HOST_ID;
  document.documentElement.appendChild(host);
  const shadow = host.attachShadow({ mode: 'open' });

  const style = document.createElement('style');
  style.textContent = `
    .card { position: fixed; z-index: 2147483000; width: 210px; box-sizing: border-box;
      background: rgba(24,26,32,.93); color: #e9ecf2; border-radius: 10px;
      box-shadow: 0 8px 24px rgba(0,0,0,.28); padding: 10px 12px;
      font: 12px/1.5 "Microsoft YaHei", system-ui, sans-serif; user-select: none; }
    .head { display: flex; justify-content: space-between; align-items: center; cursor: move; }
    .title { font-weight: 600; }
    .dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%;
      background: #3ddc84; margin-right: 6px; }
    .min { color: #8f97a6; cursor: pointer; padding: 0 2px; }
    .body { margin-top: 6px; }
    .row { display: flex; justify-content: space-between; margin: 2px 0; color: #b9c0cc; }
    .row b { color: #fff; font-weight: 600; }
    .bar { height: 4px; background: #33363f; border-radius: 2px; overflow: hidden; margin: 7px 0 9px; }
    .bar > i { display: block; height: 100%; width: 0;
      background: linear-gradient(90deg,#3ddc84,#4ea1ff); transition: width .4s ease; }
    .btns { display: flex; gap: 6px; }
    button { flex: 1; border: 0; border-radius: 6px; padding: 6px 0; font-size: 12px;
      cursor: pointer; background: #3a3f4b; color: #e9ecf2; font-family: inherit; }
    button.primary { background: #2f7cf6; color: #fff; }
    button:hover { filter: brightness(1.12); }
    button:active { transform: translateY(1px); }
    .status { margin-top: 6px; min-height: 16px; color: #8f97a6; font-size: 11px; }
    .card.collapsed .body { display: none; }
  `;
  shadow.appendChild(style);

  const card = document.createElement('div');
  card.className = 'card';
  card.style.display = 'none';
  card.innerHTML = `
    <div class="head">
      <span class="title"><span class="dot"></span>学习通页面增强</span>
      <span class="min" title="折叠/展开">—</span>
    </div>
    <div class="body">
      <div class="row"><span>章节完成</span><span><b class="done">-</b> / <b class="total">-</b></span></div>
      <div class="row"><span>未完成章节</span><b class="pend">-</b></div>
      <div class="row"><span>剩余任务点</span><b class="points">-</b></div>
      <div class="bar"><i></i></div>
      <div class="btns">
        <button class="primary" data-act="next">继续刷课</button>
        <button data-act="refresh">刷新</button>
      </div>
      <div class="status"></div>
    </div>
  `;
  shadow.appendChild(card);

  const q = (sel) => card.querySelector(sel);
  const $done = q('.done'), $total = q('.total'), $pend = q('.pend'),
        $points = q('.points'), $bar = q('.bar > i'), $status = q('.status');

  function setStatus(text) { $status.textContent = text || ''; }

  function leaves() {
    return [...document.querySelectorAll('.posCatalog_select')]
      .filter((el) => el.querySelector('.posCatalog_name'));
  }

  function tipOf(el) {
    const node = el.querySelector('.prevHoverTips');
    return node ? node.textContent.trim() : '';
  }

  function stats() {
    let done = 0, pending = 0, points = 0;
    for (const el of leaves()) {
      const tip = tipOf(el);
      if (!tip) continue;
      if (tip.includes('已完成')) { done += 1; continue; }
      pending += 1;
      const m = tip.match(/(\d+)\s*个/);
      points += m ? Number(m[1]) : 1;
    }
    return { done, pending, total: done + pending, points };
  }

  function render() {
    const s = stats();
    if (s.total === 0) { card.style.display = 'none'; return; }
    card.style.display = '';
    $done.textContent = s.done;
    $total.textContent = s.total;
    $pend.textContent = s.pending;
    $points.textContent = s.points;
    $bar.style.width = (s.done / s.total * 100) + '%';
  }

  function pageWindow() {
    try { return typeof unsafeWindow !== 'undefined' ? unsafeWindow : window; }
    catch (e) { return window; }
  }

  function jumpToNext() {
    const el = leaves().find((node) => {
      const tip = tipOf(node);
      return tip && !tip.includes('已完成');
    });
    if (!el) { setStatus('没有未完成章节'); return; }
    const span = el.querySelector('.posCatalog_name');
    const onclick = span.getAttribute('onclick') || '';
    const args = [...onclick.matchAll(/'([^']*)'/g)].map((m) => m[1]);
    const name = (span.textContent || '').replace(/\s+/g, ' ').trim();
    try {
      const w = pageWindow();
      if (args.length >= 3 && typeof w.getTeacherAjax === 'function') {
        w.getTeacherAjax(args[0], args[1], args[2]);
      } else {
        span.click();
      }
      setStatus('已跳转：' + name.slice(0, 18));
    } catch (err) {
      setStatus('跳转失败：' + err.message);
    }
  }

  function restorePos() {
    let pos = null;
    try { pos = JSON.parse(GM_getValue(POS_KEY, '') || 'null'); } catch (e) { /* ignore */ }
    if (pos && Number.isFinite(pos.left) && Number.isFinite(pos.top)) {
      card.style.left = Math.max(0, Math.min(pos.left, innerWidth - 60)) + 'px';
      card.style.top = Math.max(0, Math.min(pos.top, innerHeight - 40)) + 'px';
    } else {
      card.style.left = '16px';
      card.style.top = '80px';
    }
  }

  function enableDrag() {
    const head = card.querySelector('.head');
    let dragging = false, dx = 0, dy = 0;
    head.addEventListener('pointerdown', (e) => {
      if (e.target.classList.contains('min')) return;
      dragging = true;
      dx = e.clientX - card.getBoundingClientRect().left;
      dy = e.clientY - card.getBoundingClientRect().top;
      head.setPointerCapture(e.pointerId);
    });
    head.addEventListener('pointermove', (e) => {
      if (!dragging) return;
      const left = Math.max(0, Math.min(e.clientX - dx, innerWidth - card.offsetWidth));
      const top = Math.max(0, Math.min(e.clientY - dy, innerHeight - 40));
      card.style.left = left + 'px';
      card.style.top = top + 'px';
    });
    head.addEventListener('pointerup', () => {
      if (!dragging) return;
      dragging = false;
      try {
        GM_setValue(POS_KEY, JSON.stringify({ left: card.offsetLeft, top: card.offsetTop }));
      } catch (e) { /* ignore */ }
    });
  }

  card.addEventListener('click', (e) => {
    const act = e.target.dataset && e.target.dataset.act;
    if (act === 'next') jumpToNext();
    if (act === 'refresh') { render(); setStatus('已刷新'); }
  });
  card.querySelector('.min').addEventListener('click', () => card.classList.toggle('collapsed'));

  restorePos();
  enableDrag();
  render();

  const observer = new MutationObserver(() => render());
  observer.observe(document.body, { childList: true, subtree: true });
  setInterval(render, 3000);
})();
