#!/bin/bash
# Ensure Chromium is running properly
# - Check process count
# - If too many, restart BrowserWing

MAX_PROCS=25
LOG_FILE="/tmp/ensure_chromium.log"
CDP_PORT=44407

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check BrowserWing health first
if curl -s http://localhost:18080/health > /dev/null 2>&1; then
    PROC_COUNT=$(ps aux | grep -E "[c]hrome|[c]hromium" | grep -v grep | wc -l)
    log "Chromium process count: $PROC_COUNT"
    
    if [ $PROC_COUNT -gt $MAX_PROCS ]; then
        log "WARNING: Too many Chromium processes ($PROC_COUNT > $MAX_PROCS)"
        pkill -9 -f chrome 2>/dev/null
        pkill -f browserwing 2>/dev/null
        sleep 3
        su - browserwing -c "cd /home/browserwing && /usr/local/bin/browserwing -config config.toml &"
        sleep 15
    else
        log "OK: Process count is normal ($PROC_COUNT <= $MAX_PROCS)"
    fi
else
    log "ERROR: BrowserWing not responding, restarting..."
    pkill -f browserwing 2>/dev/null
    sleep 3
    su - browserwing -c "cd /home/browserwing && /usr/local/bin/browserwing -config config.toml &"
    sleep 15
fi

# Check CDP port
log "Checking CDP port $CDP_PORT..."
if curl -s http://localhost:$CDP_PORT/json/version > /dev/null 2>&1; then
    log "✅ CDP port $CDP_PORT is responding"
else
    log "⚠️  CDP port $CDP_PORT not responding, starting Chromium..."
    nohup chromium --headless --remote-debugging-port=$CDP_PORT --user-data-dir=/home/browserwing/chrome_user_data \
        --no-first-run --no-default-browser-check --no-sandbox --disable-dev-shm-usage --disable-gpu \
        > /tmp/chromium_$CDP_PORT.log 2>&1 &
    sleep 8
    if curl -s http://localhost:$CDP_PORT/json/version > /dev/null 2>&1; then
        log "✅ Chromium started on port $CDP_PORT"
    else
        log "❌ Failed to start Chromium on port $CDP_PORT"
    fi
fi

# Final health check
sleep 3
curl -s http://localhost:18080/health > /dev/null 2>&1 && log "BrowserWing health check: OK" || log "BrowserWing health check: FAILED"