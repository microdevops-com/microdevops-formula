#!/usr/bin/env python3
"""Redis/Valkey availability and PING latency checker daemon.

Continuously pings a local Redis/Valkey and reports slow responses, timeouts,
connection and authentication failures to notify_devilry (and thus alerta).

Two asyncio tasks share a queue:
  - prober   : pings on a fixed cadence, pushes an Event for every bad sample.
  - reporter : drains the queue, keeps a state machine, and sends/refreshes
               alerts on a heartbeat so alerta never auto-clears a live state.
"""

import argparse
import asyncio
import json
import logging
import os
import signal
import socket
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from urllib.parse import urlparse, urlunparse

import yaml
import redis.asyncio as aioredis
from redis.exceptions import (
    AuthenticationError,
    ConnectionError as RedisConnectionError,
    RedisError,
    TimeoutError as RedisTimeoutError,
)

ORIGIN = "redis_check.py"
LOG = logging.getLogger("redis_check")

# reason -> human text. Latency severity is configured via threshold_ms_<severity>
# keys; timeout/conn_error/auth_error severities are configured separately. This
# lets the operator map outcomes onto whatever severity names alerta expects.
REASON_TEXT = {
    "slow": "Redis PING slow",
    "timeout": "Redis PING timed out",
    "conn_error": "Redis connection error",
    "auth_error": "Redis authentication error",
}
# Bad samples within a report window are ranked by "badness score" (a latency
# magnitude in ms), not by severity name, so ranking stays consistent no matter
# how severities are named. Connection/auth failures are the worst possible.
UNREACHABLE_SCORE = float("inf")

DEFAULTS = {
    "redis": {
        "uri": "redis://127.0.0.1:6379/0",
        "connect_timeout": 1.0,
        "socket_timeout": 2.0,
    },
    "probe": {
        "ping_delay": 1.0,
        "command": "PING",
        # Latency -> severity buckets. Add/override threshold_ms_<severity> with
        # any alerta severity name; set one to null to disable that bucket.
        "threshold_ms_critical": 500.0,
        "threshold_ms_fatal": 1000.0,
        # Severities for non-latency failures.
        "timeout_severity": "critical",
        "conn_error_severity": "critical",
        "auth_error_severity": "critical",
    },
    "reporting": {
        "report_interval": 5.0,
        "heartbeat_interval": 900.0,
        "recovery_hold": 300.0,
    },
    "alert": {
        "service": "database",
        "environment": "prod",
        "client": None,
        "group": None,       # default: this host's fqdn
        "resource": None,    # default: {fqdn}:redis:{port}
        "ok_severity": "ok", # severity used for the healthy/recovered alert
        "timeout": 900,      # alerta auto-clear timeout; keep > heartbeat_interval
    },
    "ops": {
        "notify_devilry_path": "/opt/sysadmws/notify_devilry/notify_devilry.py",
        "log_file": None,
        "log_level": "INFO",
    },
}


@dataclass
class Event:
    mono: float       # time.monotonic() when the bad sample was taken
    wall: str         # human-readable wall-clock timestamp
    reason: str       # key into REASON_TEXT
    severity: str     # configured alerta severity name for this outcome
    rtt_ms: float     # measured PING round-trip, 0.0 when not applicable
    score: float      # badness magnitude in ms, used to rank within a window


# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #
def deep_merge(base: dict, override: dict) -> dict:
    result = dict(base)
    for key, value in (override or {}).items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_config(path: str) -> dict:
    config = {section: dict(values) for section, values in DEFAULTS.items()}
    if path and os.path.exists(path):
        with open(path, "r") as handle:
            loaded = yaml.safe_load(handle) or {}
        config = deep_merge(config, loaded)
    return config


def parse_thresholds(probe_cfg: dict):
    """Extract threshold_ms_<severity> keys as [(latency_ms, severity), ...],
    sorted by latency descending so the highest matching bucket wins."""
    thresholds = []
    for key, value in probe_cfg.items():
        if key.startswith("threshold_ms_") and value is not None:
            severity = key[len("threshold_ms_"):]
            thresholds.append((float(value), severity))
    thresholds.sort(reverse=True)
    return thresholds


def sanitize_uri(uri: str) -> str:
    """Return the uri with any password replaced by ***."""
    parsed = urlparse(uri)
    if parsed.password is None:
        return uri
    userinfo = parsed.username or ""
    netloc = f"{userinfo}:***@{parsed.hostname or ''}"
    if parsed.port:
        netloc += f":{parsed.port}"
    return urlunparse(parsed._replace(netloc=netloc))


def wall_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S %z UTC")


# --------------------------------------------------------------------------- #
# Prober
# --------------------------------------------------------------------------- #
async def prober(config: dict, queue: "asyncio.Queue[Event]", stop: asyncio.Event):
    redis_cfg = config["redis"]
    probe_cfg = config["probe"]

    uri = redis_cfg["uri"]
    command = probe_cfg["command"]
    ping_delay = float(probe_cfg["ping_delay"])
    socket_timeout = float(redis_cfg["socket_timeout"])
    connect_timeout = float(redis_cfg["connect_timeout"])
    thresholds = parse_thresholds(probe_cfg)
    timeout_severity = probe_cfg["timeout_severity"]
    conn_error_severity = probe_cfg["conn_error_severity"]
    auth_error_severity = probe_cfg["auth_error_severity"]
    # Hard guard so a hung await can never wedge the task.
    hard_timeout = socket_timeout + 1.0

    def classify_latency(rtt_ms: float):
        for latency, severity in thresholds:
            if rtt_ms >= latency:
                return severity
        return None

    async def push(reason: str, severity: str, rtt_ms: float, score: float):
        event = Event(time.monotonic(), wall_now(), reason, severity, rtt_ms, score)
        await queue.put(event)
        LOG.warning(
            "bad sample reason=%s severity=%s rtt_ms=%.1f",
            reason, severity, rtt_ms,
        )

    while not stop.is_set():
        client = aioredis.from_url(
            uri,
            socket_connect_timeout=connect_timeout,
            socket_timeout=socket_timeout,
            socket_keepalive=True,
            single_connection_client=True,
        )
        next_tick = time.monotonic()
        try:
            while not stop.is_set():
                started = time.perf_counter()
                try:
                    await asyncio.wait_for(
                        client.execute_command(command), timeout=hard_timeout
                    )
                    rtt_ms = (time.perf_counter() - started) * 1000.0
                    severity = classify_latency(rtt_ms)
                    if severity is not None:
                        await push("slow", severity, rtt_ms, rtt_ms)
                    else:
                        LOG.debug("ok rtt_ms=%.1f", rtt_ms)

                except (asyncio.TimeoutError, RedisTimeoutError):
                    await push("timeout", timeout_severity,
                               socket_timeout * 1000.0, socket_timeout * 1000.0)
                    break  # socket is questionable, reconnect
                except AuthenticationError:
                    await push("auth_error", auth_error_severity, 0.0, UNREACHABLE_SCORE)
                    break
                except RedisConnectionError:
                    await push("conn_error", conn_error_severity, 0.0, UNREACHABLE_SCORE)
                    break
                except RedisError as exc:
                    LOG.error("redis error: %s: %s", type(exc).__name__, exc)
                    await push("conn_error", conn_error_severity, 0.0, UNREACHABLE_SCORE)
                    break

                # Aligned scheduling: keep checks on their cadence rather than
                # adding the PING duration on top of ping_delay.
                next_tick += ping_delay
                sleep_for = next_tick - time.monotonic()
                if sleep_for > 0:
                    try:
                        await asyncio.wait_for(stop.wait(), timeout=sleep_for)
                    except asyncio.TimeoutError:
                        pass
                else:
                    next_tick = time.monotonic()
        finally:
            try:
                await client.aclose()
            except Exception:
                pass

        # Back off before reconnecting after a broken connection.
        if not stop.is_set():
            try:
                await asyncio.wait_for(stop.wait(), timeout=ping_delay)
            except asyncio.TimeoutError:
                pass


# --------------------------------------------------------------------------- #
# Reporter
# --------------------------------------------------------------------------- #
def build_alert(config: dict, state: str, severity: str, reason: str,
                rtt_ms: float, event_wall: str) -> dict:
    alert_cfg = config["alert"]
    fqdn = socket.getfqdn()
    port = urlparse(config["redis"]["uri"]).port or 6379
    resource = alert_cfg["resource"] or f"{fqdn}:redis:{port}"
    group = alert_cfg["group"] or fqdn

    thresholds = {sev: lat for lat, sev in parse_thresholds(config["probe"])}
    attributes = {
        "datetime": event_wall,  # when the sample occurred, not when built
        "redis-uri": sanitize_uri(config["redis"]["uri"]),
        "thresholds-ms": thresholds,
    }

    alert = {
        "service": alert_cfg["service"],
        "resource": resource,
        "environment": alert_cfg["environment"],
        "group": group,
        "origin": ORIGIN,
        "type": "sysadmws-utils",
        "attributes": attributes,
    }
    if alert_cfg.get("client"):
        alert["client"] = alert_cfg["client"]
    if alert_cfg.get("timeout") is not None:
        alert["timeout"] = alert_cfg["timeout"]

    if state == "ok":
        alert.update({
            "severity": alert_cfg["ok_severity"],
            "event": "redis_check_ok",
            "value": "ok",
            "text": "Redis PING ok detected",
            "correlate": ["redis_check_error"],
        })
    else:
        text = REASON_TEXT[reason]
        value = f"{rtt_ms:.0f}ms" if rtt_ms else text
        attributes["reason"] = reason
        attributes["rtt-ms"] = round(rtt_ms, 1)
        alert.update({
            "severity": severity,
            "event": "redis_check_error",
            "value": value,
            "text": text,
            "correlate": ["redis_check_ok"],
        })
    return alert


async def send_alert(config: dict, alert: dict, print_only: bool):
    payload = json.dumps(alert, ensure_ascii=False)
    if print_only:
        print(payload, flush=True)
        LOG.info("alert (print-only) severity=%s event=%s value=%s",
                 alert["severity"], alert["event"], alert.get("value"))
        return
    path = config["ops"]["notify_devilry_path"]
    try:
        proc = await asyncio.create_subprocess_exec(
            path,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr = await proc.communicate(input=payload.encode())
        if proc.returncode != 0:
            LOG.error("notify_devilry exit=%s stderr=%s",
                      proc.returncode, (stderr or b"").decode(errors="replace"))
        else:
            LOG.info("sent severity=%s event=%s value=%s",
                     alert["severity"], alert["event"], alert.get("value"))
    except Exception as exc:  # never let a delivery failure kill the daemon
        LOG.error("failed to run notify_devilry (%s): %s",
                  path, exc)


async def reporter(config: dict, queue: "asyncio.Queue[Event]",
                   stop: asyncio.Event, print_only: bool):
    report_interval = float(config["reporting"]["report_interval"])
    heartbeat_interval = float(config["reporting"]["heartbeat_interval"])
    recovery_hold = float(config["reporting"]["recovery_hold"])

    # Current effective state (bad state persists through recovery_hold).
    state = "ok"
    cur_severity = config["alert"]["ok_severity"]
    cur_reason = None
    cur_rtt = 0.0
    last_error_wall = None
    last_bad_mono = None       # None => no bad sample seen yet

    # What we last delivered, to decide transition vs heartbeat refresh.
    sent_key = None            # (state, severity, reason)
    last_send_mono = 0.0

    while not stop.is_set():
        # Drain everything queued since the last tick.
        events = []
        while True:
            try:
                events.append(queue.get_nowait())
            except asyncio.QueueEmpty:
                break

        now = time.monotonic()
        if events:
            worst = max(events, key=lambda e: (e.score, e.mono))
            state = "bad"
            cur_severity = worst.severity
            cur_reason = worst.reason
            cur_rtt = worst.rtt_ms
            last_error_wall = worst.wall
            last_bad_mono = now
        else:
            if last_bad_mono is None or (now - last_bad_mono) >= recovery_hold:
                # Healthy, or recovered after the anti-flap hold.
                state = "ok"
                cur_severity = config["alert"]["ok_severity"]
                cur_reason = None
                cur_rtt = 0.0
            # else: still within recovery_hold -> keep last bad state, refresh it.

        key = (state, cur_severity, cur_reason)
        transitioned = key != sent_key
        heartbeat_due = (now - last_send_mono) >= heartbeat_interval
        if transitioned or heartbeat_due:
            # Bad alerts carry the sample's own timestamp; ok has no event.
            event_wall = last_error_wall if state == "bad" else wall_now()
            alert = build_alert(config, state, cur_severity, cur_reason,
                                cur_rtt, event_wall)
            await send_alert(config, alert, print_only)
            sent_key = key
            last_send_mono = now

        try:
            await asyncio.wait_for(stop.wait(), timeout=report_interval)
        except asyncio.TimeoutError:
            pass


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def setup_logging(config: dict):
    level = getattr(logging, str(config["ops"]["log_level"]).upper(), logging.INFO)
    handlers = []
    log_file = config["ops"]["log_file"]
    if log_file:
        handlers.append(logging.FileHandler(log_file))
    else:
        handlers.append(logging.StreamHandler(sys.stderr))
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=handlers,
    )


async def run(config: dict, print_only: bool) -> int:
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)

    queue: "asyncio.Queue[Event]" = asyncio.Queue()
    LOG.info("redis_check starting: uri=%s ping_delay=%.3fs thresholds=%s",
             sanitize_uri(config["redis"]["uri"]),
             config["probe"]["ping_delay"],
             {sev: lat for lat, sev in parse_thresholds(config["probe"])})

    tasks = [
        asyncio.create_task(prober(config, queue, stop), name="prober"),
        asyncio.create_task(reporter(config, queue, stop, print_only), name="reporter"),
    ]
    await stop.wait()
    LOG.info("redis_check stopping")
    for task in tasks:
        task.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)
    return 0


def main() -> int:
    default_config = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "redis_check.yaml"
    )
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=default_config,
                        help="Path to redis_check.yaml (defaults apply if missing)")
    parser.add_argument("--print", dest="print_only", action="store_true",
                        help="Print alerts to stdout instead of sending to notify_devilry")
    parser.add_argument("--check-config", action="store_true",
                        help="Load config, print the effective config, and exit")
    args = parser.parse_args()

    config = load_config(args.config)
    setup_logging(config)

    if args.check_config:
        printable = deep_merge(config, {"redis": {
            "uri": sanitize_uri(config["redis"]["uri"])
        }})
        print(yaml.safe_dump(printable, sort_keys=False, default_flow_style=False))
        return 0

    try:
        return asyncio.run(run(config, args.print_only))
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
