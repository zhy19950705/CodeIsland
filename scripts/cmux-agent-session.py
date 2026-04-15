#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

# Persist bindings outside the repo so they survive workspace moves and pulls.
STATE_FILE = Path(os.environ.get("CMUX_AGENT_STATE_FILE", "~/.config/cmux-agent-session/bindings.jsonl")).expanduser()


# Use one place for fatal exits so the CLI stays predictable in shell automation.
def die(message: str) -> "NoReturn":
    print(f"cmux-agent-session: {message}", file=sys.stderr)
    raise SystemExit(1)


def run_cmux(*args: str) -> str:
    try:
        output = subprocess.check_output(["cmux", *args], text=True)
    except FileNotFoundError as exc:
        raise SystemExit("cmux-agent-session: 缺少命令: cmux") from exc
    except subprocess.CalledProcessError as exc:
        die(exc.output.strip() or f"cmux {' '.join(args)} 执行失败")
    return output


def normalize_cmux_handle(value: str, prefix: str) -> str:
    if value.startswith(f"{prefix}:"):
        return value
    if re.fullmatch(r"\d+", value):
        return f"{prefix}:{value}"
    return value


def current_workspace_ref() -> str:
    workspace_ref = os.environ.get("CMUX_WORKSPACE_REF")
    if workspace_ref:
        return normalize_cmux_handle(workspace_ref, "workspace")
    workspace_id = os.environ.get("CMUX_WORKSPACE_ID")
    if workspace_id:
        return normalize_cmux_handle(workspace_id, "workspace")
    return run_cmux("current-workspace").split()[0]


def current_workspace_key(workspace_ref: str) -> str:
    # Titles are user-editable, so prefer cmux's own workspace identifier to keep bindings isolated.
    workspace_id = os.environ.get("CMUX_WORKSPACE_ID")
    if workspace_id:
        return normalize_cmux_handle(workspace_id, "workspace")
    return workspace_ref


# Parse pane order and tab order from `cmux tree` so restores do not depend on runtime ids.
def parse_workspace_tree(tree_text: str) -> tuple[str, list[dict[str, object]]]:
    workspace_title = ""
    rows: list[dict[str, object]] = []
    pane_index = 0
    surface_index = 0
    surface_ref_env = normalize_cmux_handle(os.environ["CMUX_SURFACE_ID"], "surface") if os.environ.get("CMUX_SURFACE_ID") else ""

    for line in tree_text.splitlines():
        workspace_match = re.search(r'workspace\s+\S+\s+"([^"]*)"', line)
        if workspace_match and not workspace_title:
            workspace_title = workspace_match.group(1)

        if re.search(r"\bpane\s+pane:\d+", line):
            pane_index += 1
            surface_index = 0
            continue

        surface_match = re.search(r'\bsurface\s+(surface:\d+)\s+\[[^\]]+\]\s+"([^"]*)"', line)
        if not surface_match:
            continue

        surface_index += 1
        surface_ref = surface_match.group(1)
        rows.append(
            {
                "pane_index": pane_index,
                "surface_index": surface_index,
                "surface_ref": surface_ref,
                "surface_title": surface_match.group(2).replace("\t", " ").strip(),
                "is_current": "◀ here" in line or surface_ref == surface_ref_env,
            }
        )

    return workspace_title, rows


def current_workspace_snapshot() -> tuple[str, str, str, list[dict[str, object]]]:
    workspace_ref = current_workspace_ref()
    workspace_key = current_workspace_key(workspace_ref)
    workspace_title, rows = parse_workspace_tree(run_cmux("tree", "--workspace", workspace_ref))
    return workspace_ref, workspace_key, workspace_title, rows


def current_surface_row(rows: list[dict[str, object]]) -> dict[str, object]:
    for row in rows:
        if row["is_current"]:
            return row
    die("当前标签页不在 cmux 内，或无法定位当前 surface")


def encode_claude_project_dir(path: str) -> str:
    # Keep the CLI lookup aligned with the app's Swift encoding so spaces and Unicode paths resolve identically.
    return "".join("-" if char == "/" or char == " " or ord(char) > 127 else char for char in path)


# Scan recent local transcripts so bind can work without manually copying session ids.
def detect_latest_session(tool: str, cwd: str) -> str:
    real_cwd = str(Path(cwd).expanduser().resolve())
    home = Path.home()

    if tool == "codex":
        root = home / ".codex" / "sessions"
        files = sorted(root.rglob("*.jsonl"), key=lambda path: path.stat().st_mtime, reverse=True)
        for path in files[:400]:
            try:
                payload = json.loads(path.open("r", encoding="utf-8").readline()).get("payload", {})
            except Exception:
                continue
            if str(Path(payload.get("cwd", "")).resolve()) == real_cwd and payload.get("id"):
                return str(payload["id"])
        return ""

    if tool == "claude":
        project_dir = home / ".claude" / "projects" / encode_claude_project_dir(real_cwd)
        if not project_dir.is_dir():
            return ""
        files = sorted(project_dir.glob("*.jsonl"), key=lambda path: path.stat().st_mtime, reverse=True)
        for path in files[:200]:
            try:
                with path.open("r", encoding="utf-8") as handle:
                    for _ in range(30):
                        line = handle.readline()
                        if not line:
                            break
                        payload = json.loads(line)
                        session_cwd = str(Path(payload.get("cwd", "")).resolve()) if payload.get("cwd") else ""
                        if session_cwd == real_cwd and payload.get("sessionId"):
                            return str(payload["sessionId"])
            except Exception:
                continue
        return ""

    die(f"不支持的工具类型: {tool}")


def infer_tool(surface_title: str) -> str:
    lowered = surface_title.lower()
    if "codex" in lowered:
        return "codex"
    if "claude" in lowered:
        return "claude"
    return ""


def default_restore_command(tool: str, cwd: str, session_id: str) -> str:
    quoted_cwd = shlex.quote(str(Path(cwd).expanduser().resolve()))
    quoted_session = shlex.quote(session_id)
    if tool == "codex":
        return f"cd {quoted_cwd} && exec codex resume {quoted_session}"
    if tool == "claude":
        return f"cd {quoted_cwd} && exec claude -r {quoted_session}"
    die(f"不支持的工具类型: {tool}")


def ensure_state_store() -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.touch(exist_ok=True)


def load_state() -> list[dict[str, object]]:
    ensure_state_store()
    rows: list[dict[str, object]] = []
    with STATE_FILE.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


# Write through a temp file so concurrent edits never leave a half-written state file behind.
def save_state(rows: list[dict[str, object]]) -> None:
    ensure_state_store()
    rows.sort(key=lambda row: (str(row.get("workspace_key", row["workspace_title"])), int(row["pane_index"]), int(row["surface_index"])))
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, dir=STATE_FILE.parent) as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
        temp_path = Path(handle.name)
    temp_path.replace(STATE_FILE)


def binding_matches_workspace(row: dict[str, object], workspace_key: str, workspace_title: str) -> bool:
    # Legacy rows only stored titles, so keep a title fallback while new writes use the stable workspace key.
    return str(row.get("workspace_key") or "") == workspace_key or ("workspace_key" not in row and row["workspace_title"] == workspace_title)


def find_binding(rows: list[dict[str, object]], workspace_key: str, workspace_title: str, pane_index: int, surface_index: int) -> dict[str, object] | None:
    for row in rows:
        if binding_matches_workspace(row, workspace_key, workspace_title) and int(row["pane_index"]) == pane_index and int(row["surface_index"]) == surface_index:
            return row
    return None


def command_bind(args: argparse.Namespace) -> None:
    workspace_ref, workspace_key, workspace_title, tree_rows = current_workspace_snapshot()
    del workspace_ref
    current_row = current_surface_row(tree_rows)
    tool = args.tool or infer_tool(str(current_row["surface_title"]))
    if not tool:
        die("无法从标题推断工具类型，请显式传 --tool codex 或 --tool claude")

    cwd = str(Path(args.cwd or os.getcwd()).expanduser().resolve())
    session_id = args.session_id or detect_latest_session(tool, cwd)
    if not session_id:
        die(f"未找到匹配 cwd={cwd} 的最新 {tool} 会话，请显式传 --session-id")

    record = {
        "workspace_key": workspace_key,
        "workspace_title": workspace_title,
        "pane_index": int(current_row["pane_index"]),
        "surface_index": int(current_row["surface_index"]),
        "surface_title": current_row["surface_title"],
        "tool": tool,
        "cwd": cwd,
        "session_id": session_id,
        "restore_command": args.command or default_restore_command(tool, cwd, session_id),
    }

    rows = [
        row for row in load_state()
        if not (
            binding_matches_workspace(row, workspace_key, workspace_title)
            and int(row["pane_index"]) == int(record["pane_index"])
            and int(row["surface_index"]) == int(record["surface_index"])
        )
    ]
    rows.append(record)
    save_state(rows)
    print(f"已绑定: {workspace_title} pane#{record['pane_index']} tab#{record['surface_index']} -> {tool} {session_id}")


def command_list(args: argparse.Namespace) -> None:
    _, workspace_key, workspace_title, _ = current_workspace_snapshot()
    rows = [row for row in load_state() if args.all or binding_matches_workspace(row, workspace_key, workspace_title)]
    if not rows:
        print("没有绑定记录")
        return
    for row in rows:
        print(
            f"{row['workspace_title']}\tpane#{row['pane_index']}\ttab#{row['surface_index']}\t"
            f"{row['tool']}\t{row['session_id']}\t{row['surface_title']}\t{row['cwd']}"
        )


def command_remove_current(_: argparse.Namespace) -> None:
    _, workspace_key, workspace_title, tree_rows = current_workspace_snapshot()
    current_row = current_surface_row(tree_rows)
    rows = [
        row for row in load_state()
        if not (
            binding_matches_workspace(row, workspace_key, workspace_title)
            and int(row["pane_index"]) == int(current_row["pane_index"])
            and int(row["surface_index"]) == int(current_row["surface_index"])
        )
    ]
    save_state(rows)
    print(f"已删除绑定: {workspace_title} pane#{current_row['pane_index']} tab#{current_row['surface_index']}")


def command_detect(args: argparse.Namespace) -> None:
    session_id = detect_latest_session(args.tool, args.cwd or os.getcwd())
    if session_id:
        print(session_id)


def respawn_binding(workspace_ref: str, surface_ref: str, restore_command: str) -> None:
    subprocess.check_call(["cmux", "respawn-pane", "--workspace", workspace_ref, "--surface", surface_ref, "--command", restore_command])


def command_restore_current(_: argparse.Namespace) -> None:
    workspace_ref, workspace_key, workspace_title, tree_rows = current_workspace_snapshot()
    current_row = current_surface_row(tree_rows)
    binding = find_binding(load_state(), workspace_key, workspace_title, int(current_row["pane_index"]), int(current_row["surface_index"]))
    if not binding:
        die("当前标签页没有绑定记录")
    respawn_binding(workspace_ref, str(current_row["surface_ref"]), str(binding["restore_command"]))


def command_restore_workspace(args: argparse.Namespace) -> None:
    workspace_ref, workspace_key, workspace_title, tree_rows = current_workspace_snapshot()
    bindings = [row for row in load_state() if binding_matches_workspace(row, workspace_key, workspace_title)]
    if not bindings:
        die(f"当前 workspace 没有绑定记录: {workspace_title}")

    surface_map = {(int(row["pane_index"]), int(row["surface_index"])): str(row["surface_ref"]) for row in tree_rows}
    for row in sorted(bindings, key=lambda item: (int(item["pane_index"]), int(item["surface_index"]))):
        key = (int(row["pane_index"]), int(row["surface_index"]))
        surface_ref = surface_map.get(key)
        if not surface_ref:
            die(f"当前 layout 找不到 pane#{key[0]} tab#{key[1]}，请先把 workspace 布局恢复到绑定时的结构")
        if args.dry_run:
            print(f"DRY-RUN pane#{key[0]} tab#{key[1]} -> {surface_ref} :: {row['restore_command']}")
        else:
            respawn_binding(workspace_ref, surface_ref, str(row["restore_command"]))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Bind cmux panes/tabs to Codex or Claude sessions for deterministic restore.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    bind_parser = subparsers.add_parser("bind", help="Bind the current cmux tab to a Codex or Claude session.")
    bind_parser.add_argument("--tool", choices=["codex", "claude"])
    bind_parser.add_argument("--session-id")
    bind_parser.add_argument("--cwd")
    bind_parser.add_argument("--command")
    bind_parser.set_defaults(func=command_bind)

    list_parser = subparsers.add_parser("list", help="List current-workspace bindings or all bindings.")
    list_parser.add_argument("--all", action="store_true")
    list_parser.set_defaults(func=command_list)

    remove_parser = subparsers.add_parser("remove-current", help="Remove the binding for the current cmux tab.")
    remove_parser.set_defaults(func=command_remove_current)

    detect_parser = subparsers.add_parser("detect", help="Detect the latest session id for a tool in a cwd.")
    detect_parser.add_argument("--tool", required=True, choices=["codex", "claude"])
    detect_parser.add_argument("--cwd")
    detect_parser.set_defaults(func=command_detect)

    restore_current_parser = subparsers.add_parser("restore-current", help="Restore the binding for the current cmux tab.")
    restore_current_parser.set_defaults(func=command_restore_current)

    restore_workspace_parser = subparsers.add_parser("restore-workspace", help="Restore every binding in the current workspace.")
    restore_workspace_parser.add_argument("--dry-run", action="store_true")
    restore_workspace_parser.set_defaults(func=command_restore_workspace)

    return parser


def main() -> None:
    if shutil.which("python3") is None:
        die("缺少命令: python3")
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    import shutil

    main()
