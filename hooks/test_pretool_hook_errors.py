"""Executable contracts for malformed and non-applicable PreToolUse events."""
import json
import os
import subprocess
import sys
import unittest


HOOK_FILES = (
    "skill_gate.py",
    "message_scope_guard.py",
    "test_scope_guard.py",
)
HOOKS_DIR = os.path.dirname(__file__)


def _run_hook(filename: str, stdin_text: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, os.path.join(HOOKS_DIR, filename)],
        input=stdin_text,
        capture_output=True,
        text=True,
        check=False,
    )


class PreToolHookErrorTest(unittest.TestCase):
    def test_malformed_json_emits_a_structured_pretool_denial(self) -> None:
        for hook_file in HOOK_FILES:
            with self.subTest(hook_file=hook_file):
                result = _run_hook(hook_file, "{not json")
                self.assertEqual(result.returncode, 0, result.stderr)
                response = json.loads(result.stdout)
                output = response["hookSpecificOutput"]
                self.assertEqual(output["hookEventName"], "PreToolUse")
                self.assertEqual(output["permissionDecision"], "deny")
                self.assertIn("malformed PreToolUse JSON", output["permissionDecisionReason"])

    def test_missing_tool_input_emits_a_structured_pretool_denial(self) -> None:
        event = json.dumps({"tool_name": "Read"})
        for hook_file in HOOK_FILES:
            with self.subTest(hook_file=hook_file):
                result = _run_hook(hook_file, event)
                self.assertEqual(result.returncode, 0, result.stderr)
                response = json.loads(result.stdout)
                output = response["hookSpecificOutput"]
                self.assertEqual(output["hookEventName"], "PreToolUse")
                self.assertEqual(output["permissionDecision"], "deny")
                self.assertIn("malformed PreToolUse JSON", output["permissionDecisionReason"])

    def test_invalid_tool_name_emits_a_structured_pretool_denial(self) -> None:
        invalid_events = (
            {},
            {"tool_name": None},
            {"tool_name": 1},
            {"tool_name": ""},
        )
        for event_data in invalid_events:
            event_data["tool_input"] = {}
            event = json.dumps(event_data)
            for hook_file in HOOK_FILES:
                with self.subTest(event=event_data, hook_file=hook_file):
                    result = _run_hook(hook_file, event)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    response = json.loads(result.stdout)
                    output = response["hookSpecificOutput"]
                    self.assertEqual(output["hookEventName"], "PreToolUse")
                    self.assertEqual(output["permissionDecision"], "deny")
                    self.assertIn("malformed PreToolUse JSON", output["permissionDecisionReason"])

    def test_valid_non_applicable_event_remains_allowed(self) -> None:
        event = json.dumps({"tool_name": "Read", "tool_input": {}})
        for hook_file in HOOK_FILES:
            with self.subTest(hook_file=hook_file):
                result = _run_hook(hook_file, event)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
