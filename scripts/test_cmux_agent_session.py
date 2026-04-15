import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


# Load the CLI script as a module so regressions can be verified without renaming the shipped entrypoint.
SCRIPT_PATH = Path(__file__).with_name("cmux-agent-session.py")
SPEC = importlib.util.spec_from_file_location("cmux_agent_session", SCRIPT_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class CmuxAgentSessionTests(unittest.TestCase):
    # Claude transcript lookup must follow the same path encoding as the Swift app for space/Unicode cwd values.
    def test_detect_latest_claude_session_uses_encoded_project_dir(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            home = Path(temp_dir)
            cwd = "/Users/me/My Project/中文"
            transcript_dir = home / ".claude" / "projects" / MODULE.encode_claude_project_dir(cwd)
            transcript_dir.mkdir(parents=True)
            (transcript_dir / "latest.jsonl").write_text(
                '{"cwd": "/Users/me/My Project/中文", "sessionId": "claude-session-123"}\n',
                encoding="utf-8"
            )

            with patch.object(MODULE.Path, "home", return_value=home):
                session_id = MODULE.detect_latest_session("claude", cwd)

        self.assertEqual(session_id, "claude-session-123")

    # New records should isolate workspaces by cmux identity, but old title-only rows still need to remain readable.
    def test_binding_matches_workspace_prefers_workspace_key_and_keeps_legacy_title_fallback(self) -> None:
        keyed_row = {"workspace_key": "workspace:42", "workspace_title": "demo"}
        legacy_row = {"workspace_title": "demo"}

        self.assertTrue(MODULE.binding_matches_workspace(keyed_row, "workspace:42", "other-title"))
        self.assertFalse(MODULE.binding_matches_workspace(keyed_row, "workspace:99", "demo"))
        self.assertTrue(MODULE.binding_matches_workspace(legacy_row, "workspace:42", "demo"))


if __name__ == "__main__":
    unittest.main()
