# -*- coding: utf-8 -*-
"""Permanent, signature-checked Render Everything patcher for RE6/BH6.exe."""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import os
import shutil
import stat
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


APP_TITLE = "RE6 Render Everything EXE Patcher"
TARGET_FILENAME = "BH6.exe"


def _detect_ui_language() -> str:
    override = os.environ.get("RE6_RENDER_EVERYTHING_LANG", "").strip().lower()
    if override in {"zh", "zh-cn", "zh-tw", "chinese"}:
        return "zh"
    if override in {"en", "en-us", "en-gb", "english"}:
        return "en"
    if os.name == "nt":
        try:
            language_id = int(ctypes.windll.kernel32.GetUserDefaultUILanguage())
        except (AttributeError, OSError, ValueError):
            pass
        else:
            return "zh" if language_id & 0x03FF == 0x0004 else "en"
    return "en"


UI_LANGUAGE = _detect_ui_language()
UI_FONT = "Microsoft YaHei UI" if UI_LANGUAGE == "zh" else "Segoe UI"


def _t(chinese: str, english: str) -> str:
    return chinese if UI_LANGUAGE == "zh" else english


def _set_ui_language(language: str) -> None:
    if language not in {"zh", "en"}:
        raise ValueError(f"unsupported UI language: {language}")
    global UI_LANGUAGE, UI_FONT
    UI_LANGUAGE = language
    UI_FONT = "Microsoft YaHei UI" if language == "zh" else "Segoe UI"


def _hide_console_window() -> None:
    if os.name != "nt":
        return
    try:
        get_console_window = ctypes.windll.kernel32.GetConsoleWindow
        get_console_window.restype = ctypes.c_void_p
        window = get_console_window()
        if window:
            ctypes.windll.user32.ShowWindow(ctypes.c_void_p(window), 0)
    except (AttributeError, OSError):
        pass


def _relaunch_gui_with_pythonw(argv: list[str]) -> bool:
    if os.name != "nt" or getattr(sys, "frozen", False):
        return False
    executable = Path(sys.executable).resolve()
    if executable.name.casefold() == "pythonw.exe":
        return False
    pythonw = executable.with_name("pythonw.exe")
    if not pythonw.is_file():
        return False
    subprocess.Popen(
        [str(pythonw), str(Path(__file__).resolve()), *argv],
        cwd=str(Path(__file__).resolve().parent),
        close_fds=True,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    return True


# The absolute pointer loaded by MOV varies between builds, so bytes 14..17 are
# intentionally ignored. Everything else describes the complete local branch.
SIGNATURE_PREFIX = bytes.fromhex("F7 87 28 01 00 00 00 00 00 80")
SIGNATURE_SUFFIX = bytes.fromhex("80 B9 71 01 00 00 00 75 02 33 DB C6 44 24 0F 01 EB 3B")
BRANCH_OFFSET = 10
PATCH_OFFSET = 12
POINTER_OFFSET = 14
SUFFIX_OFFSET = 18
SIGNATURE_SIZE = SUFFIX_OFFSET + len(SIGNATURE_SUFFIX)

ORIGINAL_BRANCH = bytes.fromhex("75 18")
LEGACY_ENABLE_BRANCH = bytes.fromhex("EB 18")
ORIGINAL_PATCH_SITE = bytes.fromhex("8B 0D")
PERMANENT_PATCH = bytes.fromhex("EB 16")


class PatcherError(RuntimeError):
    """A refusal or recoverable patching error suitable for user display."""


@dataclass(frozen=True)
class PeSection:
    name: str
    virtual_address: int
    virtual_size: int
    raw_offset: int
    raw_size: int


@dataclass(frozen=True)
class Inspection:
    path: Path
    version: tuple[int, int, int, int] | None
    sha256: str
    section: PeSection
    signature_file_offset: int
    signature_rva: int
    patch_file_offset: int
    branch_bytes: bytes
    patch_bytes: bytes
    state: str

    @property
    def enabled(self) -> bool:
        return self.patch_bytes == PERMANENT_PATCH or self.branch_bytes == LEGACY_ENABLE_BRANCH

    @property
    def version_text(self) -> str:
        if self.version is None:
            return _t(
                "无法读取（不影响控制流签名扫描）",
                "Unavailable (control-flow signature scanning is unaffected)",
            )
        return ".".join(str(part) for part in self.version)

    @property
    def state_text(self) -> str:
        labels = {
            "disabled": _t("未启用（原始控制流）", "Disabled (original control flow)"),
            "permanent": _t("已启用（独立永久补丁）", "Enabled (independent permanent patch)"),
            "legacy": _t("已启用（旧式跳转补丁）", "Enabled (legacy jump patch)"),
            "both": _t("已启用（两种跳转均存在）", "Enabled (both jump patches present)"),
        }
        return labels[self.state]


def _read_u16(data: bytes, offset: int, label: str) -> int:
    if offset < 0 or offset + 2 > len(data):
        raise PatcherError(_t(f"PE 文件截断：无法读取 {label}。", f"Truncated PE file: cannot read {label}."))
    return struct.unpack_from("<H", data, offset)[0]


def _read_u32(data: bytes, offset: int, label: str) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise PatcherError(_t(f"PE 文件截断：无法读取 {label}。", f"Truncated PE file: cannot read {label}."))
    return struct.unpack_from("<I", data, offset)[0]


def _parse_text_section(data: bytes) -> PeSection:
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise PatcherError(_t("目标不是有效的 Windows PE 文件（缺少 MZ 头）。", "The target is not a valid Windows PE file (missing MZ header)."))
    pe_offset = _read_u32(data, 0x3C, _t("PE 头偏移", "PE header offset"))
    if pe_offset + 24 > len(data) or data[pe_offset:pe_offset + 4] != b"PE\0\0":
        raise PatcherError(_t("目标不是有效的 Windows PE 文件（缺少 PE 头）。", "The target is not a valid Windows PE file (missing PE header)."))
    machine = _read_u16(data, pe_offset + 4, "Machine")
    if machine != 0x014C:
        raise PatcherError(_t(f"仅支持 32 位 BH6.exe；当前 PE Machine=0x{machine:04X}。", f"Only 32-bit BH6.exe is supported; PE Machine is 0x{machine:04X}."))
    section_count = _read_u16(data, pe_offset + 6, _t("节数量", "section count"))
    optional_size = _read_u16(data, pe_offset + 20, _t("可选头长度", "optional-header size"))
    optional_offset = pe_offset + 24
    if _read_u16(data, optional_offset, _t("可选头 Magic", "optional-header magic")) != 0x010B:
        raise PatcherError(_t("仅支持 PE32 格式的 BH6.exe。", "Only PE32 BH6.exe files are supported."))
    table_offset = optional_offset + optional_size
    if section_count <= 0 or section_count > 96:
        raise PatcherError(_t(f"PE 节数量异常：{section_count}。", f"Invalid PE section count: {section_count}."))
    if table_offset + section_count * 40 > len(data):
        raise PatcherError(_t("PE 节表超出文件边界。", "The PE section table extends beyond the file."))
    matches: list[PeSection] = []
    for index in range(section_count):
        offset = table_offset + index * 40
        raw_name = data[offset:offset + 8].split(b"\0", 1)[0]
        name = raw_name.decode("ascii", "replace")
        virtual_size = _read_u32(data, offset + 8, f"{name} VirtualSize")
        virtual_address = _read_u32(data, offset + 12, f"{name} VirtualAddress")
        raw_size = _read_u32(data, offset + 16, f"{name} SizeOfRawData")
        raw_offset = _read_u32(data, offset + 20, f"{name} PointerToRawData")
        if raw_offset + raw_size > len(data):
            raise PatcherError(_t(f"PE 节 {name!r} 超出文件边界。", f"PE section {name!r} extends beyond the file."))
        if name == ".text":
            matches.append(
                PeSection(name, virtual_address, virtual_size, raw_offset, raw_size)
            )
    if len(matches) != 1:
        raise PatcherError(_t(f"BH6.exe 必须恰好包含一个 .text 节；当前找到 {len(matches)} 个。", f"BH6.exe must contain exactly one .text section; found {len(matches)}."))
    return matches[0]


def _candidate_matches(blob: bytes, offset: int) -> bool:
    if offset < 0 or offset + SIGNATURE_SIZE > len(blob):
        return False
    if blob[offset:offset + len(SIGNATURE_PREFIX)] != SIGNATURE_PREFIX:
        return False
    branch = blob[offset + BRANCH_OFFSET:offset + BRANCH_OFFSET + 2]
    patch_site = blob[offset + PATCH_OFFSET:offset + PATCH_OFFSET + 2]
    if branch not in (ORIGINAL_BRANCH, LEGACY_ENABLE_BRANCH):
        return False
    if patch_site not in (ORIGINAL_PATCH_SITE, PERMANENT_PATCH):
        return False
    return blob[offset + SUFFIX_OFFSET:offset + SIGNATURE_SIZE] == SIGNATURE_SUFFIX


def _find_signature_offsets(text: bytes) -> list[int]:
    offsets: list[int] = []
    cursor = 0
    while True:
        found = text.find(SIGNATURE_PREFIX, cursor)
        if found < 0:
            return offsets
        if _candidate_matches(text, found):
            offsets.append(found)
        cursor = found + 1


def _file_version(path: Path) -> tuple[int, int, int, int]:
    if os.name != "nt":
        raise PatcherError(_t("此补丁器只能在 Windows 上运行。", "This patcher only runs on Windows."))
    from ctypes import wintypes

    version = ctypes.WinDLL("version", use_last_error=True)
    version.GetFileVersionInfoSizeW.argtypes = [wintypes.LPCWSTR, ctypes.POINTER(wintypes.DWORD)]
    version.GetFileVersionInfoSizeW.restype = wintypes.DWORD
    version.GetFileVersionInfoW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID]
    version.GetFileVersionInfoW.restype = wintypes.BOOL
    version.VerQueryValueW.argtypes = [wintypes.LPCVOID, wintypes.LPCWSTR, ctypes.POINTER(wintypes.LPVOID), ctypes.POINTER(wintypes.UINT)]
    version.VerQueryValueW.restype = wintypes.BOOL

    ignored = wintypes.DWORD()
    size = version.GetFileVersionInfoSizeW(str(path), ctypes.byref(ignored))
    if not size:
        raise PatcherError(_t("无法读取 BH6.exe 的文件版本。", "Unable to read the BH6.exe file version."))
    buffer = ctypes.create_string_buffer(size)
    if not version.GetFileVersionInfoW(str(path), 0, size, buffer):
        raise PatcherError(_t("GetFileVersionInfoW 读取失败。", "GetFileVersionInfoW failed."))
    value = wintypes.LPVOID()
    value_size = wintypes.UINT()
    if not version.VerQueryValueW(buffer, "\\", ctypes.byref(value), ctypes.byref(value_size)):
        raise PatcherError(_t("BH6.exe 不包含固定版本信息。", "BH6.exe has no fixed version information."))
    if value_size.value < 52:
        raise PatcherError(_t("BH6.exe 的固定版本信息长度异常。", "BH6.exe has invalid fixed version information."))
    fixed = ctypes.string_at(value.value, value_size.value)
    signature, _struct_version, file_ms, file_ls = struct.unpack_from("<IIII", fixed, 0)
    if signature != 0xFEEF04BD:
        raise PatcherError(_t("BH6.exe 的版本信息签名异常。", "BH6.exe has an invalid version-information signature."))
    return (
        (file_ms >> 16) & 0xFFFF,
        file_ms & 0xFFFF,
        (file_ls >> 16) & 0xFFFF,
        file_ls & 0xFFFF,
    )


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def inspect_exe(
    path: os.PathLike[str] | str,
    *,
    require_target_name: bool = True,
) -> Inspection:
    target = Path(path).expanduser().resolve()
    if not target.is_file():
        raise PatcherError(_t(f"找不到目标文件：{target}", f"Target file not found: {target}"))
    if require_target_name and target.name.casefold() != TARGET_FILENAME.casefold():
        raise PatcherError(_t(f"只能选择名为 {TARGET_FILENAME} 的游戏程序。", f"The selected game executable must be named {TARGET_FILENAME}."))
    try:
        data = target.read_bytes()
    except OSError as exc:
        raise PatcherError(_t(f"无法读取 {target}：{exc}", f"Unable to read {target}: {exc}")) from exc
    try:
        version = _file_version(target)
    except PatcherError:
        version = None
    section = _parse_text_section(data)
    text = data[section.raw_offset:section.raw_offset + section.raw_size]
    matches = _find_signature_offsets(text)
    if not matches:
        raise PatcherError(
            _t(
                "在 BH6.exe 的 .text 节中没有找到 Render Everything 控制流签名；文件可能已更新或被其他补丁改写。",
                "The Render Everything control-flow signature was not found in the BH6.exe .text section; the file may have been updated or changed by another patch.",
            )
        )
    if len(matches) != 1:
        rendered = ", ".join(f"0x{section.raw_offset + item:X}" for item in matches)
        raise PatcherError(_t(f"Render Everything 签名命中 {len(matches)} 次（{rendered}）；拒绝不唯一写入。", f"The Render Everything signature matched {len(matches)} times ({rendered}); refusing a non-unique write."))
    relative = matches[0]
    signature_file_offset = section.raw_offset + relative
    signature_rva = section.virtual_address + relative
    branch = data[
        signature_file_offset + BRANCH_OFFSET:signature_file_offset + BRANCH_OFFSET + 2
    ]
    patch_site = data[
        signature_file_offset + PATCH_OFFSET:signature_file_offset + PATCH_OFFSET + 2
    ]
    if patch_site == PERMANENT_PATCH and branch == LEGACY_ENABLE_BRANCH:
        state = "both"
    elif patch_site == PERMANENT_PATCH:
        state = "permanent"
    elif branch == LEGACY_ENABLE_BRANCH:
        state = "legacy"
    else:
        state = "disabled"
    return Inspection(
        path=target,
        version=version,
        sha256=_sha256(data),
        section=section,
        signature_file_offset=signature_file_offset,
        signature_rva=signature_rva,
        patch_file_offset=signature_file_offset + PATCH_OFFSET,
        branch_bytes=branch,
        patch_bytes=patch_site,
        state=state,
    )


def _iter_bh6_processes() -> Iterable[tuple[int, str | None]]:
    if os.name != "nt":
        return
    from ctypes import wintypes

    TH32CS_SNAPPROCESS = 0x00000002
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

    class PROCESSENTRY32W(ctypes.Structure):
        _fields_ = [
            ("dwSize", wintypes.DWORD),
            ("cntUsage", wintypes.DWORD),
            ("th32ProcessID", wintypes.DWORD),
            ("th32DefaultHeapID", ctypes.c_size_t),
            ("th32ModuleID", wintypes.DWORD),
            ("cntThreads", wintypes.DWORD),
            ("th32ParentProcessID", wintypes.DWORD),
            ("pcPriClassBase", wintypes.LONG),
            ("dwFlags", wintypes.DWORD),
            ("szExeFile", wintypes.WCHAR * 260),
        ]

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    kernel32.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    kernel32.Process32FirstW.restype = wintypes.BOOL
    kernel32.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    kernel32.Process32NextW.restype = wintypes.BOOL
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL

    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if not snapshot or snapshot == INVALID_HANDLE_VALUE:
        raise PatcherError(_t("无法检查 BH6.exe 是否正在运行；为安全起见拒绝修改。", "Unable to determine whether BH6.exe is running; refusing to modify it."))
    try:
        entry = PROCESSENTRY32W()
        entry.dwSize = ctypes.sizeof(entry)
        ok = kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
        while ok:
            if entry.szExeFile.casefold() == TARGET_FILENAME.casefold():
                process_path: str | None = None
                handle = kernel32.OpenProcess(
                    PROCESS_QUERY_LIMITED_INFORMATION, False, entry.th32ProcessID
                )
                if handle:
                    try:
                        capacity = wintypes.DWORD(32768)
                        buffer = ctypes.create_unicode_buffer(capacity.value)
                        if kernel32.QueryFullProcessImageNameW(
                            handle, 0, buffer, ctypes.byref(capacity)
                        ):
                            process_path = buffer.value
                    finally:
                        kernel32.CloseHandle(handle)
                yield int(entry.th32ProcessID), process_path
            entry.dwSize = ctypes.sizeof(entry)
            ok = kernel32.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        kernel32.CloseHandle(snapshot)


def _assert_game_closed(target: Path) -> None:
    target_key = os.path.normcase(os.path.abspath(target))
    matches: list[str] = []
    unknown: list[str] = []
    for pid, process_path in _iter_bh6_processes():
        if process_path is None:
            unknown.append(str(pid))
        elif os.path.normcase(os.path.abspath(process_path)) == target_key:
            matches.append(str(pid))
    if matches:
        raise PatcherError(_t(f"BH6.exe 正在运行（PID {', '.join(matches)}）。请完全退出游戏后再操作。", f"BH6.exe is running (PID {', '.join(matches)}). Fully exit the game before continuing."))
    if unknown:
        raise PatcherError(
            _t(
                f"检测到无法确认路径的 BH6.exe（PID {', '.join(unknown)}）。请退出游戏后再操作。",
                f"Detected BH6.exe with an unreadable path (PID {', '.join(unknown)}). Exit the game before continuing.",
            )
        )


def _replace_patch_site(target: Path, current: Inspection, replacement: bytes) -> Inspection:
    if replacement not in (ORIGINAL_PATCH_SITE, PERMANENT_PATCH):
        raise ValueError("unsupported patch-site replacement")
    temporary = target.with_name(f".{target.name}.{os.getpid()}.patch.tmp")
    original_mode = stat.S_IMODE(target.stat().st_mode)
    try:
        shutil.copy2(target, temporary)
        if _sha256(temporary.read_bytes()) != current.sha256:
            raise PatcherError(_t("目标文件在扫描后发生变化；补丁已取消。", "The target changed after scanning; patching was cancelled."))
        os.chmod(temporary, original_mode | stat.S_IWRITE)
        with temporary.open("r+b") as stream:
            stream.seek(current.patch_file_offset)
            if stream.read(2) != current.patch_bytes:
                raise PatcherError(_t("目标文件在操作期间发生变化；补丁已取消。", "The target changed during the operation; patching was cancelled."))
            stream.seek(current.patch_file_offset)
            stream.write(replacement)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, original_mode)
        candidate = _inspect_alias(temporary)
        if candidate.patch_bytes != replacement:
            raise PatcherError(_t("候选文件验证失败；原 BH6.exe 未被替换。", "Candidate-file verification failed; the original BH6.exe was not replaced."))
        os.replace(temporary, target)
    except PatcherError:
        raise
    except PermissionError as exc:
        raise PatcherError(
            _t(
                "没有权限替换 BH6.exe。请确认游戏已退出，并以管理员身份运行补丁器。",
                "Permission denied while replacing BH6.exe. Confirm the game is closed and run the patcher as administrator.",
            )
        ) from exc
    except OSError as exc:
        raise PatcherError(_t(f"写入 BH6.exe 失败：{exc}", f"Failed to write BH6.exe: {exc}")) from exc
    finally:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass
    result = inspect_exe(target)
    if result.patch_bytes != replacement:
        raise PatcherError(_t("替换后的 BH6.exe 未通过最终字节验证。", "The replaced BH6.exe failed final byte verification."))
    return result


def _inspect_alias(path: Path) -> Inspection:
    return inspect_exe(path, require_target_name=False)


def apply_patch(target_path: os.PathLike[str] | str) -> tuple[Inspection, bool]:
    target = Path(target_path).expanduser().resolve()
    _assert_game_closed(target)
    current = inspect_exe(target)
    if current.patch_bytes == PERMANENT_PATCH:
        return current, False
    result = _replace_patch_site(target, current, PERMANENT_PATCH)
    return result, True


def remove_patch(target_path: os.PathLike[str] | str) -> tuple[Inspection, bool]:
    target = Path(target_path).expanduser().resolve()
    _assert_game_closed(target)
    current = inspect_exe(target)
    if current.patch_bytes == ORIGINAL_PATCH_SITE:
        return current, False
    result = _replace_patch_site(target, current, ORIGINAL_PATCH_SITE)
    return result, True


def _default_target() -> Path:
    roots: list[Path] = []
    if getattr(sys, "frozen", False):
        roots.append(Path(sys.executable).resolve().parent)
    else:
        roots.append(Path(__file__).resolve().parent)
    roots.append(Path.cwd())
    for root in roots:
        candidate = root / TARGET_FILENAME
        if candidate.is_file():
            return candidate
    return roots[0] / TARGET_FILENAME


def _format_inspection(info: Inspection) -> str:
    return "\n".join(
        (
            _t(f"文件：{info.path}", f"File: {info.path}"),
            _t(f"版本：{info.version_text}", f"Version: {info.version_text}"),
            _t(
                "兼容性：控制流签名唯一匹配（1.0.6.165 已实机验证）",
                "Compatibility: unique control-flow signature match (1.0.6.165 verified in game)",
            ),
            _t(f"状态：{info.state_text}", f"Status: {info.state_text}"),
            _t(f"签名 RVA：0x{info.signature_rva:X}", f"Signature RVA: 0x{info.signature_rva:X}"),
            _t(
                f"补丁文件偏移：0x{info.patch_file_offset:X}",
                f"Patch file offset: 0x{info.patch_file_offset:X}",
            ),
            _t(
                f"当前字节：{info.patch_bytes.hex(' ').upper()}",
                f"Current bytes: {info.patch_bytes.hex(' ').upper()}",
            ),
            _t(f"SHA-256：{info.sha256}", f"SHA-256: {info.sha256}"),
        )
    )


def _run_gui(initial_target: Path) -> int:
    try:
        import tkinter as tk
        from tkinter import filedialog, messagebox, ttk
    except Exception as exc:
        raise PatcherError(
            _t(f"当前 Python 无法启动 Tk GUI：{exc}", f"This Python cannot start the Tk GUI: {exc}")
        ) from exc

    root = tk.Tk()
    root.title(_t("RE6 Render Everything EXE 永久补丁", APP_TITLE))
    root.geometry("760x440")
    root.minsize(680, 400)
    root.option_add("*Font", (UI_FONT, 10))

    target_var = tk.StringVar(value=str(initial_target))
    status_var = tk.StringVar(value=_t("正在检测……", "Inspecting..."))
    detail_var = tk.StringVar(value="")

    outer = ttk.Frame(root, padding=18)
    outer.pack(fill="both", expand=True)
    header = ttk.Frame(outer)
    header.pack(fill="x")
    title_label = ttk.Label(
        header,
        text=_t("RE6 Render Everything 永久补丁", "RE6 Render Everything Permanent Patch"),
        font=(UI_FONT, 16, "bold"),
    )
    title_label.pack(side="left", anchor="w")
    language_frame = ttk.Frame(header)
    language_frame.pack(side="right", anchor="e")
    zh_button = ttk.Button(language_frame, text="中文", width=7)
    en_button = ttk.Button(language_frame, text="English", width=8)
    zh_button.pack(side="left", padx=(0, 4))
    en_button.pack(side="left")

    subtitle_label = ttk.Label(
        outer,
        text=_t(
            "仅修改 BH6.exe 中唯一匹配的控制流；游戏更新或验证文件后需要重新应用。",
            "Only a unique matching control flow in BH6.exe is changed; reapply after a game update or file verification.",
        ),
        justify="left",
        wraplength=710,
    )
    subtitle_label.pack(anchor="w", pady=(4, 16))

    path_row = ttk.Frame(outer)
    path_row.pack(fill="x")
    ttk.Entry(path_row, textvariable=target_var).pack(side="left", fill="x", expand=True)

    def choose_target() -> None:
        selected = filedialog.askopenfilename(
            title=_t("选择 BH6.exe", "Select BH6.exe"),
            initialdir=str(Path(target_var.get()).parent),
            filetypes=(("Resident Evil 6", "BH6.exe"), (_t("可执行文件", "Executable"), "*.exe")),
        )
        if selected:
            target_var.set(selected)
            refresh()

    browse_button = ttk.Button(path_row, text=_t("选择…", "Browse..."), command=choose_target)
    browse_button.pack(
        side="left", padx=(8, 0)
    )

    status_label = ttk.Label(outer, textvariable=status_var, font=(UI_FONT, 12, "bold"))
    status_label.pack(anchor="w", pady=(18, 8))
    detail_label = ttk.Label(outer, textvariable=detail_var, justify="left", wraplength=710)
    detail_label.pack(anchor="w", fill="x")

    buttons = ttk.Frame(outer)
    buttons.pack(side="bottom", fill="x", pady=(20, 0))

    def current_target() -> Path:
        return Path(target_var.get().strip()).expanduser()

    def refresh() -> None:
        try:
            info = inspect_exe(current_target())
        except Exception as exc:
            status_var.set(_t("无法应用补丁", "Patch unavailable"))
            detail_var.set(str(exc))
            status_label.configure(foreground="#B42318")
            apply_button.state(["disabled"])
            restore_button.state(["disabled"])
            return
        status_var.set(info.state_text)
        detail_var.set(_format_inspection(info))
        status_label.configure(foreground="#087A45" if info.enabled else "#9A6700")
        apply_button.state(["disabled"] if info.patch_bytes == PERMANENT_PATCH else ["!disabled"])
        restore_button.state(["!disabled"] if info.patch_bytes == PERMANENT_PATCH else ["disabled"])

    def apply_from_gui() -> None:
        target = current_target()
        if not messagebox.askyesno(
            _t("RE6 Render Everything EXE 永久补丁", APP_TITLE),
            _t(
                "必须先完全退出 Resident Evil 6。\n\n"
                f"将为以下文件应用永久 Render Everything 补丁：\n{target}\n\n"
                "补丁器不创建 EXE 备份；可用同一工具识别并恢复原始字节。\n\n继续吗？",
                "Resident Evil 6 must be fully closed first.\n\n"
                f"The permanent Render Everything patch will be applied to:\n{target}\n\n"
                "No EXE backup is created; this tool can recognize and restore the original bytes.\n\nContinue?",
            ),
            parent=root,
        ):
            return
        try:
            info, changed = apply_patch(target)
        except Exception as exc:
            messagebox.showerror(_t("补丁失败", "Patch Error"), str(exc), parent=root)
            refresh()
            return
        refresh()
        message = _t("永久补丁已写入。", "The permanent patch was applied.") if changed else _t(
            "目标已经包含独立永久补丁，无需重复写入。",
            "The target already contains the independent permanent patch.",
        )
        messagebox.showinfo(_t("补丁完成", "Patch Complete"), f"{message}\n\n{info.state_text}", parent=root)

    def restore_from_gui() -> None:
        target = current_target()
        if not messagebox.askyesno(
            _t("关闭永久补丁", "Disable Permanent Patch"),
            _t(
                "必须先完全退出 Resident Evil 6。\n\n"
                "将把本工具的 EB 16 永久跳转恢复为原始 8B 0D。\n\n继续吗？",
                "Resident Evil 6 must be fully closed first.\n\n"
                "This tool will restore its EB 16 permanent jump to the original 8B 0D bytes.\n\nContinue?",
            ),
            parent=root,
        ):
            return
        try:
            info, changed = remove_patch(target)
        except Exception as exc:
            messagebox.showerror(_t("恢复失败", "Restore Error"), str(exc), parent=root)
            refresh()
            return
        refresh()
        message = _t("已恢复原始字节。", "The original bytes were restored.") if changed else _t(
            "目标已经是原始字节，无需修改。",
            "The target already contains the original bytes.",
        )
        messagebox.showinfo(_t("恢复完成", "Restore Complete"), f"{message}\n\n{info.state_text}", parent=root)

    refresh_button = ttk.Button(buttons, text=_t("重新检测", "Refresh"), command=refresh)
    refresh_button.pack(side="left")
    apply_button = ttk.Button(
        buttons, text=_t("应用永久补丁", "Apply Permanent Patch"), command=apply_from_gui
    )
    apply_button.pack(side="right")
    restore_button = ttk.Button(
        buttons, text=_t("关闭永久补丁", "Disable Permanent Patch"), command=restore_from_gui
    )
    restore_button.pack(side="right", padx=(0, 8))

    def update_static_language() -> None:
        root.title(_t("RE6 Render Everything EXE 永久补丁", APP_TITLE))
        title_label.configure(
            text=_t("RE6 Render Everything 永久补丁", "RE6 Render Everything Permanent Patch"),
            font=(UI_FONT, 16, "bold"),
        )
        subtitle_label.configure(
            text=_t(
                "仅修改 BH6.exe 中唯一匹配的控制流；游戏更新或验证文件后需要重新应用。",
                "Only a unique matching control flow in BH6.exe is changed; reapply after a game update or file verification.",
            )
        )
        status_label.configure(font=(UI_FONT, 12, "bold"))
        browse_button.configure(text=_t("选择…", "Browse..."))
        refresh_button.configure(text=_t("重新检测", "Refresh"))
        apply_button.configure(text=_t("应用永久补丁", "Apply Permanent Patch"))
        restore_button.configure(text=_t("关闭永久补丁", "Disable Permanent Patch"))
        zh_button.state(["disabled"] if UI_LANGUAGE == "zh" else ["!disabled"])
        en_button.state(["disabled"] if UI_LANGUAGE == "en" else ["!disabled"])

    def switch_language(language: str) -> None:
        _set_ui_language(language)
        update_static_language()
        refresh()

    zh_button.configure(command=lambda: switch_language("zh"))
    en_button.configure(command=lambda: switch_language("en"))
    update_static_language()

    root.after_idle(refresh)
    root.mainloop()
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Signature-checked permanent Render Everything patcher for RE6/BH6.exe."
    )
    parser.add_argument("--target", type=Path, default=None, help="Path to BH6.exe")
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--status", action="store_true", help="Inspect without writing")
    action.add_argument("--apply", action="store_true", help="Apply the permanent patch")
    action.add_argument("--restore", action="store_true", help="Restore the original instruction bytes")
    action.add_argument("--gui", action="store_true", help="Open the graphical interface")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    effective_argv = list(sys.argv[1:] if argv is None else argv)
    args = parser.parse_args(effective_argv)
    target = (args.target or _default_target()).expanduser()
    try:
        if args.apply:
            info, changed = apply_patch(target)
            print("PATCHED" if changed else "ALREADY_PATCHED")
            print(_format_inspection(info))
            return 0
        if args.restore:
            info, changed = remove_patch(target)
            print("RESTORED" if changed else "ALREADY_ORIGINAL")
            print(_format_inspection(info))
            return 0
        if args.status:
            print(_format_inspection(inspect_exe(target)))
            return 0
        _hide_console_window()
        if _relaunch_gui_with_pythonw(effective_argv):
            return 0
        return _run_gui(target)
    except PatcherError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
