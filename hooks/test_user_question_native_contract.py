"""Acceptance checks for Claude Code native AskUserQuestion responses."""

import json
import tempfile
import unittest
from pathlib import Path

from hooks import user_question_guard


class NativeQuestionContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        (self.root / ".lbwc-planning").mkdir()
        self.session_id = "native-question-session"

    def hook(self, event: dict[str, object], event_name: str) -> str | None:
        return user_question_guard.verdict(json.dumps(event), event_name)

    def question_event(self) -> dict[str, object]:
        return {
            "session_id": self.session_id,
            "cwd": str(self.root),
            "tool_name": "AskUserQuestion",
            "tool_input": {
                "questions": [
                    {
                        "header": "Review pace",
                        "question": "Which review pace should this project use?",
                        "options": [
                            {
                                "label": "Fast",
                                "description": "Finish the review sooner.",
                            },
                            {
                                "label": "Careful",
                                "description": "Check each change in detail.",
                            },
                        ],
                        "multiSelect": False,
                    }
                ]
            },
        }

    def test_pretool_validation_does_not_persist_a_record_for_an_invalid_question(
        self,
    ) -> None:
        event = self.question_event()
        event["tool_input"] = {
            "questions": [
                {
                    "header": "Review pace",
                    "question": "Which review pace should this project use?",
                    "options": [
                        {"label": "Fast", "description": "Finish the review sooner."},
                    ],
                    "multiSelect": False,
                }
            ]
        }
        self.assertIn("two to four choices", self.hook(event, "pretool") or "")
        store = user_question_guard.DecisionStore(self.root / ".lbwc-planning")
        self.assertEqual(store.state(self.session_id), "none")

    def test_native_other_does_not_require_a_duplicate_visible_option(self) -> None:
        self.assertIsNone(self.hook(self.question_event(), "pretool"))
        response = self.question_event()
        response["tool_input"] = {
            "answers": {
                "Which review pace should this project use?": "Use a calm but complete review."
            }
        }

        self.assertIsNone(self.hook(response, "posttool"))
        store = user_question_guard.DecisionStore(self.root / ".lbwc-planning")
        record = store.record(self.session_id)
        self.assertEqual(record["status"], "resolved")
        self.assertEqual(record["response"], {"kind": "freeform", "received": True})
        self.assertNotIn("Use a calm", json.dumps(record))

    def test_prompt_hook_drains_a_pre_upgrade_awaiting_freeform_record(self) -> None:
        """A record persisted by a pre-fix build can still land in "awaiting_freeform".

        The two-step sentinel-based state machine this contract replaces no longer
        writes that status, but an on-disk record from before the upgrade can still
        carry it. The UserPromptSubmit hook must still drain it to "resolved" so an
        old pending decision does not block the session forever.
        """
        planning_dir = self.root / ".lbwc-planning"
        store = user_question_guard.DecisionStore(planning_dir)
        self.assertIsNone(self.hook(self.question_event(), "pretool"))
        record = store.record(self.session_id)
        fingerprint = record["state_fingerprint"]
        path = store._record_path(self.session_id, create=True)
        assert path is not None
        record["status"] = "awaiting_freeform"
        store._persist(path, record)
        self.assertEqual(store.state(self.session_id), "awaiting_freeform")

        prompt_event: dict[str, object] = {
            "session_id": self.session_id,
            "cwd": str(self.root),
            "prompt": "Use a calm but complete review.",
        }
        self.assertIsNone(self.hook(prompt_event, "prompt"))

        drained = store.record(self.session_id)
        self.assertEqual(drained["status"], "resolved")
        self.assertEqual(drained["response"], {"kind": "freeform", "received": True})
        self.assertEqual(drained["state_fingerprint"], fingerprint)


if __name__ == "__main__":
    unittest.main()
