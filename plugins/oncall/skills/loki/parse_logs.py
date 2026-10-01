#!/usr/bin/env python3
"""Helpers for the loki skill. Stdlib only; the only python3 the skill runs.

Modes:
  (no arguments)     Parse a Loki query_range JSON response from stdin and
                     print the log entries, newest first.
  --list             Parse a Loki labels or label-values JSON response from
                     stdin and print the sorted names (internal "__" labels
                     are skipped).
  --range LOOKBACK   Print the query window as Unix nanoseconds, one
                     "start=" and one "end=" line, for a lookback such as
                     30m, 1h, 6h, 24h, 2d or 7d (end is now).

Exit codes: 0 output printed (or nothing found), 1 the input could not be
used (empty, not JSON, not a Loki success response, not a log-stream result,
bad lookback). Every failure prints one explanatory line, never a traceback.
"""
import json
import re
import sys
import time
from datetime import datetime, timezone

MAX_LINE = 500
PREVIEW = 200
UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 7 * 86400}


def fail(message):
    print(f"ERROR: {message}")
    sys.exit(1)


def format_entry(ts_ns, line):
    """Return (timestamp, message, source) for one [ts, line] pair."""
    try:
        ts = datetime.fromtimestamp(int(ts_ns) / 1e9, tz=timezone.utc)
        when = ts.strftime("%Y-%m-%d %H:%M:%S UTC")
    except (ValueError, TypeError, OverflowError, OSError):
        when = str(ts_ns)
    if not isinstance(line, str):
        line = json.dumps(line)
    msg, src = line[:MAX_LINE], ""
    try:
        log = json.loads(line)
    except (json.JSONDecodeError, TypeError, ValueError):
        log = None
    if isinstance(log, dict):
        msg = log.get("message") or log.get("textPayload") or log.get("msg") or line[:MAX_LINE]
        if not isinstance(msg, str):
            msg = json.dumps(msg)
        loc = log.get("sourceLocation")
        if isinstance(loc, dict) and loc:
            src = f' [{loc.get("file", "")}:{loc.get("line", "")}]'
    return when, msg, src


def read_response():
    """Read stdin and return the decoded Loki success response, or fail."""
    raw = sys.stdin.read()
    if not raw.strip():
        fail("Empty response from Loki")
    try:
        data = json.loads(raw)
    except ValueError as exc:
        fail(f"Loki response is not JSON ({exc}). First {PREVIEW} bytes:\n{raw[:PREVIEW]}")
    if not isinstance(data, dict):
        fail(f"Loki response is not a JSON object. First {PREVIEW} bytes:\n{raw[:PREVIEW]}")
    if data.get("status") != "success":
        fail(f"Loki query failed: {json.dumps(data)[:PREVIEW]}")
    return data


def print_range(lookback):
    """Print start= and end= in Unix nanoseconds for a lookback like 6h."""
    match = re.fullmatch(r"\s*(\d+)\s*([smhdw])\s*", lookback or "", re.IGNORECASE)
    if not match:
        fail(f"Bad lookback {lookback!r}; use a number and a unit, e.g. 30m, 1h, 6h, 24h, 2d, 7d")
    seconds = int(match.group(1)) * UNITS[match.group(2).lower()]
    if seconds <= 0:
        fail("Lookback must be positive")
    end = int(time.time())
    print(f"start={end - seconds}000000000")
    print(f"end={end}000000000")


def print_list():
    """Print the names from a /labels or /label/<name>/values response."""
    data = read_response()
    names = data.get("data")
    if names is None:
        names = []
    if not isinstance(names, list):
        fail("Loki response 'data' is not a list; this mode reads /labels and /label/<name>/values responses")
    names = sorted(str(n) for n in names if not str(n).startswith("__"))
    if not names:
        print("No names returned (empty list).")
        return
    print(f"{len(names)} names:")
    for name in names:
        print(f"  - {name}")


def print_logs():
    """Print the entries of a query_range response, newest first."""
    data = read_response()
    body = data.get("data")
    if not isinstance(body, dict):
        fail("Loki response has no 'data' object")
    result_type = body.get("resultType", "streams")
    if result_type != "streams":
        fail(
            f"resultType is {result_type!r}; this parser reads log streams only. "
            "Run a log query (a stream selector without a metric function such as rate() or count_over_time()) "
            "or read the raw JSON."
        )
    results = body.get("result") or []
    if not isinstance(results, list):
        fail("Loki 'result' is not a list")
    if not results:
        print("No logs found for the given query and time range.")
        return

    entries = []
    for stream in results:
        if not isinstance(stream, dict):
            continue
        labels = stream.get("stream") if isinstance(stream.get("stream"), dict) else {}
        svc = labels.get("service_name", "unknown")
        sev = labels.get("severity", "UNKNOWN")
        for value in stream.get("values") or []:
            if not isinstance(value, (list, tuple)) or len(value) < 2:
                continue
            when, msg, src = format_entry(value[0], value[1])
            entries.append((when, svc, sev, msg, src))

    if not entries:
        print("No log lines in the Loki result (streams present but every 'values' list is empty or malformed).")
        return

    entries.sort(key=lambda e: e[0], reverse=True)  # most recent first
    print(f"Found {len(entries)} log entries:\n")
    for when, svc, sev, msg, src in entries:
        print(f"[{when}] [{svc}] [{sev}]{src}")
        print(f"  {msg}")
        print()


def main(argv):
    if not argv:
        print_logs()
    elif argv == ["--list"]:
        print_list()
    elif argv[0] == "--range" and len(argv) == 2:
        print_range(argv[1])
    else:
        fail("Usage: parse_logs.py [--list | --range LOOKBACK] (log JSON on stdin)")


if __name__ == "__main__":
    main(sys.argv[1:])
