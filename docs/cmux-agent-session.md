# cmux 多 Pane 会话恢复

这个脚本解决的是：

- `cmux` 退出后，原来的 `codex` / `claude` 进程已经死掉
- 但你希望重新打开 `cmux` 后，把不同 pane 或 tab 精确恢复到各自绑定的 session

脚本位置：

```bash
bash scripts/cmux-agent-session.sh --help
```

## 设计

- 绑定维度不是 “最近一次会话”，而是：
  `workspace 标题 + pane 顺序 + tab 顺序`
- 恢复时用 `cmux respawn-pane` 拉起新进程
- `session id` 默认按 `cwd` 自动探测最新的 Codex/Claude transcript
- 绑定数据默认保存在：
  `~/.config/cmux-agent-session/bindings.jsonl`

## 常用命令

1. 在某个 Codex 标签里绑定当前会话：

```bash
bash scripts/cmux-agent-session.sh bind --tool codex
```

2. 在某个 Claude 标签里绑定指定会话：

```bash
bash scripts/cmux-agent-session.sh bind --tool claude --session-id <session-id>
```

3. 查看当前 workspace 的绑定：

```bash
bash scripts/cmux-agent-session.sh list
```

4. 重进 `cmux` 后，恢复当前 workspace 的全部绑定：

```bash
bash scripts/cmux-agent-session.sh restore-workspace
```

5. 只恢复当前标签：

```bash
bash scripts/cmux-agent-session.sh restore-current
```

## 建议用法

- 先把 workspace 的 pane/tab 布局固定下来
- 每个要恢复的标签都执行一次 `bind`
- 以后重新打开同一个 workspace，只要 pane/tab 顺序没变，直接执行 `restore-workspace`

## 限制

- 它依赖当前 workspace 的 pane/tab 顺序；如果布局顺序变化，脚本会拒绝误恢复
- 默认自动探测的是“同一个 `cwd` 下最新的会话”；如果你同目录并行开了多个 session，建议显式传 `--session-id`
- 如果你需要额外启动参数，可以在绑定时传 `--command 'cd ... && exec codex resume ...'`
