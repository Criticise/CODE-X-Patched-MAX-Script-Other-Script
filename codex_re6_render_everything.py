# -*- coding: utf-8 -*-
"""Strict runtime-only Render Everything switch for Resident Evil 6."""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import subprocess
import sys
import time
from contextlib import contextmanager
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterator


PROCESS_NAME = "BH6.exe"
SUPPORTED_FILE_VERSION = "1.0.6.165"
SUPPORTED_FILE_SIZE = 20_871_736
SUPPORTED_SHA256 = "72B52D06A1C878A6D66701B192A47557BD844A0473D6F3CAFB0C736144235F74"


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

PATCH_RVA = 0x00BE4254
PATCH_OFF_OPCODE = 0x75  # jne +0x18
PATCH_ON_OPCODE = 0xEB   # jmp +0x18
INDEPENDENT_PATCH_RVA = 0x00BE4256
INDEPENDENT_PATCH_OFF = bytes.fromhex("8B 0D")
INDEPENDENT_PATCH_ON = bytes.fromhex("EB 16")
PATCH_CONTEXT_PREFIX_SIZE = 16
PATCH_CONTEXT_OFF = bytes.fromhex(
    "00 00 A8 01 74 24 F7 87 28 01 00 00 00 00 00 80 "
    "75 18 8B 0D BC 48 86 01 80 B9 71 01 00 00 00 75 02"
)
PATCH_CONTEXT_ON = bytes.fromhex(
    "00 00 A8 01 74 24 F7 87 28 01 00 00 00 00 00 80 "
    "EB 18 8B 0D BC 48 86 01 80 B9 71 01 00 00 00 75 02"
)


class RenderEverythingError(RuntimeError):
    pass


class GameNotRunningError(RenderEverythingError):
    pass


class MultipleGameProcessesError(RenderEverythingError):
    pass


class UnsupportedGameError(RenderEverythingError):
    pass


class PatchConflictError(RenderEverythingError):
    pass


class ProcessAccessError(RenderEverythingError):
    pass


def _localized_runtime_error(error: BaseException) -> str:
    if UI_LANGUAGE != "zh":
        return str(error)
    if isinstance(error, GameNotRunningError):
        summary = "未检测到正在运行的 BH6.exe。"
    elif isinstance(error, MultipleGameProcessesError):
        summary = "检测到多个 BH6.exe 进程，请使用 --pid 指定目标。"
    elif isinstance(error, UnsupportedGameError):
        summary = "当前 BH6.exe 与内存工具已验证的 1.0.6.165 文件不一致，未修改内存。"
    elif isinstance(error, PatchConflictError):
        summary = "Render Everything 指令与已验证签名不一致，未修改内存。"
    elif isinstance(error, ProcessAccessError):
        summary = "无法访问 BH6.exe，请让此工具与游戏使用相同的管理员权限。"
    else:
        summary = "操作失败。"
    return f"{summary}\n\n技术详情：{error}"


@dataclass(frozen=True)
class ModuleInfo:
    pid: int
    name: str
    path: str
    base_address: int
    image_size: int


@dataclass(frozen=True)
class RenderEverythingStatus:
    pid: int
    process: str
    executable_path: str
    file_version: str
    file_sha256: str
    module_base: str
    patch_rva: str
    patch_address: str
    opcode: str
    independent_patch_address: str
    independent_opcode: str
    enabled_sources: tuple[str, ...]
    enabled: bool


@dataclass(frozen=True)
class PatchResult:
    changed: bool
    method: str
    status: RenderEverythingStatus


if os.name == "nt":
    from ctypes import wintypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    TH32CS_SNAPPROCESS = 0x00000002
    TH32CS_SNAPMODULE = 0x00000008
    TH32CS_SNAPMODULE32 = 0x00000010
    ERROR_BAD_LENGTH = 24
    ERROR_ACCESS_DENIED = 5
    INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

    PROCESS_VM_OPERATION = 0x0008
    PROCESS_VM_READ = 0x0010
    PROCESS_VM_WRITE = 0x0020
    PROCESS_QUERY_INFORMATION = 0x0400
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    PAGE_EXECUTE_READWRITE = 0x40

    MAX_PATH = 260
    MAX_MODULE_NAME32 = 255
    ULONG_PTR = ctypes.c_size_t

    class PROCESSENTRY32W(ctypes.Structure):
        _fields_ = [
            ("dwSize", wintypes.DWORD),
            ("cntUsage", wintypes.DWORD),
            ("th32ProcessID", wintypes.DWORD),
            ("th32DefaultHeapID", ULONG_PTR),
            ("th32ModuleID", wintypes.DWORD),
            ("cntThreads", wintypes.DWORD),
            ("th32ParentProcessID", wintypes.DWORD),
            ("pcPriClassBase", wintypes.LONG),
            ("dwFlags", wintypes.DWORD),
            ("szExeFile", wintypes.WCHAR * MAX_PATH),
        ]

    class MODULEENTRY32W(ctypes.Structure):
        _fields_ = [
            ("dwSize", wintypes.DWORD),
            ("th32ModuleID", wintypes.DWORD),
            ("th32ProcessID", wintypes.DWORD),
            ("GlblcntUsage", wintypes.DWORD),
            ("ProccntUsage", wintypes.DWORD),
            ("modBaseAddr", ctypes.POINTER(ctypes.c_ubyte)),
            ("modBaseSize", wintypes.DWORD),
            ("hModule", wintypes.HMODULE),
            ("szModule", wintypes.WCHAR * (MAX_MODULE_NAME32 + 1)),
            ("szExePath", wintypes.WCHAR * MAX_PATH),
        ]

    kernel32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    kernel32.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    kernel32.Process32FirstW.restype = wintypes.BOOL
    kernel32.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    kernel32.Process32NextW.restype = wintypes.BOOL
    kernel32.Module32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(MODULEENTRY32W)]
    kernel32.Module32FirstW.restype = wintypes.BOOL
    kernel32.Module32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(MODULEENTRY32W)]
    kernel32.Module32NextW.restype = wintypes.BOOL
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.ReadProcessMemory.argtypes = [
        wintypes.HANDLE,
        wintypes.LPCVOID,
        wintypes.LPVOID,
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_size_t),
    ]
    kernel32.ReadProcessMemory.restype = wintypes.BOOL
    kernel32.WriteProcessMemory.argtypes = [
        wintypes.HANDLE,
        wintypes.LPVOID,
        wintypes.LPCVOID,
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_size_t),
    ]
    kernel32.WriteProcessMemory.restype = wintypes.BOOL
    kernel32.VirtualProtectEx.argtypes = [
        wintypes.HANDLE,
        wintypes.LPVOID,
        ctypes.c_size_t,
        wintypes.DWORD,
        ctypes.POINTER(wintypes.DWORD),
    ]
    kernel32.VirtualProtectEx.restype = wintypes.BOOL
    kernel32.FlushInstructionCache.argtypes = [wintypes.HANDLE, wintypes.LPCVOID, ctypes.c_size_t]
    kernel32.FlushInstructionCache.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL

    shell32 = ctypes.WinDLL("shell32", use_last_error=True)
    shell32.IsUserAnAdmin.argtypes = []
    shell32.IsUserAnAdmin.restype = wintypes.BOOL
    shell32.ShellExecuteW.argtypes = [
        wintypes.HWND,
        wintypes.LPCWSTR,
        wintypes.LPCWSTR,
        wintypes.LPCWSTR,
        wintypes.LPCWSTR,
        ctypes.c_int,
    ]
    shell32.ShellExecuteW.restype = wintypes.HINSTANCE


_hash_cache: dict[tuple[str, int, int], str] = {}


def _require_windows() -> None:
    if os.name != "nt":
        raise RenderEverythingError("This tool only supports Windows.")


def _is_administrator() -> bool:
    _require_windows()
    return bool(shell32.IsUserAnAdmin())


def _relaunch_gui_as_administrator(argv: list[str]) -> bool:
    if _is_administrator():
        return False
    executable = Path(sys.executable)
    pythonw = executable.with_name("pythonw.exe")
    if pythonw.is_file():
        executable = pythonw
    script = str(Path(__file__).resolve())
    parameters = subprocess.list2cmdline([script, *argv])
    raw_result = shell32.ShellExecuteW(
        None,
        "runas",
        str(executable),
        parameters,
        str(Path(__file__).resolve().parent),
        1,
    )
    result = int(raw_result or 0)
    if result <= 32:
        raise ProcessAccessError(
            f"Unable to start the GUI as administrator (ShellExecuteW result {result})."
        )
    return True


def _winerror(prefix: str) -> ProcessAccessError:
    code = ctypes.get_last_error()
    detail = ctypes.FormatError(code).strip() if code else "unknown Windows error"
    if code == ERROR_ACCESS_DENIED:
        detail += "; run this script at the same privilege level as BH6.exe"
    return ProcessAccessError(f"{prefix} (WinError {code}: {detail})")


def _close_handle(handle: int) -> None:
    if handle and handle != INVALID_HANDLE_VALUE:
        kernel32.CloseHandle(handle)


def _snapshot(flags: int, pid: int = 0) -> int:
    for _ in range(8):
        ctypes.set_last_error(0)
        handle = kernel32.CreateToolhelp32Snapshot(flags, pid)
        if handle != INVALID_HANDLE_VALUE:
            return handle
        if ctypes.get_last_error() != ERROR_BAD_LENGTH:
            break
    raise _winerror("Unable to enumerate Windows processes or modules")


def _find_processes_by_name(process_name: str) -> list[int]:
    _require_windows()
    snapshot = _snapshot(TH32CS_SNAPPROCESS)
    try:
        entry = PROCESSENTRY32W()
        entry.dwSize = ctypes.sizeof(entry)
        found: list[int] = []
        if kernel32.Process32FirstW(snapshot, ctypes.byref(entry)):
            while True:
                if entry.szExeFile.casefold() == process_name.casefold():
                    found.append(int(entry.th32ProcessID))
                if not kernel32.Process32NextW(snapshot, ctypes.byref(entry)):
                    break
        return sorted(found)
    finally:
        _close_handle(snapshot)


def find_game_processes() -> list[int]:
    return _find_processes_by_name(PROCESS_NAME)


def _resolve_pid(pid: int | None) -> int:
    candidates = find_game_processes()
    if pid is not None:
        if pid not in candidates:
            raise GameNotRunningError(f"PID {pid} is not a running {PROCESS_NAME} process.")
        return pid
    if not candidates:
        raise GameNotRunningError(f"{PROCESS_NAME} is not running.")
    if len(candidates) > 1:
        joined = ", ".join(str(value) for value in candidates)
        raise MultipleGameProcessesError(
            f"Multiple {PROCESS_NAME} processes are running ({joined}); select one with --pid."
        )
    return candidates[0]


def _main_module(pid: int, module_name: str = PROCESS_NAME) -> ModuleInfo:
    snapshot = _snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid)
    try:
        entry = MODULEENTRY32W()
        entry.dwSize = ctypes.sizeof(entry)
        if not kernel32.Module32FirstW(snapshot, ctypes.byref(entry)):
            raise _winerror(f"Unable to read modules for PID {pid}")
        while True:
            if entry.szModule.casefold() == module_name.casefold():
                base = ctypes.cast(entry.modBaseAddr, ctypes.c_void_p).value
                if not base:
                    raise ProcessAccessError(f"{module_name} returned an invalid module base address.")
                return ModuleInfo(
                    pid=pid,
                    name=str(entry.szModule),
                    path=str(entry.szExePath),
                    base_address=int(base),
                    image_size=int(entry.modBaseSize),
                )
            if not kernel32.Module32NextW(snapshot, ctypes.byref(entry)):
                break
    finally:
        _close_handle(snapshot)
    raise UnsupportedGameError(f"PID {pid} does not contain a {module_name} module.")


def _file_sha256(path: Path) -> str:
    stat = path.stat()
    key = (str(path.resolve()).casefold(), int(stat.st_size), int(stat.st_mtime_ns))
    cached = _hash_cache.get(key)
    if cached is not None:
        return cached
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    result = digest.hexdigest().upper()
    _hash_cache.clear()
    _hash_cache[key] = result
    return result


def _verify_file_identity(
    module: ModuleInfo,
    *,
    process_name: str,
    file_version: str,
    file_size: int,
    sha256: str,
) -> str:
    path = Path(module.path)
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise UnsupportedGameError(f"Unable to inspect {path}: {exc}") from exc
    if size != file_size:
        raise UnsupportedGameError(
            f"Unsupported {process_name} size {size}; expected {file_size} "
            f"for version {file_version}."
        )
    digest = _file_sha256(path)
    if digest != sha256:
        raise UnsupportedGameError(
            f"Unsupported {process_name} SHA-256 {digest}; expected {sha256} "
            f"for version {file_version}."
        )
    return digest


def _verify_module(module: ModuleInfo) -> str:
    digest = _verify_file_identity(
        module,
        process_name=PROCESS_NAME,
        file_version=SUPPORTED_FILE_VERSION,
        file_size=SUPPORTED_FILE_SIZE,
        sha256=SUPPORTED_SHA256,
    )
    if module.image_size <= PATCH_RVA:
        raise UnsupportedGameError(
            f"The loaded image is too small for patch RVA 0x{PATCH_RVA:08X}."
        )
    return digest


@contextmanager
def _open_process(pid: int, *, writable: bool) -> Iterator[int]:
    access = PROCESS_QUERY_INFORMATION | PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ
    if writable:
        access |= PROCESS_VM_OPERATION | PROCESS_VM_WRITE
    ctypes.set_last_error(0)
    handle = kernel32.OpenProcess(access, False, pid)
    if not handle:
        raise _winerror(f"Unable to open {PROCESS_NAME} PID {pid}")
    try:
        yield handle
    finally:
        _close_handle(handle)


def _read_memory(handle: int, address: int, size: int) -> bytes:
    buffer = ctypes.create_string_buffer(size)
    read = ctypes.c_size_t()
    ctypes.set_last_error(0)
    ok = kernel32.ReadProcessMemory(
        handle,
        ctypes.c_void_p(address),
        buffer,
        size,
        ctypes.byref(read),
    )
    if not ok or read.value != size:
        raise _winerror(f"Unable to read {size} byte(s) at 0x{address:08X}")
    return buffer.raw


def _decode_context(context: bytes) -> tuple[bool, bool, tuple[str, ...]]:
    primary = context[PATCH_CONTEXT_PREFIX_SIZE:PATCH_CONTEXT_PREFIX_SIZE + 2]
    independent = context[PATCH_CONTEXT_PREFIX_SIZE + 2:PATCH_CONTEXT_PREFIX_SIZE + 4]
    normalized = bytearray(context)
    if len(normalized) == len(PATCH_CONTEXT_OFF):
        normalized[PATCH_CONTEXT_PREFIX_SIZE:PATCH_CONTEXT_PREFIX_SIZE + 4] = (
            PATCH_CONTEXT_OFF[PATCH_CONTEXT_PREFIX_SIZE:PATCH_CONTEXT_PREFIX_SIZE + 4]
        )
    primary_on = primary == bytes((PATCH_ON_OPCODE, 0x18))
    primary_off = primary == bytes((PATCH_OFF_OPCODE, 0x18))
    independent_on = independent == INDEPENDENT_PATCH_ON
    independent_off = independent == INDEPENDENT_PATCH_OFF
    if bytes(normalized) == PATCH_CONTEXT_OFF and (primary_on or primary_off) and (
        independent_on or independent_off
    ):
        sources: list[str] = []
        if primary_on:
            sources.append("primary")
        if independent_on:
            sources.append("independent")
        return primary_on, independent_on, tuple(sources)
    raise PatchConflictError(
        "The Render Everything instruction no longer matches the verified signature; "
        f"no memory was changed. Current bytes: {context.hex(' ').upper()}"
    )


def _context_state(context: bytes) -> bool:
    primary_on, independent_on, _sources = _decode_context(context)
    return primary_on or independent_on


def _make_status(
    module: ModuleInfo,
    digest: str,
    context: bytes,
) -> RenderEverythingStatus:
    enabled = _context_state(context)
    _primary_on, _independent_on, sources = _decode_context(context)
    address = module.base_address + PATCH_RVA
    independent_address = module.base_address + INDEPENDENT_PATCH_RVA
    opcode = context[PATCH_CONTEXT_PREFIX_SIZE]
    independent = context[PATCH_CONTEXT_PREFIX_SIZE + 2:PATCH_CONTEXT_PREFIX_SIZE + 4]
    return RenderEverythingStatus(
        pid=module.pid,
        process=module.name,
        executable_path=module.path,
        file_version=SUPPORTED_FILE_VERSION,
        file_sha256=digest,
        module_base=f"0x{module.base_address:08X}",
        patch_rva=f"0x{PATCH_RVA:08X}",
        patch_address=f"0x{address:08X}",
        opcode=f"0x{opcode:02X}",
        independent_patch_address=f"0x{independent_address:08X}",
        independent_opcode=f"0x{independent.hex().upper()}",
        enabled_sources=sources,
        enabled=enabled,
    )


def get_render_everything_status(pid: int | None = None) -> RenderEverythingStatus:
    """Return the live, strictly verified Render Everything state."""
    _require_windows()
    resolved_pid = _resolve_pid(pid)
    module = _main_module(resolved_pid)
    digest = _verify_module(module)
    address = module.base_address + PATCH_RVA
    context_address = address - PATCH_CONTEXT_PREFIX_SIZE
    with _open_process(resolved_pid, writable=False) as handle:
        context = _read_memory(handle, context_address, len(PATCH_CONTEXT_OFF))
    return _make_status(module, digest, context)


def _write_patch(handle: int, address: int, data: bytes) -> None:
    if not data:
        raise ValueError("Patch data must not be empty.")
    size = len(data)
    old_protect = wintypes.DWORD()
    ctypes.set_last_error(0)
    if not kernel32.VirtualProtectEx(
        handle,
        ctypes.c_void_p(address),
        size,
        PAGE_EXECUTE_READWRITE,
        ctypes.byref(old_protect),
    ):
        raise _winerror(f"Unable to change memory protection at 0x{address:08X}")

    write_error: ProcessAccessError | None = None
    restore_error: ProcessAccessError | None = None
    try:
        value = (ctypes.c_ubyte * size).from_buffer_copy(data)
        written = ctypes.c_size_t()
        ctypes.set_last_error(0)
        if not kernel32.WriteProcessMemory(
            handle,
            ctypes.c_void_p(address),
            ctypes.byref(value),
            size,
            ctypes.byref(written),
        ) or written.value != size:
            write_error = _winerror(f"Unable to write {size} byte(s) at 0x{address:08X}")
        elif not kernel32.FlushInstructionCache(handle, ctypes.c_void_p(address), size):
            write_error = _winerror(f"Unable to flush the instruction cache at 0x{address:08X}")
    finally:
        ignored = wintypes.DWORD()
        ctypes.set_last_error(0)
        if not kernel32.VirtualProtectEx(
            handle,
            ctypes.c_void_p(address),
            size,
            old_protect.value,
            ctypes.byref(ignored),
        ):
            restore_error = _winerror(f"Unable to restore memory protection at 0x{address:08X}")

    if write_error is not None:
        raise write_error
    if restore_error is not None:
        raise restore_error


def set_render_everything(enabled: bool, pid: int | None = None) -> PatchResult:
    """Enable or disable the runtime patch without modifying BH6.exe on disk."""
    _require_windows()
    resolved_pid = _resolve_pid(pid)
    module = _main_module(resolved_pid)
    digest = _verify_module(module)
    address = module.base_address + PATCH_RVA
    independent_address = module.base_address + INDEPENDENT_PATCH_RVA
    context_address = address - PATCH_CONTEXT_PREFIX_SIZE
    with _open_process(resolved_pid, writable=True) as handle:
        before = _read_memory(handle, context_address, len(PATCH_CONTEXT_OFF))
        primary_on, independent_on, _sources = _decode_context(before)

        if enabled:
            if independent_on:
                return PatchResult(False, "direct_memory", _make_status(module, digest, before))
            try:
                _write_patch(handle, independent_address, INDEPENDENT_PATCH_ON)
                after = _read_memory(handle, context_address, len(PATCH_CONTEXT_OFF))
                _primary_after, independent_after, _sources = _decode_context(after)
                if not independent_after:
                    raise PatchConflictError("The independent BH6.exe jump was not installed.")
                time.sleep(0.35)
                settled = _read_memory(handle, context_address, len(PATCH_CONTEXT_OFF))
                _primary_settled, independent_settled, _sources = _decode_context(settled)
                if not independent_settled:
                    raise PatchConflictError("The independent BH6.exe jump did not remain installed.")
            except RenderEverythingError:
                try:
                    _write_patch(handle, independent_address, INDEPENDENT_PATCH_OFF)
                except RenderEverythingError:
                    pass
                raise
            return PatchResult(True, "direct_memory", _make_status(module, digest, settled))

        changed = independent_on or primary_on
        if not changed:
            return PatchResult(False, "direct_memory", _make_status(module, digest, before))
        if independent_on:
            _write_patch(handle, independent_address, INDEPENDENT_PATCH_OFF)
        if primary_on:
            _write_patch(handle, address, bytes((PATCH_OFF_OPCODE,)))
        settled = _read_memory(handle, context_address, len(PATCH_CONTEXT_OFF))
        _primary_settled, independent_settled, _sources = _decode_context(settled)
        if independent_settled:
            raise PatchConflictError("The independent BH6.exe jump was not removed.")

    return PatchResult(changed, "direct_memory", _make_status(module, digest, settled))


def toggle_render_everything(pid: int | None = None) -> PatchResult:
    status = get_render_everything_status(pid)
    return set_render_everything(not status.enabled, status.pid)


def _status_payload(status: RenderEverythingStatus) -> dict[str, object]:
    return asdict(status)


def _result_payload(result: PatchResult) -> dict[str, object]:
    return {
        "changed": result.changed,
        "method": result.method,
        "status": _status_payload(result.status),
    }


def _print_human(status: RenderEverythingStatus, *, changed: bool | None = None) -> None:
    state = "ON" if status.enabled else "OFF"
    prefix = "changed" if changed else "unchanged" if changed is False else "status"
    print(
        f"Render Everything: {state} ({prefix})\n"
        f"BH6.exe PID: {status.pid}\n"
        f"Address: {status.patch_address} [RVA {status.patch_rva}]\n"
        f"Primary opcode: {status.opcode}\n"
        f"Independent opcode: {status.independent_opcode}\n"
        f"Disk file: {status.executable_path}\n"
        "Disk modification: none"
    )


def _run_gui(pid: int | None) -> int:
    try:
        import tkinter as tk
        from tkinter import messagebox, ttk
    except ImportError as exc:
        raise RenderEverythingError(
            _t(
                "当前 Python 无法使用 Tkinter，请改用 status/on/off/toggle 命令。",
                "Tkinter is unavailable; use the status/on/off/toggle CLI actions.",
            )
        ) from exc

    root = tk.Tk()
    root.withdraw()
    root.title(_t("RE6 Render Everything 内存开关", "RE6 Render Everything"))
    root.resizable(False, False)
    root.option_add("*Font", (UI_FONT, 9))

    frame = ttk.Frame(root, padding=16)
    frame.grid(row=0, column=0, sticky="nsew")
    title = ttk.Label(
        frame,
        text=_t("Resident Evil 6 - Render Everything 内存开关", "Resident Evil 6 - Render Everything"),
        font=(UI_FONT, 12, "bold"),
    )
    title.grid(row=0, column=0, columnspan=2, sticky="w")

    language_frame = ttk.Frame(frame)
    language_frame.grid(row=0, column=2, sticky="e")
    zh_button = ttk.Button(language_frame, text="中文", width=7)
    en_button = ttk.Button(language_frame, text="English", width=8)
    zh_button.pack(side="left", padx=(0, 4))
    en_button.pack(side="left")

    state_var = tk.StringVar(value=_t("正在检测 BH6.exe……", "Checking BH6.exe..."))
    detail_var = tk.StringVar(value="")
    state_label = ttk.Label(frame, textvariable=state_var, font=(UI_FONT, 11, "bold"))
    state_label.grid(
        row=1, column=0, columnspan=3, sticky="w", pady=(12, 2)
    )
    ttk.Label(frame, textvariable=detail_var, justify="left").grid(
        row=2, column=0, columnspan=3, sticky="w", pady=(0, 12)
    )

    enable_button = tk.Button(
        frame, text=_t("开启", "Enable"), width=13, font=(UI_FONT, 9, "bold")
    )
    disable_button = tk.Button(
        frame, text=_t("关闭", "Disable"), width=13, font=(UI_FONT, 9, "bold")
    )
    refresh_button = ttk.Button(frame, text=_t("刷新", "Refresh"))
    enable_button.grid(row=3, column=0, padx=(0, 8), sticky="ew")
    disable_button.grid(row=3, column=1, padx=(0, 8), sticky="ew")
    refresh_button.grid(row=3, column=2, sticky="ew")
    footer_label = ttk.Label(
        frame,
        text=_t(
            "仅修改运行时内存，绝不修改磁盘上的 BH6.exe。",
            "Runtime memory only. BH6.exe on disk is never modified.",
        ),
    )
    footer_label.grid(
        row=4, column=0, columnspan=3, sticky="w", pady=(12, 0)
    )
    for column in range(3):
        frame.columnconfigure(column, weight=1)

    refresh_job: str | None = None

    def show_status() -> None:
        nonlocal refresh_job
        if refresh_job is not None:
            try:
                root.after_cancel(refresh_job)
            except tk.TclError:
                pass
            refresh_job = None
        try:
            status = get_render_everything_status(pid)
        except RenderEverythingError as exc:
            state_var.set(_t("BH6.exe 不可用", "BH6.exe unavailable"))
            detail_var.set(_localized_runtime_error(exc))
            for button in (enable_button, disable_button):
                button.configure(
                    state=tk.DISABLED,
                    bg="#D1D5DB",
                    fg="#6B7280",
                    disabledforeground="#6B7280",
                    relief=tk.RAISED,
                )
        else:
            state_var.set(
                _t(
                    f"Render Everything：{'已开启' if status.enabled else '已关闭'}",
                    f"Render Everything: {'ON' if status.enabled else 'OFF'}",
                )
            )
            detail_var.set(
                f"PID {status.pid}    primary {status.opcode}    independent {status.independent_opcode}\n"
                + _t(
                    f"已验证 BH6.exe {status.file_version}",
                    f"Verified BH6.exe {status.file_version}",
                )
            )
            if status.enabled:
                enable_button.configure(
                    text=_t("开启（当前已开）", "Enable (ON)"),
                    state=tk.DISABLED,
                    bg="#178447",
                    fg="white",
                    disabledforeground="white",
                    relief=tk.SUNKEN,
                )
                disable_button.configure(
                    text=_t("关闭", "Disable"),
                    state=tk.NORMAL,
                    bg="#E5E7EB",
                    fg="#111827",
                    activebackground="#D1D5DB",
                    relief=tk.RAISED,
                )
            else:
                enable_button.configure(
                    text=_t("开启", "Enable"),
                    state=tk.NORMAL,
                    bg="#E5E7EB",
                    fg="#111827",
                    activebackground="#D1D5DB",
                    relief=tk.RAISED,
                )
                disable_button.configure(
                    text=_t("关闭（当前已关）", "Disable (OFF)"),
                    state=tk.DISABLED,
                    bg="#B53A3A",
                    fg="white",
                    disabledforeground="white",
                    relief=tk.SUNKEN,
                )
        refresh_job = root.after(1000, show_status)

    def apply(enabled: bool) -> None:
        try:
            set_render_everything(enabled, pid)
        except RenderEverythingError as exc:
            messagebox.showerror(
                _t("Render Everything 操作失败", "Render Everything Error"),
                _localized_runtime_error(exc),
                parent=root,
            )
        show_status()

    def update_static_language() -> None:
        root.title(_t("RE6 Render Everything 内存开关", "RE6 Render Everything"))
        title.configure(
            text=_t(
                "Resident Evil 6 - Render Everything 内存开关",
                "Resident Evil 6 - Render Everything",
            ),
            font=(UI_FONT, 12, "bold"),
        )
        state_label.configure(font=(UI_FONT, 11, "bold"))
        enable_button.configure(text=_t("开启", "Enable"), font=(UI_FONT, 9, "bold"))
        disable_button.configure(text=_t("关闭", "Disable"), font=(UI_FONT, 9, "bold"))
        refresh_button.configure(text=_t("刷新", "Refresh"))
        footer_label.configure(
            text=_t(
                "仅修改运行时内存，绝不修改磁盘上的 BH6.exe。",
                "Runtime memory only. BH6.exe on disk is never modified.",
            )
        )
        zh_button.state(["disabled"] if UI_LANGUAGE == "zh" else ["!disabled"])
        en_button.state(["disabled"] if UI_LANGUAGE == "en" else ["!disabled"])

    def switch_language(language: str) -> None:
        _set_ui_language(language)
        update_static_language()
        show_status()

    enable_button.configure(command=lambda: apply(True))
    disable_button.configure(command=lambda: apply(False))
    refresh_button.configure(command=show_status)
    zh_button.configure(command=lambda: switch_language("zh"))
    en_button.configure(command=lambda: switch_language("en"))

    update_static_language()
    show_status()
    root.update_idletasks()
    width = root.winfo_reqwidth()
    height = root.winfo_reqheight()
    x = max(0, (root.winfo_screenwidth() - width) // 2)
    y = max(0, (root.winfo_screenheight() - height) // 2)
    root.geometry(f"{width}x{height}+{x}+{y}")
    root.deiconify()
    root.mainloop()
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Strict runtime-only Render Everything switch for Resident Evil 6 "
            f"BH6.exe {SUPPORTED_FILE_VERSION}."
        )
    )
    parser.add_argument(
        "action",
        nargs="?",
        default="gui",
        choices=("gui", "status", "on", "off", "toggle"),
        help="Action to perform; the default is gui.",
    )
    parser.add_argument("--pid", type=int, help="Target a specific BH6.exe PID.")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON for CLI actions.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    effective_argv = list(sys.argv[1:] if argv is None else argv)
    args = parser.parse_args(effective_argv)
    if args.pid is not None and args.pid <= 0:
        parser.error("--pid must be greater than zero")
    if args.action == "gui":
        if args.json:
            parser.error("--json cannot be used with gui")
        _hide_console_window()
        if _relaunch_gui_as_administrator(effective_argv):
            return 0
        if _relaunch_gui_with_pythonw(effective_argv):
            return 0
        return _run_gui(args.pid)

    try:
        if args.action == "status":
            status = get_render_everything_status(args.pid)
            if args.json:
                print(json.dumps(_status_payload(status), ensure_ascii=False, indent=2))
            else:
                _print_human(status)
            return 0

        if args.action == "on":
            result = set_render_everything(True, args.pid)
        elif args.action == "off":
            result = set_render_everything(False, args.pid)
        else:
            result = toggle_render_everything(args.pid)
        if args.json:
            print(json.dumps(_result_payload(result), ensure_ascii=False, indent=2))
        else:
            _print_human(result.status, changed=result.changed)
        return 0
    except RenderEverythingError as exc:
        if args.json:
            print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False, indent=2))
        else:
            print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
