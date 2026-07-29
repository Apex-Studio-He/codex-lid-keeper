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
- `scripts`: build, Hook merge, install, recovery, uninstall, integration tests
- `Resources`: launchd definitions

Prefer small caller-facing interfaces with safety complexity kept inside the
core module. Preserve fail-open Hook behavior and fail-safe power recovery.

## 简体中文

### 提交 Issue 前

- 阅读 [TESTING.md](TESTING.md) 并搜索已有 Issue。
- 尽可能使用 dry-run 复现。
- 删除提示词、对话、密钥、session ID 和个人路径。
- 漏洞请使用 GitHub Security Advisory 私下报告。

### 开发流程

```bash
git clone https://github.com/Apex-Studio-He/codex-lid-keeper.git
cd codex-lid-keeper
./scripts/build.sh
/usr/bin/python3 scripts/test_hooks_config.py
/usr/bin/python3 scripts/test_e2e.py --binary .build/release/codex-lid-keeper
```

开发环境要求 macOS 13+、Swift 6 和 Python 3。

### 安全不变量

自动测试绝不能修改开发机器真实的 `pmset` 配置。请使用
`RecordingCommandRunner`、`FakePowerController` 或
`CODEX_LID_KEEPER_DRY_RUN=1`。任何真实电源测试都必须是手动、明确标记且不进入
CI 的测试。

### Pull Request 要求

- 每个 PR 保持主题集中。
- 行为变化必须增加回归测试。
- 涉及用户行为时同时更新英文和中文文档。
- 运行上面的完整构建与测试命令。
- 在 PR 中说明权限、持久化与恢复语义的变化。
- 不提交 `.build` 或本地规划文件。

代码应保持 Hook fail-open、电源恢复 fail-safe，并把安全复杂度留在核心模块内部。
