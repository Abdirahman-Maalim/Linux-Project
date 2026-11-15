#!/usr/bin/env bash
#
# health-check.sh - Linux Administration Project
#
# Purpose : Validate the project environment: users, groups, directory
#           ownership/permissions, the NGINX service, and the website.
# Usage   : sudo -u webadmin /opt/linuxproject/scripts/health-check.sh
# Output  : PASS/WARN/FAIL lines on screen, a timestamped log in
#           /opt/linuxproject/logs and a copy in /opt/linuxproject/reports.
# Exit    : 0 when there are no FAIL results, 1 otherwise.

set -u

# ---------- Variables ----------
PROJECT_DIR="/opt/linuxproject"
WEB_ROOT="/var/www/linuxproject/html"
LOG_DIR="$PROJECT_DIR/logs"
REPORT_DIR="$PROJECT_DIR/reports"
SITE_URL="http://localhost"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/health-check-$TIMESTAMP.log"
REPORT_FILE="$REPORT_DIR/latest-report.txt"

EXPECTED_USERS=("webadmin" "auditor")
EXPECTED_GROUPS=("webteam" "webaudit")
EXPECTED_MEMBERS=("webadmin:webteam" "auditor:webaudit")   # user:group
# path:owner:group:mode
EXPECTED_DIRS=(
    "$PROJECT_DIR:root:root:755"
    "$PROJECT_DIR/scripts:webadmin:webteam:2775"
    "$PROJECT_DIR/docs:webadmin:webteam:2775"
    "$PROJECT_DIR/config:webadmin:webteam:2770"
    "$PROJECT_DIR/logs:webadmin:webaudit:2750"
    "$PROJECT_DIR/reports:webadmin:webaudit:2750"
    "/var/www/linuxproject:webadmin:webteam:2775"
    "$WEB_ROOT:webadmin:webteam:2775"
)
EXPECTED_SITE_FILES=("index.html" "styles.css")
EXPECTED_URLS=("/" "/styles.css")

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
LOG_OK="no"

# ---------- Helper functions ----------
# Print a line to the screen and, when possible, append it to the log file.
log() {
    echo "$*"
    if [ "$LOG_OK" = "yes" ]; then
        echo "$*" >> "$LOG_FILE"
    fi
}

# record STATUS MESSAGE : count the result and print it.
record() {
    local status="$1"
    shift
    case "$status" in
        PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    esac
    log "[$status] $*"
}

# ---------- Check functions ----------
check_users_groups() {
    log ""
    log "--- Users and groups ---"
    local u g pair
    for u in "${EXPECTED_USERS[@]}"; do
        if id "$u" >/dev/null 2>&1; then
            record PASS "User '$u' exists"
        else
            record FAIL "User '$u' is missing"
        fi
    done
    for g in "${EXPECTED_GROUPS[@]}"; do
        if getent group "$g" >/dev/null 2>&1; then
            record PASS "Group '$g' exists"
        else
            record FAIL "Group '$g' is missing"
        fi
    done
    for pair in "${EXPECTED_MEMBERS[@]}"; do
        u="${pair%%:*}"
        g="${pair##*:}"
        if id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
            record PASS "'$u' is a member of '$g'"
        else
            record FAIL "'$u' is NOT a member of '$g'"
        fi
    done
}

check_directories() {
    log ""
    log "--- Directory ownership and permissions ---"
    local entry path owner group mode actual expected
    for entry in "${EXPECTED_DIRS[@]}"; do
        IFS=':' read -r path owner group mode <<< "$entry"
        if [ ! -d "$path" ]; then
            record FAIL "Directory missing: $path"
            continue
        fi
        actual="$(stat -c '%U:%G:%a' "$path")"
        expected="$owner:$group:$mode"
        if [ "$actual" = "$expected" ]; then
            record PASS "$path is $actual"
        else
            record FAIL "$path expected $expected but found $actual"
        fi
    done
}

check_nginx() {
    log ""
    log "--- NGINX service ---"
    if ! command -v nginx >/dev/null 2>&1; then
        record FAIL "NGINX is not installed"
        return
    fi
    record PASS "NGINX is installed ($(nginx -v 2>&1 | cut -d/ -f2))"

    if systemctl is-active --quiet nginx; then
        record PASS "NGINX service is active"
    else
        record FAIL "NGINX service is not active"
    fi

    if systemctl is-enabled --quiet nginx; then
        record PASS "NGINX is enabled at boot"
    else
        record WARN "NGINX is not enabled at boot"
    fi

    # nginx -t needs root; webadmin is allowed this single command via sudoers.
    local out rc
    out="$(sudo -n /usr/sbin/nginx -t 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        record PASS "NGINX configuration test passed"
    elif echo "$out" | grep -q "^sudo:"; then
        record WARN "Could not run 'nginx -t' (sudo not permitted for this user)"
    else
        record FAIL "NGINX configuration test failed: $(echo "$out" | head -1)"
    fi

    if ss -ltn | awk '{print $4}' | grep -qE ':80$'; then
        record PASS "A listener is bound to port 80"
    else
        record FAIL "Nothing is listening on port 80"
    fi
}

check_website() {
    log ""
    log "--- Website ---"
    local f p code
    for f in "${EXPECTED_SITE_FILES[@]}"; do
        if [ -f "$WEB_ROOT/$f" ]; then
            record PASS "Site file present: $WEB_ROOT/$f"
        else
            record FAIL "Site file missing: $WEB_ROOT/$f"
        fi
    done
    if ! command -v curl >/dev/null 2>&1; then
        record WARN "curl not found, skipping HTTP checks"
        return
    fi
    for p in "${EXPECTED_URLS[@]}"; do
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$SITE_URL$p")"
        if [ "$code" = "200" ]; then
            record PASS "GET $SITE_URL$p returned HTTP $code"
        else
            record FAIL "GET $SITE_URL$p returned HTTP $code (expected 200)"
        fi
    done
}

# ---------- Main ----------
if [ -w "$LOG_DIR" ]; then
    LOG_OK="yes"
else
    echo "[WARN] Cannot write to $LOG_DIR - output will not be logged"
fi

log "=== Project health check: $(date) ==="
log "Host: $(hostname) | Run as: $(whoami)"

check_users_groups
check_directories
check_nginx
check_website

log ""
log "=== Summary: $PASS_COUNT passed, $WARN_COUNT warnings, $FAIL_COUNT failed ==="

if [ "$LOG_OK" = "yes" ] && [ -w "$REPORT_DIR" ]; then
    cp "$LOG_FILE" "$REPORT_FILE"
    echo "Log saved to: $LOG_FILE"
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
