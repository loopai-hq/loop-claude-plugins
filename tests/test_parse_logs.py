#!/usr/bin/env python3
"""Fixture tests for plugins/oncall/skills/loki/parse_logs.py.

Runs the parser exactly as the skill does (a subprocess reading stdin) against
the files in tests/fixtures/loki and checks exit codes and output. Stdlib only:
    python3 tests/test_parse_logs.py
"""
import os
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARSER = os.path.join(ROOT, "plugins", "oncall", "skills", "loki", "parse_logs.py")
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "loki")


def run(stdin_text, *args):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    proc = subprocess.run(
        [sys.executable, PARSER, *args], input=stdin_text, capture_output=True, text=True, env=env
    )
    return proc.returncode, proc.stdout, proc.stderr


def fixture(name):
    with open(os.path.join(FIXTURES, name), encoding="utf-8") as fh:
        return fh.read()


class ParseLogsTests(unittest.TestCase):
    def assertNoTraceback(self, stderr):
        self.assertNotIn("Traceback", stderr, stderr)

    def test_streams_are_rendered_newest_first(self):
        code, out, err = run(fixture("streams.json"))
        self.assertEqual(code, 0, err)
        self.assertNoTraceback(err)
        self.assertIn("Found 3 log entries", out)
        self.assertIn("[api] [ERROR] [handler.go:42]", out)
        self.assertIn("upstream timeout", out)
        self.assertIn("[worker] [UNKNOWN]", out)
        self.assertIn("job failed", out)
        self.assertIn("plain text line without json", out)
        self.assertLess(out.index("job failed"), out.index("upstream timeout"))
        self.assertLess(out.index("upstream timeout"), out.index("plain text line"))

    def test_empty_result_exits_zero(self):
        code, out, err = run(fixture("empty.json"))
        self.assertEqual(code, 0, err)
        self.assertIn("No logs found", out)

    def test_loki_error_status_exits_one(self):
        code, out, err = run(fixture("error.json"))
        self.assertEqual(code, 1)
        self.assertNoTraceback(err)
        self.assertIn("Loki query failed", out)

    def test_empty_stdin_exits_one(self):
        code, out, err = run("")
        self.assertEqual(code, 1)
        self.assertNoTraceback(err)
        self.assertIn("Empty response", out)

    def test_non_json_body_exits_one_with_preview(self):
        code, out, err = run(fixture("gateway_502.html"))
        self.assertEqual(code, 1)
        self.assertNoTraceback(err)
        self.assertIn("not JSON", out)
        self.assertIn("502 Bad Gateway", out)

    def test_non_object_log_lines_do_not_crash(self):
        code, out, err = run(fixture("non_object_lines.json"))
        self.assertEqual(code, 0, err)
        self.assertNoTraceback(err)
        self.assertIn("Found 5 log entries", out)
        for literal in ("12345", "[1,2]", "null", '"a json string"', "odd timestamp"):
            self.assertIn(literal, out)
        self.assertIn("[not-a-timestamp]", out)

    def test_matrix_result_is_rejected_clearly(self):
        code, out, err = run(fixture("matrix.json"))
        self.assertEqual(code, 1)
        self.assertNoTraceback(err)
        self.assertIn("resultType is 'matrix'", out)

    def test_scalar_body_is_rejected(self):
        code, out, err = run(fixture("scalar.json"))
        self.assertEqual(code, 1)
        self.assertNoTraceback(err)
        self.assertIn("not a JSON object", out)

    def test_list_mode_sorts_and_skips_internal_labels(self):
        code, out, err = run(fixture("labels.json"), "--list")
        self.assertEqual(code, 0, err)
        self.assertNoTraceback(err)
        self.assertIn("4 names:", out)
        self.assertNotIn("__name__", out)
        self.assertLess(out.index("cluster"), out.index("job"))
        self.assertLess(out.index("job"), out.index("service_name"))
        self.assertLess(out.index("service_name"), out.index("severity"))

    def test_list_mode_rejects_a_streams_body(self):
        code, out, err = run(fixture("streams.json"), "--list")
        self.assertEqual(code, 1)
        self.assertNoTraceback(err)
        self.assertIn("not a list", out)

    def test_range_mode_prints_nanosecond_window(self):
        code, out, err = run("", "--range", "6h")
        self.assertEqual(code, 0, err)
        self.assertNoTraceback(err)
        lines = dict(line.split("=", 1) for line in out.split())
        self.assertEqual(sorted(lines), ["end", "start"])
        start, end = int(lines["start"]), int(lines["end"])
        self.assertEqual(end - start, 6 * 3600 * 10**9)
        self.assertTrue(lines["end"].endswith("000000000"))

    def test_range_mode_rejects_a_bad_lookback(self):
        code, out, err = run("", "--range", "yesterday")
        self.assertEqual(code, 1)
        self.assertNoTraceback(err)
        self.assertIn("Bad lookback", out)

    def test_unknown_arguments_fail_clearly(self):
        code, out, err = run("", "--frobnicate")
        self.assertEqual(code, 1)
        self.assertNoTraceback(err)
        self.assertIn("Usage", out)


if __name__ == "__main__":
    unittest.main(verbosity=1)
