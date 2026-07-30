# Contributing / 参与贡献

Thank you for helping test or improve Codex Lid Keeper.

感谢你参与测试或改进 Codex Lid Keeper。

## English

### Before opening an issue

- Read [TESTING.md](TESTING.md) and search existing issues.
- Use dry-run reproduction whenever possible.
- Remove prompts, transcripts, secrets, session IDs, and personal paths.
- Use GitHub Security Advisories instead of a public issue for vulnerabilities.

### Development workflow

```bash
git clone https://github.com/Apex-Studio-He/codex-lid-keeper.git
cd codex-lid-keeper
./scripts/build.sh
/usr/bin/python3 scripts/test_hooks_config.py
/usr/bin/python3 scripts/test_e2e.py --binary .build/release/codex-lid-keeper
./scripts/build_distribution.sh
```

Development requirements:

- macOS 13+
- Swift 6
- Python 3 from macOS or newer

### Safety invariant

Automated tests must never change the developer machine's live `pmset`
configuration. Use `RecordingCommandRunner`, `FakePowerController`, or
`CODEX_LID_KEEPER_DRY_RUN=1`. Any test that intentionally changes live power
must be manual, clearly labeled, and excluded from CI.

### Pull requests

- Keep changes focused.
- Add a regression test for behavior changes.
- Update both English and Chinese user-facing documentation when applicable.
- Run the complete build and test commands above.
- Explain privilege, persistence, and recovery effects in the PR description.
- Do not include generated `.build` content or local planning files.

### Code structure

- `CodexLidKeeperCore`: state, queue, power, and reconciliation logic
- `CodexLidKeeperCLI`: command routing and system integration
- `CodexLidKeeperSelfTests`: zero-dependency native regression suite
- `scripts`: build, distribution, install, recovery, uninstall, integration tests
- `Resources`: app metadata, launchd definitions, and distribution entry points

Prefer small caller-facing interfaces with safety complexity kept inside the
core module. Preserve fail-open Hook behavior and fail-safe power recovery.

## 中文贡献说明

### 报问题之前

- 先看[测试指南](TESTING.md)，再搜一下有没有相同 Issue。
- 能用 dry-run 复现，就不要直接动真实电源设置。
- 提交内容里不要出现提示词、聊天记录、密钥、session ID 或个人路径。
- 如果涉及权限绕过、sudoers 或恢复失效，请走 GitHub Security Advisory，
  不要发公开 Issue。

### 本地开发

```bash
git clone https://github.com/Apex-Studio-He/codex-lid-keeper.git
cd codex-lid-keeper
./scripts/build.sh
/usr/bin/python3 scripts/test_hooks_config.py
/usr/bin/python3 scripts/test_e2e.py --binary .build/release/codex-lid-keeper
./scripts/build_distribution.sh
```

需要 macOS 13 或更高版本、Swift 6 和 Python 3。

### 有一条底线不能破

自动测试绝不能修改开发机真实的 `pmset`。测试电源逻辑时，请使用
`RecordingCommandRunner`、`FakePowerController` 或
`CODEX_LID_KEEPER_DRY_RUN=1`。

确实需要改真实电源的测试，只能手动执行，必须写清风险，也不能放进 CI。

### 提 PR 时

- 一个 PR 尽量只解决一件事；
- 改了行为，就补一条能防止回归的测试；
- 用户能看到的变化，要同时更新中英文文档；
- 提交前跑完上面的构建和测试；
- 如果涉及权限、落盘内容或故障恢复，请在 PR 说明里单独写清楚；
- 不要提交 `.build`、本地日志或规划文件。

代码层面请继续守住两个原则：Hook 出错不能拖住 Codex；电源控制出错时要优先
恢复正常睡眠。时序和安全判断尽量放在 Core 里，不要散落到 CLI。
