#!/usr/bin/env python3
"""
AI Quota & Limits Collector
Fetches real-time rate limits, gauges, and usage stats for Codex, Claude, and Antigravity.
"""

import sys
import os
import json
import time
import subprocess
import glob
import base64
import re
import urllib.error
import urllib.request
from datetime import datetime

CACHE_DIR = os.path.expanduser("~/Library/Caches/BillionTokens")
CACHE_FILE = os.path.join(CACHE_DIR, "cache.json")
CACHE_TTL = 45  # seconds

CONFIG_FILE = os.path.expanduser("~/Library/Application Support/BillionTokens/config.json")
DEFAULT_PROVIDERS = {
    "codex": True,
    "claude": True,
    # Uses an undocumented Google endpoint and a token read from Keychain, so it is opt-in.
    "antigravity": False,
}


def work_dir():
    """Private working directory for CLI subprocesses.

    Never run them from /tmp: any local user can plant project config there
    (e.g. .claude/settings.json hooks) that the CLIs would load and execute.
    """
    os.makedirs(CACHE_DIR, mode=0o700, exist_ok=True)
    return CACHE_DIR


def load_providers():
    providers = dict(DEFAULT_PROVIDERS)
    try:
        with open(CONFIG_FILE) as f:
            providers.update(json.load(f).get("providers", {}))
    except Exception:
        pass
    return providers


def get_codex_limits():
    """Query Codex real-time rate limits via app-server JSON-RPC."""
    try:
        proc = subprocess.Popen(
            ["codex", "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            cwd=work_dir()
        )

        init_req = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {"clientInfo": {"name": "billiontokens", "version": "1.0"}, "capabilities": {}}
        }
        proc.stdin.write(json.dumps(init_req) + "\n")
        proc.stdin.flush()

        start_time = time.time()
        while time.time() - start_time < 3:
            line = proc.stdout.readline()
            if not line:
                break
            try:
                msg = json.loads(line)
                if msg.get("id") == 1:
                    break
            except Exception:
                continue

        rate_req = {"jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read", "params": None}
        proc.stdin.write(json.dumps(rate_req) + "\n")
        proc.stdin.flush()

        rate_data = None
        while time.time() - start_time < 5:
            line = proc.stdout.readline()
            if not line:
                break
            try:
                msg = json.loads(line)
                if msg.get("id") == 2 and "result" in msg:
                    rate_data = msg["result"]
                    break
            except Exception:
                continue

        proc.terminate()
        try:
            proc.wait(timeout=1)
        except Exception:
            proc.kill()

        if rate_data:
            rl = rate_data.get("rateLimits", {})
            primary = rl.get("primary") or {}
            secondary = rl.get("secondary") or {}
            reset_credits = rate_data.get("rateLimitResetCredits") or {}

            now = int(time.time())
            pri_reset = primary.get("resetsAt")
            pri_mins = max(0, int((pri_reset - now) / 60)) if pri_reset else 0
            pri_reset_str = f"{pri_mins // 60}h {pri_mins % 60}m" if pri_mins >= 60 else f"{pri_mins}m"

            sec_reset = secondary.get("resetsAt")
            sec_hours = max(0, int((sec_reset - now) / 3600)) if sec_reset else 0
            sec_days = round(sec_hours / 24.0, 1)

            return {
                "status": "connected",
                "plan": rl.get("planType", "plus").capitalize(),
                "primary": {
                    "used_percent": primary.get("usedPercent", 0),
                    "window_mins": primary.get("windowDurationMins", 300),
                    "resets_in_mins": pri_mins,
                    "reset_str": pri_reset_str,
                    "resets_at": pri_reset
                },
                "secondary": {
                    "used_percent": secondary.get("usedPercent", 0),
                    "window_mins": secondary.get("windowDurationMins", 10080),
                    "resets_in_days": sec_days,
                    "reset_str": f"{sec_days}d",
                    "resets_at": sec_reset
                },
                "reset_credits": reset_credits.get("availableCount", 0),
                "account_id": rate_data.get("accountId")
            }
    except Exception as e:
        return {"status": "error", "error": str(e)}

    return {"status": "offline"}


def get_claude_limits():
    """Fetch Claude limits via `claude -p /cost` and account metadata."""
    info = {
        "status": "offline",
        "plan": "",
        "billing": "",
        "email": "",
        "tier": "",
        "primary": {
            "used_percent": 0,
            "reset_str": "--"
        },
        "secondary": {
            "used_percent": 0,
            "reset_str": "--"
        },
        "recent_tokens": {
            "input": 0,
            "output": 0,
            "cache_read": 0,
            "cache_creation": 0
        }
    }

    try:
        claude_json = os.path.expanduser("~/.claude.json")
        if os.path.exists(claude_json):
            with open(claude_json) as f:
                data = json.load(f)
            acc = data.get("oauthAccount", {})
            if acc:
                info["status"] = "connected"
                info["email"] = acc.get("emailAddress", "")
                org_type = acc.get("organizationType", "claude_pro")
                info["plan"] = org_type.replace("_", " ").title()
                info["billing"] = acc.get("billingType", "")
                info["tier"] = acc.get("organizationRateLimitTier", "default_claude_ai")

        # Run `claude -p /cost` for live session and weekly limit usage.
        # /cost is a local command (no model call); --no-session-persistence keeps
        # each poll from writing a session file under ~/.claude/projects.
        try:
            cost_proc = subprocess.run(
                ["claude", "-p", "--no-session-persistence", "/cost"],
                capture_output=True,
                text=True,
                timeout=15,
                cwd=work_dir()
            )
            cost_out = cost_proc.stdout

            session_match = re.search(r'Current session:\s*(\d+)%\s*used[^\w\n]*resets?\s*([^\n\(\)]+)', cost_out, re.IGNORECASE)
            week_match = re.search(r'Current week[^:]*:\s*(\d+)%\s*used[^\w\n]*resets?\s*([^\n\(\)]+)', cost_out, re.IGNORECASE)

            if session_match:
                pct = int(session_match.group(1))
                r_str = session_match.group(2).strip()
                # Clean up e.g. "Sep 28 at 1:09pm" -> "1:09 PM"
                if " at " in r_str:
                    r_str = r_str.split(" at ")[-1].strip()
                info["primary"] = {
                    "used_percent": pct,
                    "reset_str": f"Resets at {r_str}"
                }
            if week_match:
                pct = int(week_match.group(1))
                r_str = week_match.group(2).strip()
                info["secondary"] = {
                    "used_percent": pct,
                    "reset_str": f"Resets {r_str}"
                }
        except Exception:
            pass

        # Find latest session tokens (skip sessions with no model usage, e.g. /cost runs)
        files = glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl"))
        for path in sorted(files, key=os.path.getmtime, reverse=True)[:10]:
            with open(path) as f:
                last_usage = None
                for line in f:
                    try:
                        record = json.loads(line)
                        if "usage" in record:
                            last_usage = record["usage"]
                        elif "message" in record and isinstance(record["message"], dict) and "usage" in record["message"]:
                            last_usage = record["message"]["usage"]
                    except Exception:
                        pass
                if last_usage:
                    info["recent_tokens"] = {
                        "input": last_usage.get("input_tokens", 0),
                        "output": last_usage.get("output_tokens", 0),
                        "cache_read": last_usage.get("cache_read_input_tokens", 0),
                        "cache_creation": last_usage.get("cache_creation_input_tokens", 0)
                    }
                    break
    except Exception as e:
        info["error"] = str(e)

    return info


def get_antigravity_limits():
    """Fetch Google Antigravity account status and real-time quota limits from cloudcode API."""
    info = {
        "status": "offline",
        "plan": "Consumer",
        "email": "",
        "auth_method": "",
        "conversations_count": 0,
        "active_model": "",
        "last_active": "",
        "primary": {
            "used_percent": 0,
            "reset_str": "--"
        },
        "secondary": {
            "used_percent": 0,
            "reset_str": "--"
        }
    }

    try:
        # Check Keychain for token
        res = subprocess.run(
            ["security", "find-generic-password", "-s", "gemini", "-a", "antigravity", "-w"],
            capture_output=True,
            text=True,
            cwd=work_dir()
        )
        token = None
        if res.returncode == 0:
            val = res.stdout.strip().replace("go-keyring-base64:", "")
            try:
                raw = base64.b64decode(val).decode()
                d = json.loads(raw)
                info["status"] = "connected"
                info["auth_method"] = d.get("auth_method", "consumer")
                token = d.get("token", {}).get("access_token")
                expiry = d.get("token", {}).get("expiry")
                if expiry:
                    info["token_expiry"] = expiry
            except Exception:
                pass

        # Query cloudcode-pa quota API with token
        if token:
            try:
                req = urllib.request.Request(
                    "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
                    headers={
                        "Authorization": f"Bearer {token}",
                        "Content-Type": "application/json",
                        "User-Agent": "Antigravity/1.0"
                    },
                    data=b"{}"
                )
                with urllib.request.urlopen(req, timeout=4) as resp:
                    data = json.loads(resp.read().decode())
                    for g in data.get("groups", []):
                        if g.get("displayName") == "Gemini Models":
                            for b in g.get("buckets", []):
                                window = b.get("window")
                                rem = b.get("remainingFraction", 1.0)
                                used_pct = max(0, min(100, round((1.0 - rem) * 100)))
                                desc = b.get("description", "")
                                reset_time = b.get("resetTime")

                                # Extract refresh time string from description
                                r_str = ""
                                if "refresh in " in desc:
                                    r_str = desc.split("refresh in ")[-1].rstrip(".")
                                elif reset_time:
                                    r_str = reset_time

                                if window == "5h":
                                    info["primary"] = {
                                        "used_percent": used_pct,
                                        "reset_str": f"Resets in {r_str}" if r_str else "--"
                                    }
                                elif window == "weekly":
                                    info["secondary"] = {
                                        "used_percent": used_pct,
                                        "reset_str": f"Resets in {r_str}" if r_str else "--"
                                    }
            except urllib.error.HTTPError as api_err:
                info["quota_api_error"] = str(api_err)
                if api_err.code == 401:
                    info["status"] = "token_expired"
            except Exception as api_err:
                info["quota_api_error"] = str(api_err)

        # Check history.jsonl
        hist_path = os.path.expanduser("~/.gemini/antigravity-cli/history.jsonl")
        if os.path.exists(hist_path):
            with open(hist_path) as f:
                lines = [l for l in f if l.strip()]
                info["conversations_count"] = len(lines)
                if lines:
                    last = json.loads(lines[-1])
                    ts = last.get("timestamp")
                    if ts:
                        info["last_active"] = time.strftime("%H:%M:%S", time.localtime(ts / 1000.0))

        # Check recent log for account email
        log_dir = os.path.expanduser("~/.gemini/antigravity-cli/log")
        if os.path.exists(log_dir):
            logs = sorted(os.listdir(log_dir))
            if logs:
                with open(os.path.join(log_dir, logs[-1])) as f:
                    for line in f:
                        if "applyAuthResult: email=" in line:
                            parts = line.split("email=")
                            if len(parts) > 1:
                                info["email"] = parts[1].split(",")[0].strip()
    except Exception as e:
        info["error"] = str(e)

    return info


def collect_all(force=False):
    if not force and os.path.exists(CACHE_FILE):
        try:
            mtime = os.path.getmtime(CACHE_FILE)
            if time.time() - mtime < CACHE_TTL:
                with open(CACHE_FILE) as f:
                    data = json.load(f)
                    data["from_cache"] = True
                    return data
        except Exception:
            pass

    providers = load_providers()
    disabled = {"status": "disabled"}
    data = {
        "timestamp": int(time.time()),
        "time_str": time.strftime("%I:%M %p"),
        "codex": get_codex_limits() if providers.get("codex") else disabled,
        "claude": get_claude_limits() if providers.get("claude") else disabled,
        "antigravity": get_antigravity_limits() if providers.get("antigravity") else disabled,
        "from_cache": False
    }

    # Cache holds account emails, so keep it private to the user (0600, atomic replace).
    try:
        os.makedirs(CACHE_DIR, mode=0o700, exist_ok=True)
        tmp = CACHE_FILE + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(data, f)
        os.replace(tmp, CACHE_FILE)
    except Exception:
        pass

    return data


if __name__ == "__main__":
    force_refresh = "--force" in sys.argv
    result = collect_all(force=force_refresh)
    print(json.dumps(result, indent=2))
