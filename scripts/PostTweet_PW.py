#!/usr/bin/env python3
import argparse, json, os, time
from playwright.sync_api import sync_playwright


def to_cookie(c):
    ss = str(c.get('sameSite', '')).lower()
    if ss in ('none', 'no_restriction'):
        same = 'None'
    elif ss == 'strict':
        same = 'Strict'
    else:
        same = 'Lax'
    d = {
        'name': c['name'], 'value': c['value'], 'domain': c['domain'],
        'path': c.get('path', '/'), 'httpOnly': bool(c.get('httpOnly', False)),
        'secure': bool(c.get('secure', True)), 'sameSite': same
    }
    if c.get('expirationDate'):
        d['expires'] = int(c['expirationDate'])
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cookie-file', required=True)
    ap.add_argument('--text', required=True)
    ap.add_argument('--media', default='')
    args = ap.parse_args()

    raw = json.load(open(args.cookie_file, 'r', encoding='utf-8'))
    cookies = [to_cookie(c) for c in raw if c.get('name') and c.get('value') and c.get('domain')]

    result = {'ok': False}
    with sync_playwright() as p:
        launch_kwargs = {'headless': True, 'args': ['--no-sandbox', '--disable-dev-shm-usage']}
        if os.path.exists('/usr/bin/chromium'):
            launch_kwargs['executable_path'] = '/usr/bin/chromium'
        browser = p.chromium.launch(**launch_kwargs)
        context = browser.new_context(viewport={'width': 1366, 'height': 900})
        context.add_cookies(cookies)
        page = context.new_page()

        try:
            try:
                page.goto('https://x.com/compose/post', wait_until='domcontentloaded', timeout=60000)
            except Exception:
                page.goto('https://twitter.com/compose/post', wait_until='domcontentloaded', timeout=60000)
            page.wait_for_timeout(5000)

            # dismiss possible overlays/cookie masks
            for _ in range(3):
                page.keyboard.press('Escape')
                page.wait_for_timeout(300)
            # try close known cookie/dialog buttons if present
            for sel in ['button:has-text("Accept")','button:has-text("I understand")','button:has-text("Not now")','[data-testid="SheetDialog"] button']:
                try:
                    btn = page.locator(sel).first
                    if btn.count() > 0:
                        btn.click(timeout=1200)
                        page.wait_for_timeout(300)
                except Exception:
                    pass
            # hide blocking mask if exists
            try:
                page.evaluate("""() => {
                  const m = document.querySelector('[data-testid="twc-cc-mask"]');
                  if (m) m.remove();
                }""")
            except Exception:
                pass

            box = page.locator('div[role="textbox"][data-testid="tweetTextarea_0"]').first
            if box.count() == 0:
                box = page.locator('[data-testid="tweetTextarea_0_label"]').first
            try:
                box.click(timeout=12000)
            except Exception:
                box.click(timeout=12000, force=True)
            page.keyboard.type(args.text, delay=8)

            if args.media:
                if not os.path.exists(args.media):
                    raise RuntimeError(f'media not found: {args.media}')
                file_input = page.locator('input[type="file"][data-testid="fileInput"]').first
                if file_input.count() == 0:
                    file_input = page.locator('input[type="file"]').first
                file_input.set_input_files(args.media)
                page.wait_for_timeout(9000)

            btn = page.locator('[data-testid="tweetButton"]').first
            if btn.count() == 0:
                btn = page.locator('[data-testid="tweetButtonInline"]').first
            if btn.count() == 0:
                raise RuntimeError('tweet button not found')
            if btn.get_attribute('aria-disabled') == 'true':
                raise RuntimeError('tweet button disabled')

            clicked = False
            click_err = None
            for method in ('normal', 'force', 'js'):
                try:
                    if method == 'normal':
                        btn.click(timeout=8000)
                    elif method == 'force':
                        btn.click(timeout=8000, force=True)
                    else:
                        page.evaluate("(el)=>el.click()", btn.element_handle())
                    clicked = True
                    break
                except Exception as e:
                    click_err = e
                    # try closing common overlays and retry
                    page.keyboard.press('Escape')
                    page.wait_for_timeout(600)

            if not clicked:
                # final fallback: Ctrl/Cmd+Enter submit
                try:
                    page.keyboard.press('Control+Enter')
                    clicked = True
                except Exception:
                    pass

            if not clicked:
                ts = int(time.time())
                shot = f"/root/.openclaw/workspace/tmp/posttweet_click_fail_{ts}.png"
                page.screenshot(path=shot, full_page=True)
                raise RuntimeError(f'tweet button click failed: {click_err}; screenshot={shot}')

            page.wait_for_timeout(7000)
            cur = page.url
            result = {'ok': True, 'url': cur}
        except Exception as e:
            try:
                ts = int(time.time())
                shot = f"/root/.openclaw/workspace/tmp/posttweet_error_{ts}.png"
                page.screenshot(path=shot, full_page=True)
                result = {'ok': False, 'error': str(e), 'screenshot': shot}
            except Exception:
                result = {'ok': False, 'error': str(e)}
        finally:
            browser.close()

    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
