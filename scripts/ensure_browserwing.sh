#!/bin/bash
# Ensure BrowserWing is running and logged in to X
# - Start BrowserWing if not running
# - Set X cookies for authentication
# - Return CDP port for scripts to use

LOG_FILE="/tmp/ensure_browserwing.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if BrowserWing is responding
if curl -s http://localhost:18080/health > /dev/null 2>&1; then
    log "BrowserWing is running"
else
    log "Starting BrowserWing..."
    pkill -f browserwing 2>/dev/null
    sleep 3
    su - browserwing -c "cd /home/browserwing && /usr/local/bin/browserwing -config config.toml &"
    sleep 20
fi

# Navigate to X and set cookies
log "Setting X authentication cookies..."
curl -s -X POST http://localhost:18080/api/v1/executor/navigate \
    -H "Content-Type: application/json" \
    -d '{"url":"https://x.com/home","wait_until":"networkidle2","timeout":30}' > /dev/null 2>&1

sleep 3

# Set X cookies via Node.js
NODE_PATH=/tmp/node_modules node -e '
const puppeteer = require("puppeteer-core");
(async () => {
    try {
        const browser = await puppeteer.connect({browserURL: "http://localhost:18080"});
        const pages = await browser.pages();
        const page = pages[0] || await browser.newPage();
        const cookies = JSON.parse(require("fs").readFileSync("/home/browserwing/cookie.json", "utf8"));
        for (const c of cookies) {
            await page.setCookie({
                name: c.name,
                value: c.value,
                domain: c.domain || ".x.com",
                path: c.path || "/",
                httpOnly: !!c.httpOnly,
                secure: !!c.secure
            });
        }
        console.log("X cookies set successfully");
        await browser.disconnect();
    } catch(e) {
        console.error("Error setting cookies:", e.message);
    }
})();
' 2>&1

log "BrowserWing ready with X authentication"
echo "18080" > /tmp/cdp_port.txt