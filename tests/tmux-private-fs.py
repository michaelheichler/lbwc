#!/usr/bin/env python3
import importlib.util
import json
import os
import tempfile
import unittest
from unittest import mock


HELPER = os.path.join(os.path.dirname(__file__), "..", "scripts", "lib", "tmux-private-fs.py")
SPEC = importlib.util.spec_from_file_location("tmux_private_fs", HELPER)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class TmuxPrivateFilesystemTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = self.temp.name
        os.chmod(self.root, 0o700)
        os.mkdir(os.path.join(self.root, "inbox"), 0o700)
        os.mkdir(os.path.join(self.root, "acked"), 0o700)
        MODULE.write_json(self.root, "inbox/job.json", json.dumps({"message": "source"}))

    def tearDown(self):
        self.temp.cleanup()

    def test_move_does_not_replace_existing_destination(self):
        MODULE.write_json(self.root, "acked/job.json", json.dumps({"message": "destination"}))
        with self.assertRaises(RuntimeError):
            MODULE.move(self.root, "inbox/job.json", "acked/job.json")
        with open(os.path.join(self.root, "inbox", "job.json")) as source:
            self.assertEqual(json.load(source)["message"], "source")

    def test_read_json_preserves_the_private_descriptor(self):
        MODULE.write_json(self.root, "credentials/bootstrap.json", json.dumps({"credential": "secret"}))

        document = MODULE.read_json(self.root, "credentials/bootstrap.json")

        self.assertEqual(json.loads(document)["credential"], "secret")
        self.assertTrue(os.path.exists(os.path.join(self.root, "credentials", "bootstrap.json")))

    def test_publish_directory_removes_staging_directory_after_contention(self):
        MODULE.publish_directory(self.root, "locks/registry.lock", json.dumps({"pid": 1}))
        with self.assertRaises(FileExistsError):
            MODULE.publish_directory(self.root, "locks/registry.lock", json.dumps({"pid": 2}))
        entries = os.listdir(os.path.join(self.root, "locks"))
        self.assertEqual(entries, ["registry.lock"])

    def test_complete_ack_resumes_after_both_names_interruption(self):
        with mock.patch.dict(os.environ, {"LBWC_TMUX_FS_FAIL_AFTER_ACK_LINK": "1"}):
            with self.assertRaises(RuntimeError):
                MODULE.complete_ack(self.root, "inbox/job.json", "acked/job.json")
        self.assertTrue(os.path.exists(os.path.join(self.root, "inbox", "job.json")))
        self.assertTrue(os.path.exists(os.path.join(self.root, "acked", "job.json")))

        MODULE.complete_ack(self.root, "inbox/job.json", "acked/job.json")

        self.assertFalse(os.path.exists(os.path.join(self.root, "inbox", "job.json")))
        with open(os.path.join(self.root, "acked", "job.json")) as acknowledged:
            self.assertEqual(json.load(acknowledged)["message"], "source")

    def test_complete_ack_accepts_an_orphaned_destination(self):
        MODULE.move(self.root, "inbox/job.json", "acked/job.json")

        MODULE.complete_ack(self.root, "inbox/job.json", "acked/job.json")

        self.assertTrue(os.path.exists(os.path.join(self.root, "acked", "job.json")))

    def test_check_directories_rejects_the_whole_set_when_one_member_is_not_private(self):
        good = os.path.join(self.root, "inbox")
        bad = os.path.join(self.root, "world")
        os.mkdir(bad, 0o755)
        with self.assertRaises(RuntimeError):
            MODULE.check_directories([good, bad])

    def test_list_json_returns_newest_private_files_first(self):
        inbox = os.path.join(self.root, "inbox")
        MODULE.write_json(self.root, "inbox/old.json", json.dumps({"n": 1}))
        os.utime(os.path.join(inbox, "old.json"), ns=(1, 1))
        MODULE.write_json(self.root, "inbox/name with spaces.json", json.dumps({"n": 2}))
        names = []
        with mock.patch.object(MODULE, "print") as printer:
            MODULE.list_json(inbox)
            names = [call.args[0] for call in printer.call_args_list]
        self.assertEqual(names[0], "name with spaces.json")
        self.assertIn("old.json", names)


if __name__ == "__main__":
    unittest.main()
