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
    log "⚠️  CDP port $CDP_PORT not responding, restarting BrowserWing..."
    # Kill existing processes
    pkill -9 -f chrome 2>/dev/null || true
    pkill -f browserwing 2>/dev/null || true
    sleep 3
    
    # Start BrowserWing (which manages Chromium with CDP)
    su - browserwing -c "cd /home/browserwing && /usr/local/bin/browserwing -config config.toml &"
    
    # Wait for CDP to be ready
    log "Waiting for CDP port $CDP_PORT..."
    for i in {1..30}; do
        if curl -s http://localhost:$CDP_PORT/json/version > /dev/null 2>&1; then
            log "✅ CDP port $CDP_PORT is ready"
            break
        fi
        sleep 2
    done
    
    if ! curl -s http://localhost:$CDP_PORT/json/version > /dev/null 2>&1; then
        log "❌ Failed to start CDP on port $CDP_PORT after 60s"
        exit 1
    fi
fi

# Final health check
sleep 3
curl -s http://localhost:18080/health > /dev/null 2>&1 && log "BrowserWing health check: OK" || log "BrowserWing health check: FAILED"