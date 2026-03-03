#!/bin/bash
# Ensure X cookie is set in BrowserWing browser

COOKIE_FILE="/home/browserwing/cookie.json"

if [ ! -f "$COOKIE_FILE" ]; then
    echo "❌ Cookie file not found: $COOKIE_FILE"
    exit 1
fi

# Get CDP port - BrowserWing uses fixed port 44407
CDP_PORT=44407

echo "Setting X cookie (CDP port: $CDP_PORT)..."

NODE_PATH=/tmp/node_modules node -e "
const puppeteer = require('puppeteer-core');
const fs = require('fs');
const cookieFile = '$COOKIE_FILE';
const cdpPort = $CDP_PORT;

(async () => {
    try {
        const browser = await puppeteer.connect({browserURL: 'http://localhost:' + cdpPort});
        const pages = await browser.pages();
        const page = pages[0] || await browser.newPage();
        
        const cookies = JSON.parse(fs.readFileSync(cookieFile, 'utf8'));
        for (const c of cookies) {
            await page.setCookie({
                name: c.name,
                value: c.value,
                domain: c.domain || '.x.com',
                path: c.path || '/',
                httpOnly: !!c.httpOnly,
                secure: !!c.secure
            });
        }
        console.log('✅ Cookie set successfully');
        await browser.disconnect();
    } catch (e) {
        console.error('❌ Error:', e.message);
        process.exit(1);
    }
})();
" 2>&1
