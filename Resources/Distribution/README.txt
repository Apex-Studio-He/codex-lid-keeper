CODEX LID KEEPER — PUBLIC ALPHA / 公开测试版
================================================

QUICK INSTALL / 快速安装

1. Double-click “Install Codex Lid Keeper.command”.
   双击“Install Codex Lid Keeper.command”。
2. Terminal asks for the administrator password through standard macOS sudo.
   管理员密码只会由终端里的 macOS sudo 询问，App 不会读取或保存。
3. Open /hooks in Codex, review the five lifecycle Hooks, and trust them.
   在 Codex 中打开 /hooks，检查并信任五个生命周期 Hook。

If macOS blocks the installer because this Alpha is not notarized, Control-click
the installer and choose Open. Do not disable Gatekeeper system-wide.

如果 macOS 因当前 Alpha 尚未 notarize 而拦截，请按住 Control 点击安装程序，
再选择“打开”。不要在系统范围内关闭 Gatekeeper。

SAFETY / 安全

This experimental app uses the undocumented “pmset disablesleep” setting.
Never put a running, closed MacBook in a bag, sleeve, drawer, bed, sofa, or
other poorly ventilated space. Keep the first test supervised on a hard,
open desk and stop if the computer becomes unusually warm.

本项目会使用 macOS 没有公开文档的“pmset disablesleep”。不要把合盖运行中的
MacBook 放进背包、内胆包、抽屉、床铺、沙发或其他不通风的空间。第一次测试
必须在坚硬、开阔的桌面上有人看守，异常发热时立即停止。

SIGNING / 签名状态

This package is ad-hoc signed for local bundle-consistency checks; that
signature does not authenticate the publisher. It is not Developer ID signed
or Apple-notarized. Source and SHA-256 checksums are published at:

当前安装包使用 ad-hoc 签名检查 Bundle 内部是否自洽，但它不能证明发布者身份。
这版尚未使用 Developer ID 签名，也没有通过 Apple notarization。源码与
SHA-256 校验值发布在：

https://github.com/Apex-Studio-He/codex-lid-keeper

UNINSTALL / 卸载

Double-click “Uninstall Codex Lid Keeper.command”. The uninstaller restores
owned power state before removing the app, helper, launchd jobs, sudoers rule,
and project Hooks. User logs and configuration are retained.

双击“Uninstall Codex Lid Keeper.command”。卸载程序会先恢复本项目接管的电源
状态，再移除 App、Helper、launchd、sudoers 规则和本项目 Hooks。用户日志与
配置会保留。
