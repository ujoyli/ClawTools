#!/usr/bin/env python3
import argparse, json, re


def to_playwright_cookie(c):
    same_site = str(c.get('sameSite', '')).lower()
    if same_site in ('no_restriction', 'none'):
        ss = 'None'
    elif same_site == 'strict':
        ss = 'Strict'
    else:
        ss = 'Lax'
    d = {
        'name': c['name'], 'value': c['value'], 'domain': c['domain'],
        'path': c.get('path', '/'), 'httpOnly': bool(c.get('httpOnly', False)),
        'secure': bool(c.get('secure', True)), 'sameSite': ss,
    }
    if c.get('expirationDate'):
        d['expires'] = int(c['expirationDate'])
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cookie-file', required=True)
    ap.add_argument('--url', required=True)
    ap.add_argument('--reply', required=True)
    args = ap.parse_args()

    try:
        from playwright.sync_api import sync_playwright
    except Exception:
        print(json.dumps({'ok': False, 'error': 'playwright not installed'}))
        return

    cookies_raw = json.load(open(args.cookie_file, 'r', encoding='utf-8'))
    cookies = [to_playwright_cookie(c) for c in cookies_raw if c.get('name') and c.get('value') and c.get('domain')]

    result = {'ok': False, 'error': ''}
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, executable_path='/usr/bin/chromium', args=['--no-sandbox', '--disable-dev-shm-usage'])
        context = browser.new_context(viewport={'width': 1366, 'height': 900})
        context.add_cookies(cookies)
        page = context.new_page()

        try:
            page.goto(args.url, wait_until='domcontentloaded', timeout=60000)
            page.wait_for_timeout(4000)

            # open reply box
            try:
                page.locator('[data-testid="reply"]').first.click(timeout=5000)
            except Exception:
                pass
            page.wait_for_timeout(1200)

            box = page.locator('div[role="textbox"][data-testid="tweetTextarea_0"]').first
            if box.count() == 0:
                box = page.locator('[data-testid="tweetTextarea_0_label"]').first
            box.click(timeout=10000)
            page.keyboard.type(args.reply, delay=8)

            btn = page.locator('[data-testid="tweetButton"]').first
            if btn.count() == 0:
                btn = page.locator('[data-testid="tweetButtonInline"]').first
            if btn.count() == 0:
                raise RuntimeError('tweet button not found')

            disabled = btn.get_attribute('aria-disabled')
            if disabled == 'true':
                raise RuntimeError('tweet button disabled')

            btn.click(timeout=10000)
            page.wait_for_timeout(5000)

            # soft confirmation
            cur = page.url
            result['ok'] = True
            result['url'] = cur
        except Exception as e:
            result['error'] = str(e)
        finally:
            browser.close()

    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
