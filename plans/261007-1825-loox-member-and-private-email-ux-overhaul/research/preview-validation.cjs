const fs = require('fs');
const vm = require('vm');
const crypto = require('crypto');
const { chromium } = require('/Users/bervion/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

(async () => {
  const artifact = '/Users/bervion/Developer/Projects/mobile/ios/Vaultify/plans/261007-1825-loox-member-and-private-email-ux-overhaul/design-preview.html';
  const evidenceDir = '/tmp/loox-preview-qa';
  const browserPath = '/Users/bervion/Library/Caches/ms-playwright/chromium-1148/chrome-mac/Chromium.app/Contents/MacOS/Chromium';
  fs.mkdirSync(evidenceDir, { recursive: true });
  const html = fs.readFileSync(artifact, 'utf8');
  new vm.Script(html.match(/<script>([\s\S]*?)<\/script>/)[1]);
  const browser = await chromium.launch({ headless: true, executablePath: browserPath });
  const page = await browser.newPage({ viewport: { width: 1200, height: 1060 } });
  const scriptErrors = [];
  const nonFileRequests = [];
  page.on('pageerror', error => scriptErrors.push(error.message));
  page.on('request', request => { if (!request.url().startsWith('file:')) nonFileRequests.push(request.url()); });
  await page.goto('file://' + artifact);
  const screens = ['overview', 'services', 'service-detail', 'create', 'alias', 'inbox', 'domains', 'member', 'links', 'browser', 'family'];
  const failures = [];
  let combinations = 0;
  for (const theme of ['light', 'dark']) for (const width of [375, 430]) {
    for (const large of [false, true]) for (const status of ['verified', 'pending', 'offline']) {
      for (const screen of screens) {
        await page.evaluate(config => { Object.assign(state, config); render(); }, { screen, status, theme, width, large, longEmail: true });
        const result = await page.evaluate(() => {
          const root = document.getElementById('phone');
          const content = document.getElementById('phone-screen');
          return {
            horizontalOverflow: content.scrollWidth > content.clientWidth,
            primaryCount: root.querySelectorAll('.primary').length,
            controlsBelow44px: [...root.querySelectorAll('button')].filter(button => button.getBoundingClientRect().height < 43.9).map(button => button.textContent.trim()),
            unresolvedIcons: [...root.querySelectorAll('use')].filter(use => !document.getElementById(use.getAttribute('href').slice(1))).length
          };
        });
        combinations++;
        if (result.horizontalOverflow || result.primaryCount > 1 || result.controlsBelow44px.length || result.unresolvedIcons) {
          failures.push({ screen, status, theme, width, large, ...result });
        }
      }
    }
  }
  const screenshots = {};
  for (const screen of screens) {
    await page.evaluate(screen => { Object.assign(state, { screen, status: 'verified', theme: 'light', width: 375, large: false, longEmail: false }); render(); }, screen);
    const image = evidenceDir + '/' + screen + '-375.png';
    await page.screenshot({ path: image });
    screenshots[screen] = image;
  }
  await page.evaluate(() => { Object.assign(state, { screen: 'inbox', status: 'pending', theme: 'light', width: 375 }); render(); });
  screenshots.inboxPending = evidenceDir + '/inbox-pending-375.png';
  await page.screenshot({ path: screenshots.inboxPending });
  for (const screen of ['inbox', 'member', 'services', 'service-detail']) {
    await page.evaluate(screen => { Object.assign(state, { screen, status: 'verified', theme: 'dark', width: 430, large: true, longEmail: true }); render(); }, screen);
    screenshots[screen + 'DarkLarge'] = evidenceDir + '/' + screen + '-dark-large-430.png';
    await page.screenshot({ path: screenshots[screen + 'DarkLarge'] });
  }
  await page.evaluate(() => { Object.assign(state, { screen: 'overview', status: 'verified', theme: 'light', width: 375, large: false, longEmail: false }); render(); });
  await page.locator('[data-action="all-linked-services"]').click();
  const allServicesListed = (await page.locator('[data-service-id]').count()) === 3;
  const personaAndTrustedAddressFilter = await page.evaluate(() => {
    demoLogins.push({ id: 'other-persona', personaID: 'work', title: 'Other', privateEmail: 'b4p8q2@relay.looxpassword.com' }, { id: 'unknown-address', personaID: 'personal', title: 'Other', privateEmail: 'unknown@example.com' });
    const valid = linkedServices().length === 3;
    demoLogins.splice(-2, 2);
    return valid;
  });
  await page.selectOption('#screen-select', 'overview');
  await page.locator('[data-alias-address="b4p8q2@relay.looxpassword.com"]').click();
  await page.locator('[data-action="alias-linked-services"]').click();
  const aliasFiltered = (await page.locator('[data-service-id]').count()) === 2 && (await page.locator('[data-service-id="github"]').count()) === 0;
  screenshots.servicesFiltered = evidenceDir + '/services-filtered-375.png';
  await page.screenshot({ path: screenshots.servicesFiltered });
  await page.locator('[data-service-id="facebook"]').click();
  await page.locator('[data-action="open-service-login"]').click();
  const loginDetailOpened = (await page.locator('#choice-dialog').innerText()).includes('facebook.person@example.com') && (await page.locator('#choice-dialog').innerText()).includes('b4p8q2@relay.looxpassword.com');
  await page.locator('[data-action="close-dialog"]').click();
  await page.locator('[data-action="confirm-unlink"]').click();
  const unlinkConfirmationClear = (await page.locator('#dialog-description').innerText()) === 'Gỡ địa chỉ này khỏi mục Facebook trong vault. Địa chỉ vẫn nhận thư. Tài khoản Facebook giữ nguyên email đăng nhập.';
  screenshots.unlinkConfirmation = evidenceDir + '/service-unlink-confirmation-375.png';
  await page.screenshot({ path: screenshots.unlinkConfirmation });
  await page.locator('[data-action="close-dialog"]').click();
  const cancellationPreservedField = await page.evaluate(() => linkedServices('b4p8q2@relay.looxpassword.com').length === 2);
  await page.locator('[data-action="confirm-unlink"]').click();
  await page.locator('[data-action="unlink-confirmed"]').click();
  const unlinkFilteredCount = (await page.locator('[data-service-id]').count()) === 1 && (await page.locator('[data-service-id="gmail"]').count()) === 1;
  const unlinkPreservedLoginAndAlias = await page.evaluate(() => demoLogins.length === 3 && demoLogins.find(login => login.id === 'facebook').username === 'facebook.person@example.com' && demoLogins.find(login => login.id === 'facebook').privateEmail === null && trustedAliasAddresses.size === 2 && state.aliasPaused === false);
  screenshots.servicesAfterUnlink = evidenceDir + '/services-after-unlink-375.png';
  await page.screenshot({ path: screenshots.servicesAfterUnlink });
  await page.locator('[data-action="all-linked-services"]').click();
  const unlinkGeneralCount = (await page.locator('[data-service-id]').count()) === 2;
  await page.selectOption('#screen-select', 'overview');
  const overviewCountUpdated = (await page.locator('#phone-screen').innerText()).includes('2 mục đăng nhập trong hồ sơ Cá nhân');
  await page.evaluate(() => { Object.assign(state, { screen: 'create', status: 'verified', theme: 'light', width: 375, large: false, longEmail: false }); render(); });
  await page.fill('#alias-label', 'Tên gợi nhớ mẫu dài');
  await page.fill('#alias-website', 'forum.example.com');
  await page.locator('[data-action="reveal-composer"]').click();
  const composerReveal = (await page.locator('#phone-screen').innerText()).includes('minh@example.com');
  await page.locator('[data-screen="domains"]').click();
  await page.locator('[data-domain="relay.looxpassword.com"]').click();
  await page.locator('[data-action="domain-done"]').click();
  const draftRetained = (await page.inputValue('#alias-label')) === 'Tên gợi nhớ mẫu dài';
  await page.selectOption('#screen-select', 'inbox');
  await page.selectOption('#state-select', 'pending');
  await page.locator('[data-action="check-status"]').click();
  await page.waitForTimeout(800);
  const mockVerificationCompleted = (await page.locator('#phone-screen').innerText()).includes('Đã xác minh');
  await page.locator('[data-action="reveal"]').click();
  const concealWorked = (await page.locator('.email-full').innerText()) === 'mi***@example.com';
  await page.selectOption('#state-select', 'pending');
  await page.locator('[data-action="check-status"]').click();
  await page.selectOption('#state-select', 'offline');
  await page.waitForTimeout(800);
  const staleMockIgnored = (await page.inputValue('#state-select')) === 'offline';
  await page.selectOption('#state-select', 'verified');
  await page.selectOption('#screen-select', 'create');
  await page.locator('[data-purpose="reusable"]').click();
  await page.locator('[data-action="create-complete"]').click();
  const reusableHasNoWebsite = (await page.locator('#phone-screen').getByText('Trang web', { exact: true }).count()) === 0;
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const reducedMotionTransition = await page.evaluate(() => getComputedStyle(document.querySelector('.primary')).transitionDuration);
  const interactions = { allServicesListed, personaAndTrustedAddressFilter, aliasFiltered, loginDetailOpened, unlinkConfirmationClear, cancellationPreservedField, unlinkFilteredCount, unlinkPreservedLoginAndAlias, unlinkGeneralCount, overviewCountUpdated, composerReveal, draftRetained, mockVerificationCompleted, concealWorked, staleMockIgnored, reusableHasNoWebsite, reducedMotionTransition };
  const receipt = {
    recordedAtUTC: new Date().toISOString(), artifact, sha256: crypto.createHash('sha256').update(html).digest('hex'),
    bytes: Buffer.byteLength(html), syntax: 'passed', runner: 'Bundled Playwright with existing Chromium 1148',
    combinations, failures, scriptErrors, nonFileRequests, interactions, screenshots,
    scope: 'HTML concept only. Status transitions simulated locally. No app tests, mail delivery, domain activation, signing, deploy, or native device QA.'
  };
  fs.writeFileSync(evidenceDir + '/validation.json', JSON.stringify(receipt, null, 2) + '\n');
  console.log(JSON.stringify({ receipt: evidenceDir + '/validation.json', ...receipt }, null, 2));
  await browser.close();
  if (failures.length || scriptErrors.length || nonFileRequests.length || Object.entries(interactions).some(([key, value]) => key !== 'reducedMotionTransition' && !value) || reducedMotionTransition !== '0s') process.exitCode = 1;
})().catch(error => { console.error(error.message); process.exit(1); });
