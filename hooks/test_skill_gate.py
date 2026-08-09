"""Unit tests for skill_gate.py's bundle and architecture read-gating."""
import json
import os
import sys
import tempfile
import unittest
import uuid

sys.path.insert(0, os.path.dirname(__file__))

import skill_gate


def _manifest(tmp_root, agents):
    planning_dir = os.path.join(tmp_root, ".lbwc-planning")
    os.makedirs(planning_dir, exist_ok=True)
    manifest_path = os.path.join(planning_dir, ".agent-manifest.json")
    with open(manifest_path, "w") as manifest_file:
        json.dump({"agents": agents}, manifest_file)


def _event(session_id, identifier, tool_name, tool_input):
    return json.dumps({
        "session_id": session_id,
        "agent_id": identifier,
        "tool_name": tool_name,
        "tool_input": tool_input,
    })


class SkillGateTest(unittest.TestCase):
    def setUp(self):
        self.tmp_root = tempfile.mkdtemp()
        self.session_id = f"test-{uuid.uuid4().hex}"

        def _cleanup_state_file():
            state_path = skill_gate._state_path(self.session_id)
            if os.path.exists(state_path):
                os.remove(state_path)

        self.addCleanup(_cleanup_state_file)

    def test_lead_blocked_until_architecture_read_then_allowed(self):
        _manifest(self.tmp_root, {"agent-lead-1": {"role": "lead"}})

        write_event = _event(
            self.session_id, "agent-lead-1", "Write",
            {"file_path": "/repo/PLAN.md", "content": "x"},
        )
        reason = skill_gate.verdict(write_event, cwd=self.tmp_root)
        self.assertIsNotNone(reason)
        assert reason is not None
        self.assertIn("ARCHITECTURE.md", reason)

        read_event = _event(
            self.session_id, "agent-lead-1", "Read",
            {"file_path": "/repo/ARCHITECTURE.md"},
        )
        self.assertIsNone(skill_gate.verdict(read_event, cwd=self.tmp_root))

        self.assertIsNone(skill_gate.verdict(write_event, cwd=self.tmp_root))

    def test_team_role_unaffected_still_gated_on_bundle_only(self):
        _manifest(self.tmp_root, {"agent-py-1": {"role": "python-engineer"}})

        write_event = _event(
            self.session_id, "agent-py-1", "Write",
            {"file_path": "/repo/app.py", "content": "x"},
        )
        reason = skill_gate.verdict(write_event, cwd=self.tmp_root)
        self.assertIsNotNone(reason)
        assert reason is not None
        self.assertIn("skills-bundle", reason)
        self.assertNotIn("ARCHITECTURE.md", reason)

        arch_read_event = _event(
            self.session_id, "agent-py-1", "Read",
            {"file_path": "/repo/ARCHITECTURE.md"},
        )
        skill_gate.verdict(arch_read_event, cwd=self.tmp_root)
        self.assertIsNotNone(skill_gate.verdict(write_event, cwd=self.tmp_root))

        bundle_read_event = _event(
            self.session_id, "agent-py-1", "Read",
            {"file_path": "/repo/skills-bundle/fluent-python/SKILL.md"},
        )
        self.assertIsNone(skill_gate.verdict(bundle_read_event, cwd=self.tmp_root))
        self.assertIsNone(skill_gate.verdict(write_event, cwd=self.tmp_root))

    def test_mcp_call_does_not_satisfy_the_gate(self):
        _manifest(self.tmp_root, {"agent-py-2": {"role": "python-engineer"}})

        mcp_call_event = _event(
            self.session_id, "agent-py-2", "mcp__some_server__search",
            {"query": "clean code"},
        )
        self.assertIsNone(skill_gate.verdict(mcp_call_event, cwd=self.tmp_root))

        write_event = _event(
            self.session_id, "agent-py-2", "Write",
            {"file_path": "/repo/app.py", "content": "x"},
        )
        reason = skill_gate.verdict(write_event, cwd=self.tmp_root)
        self.assertIsNotNone(reason)
        assert reason is not None
        self.assertIn("skills-bundle", reason)


if __name__ == "__main__":
    unittest.main()
