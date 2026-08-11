import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

from hooks import user_question_guard

PROJECT_ROOT = Path(__file__).resolve().parent.parent
HOOKS_CONFIG = PROJECT_ROOT / "hooks" / "hooks.json"
ROLE_DEFAULTS = PROJECT_ROOT / "templates" / "agent-roles" / "defaults.json"


def question_event(session_id: str, cwd: Path) -> dict[str, Any]:
    return {
        "session_id": session_id,
        "cwd": str(cwd),
        "tool_name": "AskUserQuestion",
        "tool_input": {
            "questions": [
                {
                    "header": "Review pace",
                    "question": "Which review pace should this project use?",
                    "options": [
                        {"label": "Fast", "description": "Finish the review sooner."},
                        {
                            "label": "Careful",
                            "description": "Check each change in detail.",
                        },
                    ],
                }
            ]
        },
    }


class UserQuestionGuardTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.planning_dir = self.root / ".lbwc-planning"
        self.planning_dir.mkdir()
        self.session_id = "session-1"

    def hook(self, event: dict[str, Any], event_name: str) -> str | None:
        return user_question_guard.verdict(json.dumps(event), event_name)

    def store(self) -> user_question_guard.DecisionStore:
        return user_question_guard.DecisionStore(self.planning_dir)

    def test_main_question_creates_pending_record_and_blocks_mutation(self) -> None:
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )
        saved = self.store().record(self.session_id)
        self.assertEqual(saved["status"], "pending")
        self.assertEqual(saved["command"], "AskUserQuestion")
        mutation = {
            "session_id": self.session_id,
            "cwd": str(self.root),
            "tool_name": "Write",
            "tool_input": {"file_path": "src/app.py", "content": "x"},
        }
        self.assertIn("pending", self.hook(mutation, "pretool") or "")
        inspection = {
            "session_id": self.session_id,
            "cwd": str(self.root),
            "tool_name": "Read",
            "tool_input": {"file_path": "src/app.py"},
        }
        self.assertIsNone(self.hook(inspection, "pretool"))

    def test_bounded_answer_resolves_the_pending_record(self) -> None:
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )
        response = question_event(self.session_id, self.root)
        response["tool_input"] = {
            "answers": {"Which review pace should this project use?": "Careful"}
        }
        self.assertIsNone(self.hook(response, "posttool"))
        saved = self.store().record(self.session_id)
        self.assertEqual(saved["status"], "resolved")
        self.assertEqual(saved["response"], "Careful")

    def test_freeform_answer_resolves_immediately_and_never_stores_the_text(
        self,
    ) -> None:
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )
        response = question_event(self.session_id, self.root)
        response["tool_input"] = {
            "answers": {
                "Which review pace should this project use?": "Use a calm but complete review."
            }
        }
        self.assertIsNone(self.hook(response, "posttool"))
        saved = self.store().record(self.session_id)
        self.assertEqual(saved["status"], "resolved")
        self.assertEqual(saved["response"], {"kind": "freeform", "received": True})
        self.assertNotIn("Use a calm", json.dumps(saved))

    def test_generated_agent_cannot_present_a_user_question(self) -> None:
        event = question_event(self.session_id, self.root)
        event["agent_id"] = "lbwc-worker"
        self.assertIn("main session", self.hook(event, "pretool") or "")

    def test_invalid_question_does_not_create_a_record(self) -> None:
        event = question_event(self.session_id, self.root)
        event["tool_input"] = {
            "questions": [
                {
                    "question": "Which JSON schema should we use?",
                    "options": [
                        {"label": "One", "description": "Choose the first option."},
                        {"label": "Two", "description": "Choose the second option."},
                    ],
                }
            ]
        }
        self.assertIn("plain language", self.hook(event, "pretool") or "")
        self.assertEqual(self.store().state(self.session_id), "none")

    def test_state_lookup_does_not_create_runtime_state(self) -> None:
        self.assertEqual(self.store().state(self.session_id), "none")
        self.assertFalse((self.planning_dir / ".runtime").exists())

    def test_tampered_record_blocks_stop(self) -> None:
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )
        path = self.planning_dir / ".runtime" / "decisions" / f"{self.session_id}.json"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "AskUserQuestion", "AskUserQuestionX"
            ),
            encoding="utf-8",
        )
        reason = self.hook(
            {"session_id": self.session_id, "cwd": str(self.root)}, "stop"
        )
        self.assertIn("invalid", reason or "")

    def test_recomputed_record_checksum_without_hook_transition_is_invalid(
        self,
    ) -> None:
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )
        path = self.planning_dir / ".runtime" / "decisions" / f"{self.session_id}.json"
        record = json.loads(path.read_text(encoding="utf-8"))
        record["command"] = "forged"
        unsigned = {
            key: value for key, value in record.items() if key != "record_digest"
        }
        encoded = json.dumps(unsigned, sort_keys=True, separators=(",", ":")).encode(
            "utf-8"
        )
        record["record_digest"] = hashlib.sha256(encoded).hexdigest()
        path.write_text(json.dumps(record, separators=(",", ":")), encoding="utf-8")
        with self.assertRaisesRegex(
            user_question_guard.DecisionStateError, "integrity"
        ):
            self.store().state(self.session_id)

    def test_missing_session_blocks_mutation_and_stop(self) -> None:
        mutation = {
            "cwd": str(self.root),
            "tool_name": "Write",
            "tool_input": {"file_path": "src/app.py", "content": "x"},
        }
        self.assertIn("session id", self.hook(mutation, "pretool") or "")
        self.assertIn("session id", self.hook({"cwd": str(self.root)}, "stop") or "")

    def test_missing_session_blocks_question_before_any_decision_record(self) -> None:
        event = question_event(self.session_id, self.root)
        del event["session_id"]
        reason = self.hook(event, "pretool")
        self.assertIn("session id", reason or "")
        self.assertFalse((self.planning_dir / ".runtime").exists())

    def test_symlinked_planning_state_blocks_mutation_and_stop(self) -> None:
        linked_root = Path(tempfile.mkdtemp())
        (linked_root / ".lbwc-planning").symlink_to(
            self.planning_dir, target_is_directory=True
        )
        mutation = {
            "session_id": self.session_id,
            "cwd": str(linked_root),
            "tool_name": "Write",
            "tool_input": {"file_path": "src/app.py", "content": "x"},
        }
        self.assertIn("invalid", self.hook(mutation, "pretool") or "")
        stop = self.hook(
            {"session_id": self.session_id, "cwd": str(linked_root)}, "stop"
        )
        self.assertIn("invalid", stop or "")

    def test_pending_decision_blocks_sed_in_place_bash(self) -> None:
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )
        bash = {
            "session_id": self.session_id,
            "cwd": str(self.root),
            "tool_name": "Bash",
            "tool_input": {"command": "sed -i '' 's/old/new/' config.json"},
        }
        self.assertIn("pending", self.hook(bash, "pretool") or "")

    def test_freeform_text_matching_the_native_sentinel_word_still_resolves(
        self,
    ) -> None:
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )
        response = question_event(self.session_id, self.root)
        response["tool_input"] = {
            "answers": {"Which review pace should this project use?": "Other"}
        }
        self.assertIsNone(self.hook(response, "posttool"))
        saved = self.store().record(self.session_id)
        self.assertEqual(saved["status"], "resolved")
        self.assertEqual(saved["response"], {"kind": "freeform", "received": True})

    def test_stale_state_blocks_answer_and_stop(self) -> None:
        config = self.planning_dir / "config.json"
        config.write_text(json.dumps({"review": "careful"}), encoding="utf-8")
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )
        config.write_text(json.dumps({"review": "fast"}), encoding="utf-8")
        response = question_event(self.session_id, self.root)
        response["tool_input"] = {
            "answers": {"Which review pace should this project use?": "Careful"}
        }
        self.assertIn("state changed", self.hook(response, "posttool") or "")
        stop = self.hook({"session_id": self.session_id, "cwd": str(self.root)}, "stop")
        self.assertIn("state changed", stop or "")

    def test_stale_state_blocks_freeform_answer(self) -> None:
        routing = self.planning_dir / "routing.json"
        routing.write_text(json.dumps({"profile": "balanced"}), encoding="utf-8")
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )
        routing.write_text(json.dumps({"profile": "turbo"}), encoding="utf-8")
        response = question_event(self.session_id, self.root)
        response["tool_input"] = {
            "answers": {
                "Which review pace should this project use?": "Use a calm but complete review."
            }
        }
        self.assertIn("state changed", self.hook(response, "posttool") or "")

    def test_changed_state_replaces_a_stale_pending_question(self) -> None:
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )
        config = self.planning_dir / "config.json"
        config.write_text(json.dumps({"review": "changed"}), encoding="utf-8")
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )

    def test_unchanged_state_cannot_replace_a_pending_question(self) -> None:
        self.assertIsNone(
            self.hook(question_event(self.session_id, self.root), "pretool")
        )
        reason = self.hook(question_event(self.session_id, self.root), "pretool")
        self.assertIn("already pending", reason or "")

    def test_technical_option_wording_is_rejected(self) -> None:
        event = question_event(self.session_id, self.root)
        event["tool_input"] = {
            "questions": [
                {
                    "question": "Which review pace should this project use?",
                    "options": [
                        {
                            "label": "API choice",
                            "description": "Choose this review pace.",
                        },
                        {
                            "label": "Careful",
                            "description": "Change the JSON schema safely.",
                        },
                    ],
                }
            ]
        }
        self.assertIn("plain language", self.hook(event, "pretool") or "")

    def test_visible_other_option_is_rejected(self) -> None:
        event = question_event(self.session_id, self.root)
        event["tool_input"] = {
            "questions": [
                {
                    "question": "Which review pace should this project use?",
                    "options": [
                        {"label": "Fast", "description": "Finish the review sooner."},
                        {"label": "Other", "description": "Something else entirely."},
                    ],
                }
            ]
        }
        self.assertIn("native Other", self.hook(event, "pretool") or "")

    def test_runtime_paths_are_reserved_without_a_pending_record(self) -> None:
        bash = {
            "session_id": self.session_id,
            "cwd": str(self.root),
            "tool_name": "Bash",
            "tool_input": {"command": "mkdir -p .lbwc-planning/.runtime/decisions"},
        }
        self.assertIn("reserved", self.hook(bash, "pretool") or "")
        script_bash = dict(bash)
        script_bash["tool_input"] = {
            "command": "bash scripts/pending-decision.sh create .lbwc-planning session-1",
        }
        self.assertIn("reserved", self.hook(script_bash, "pretool") or "")
        runtime_write = {
            "session_id": self.session_id,
            "cwd": str(self.root),
            "tool_name": "Write",
            "tool_input": {
                "file_path": ".lbwc-planning/.runtime/decisions/forged.json",
                "content": "{}",
            },
        }
        self.assertIn("reserved", self.hook(runtime_write, "pretool") or "")

    def test_symlink_and_traversal_aliases_to_protected_paths_are_reserved(
        self,
    ) -> None:
        script_alias = self.root / "decision-alias"
        script_alias.symlink_to(PROJECT_ROOT / "scripts" / "pending-decision.sh")
        script_bash = {
            "session_id": self.session_id,
            "cwd": str(self.root),
            "tool_name": "Bash",
            "tool_input": {
                "command": f"bash {script_alias} create .lbwc-planning session-1"
            },
        }
        self.assertIn("reserved", self.hook(script_bash, "pretool") or "")
        runtime = self.planning_dir / ".runtime"
        runtime.mkdir()
        runtime_alias = self.root / "runtime-alias"
        runtime_alias.symlink_to(runtime, target_is_directory=True)
        runtime_bash = dict(script_bash)
        runtime_bash["tool_input"] = {"command": f"mkdir -p {runtime_alias}/decisions"}
        self.assertIn("reserved", self.hook(runtime_bash, "pretool") or "")
        traversal_bash = dict(script_bash)
        traversal_bash["tool_input"] = {
            "command": "mkdir -p .lbwc-planning/cache/../.runtime/decisions",
        }
        self.assertIn("reserved", self.hook(traversal_bash, "pretool") or "")

    def test_indirect_runtime_tampering_fails_closed_for_later_tools(self) -> None:
        decisions = self.planning_dir / ".runtime" / "decisions"
        decisions.mkdir(parents=True)
        (decisions / f"{self.session_id}.json").write_text("{}", encoding="utf-8")
        mutation = {
            "session_id": self.session_id,
            "cwd": str(self.root),
            "tool_name": "Write",
            "tool_input": {"file_path": "src/app.py", "content": "x"},
        }
        self.assertIn("invalid", self.hook(mutation, "pretool") or "")

    def test_hook_verdicts_use_claude_code_response_shapes(self) -> None:
        event = question_event(self.session_id, self.root)
        self.assertIsNone(self.hook(event, "pretool"))
        stop = self.hook({"session_id": self.session_id, "cwd": str(self.root)}, "stop")
        self.assertIn("pending", stop or "")

    def test_hooks_register_each_user_decision_lifecycle_event(self) -> None:
        config = json.loads(HOOKS_CONFIG.read_text(encoding="utf-8"))
        expected = {
            "PreToolUse": "pretool",
            "PostToolUse": "posttool",
            "UserPromptSubmit": "prompt",
            "Stop": "stop",
        }
        for event, mode in expected.items():
            commands = [
                hook["command"]
                for entry in config["hooks"][event]
                for hook in entry["hooks"]
            ]
            self.assertTrue(
                any(
                    "user_question_guard.py" in command and command.endswith(f" {mode}")
                    for command in commands
                )
            )
        stop_commands = [
            hook["command"]
            for entry in config["hooks"]["Stop"]
            for hook in entry["hooks"]
        ]
        self.assertTrue(any("session-stop.sh" in command for command in stop_commands))

    def test_generated_roles_deny_questions_and_return_the_handoff_shape(self) -> None:
        defaults = json.loads(ROLE_DEFAULTS.read_text(encoding="utf-8"))
        roles = {
            name: settings
            for name, settings in defaults.items()
            if name not in {"trios", "oracles"}
        }
        self.assertTrue(roles)
        for name, settings in roles.items():
            with self.subTest(role=name):
                tools = settings.get("disallowedTools", "").split(", ")
                self.assertIn("AskUserQuestion", tools)
                prompt = settings.get("initialPrompt", "")
                self.assertIn("user_decision_required", prompt)
                self.assertIn("question", prompt)
                self.assertIn("response_shape", prompt)


if __name__ == "__main__":
    unittest.main()
