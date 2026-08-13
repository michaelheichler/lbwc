"""Unit tests for message_scope_guard.py's pair-aware SendMessage gating."""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import message_scope_guard


def _manifest(tmp_root: str, agents: dict) -> None:
    planning_dir = os.path.join(tmp_root, ".lbwc-planning")
    os.makedirs(planning_dir, exist_ok=True)
    manifest_path = os.path.join(planning_dir, ".agent-manifest.json")
    with open(manifest_path, "w") as manifest_file:
        json.dump({"agents": agents}, manifest_file)


def _send_message_event(identifier: str, to: str) -> str:
    return json.dumps({
        "agent_id": identifier,
        "tool_name": "SendMessage",
        "tool_input": {"to": to},
    })


class MessageScopeGuardTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp_root = tempfile.mkdtemp()

    def test_solo_qa_may_report_to_main(self) -> None:
        _manifest(self.tmp_root, {
            "agent-qa-1": {"role": "qa", "pair_id": None},
        })
        event = _send_message_event("agent-qa-1", "main")
        self.assertIsNone(message_scope_guard.verdict(event, cwd=self.tmp_root))

    def test_paired_engineer_may_not_report_to_main(self) -> None:
        _manifest(self.tmp_root, {
            "agent-eng-1": {"role": "python-engineer", "pair_id": "p1"},
            "agent-critic-1": {"role": "python-critic", "pair_id": "p1"},
        })
        event = _send_message_event("agent-eng-1", "main")
        reason = message_scope_guard.verdict(event, cwd=self.tmp_root)
        self.assertIsNotNone(reason)
        assert reason is not None
        self.assertIn("critic", reason)

    def test_native_team_member_may_message_main(self) -> None:
        _manifest(self.tmp_root, {
            "agent-eng-1": {
                "role": "python-engineer",
                "pair_id": "p1",
                "runtime_kind": "native-team",
                "communication_policy": "native-team",
            },
        })
        event = _send_message_event("agent-eng-1", "main")
        self.assertIsNone(message_scope_guard.verdict(event, cwd=self.tmp_root))

    def test_native_team_member_may_message_a_peer(self) -> None:
        _manifest(self.tmp_root, {
            "agent-eng-1": {
                "role": "python-engineer",
                "runtime_kind": "native-team",
                "communication_policy": "native-team",
            },
        })
        event = _send_message_event("agent-eng-1", "agent-critic-1")
        self.assertIsNone(message_scope_guard.verdict(event, cwd=self.tmp_root))

    def test_legacy_test_dev_may_report_to_main(self) -> None:
        _manifest(self.tmp_root, {
            "agent-test-1": {
                "role": "test-dev",
                "pair_id": "p1",
                "runtime_kind": "legacy-subagent",
                "communication_policy": "critic-relay",
            },
            "agent-critic-1": {"role": "python-critic", "pair_id": "p1"},
        })
        event = _send_message_event("agent-test-1", "main")
        self.assertIsNone(message_scope_guard.verdict(event, cwd=self.tmp_root))


if __name__ == "__main__":
    unittest.main()
