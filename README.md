# CODE X Patched MAX Script - Other Script

[English](#english) | [中文](#中文)

## English

Legacy 3ds Max and helper scripts with AI-assisted repair, compatibility
maintenance, and workflow fixes. This repository contains the local source
files directly; the matching archive is available from the Release page.

### Script List

| File | Purpose |
| --- | --- |
| `RE5_unoffical-v0-33a.ms` | Resident Evil 5 `.mod` model import, editing, and export tool. This maintained version keeps the original format behavior while improving newer 3ds Max compatibility, UI responsiveness, and export stability. |
| `REEM_NOESIS_CMD_FocusFix_CN_EN.ms` | Noesis-command-based RE Engine MESH import/export workflow for 3ds Max, with Chinese/English UI support plus dialog-focus and scene-export helper fixes. |
| `fbxskel_tool_v0.1_v0.4_Max2026.ms` | RE Engine `fbxskel.2`, `.3`, and `.5` skeleton tool. Imports skeletons and supports either pose-preserving updates or complete rebuilding from scene bones. |
| `codex_re6_render_everything.py` | Runtime-only Render Everything switch for RE6 `BH6.exe`. It verifies the target process and instruction signature before changing memory only; it does not write the EXE file. |
| `codex_re6_render_everything_exe_patcher.py` | Signature-checked permanent Render Everything patcher for RE6 `BH6.exe`. It can inspect state, apply the patch, and restore the original bytes. |

### RE6 Render Everything Only

`codex_re6_render_everything.py` and
`codex_re6_render_everything_exe_patcher.py` are for users who do not want to
enable Ultimate Trainer and only need to address RE6 model visibility/rendering.
The first changes target-process memory for the current run only; the second is
an inspectable, reversible permanent patch for an EXE with a verified signature.

In local testing, Ultimate Trainer affected Melee close-range damage detection
for some main-story playable entities. One observed case was that stomping an
enemy body produced no damage. This is an observation from a specific test
environment, not a claim that every version or scene behaves this way. It is
enough to show why enabling a full trainer solely for model visibility is not
always appropriate.

For that reason, this repository supplies only the two Render Everything paths:
a runtime memory tool and a reversible EXE patcher. It does not provide general
trainer features. In the local test setup, Wilsonso's Shader Pack can provide
Missing Files Fix-like support for resilient loading when a resource is absent;
it does not replace Render Everything for model visibility.

Wilsonso's Shader Pack does not always resolve Missing File popups, loading
errors, or game crashes. If the game still crashes, first check that the MOD
package is complete and repair the actual missing resource. Under the current
tooling, Ultimate Trainer - Missing Files Fix remains the final fallback for
resource-missing failures. This repository does not yet provide an AI-built
Missing Files Fix-like patch script.

### Notes

- The `.ms` files are intended for Autodesk 3ds Max. Their original tool
  dependencies, such as Noesis or RE5 conversion utilities, are not bundled.
- `.mod`, `fbxskel`, and game executable operations can affect assets or game
  files. Work on copies and verify results in the target environment.
- No Resident Evil game assets are included in this repository.

### Credits

Original scripts and their authors retain their respective rights. AI-assisted
repairs in this repository do not claim ownership of the original works.

---

## 中文

老旧 3ds Max 脚本和辅助工具的 AI 协助修复版，重点是兼容性维护、实际工作流修复和稳定性改进。仓库直接提供当前本地使用的源代码，对应压缩包见 Release 页面。

### 脚本清单

| 文件 | 作用 |
| --- | --- |
| `RE5_unoffical-v0-33a.ms` | 《生化危机 5》`.mod` 模型导入、编辑和导出脚本。此版本保留原始格式逻辑，并补充较新 3ds Max 的兼容性、界面响应和导出稳定性维护。 |
| `REEM_NOESIS_CMD_FocusFix_CN_EN.ms` | 基于 Noesis 命令行的 RE Engine MESH 导入/导出工作流脚本，带中英文界面，并修复窗口焦点和场景导出辅助逻辑。 |
| `fbxskel_tool_v0.1_v0.4_Max2026.ms` | RE Engine `fbxskel.2`、`.3`、`.5` 骨骼文件工具。可导入骨骼，并支持保留当前姿势更新或从场景骨骼完整重建。 |
| `codex_re6_render_everything.py` | RE6 `BH6.exe` 运行时 Render Everything 开关。先核验目标进程和指令签名，再只修改内存，不写入 EXE 文件。 |
| `codex_re6_render_everything_exe_patcher.py` | RE6 `BH6.exe` Render Everything 永久补丁工具。通过签名定位目标指令，可检测状态、写入补丁并恢复原始字节。 |

### 仅提供 RE6 Render Everything

`codex_re6_render_everything.py` 和
`codex_re6_render_everything_exe_patcher.py` 是为“不想开启 Ultimate Trainer、但只需要
解决 RE6 模型可见性/渲染问题”的用户准备的。前者只在运行期间修改目标进程内存，关闭
游戏后失效；后者为已经核验过签名的 EXE 提供可检查、可恢复的永久补丁。

本地实测中，Ultimate Trainer 会影响一部分主线可操作对象的 Melee 近身伤害判定；例如，
踩踏敌人身体时可能不产生伤害。该现象是特定测试环境中的观察结果，不代表所有版本、
所有场景都会发生，但足以说明“只为模型显示而开启完整修改器”并不总是合适。

本仓库因此只提供两种 Render Everything 路线：运行时内存工具或可恢复的 EXE 补丁，
不提供完整修改器功能。对于缺失资源后的稳定加载/防闪退需求，本地测试可由
Wilsonso's Shader Pack 提供与 Missing Files Fix 类似的支持；它不替代 Render Everything
本身的模型可见性作用。

Wilsonso's Shader Pack 并不总能解决 Missing File 弹窗、加载报错或游戏闪退。若游戏仍然
闪退，先检查 MOD 包是否完整并修复实际缺失资源；在当前工具条件下，Ultimate Trainer -
Missing Files Fix 仍是资源缺失问题的最终兜底。本仓库目前尚未提供由 AI 制作的
Missing Files Fix 类补丁脚本。

### 说明

- `.ms` 脚本面向 Autodesk 3ds Max 使用。Noesis、RE5 转换工具等原始依赖不随本仓库提供。
- `.mod`、`fbxskel` 和游戏 EXE 操作可能影响资源或游戏文件，请在副本上操作并在目标环境中验证结果。
- 本仓库不包含任何《生化危机》游戏资源。

### 致谢

原始脚本及其作者保留各自权利。本仓库中的 AI 协助修复不主张对原始作品的所有权。
