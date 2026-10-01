#!/usr/bin/env python3
"""Date arithmetic for the on-call-report skill; the only python3 it runs.

    python3 dates.py DAYS_AGO

prints three lines for the moment DAYS_AGO days before now (UTC):

    days_ago=1
    date=2026-09-30          ISO date, for `gh ... --search "updated:>=..."`
    unix=1759190400          Unix seconds, for the Slack `oldest` argument

Stdlib only, and portable: it replaces GNU-only `date -d` and BSD-only
`date -v`. Exit code 1 with one explanatory line on a bad argument.
"""
import sys
import time
from datetime import datetime, timedelta, timezone


def main(argv):
    if len(argv) != 1 or not argv[0].isdigit():
        print("ERROR: usage: dates.py DAYS_AGO (a whole number, e.g. 1 or 7)")
        sys.exit(1)
    days = int(argv[0])
    now = int(time.time())
    then = datetime.fromtimestamp(now, tz=timezone.utc) - timedelta(days=days)
    print(f"days_ago={days}")
    print(f"date={then.date().isoformat()}")
    print(f"unix={now - days * 86400}")


if __name__ == "__main__":
    main(sys.argv[1:])
