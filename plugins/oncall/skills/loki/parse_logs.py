#!/usr/bin/env python3
"""Parse a Loki query_range JSON response from stdin and print the log entries.

Exit codes: 0 entries printed (or none found), 1 the response could not be
used (empty, not JSON, not a Loki success response, not a log-stream result).
Every failure prints one explanatory line, never a traceback.
"""
import json
import sys
from datetime import datetime, timezone

MAX_LINE = 500
PREVIEW = 200


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


def main():
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


if __name__ == "__main__":
    main()
