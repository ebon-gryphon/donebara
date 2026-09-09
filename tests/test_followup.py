import importlib.util
import fcntl
import json
import os
from pathlib import Path
import socket
import struct
import tempfile
import threading
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("followup", Path(__file__).parents[1] / "scripts/donebara_followup.py")
followup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(followup)
THREAD = "01a084e3-f2d1-7d30-8359-c5f3eb737713"


class FakeDesktop:
    state = "idle"
    fail_after_send = False
    starts = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def request(self, method, params, version=0, target=None):
        if method == "thread-owner-discovery":
            return {"handledByClientId": "owner"}
        self.starts.append(params)
        if self.fail_after_send:
            raise TimeoutError()
        return {"result": {"result": {"turn": {"id": "new-turn"}}}}

    def snapshot(self, thread, owner):
        return {"id": thread, "hostId": "local", "threadRuntimeStatus": {"type": self.state}}


class FollowupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.report = {"report_id": "report-1", "thread_id": THREAD, "host_id": "local",
                       "session_id": "a-different-root", "blockers": ["tests failed"]}
        FakeDesktop.starts = []
        FakeDesktop.state = "idle"
        FakeDesktop.fail_after_send = False

    def send(self, prompt="请检查原因"):
        return followup.deliver(self.report, prompt, self.root, FakeDesktop)

    def test_exact_thread_and_literal_prompt_without_setting_overrides(self):
        prompt = '请检查 `echo secret` $(touch /tmp/never)\n不要修复'
        self.assertEqual(self.send(prompt)["status"], "sent")
        start = FakeDesktop.starts[0]
        self.assertEqual(start["conversationId"], THREAD)
        request = start["turnStart"]["request"]
        self.assertEqual(set(request), {"threadId", "input"})
        self.assertTrue(request["input"][0]["text"].startswith(prompt))
        self.assertIn("tests failed", request["input"][0]["text"])
        self.assertTrue(start["turnStart"]["context"]["inheritThreadSettings"])

    def test_duplicate_is_not_sent_again_and_receipt_has_no_prompt(self):
        self.send("only-once-private-prompt")
        self.send("only-once-private-prompt")
        self.assertEqual(len(FakeDesktop.starts), 1)
        self.assertNotIn("private-prompt", next((self.root / "followups").glob("*.json")).read_text())

    def test_busy_task_can_retry_after_completion(self):
        FakeDesktop.state = "active"
        with self.assertRaises(followup.FollowupError):
            self.send()
        self.assertFalse(FakeDesktop.starts)
        FakeDesktop.state = "idle"
        self.assertEqual(self.send()["status"], "sent")

    def test_old_report_does_not_use_session_id(self):
        self.report.pop("thread_id")
        self.report["session_id"] = THREAD
        with self.assertRaises(followup.FollowupError):
            self.send()
        self.assertFalse(FakeDesktop.starts)

    def test_remote_missing_target_and_empty_input_fail_closed(self):
        for key, value in [("host_id", "remote"), ("thread_id", "../bad")]:
            with self.subTest(key=key), mock.patch.dict(self.report, {key: value}):
                with self.assertRaises(followup.FollowupError):
                    self.send()
        for prompt in ["  ", "x" * 8001]:
            with self.assertRaises(followup.FollowupError):
                self.send(prompt)

    def test_uncertain_delivery_never_auto_retries(self):
        FakeDesktop.fail_after_send = True
        for _ in range(2):
            with self.assertRaises(followup.FollowupError) as error:
                self.send()
            self.assertTrue(error.exception.uncertain)
        self.assertEqual(len(FakeDesktop.starts), 1)

    def test_thread_lock_prevents_concurrent_distinct_messages(self):
        directory = self.root / "followups"
        directory.mkdir()
        with (directory / (THREAD + ".lock")).open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(followup.FollowupError):
                self.send("different text")
        self.assertFalse(FakeDesktop.starts)

    def test_real_socket_fragmented_utf8_and_unrelated_broadcast(self):
        left, right = socket.socketpair()
        self.addCleanup(left.close)
        self.addCleanup(right.close)
        ipc = followup.DesktopIPC(timeout=2)
        ipc.sock = left

        def server():
            size = struct.unpack("<I", right.recv(4))[0]
            data = bytearray()
            while len(data) < size:
                data.extend(right.recv(size - len(data)))
            request = json.loads(data)
            messages = [{"type": "broadcast", "method": "irrelevant"},
                        {"type": "response", "requestId": request["requestId"], "resultType": "success",
                         "result": {"message": "中文已收到"}}]
            for message in messages:
                data = json.dumps(message, ensure_ascii=False).encode()
                frame = struct.pack("<I", len(data)) + data
                for byte in frame:
                    right.sendall(bytes([byte]))

        worker = threading.Thread(target=server)
        worker.start()
        result = ipc.request("test", {})
        worker.join(3)
        self.assertEqual(result["result"]["message"], "中文已收到")


if __name__ == "__main__":
    unittest.main()
