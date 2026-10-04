/* Actual Chromium/WebGL smoke and touch tests. This is not physical-phone QA.
 * npm install playwright; npx playwright install chromium
 * node tools/test_web_browser.cjs http://127.0.0.1:8060/ [screenshot-directory]
 * PLAYWRIGHT_MODULE_PATH optionally points at an existing Playwright package.
 */
'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright');
const url = process.argv[2];
const output = process.argv[3];
assert(url && /^https?:\/\//.test(url), 'An HTTP/HTTPS game URL is required');
if (output) fs.mkdirSync(output, {recursive:true});
let assertions = 0;
const check = (value, message) => { assert(value, message); assertions++; };
const state = page => page.evaluate(() => JSON.parse(window.thunderStateJson || '{}'));
async function action(page, name) {
  await page.evaluate(name => window.thunderDeviceAction(name, true), name);
  await page.waitForTimeout(350);
  if (process.env.WEB_TEST_TRACE) console.log(JSON.stringify({action:name,state:await state(page)}));
}
async function resume(page) {
  const s = await state(page);
  if (s.dead) await action(page, 'restart');
  if ((await state(page)).paused) await action(page, 'pause');
}
async function testViewport(browser, spec) {
  const context = await browser.newContext({viewport:spec.viewport, hasTouch:spec.touch, isMobile:spec.touch, deviceScaleFactor:1});
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', entry => {
    if (/SCRIPT ERROR:|^ERROR:/.test(entry.text())) errors.push(entry.text());
    if (process.env.WEB_TEST_TRACE && entry.type()==='error') console.log('BROWSER_CONSOLE '+entry.text());
  });
  const response = await page.goto(url);
  check(response.ok(), spec.name + ': HTTP page');
  await page.locator('#start').click();
  await page.waitForFunction(() => window.thunderWebReady && window.thunderStateJson, null, {timeout:90000});
  check(await page.evaluate(() => !window.thunderWebError), spec.name + ': engine ready');
  check(await page.evaluate(() => !crossOriginIsolated), spec.name + ': no isolation headers required');
  await resume(page);
  let s = await state(page);
  check(s.hp > 0 && s.weapon_mode === 1, spec.name + ': live initial game');
  await action(page, 'weapon_cycle');
  check((await state(page)).weapon_mode === 2, spec.name + ': missiles');
  await action(page, 'weapon_cycle');
  check((await state(page)).weapon_mode === 3, spec.name + ': lightning');
  await action(page, 'weapon_cycle');
  check((await state(page)).weapon_mode === 4, spec.name + ': laser');
  await action(page, 'pause');
  check((await state(page)).paused, spec.name + ': pause');
  await action(page, 'weapon_cycle');
  check((await state(page)).weapon_mode === 4, spec.name + ': paused weapon guard');
  await action(page, 'settings');
  check((await state(page)).settings, spec.name + ': settings');
  await action(page, 'focus_lost');
  check((await state(page)).paused && (await state(page)).settings, spec.name + ': settings focus freeze');
  await action(page, 'confirm');
  check(!(await state(page)).settings && (await state(page)).paused, spec.name + ': settings return to pause');
  await action(page, 'pause');
  await action(page, 'overdrive');
  check((await state(page)).overdrive_seconds > 0, spec.name + ': hundred-shot overdrive');
  if (spec.touch) {
    check(await page.locator('#controls').isVisible(), spec.name + ': touch panel');
    const dimensions = await page.locator('[data-action="fire"]').evaluate(element => { const r=element.getBoundingClientRect(); return {width:r.width,height:r.height}; });
    check(dimensions.width >= 48 && dimensions.height >= 48, spec.name + ': accessible button dimensions');
    await page.locator('#stick').scrollIntoViewIfNeeded();
    const stick = await page.locator('#stick').boundingBox();
    const fire = await page.locator('[data-action="fire"]').boundingBox();
    const cdp = await context.newCDPSession(page);
    const p1={id:1,x:stick.x+stick.width*.8,y:stick.y+stick.height*.5};
    const p2={id:2,x:fire.x+fire.width*.5,y:fire.y+fire.height*.5};
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[p1,p2]});
    await page.waitForTimeout(250);
    check(await page.locator('[data-action="fire"]').evaluate(element=>element.classList.contains('active')), spec.name + ': independent fire pointer');
    check(await page.locator('#knob').evaluate(element=>element.style.transform !== ''), spec.name + ': simultaneous move pointer');
    // CDP/Chromium identifies the finger being released, not the one remaining.
    // Verified with trusted pointerup(target=stick), changedTouches=[1].
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[p1]});
    check(await page.locator('#knob').evaluate(element=>element.style.transform === ''), spec.name + ': releasing move clears only joystick');
    check(await page.locator('[data-action="fire"]').evaluate(element=>element.classList.contains('active')), spec.name + ': releasing move does not stop fire');
    await cdp.send('Input.dispatchTouchEvent',{type:'touchCancel',touchPoints:[]});
    check(!(await page.locator('[data-action="fire"]').evaluate(element=>element.classList.contains('active'))), spec.name + ': cancel clears fire');
    await page.locator('[data-action="pause"]').tap();
    await page.waitForTimeout(350);
    check((await state(page)).paused, spec.name + ': actual touch pause');
    await page.locator('[data-action="pause"]').tap();
    await page.waitForTimeout(350);
    check(!(await state(page)).paused, spec.name + ': actual touch resume');
  } else {
    await resume(page);
    await page.locator('#canvas').focus();
    await page.keyboard.press('1');
    await page.waitForFunction(() => JSON.parse(window.thunderStateJson || '{}').weapon_mode === 1, null, {timeout:10000});
    console.log(JSON.stringify({keyboard_probe:spec.name,state:await state(page),focus:await page.evaluate(()=>document.activeElement?.id)}));
    check((await state(page)).weapon_mode === 1, spec.name + ': actual keyboard mode');
    await page.keyboard.down('Space');
    await page.keyboard.down('ArrowLeft');
    await page.waitForTimeout(300);
    await page.keyboard.up('ArrowLeft');
    await page.keyboard.up('Space');
  }
  // DOM blur explicitly pauses even where the engine's focus notification differs.
  await page.evaluate(() => window.dispatchEvent(new Event('blur')));
  await page.waitForTimeout(350);
  check((await state(page)).paused, spec.name + ': focus loss pauses');
  await action(page,'pause');
  const bounds = await page.locator('#stage').boundingBox();
  check(Math.abs(bounds.width/bounds.height-16/9)<.025, spec.name + ': uncropped 16:9');
  check(bounds.x>=0 && bounds.x+bounds.width<=spec.viewport.width+1, spec.name + ': viewport bounds');
  if (output) await page.screenshot({path:path.join(output,'web-'+spec.name+'.png'),fullPage:true});
  check(errors.length===0, spec.name + ': JavaScript errors ' + JSON.stringify(errors));
  await page.waitForFunction(() => window.thunderOfflineReady === true, null, {timeout:90000});
  const worker = await page.evaluate(async () => { const r=await navigator.serviceWorker.ready; return {scope:r.scope,active:Boolean(r.active)}; });
  check(worker.active && worker.scope===new URL('.',url).href, spec.name + ': correct worker subpath');
  check(await page.evaluate(() => window.thunderOfflineReady), spec.name + ': full offline cache verified');
  if (spec.name==='desktop') {
    await page.waitForTimeout(2500);
    await context.setOffline(true);
    await page.reload();
    await page.locator('#start').click();
    await page.waitForFunction(() => window.thunderWebReady && window.thunderStateJson, null, {timeout:60000});
    check((await state(page)).hp>0, 'desktop: real offline reload/game start');
    await context.setOffline(false);
  }
  console.log(JSON.stringify({viewport:spec.name,webgl:'actual-Chromium',physical_device:false,errors,worker,status:'PASS'}));
  await context.close();
}
(async () => {
  const browser = await chromium.launch({channel:process.env.WEB_TEST_BROWSER_CHANNEL || 'chrome',headless:true});
  try {
    const specs = [
      {name:'desktop',viewport:{width:1280,height:900},touch:false},
      {name:'phone-portrait',viewport:{width:390,height:844},touch:true},
      {name:'phone-landscape',viewport:{width:844,height:390},touch:true},
      {name:'tablet',viewport:{width:768,height:1024},touch:true}
    ];
    const requested = process.env.WEB_TEST_VIEWPORTS?.split(',');
    for (const spec of specs.filter(spec => !requested || requested.includes(spec.name))) await testViewport(browser,spec);
    console.log('WEB_BROWSER_TEST_PASS assertions='+assertions+' browser=Chromium phone=emulation offline=actual');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode=1; });
