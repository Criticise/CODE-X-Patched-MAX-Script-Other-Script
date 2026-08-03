# CODE X Patched MAX Script - Other Script

Legacy 3ds Max and helper scripts with AI-assisted repair, compatibility
maintenance, and workflow fixes. This repository contains the local source
files directly; the matching archive is available from the Release page.

老旧 3ds Max 脚本和辅助工具的 AI 协助修复版，重点是兼容性维护、实际工作流修复和稳定性改进。仓库直接提供当前本地使用的源代码，对应压缩包见 Release 页面。

## Script List / 脚本清单

| File / 文件 | 中文作用 | English purpose |
| --- | --- | --- |
| `RE5_unoffical-v0-33a.ms` | 《生化危机 5》`.mod` 模型导入、编辑和导出脚本。此版本保留原始格式逻辑，并补充较新 3ds Max 的兼容性、界面响应和导出稳定性维护。 | Resident Evil 5 `.mod` model import, editing, and export tool. This maintained version keeps the original format behavior while improving newer 3ds Max compatibility, UI responsiveness, and export stability. |
| `REEM_NOESIS_CMD_FocusFix_CN_EN.ms` | 基于 Noesis 命令行的 RE Engine MESH 导入/导出工作流脚本，带中英文界面，并修复窗口焦点和场景导出辅助逻辑。 | Noesis-command-based RE Engine MESH import/export workflow for 3ds Max, with Chinese/English UI support plus dialog-focus and scene-export helper fixes. |
| `fbxskel_tool_v0.1_v0.4_Max2026.ms` | RE Engine `fbxskel.2`、`.3`、`.5` 骨骼文件工具。可导入骨骼，并支持保留当前姿势更新或从场景骨骼完整重建。 | RE Engine `fbxskel.2`, `.3`, and `.5` skeleton tool. Imports skeletons and supports either pose-preserving updates or complete rebuilding from scene bones. |
| `codex_re6_render_everything.py` | RE6 `BH6.exe` 运行时 Render Everything 开关。先核验目标进程和指令签名，再只修改内存，不写入 EXE 文件。 | Runtime-only Render Everything switch for RE6 `BH6.exe`. It verifies the target process and instruction signature before changing memory only; it does not write the EXE file. |
| `codex_re6_render_everything_exe_patcher.py` | RE6 `BH6.exe` Render Everything 永久补丁工具。通过签名定位目标指令，可检测状态、写入补丁并恢复原始字节。 | Signature-checked permanent Render Everything patcher for RE6 `BH6.exe`. It can inspect state, apply the patch, and restore the original bytes. |

## Notes / 说明

- The `.ms` files are intended for Autodesk 3ds Max. Their original tool
  dependencies, such as Noesis or RE5 conversion utilities, are not bundled.
- `.mod`, `fbxskel`, and game executable operations can affect assets or game
  files. Work on copies and verify results in the target environment.
- No Resident Evil game assets are included in this repository.

- `.ms` 脚本面向 Autodesk 3ds Max 使用。Noesis、RE5 转换工具等原始依赖不随本仓库提供。
- `.mod`、`fbxskel` 和游戏 EXE 操作可能影响资源或游戏文件，请在副本上操作并在目标环境中验证结果。
- 本仓库不包含任何《生化危机》游戏资源。

## Credits / 致谢

Original scripts and their authors retain their respective rights. AI-assisted
repairs in this repository do not claim ownership of the original works.

原始脚本及其作者保留各自权利。本仓库中的 AI 协助修复不主张对原始作品的所有权。
