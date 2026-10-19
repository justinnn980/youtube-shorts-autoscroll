#!/usr/bin/env python3
"""
순정 YouTube.ipa 내부의 Mach-O 실행 바이너리에 YouTubeAutoShorts.dylib(LC_LOAD_DYLIB)을
직접 주입하여 단일 설치 파일(YouTube-AutoShorts.ipa)을 생성하는 스크립트.
"""
import os
import sys
import struct
import shutil
import zipfile
import plistlib
import subprocess

MH_MAGIC_64 = 0xFEEDFACF
LC_LOAD_DYLIB = 0x0000000C


def inject_lc_load_dylib(macho_path: str, dylib_install_name: str) -> None:
    with open(macho_path, "rb") as f:
        data = bytearray(f.read())

    magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack(
        "<IIIIIIII", data[:32]
    )
    if magic != MH_MAGIC_64:
        raise RuntimeError(f"Unsupported Mach-O magic: {hex(magic)} (expected 64-bit arm64 Mach-O)")

    name_bytes = dylib_install_name.encode("utf-8") + b"\x00"
    # 이미 주입되어 있는지 확인
    if name_bytes in data[32 : 32 + sizeofcmds]:
        print(f"[✓] 이미 {dylib_install_name} 이(가) 주입되어 있습니다.")
        return

    cmd_header_size = 24
    raw_size = cmd_header_size + len(name_bytes)
    # 8바이트 정렬
    cmdsize = (raw_size + 7) & ~7
    padding_len = cmdsize - raw_size

    lc_bytes = (
        struct.pack(
            "<IIIIII",
            LC_LOAD_DYLIB,
            cmdsize,
            cmd_header_size,  # name offset (24)
            2,                # timestamp
            0x00010000,       # current_version (1.0.0)
            0x00010000,       # compatibility_version (1.0.0)
        )
        + name_bytes
        + (b"\x00" * padding_len)
    )

    insert_offset = 32 + sizeofcmds
    # 헤더 패딩 영역이 비어 있는지 확인
    pad_slice = data[insert_offset : insert_offset + cmdsize]
    if any(b != 0 for b in pad_slice):
        raise RuntimeError("Mach-O header padding space is insufficient")

    data[insert_offset : insert_offset + cmdsize] = lc_bytes
    ncmds += 1
    sizeofcmds += cmdsize
    data[:32] = struct.pack(
        "<IIIIIIII", magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved
    )

    with open(macho_path, "wb") as f:
        f.write(data)
    print(f"[✓] Mach-O LC_LOAD_DYLIB 주입 완료: {dylib_install_name}")


def build_injected_ipa(input_ipa: str, dylib_path: str, output_ipa: str) -> None:
    work_dir = "/tmp/yt_autoshorts_ipa_work"
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    os.makedirs(work_dir, exist_ok=True)

    print(f"[1/4] {input_ipa} 압축 해제 중...")
    with zipfile.ZipFile(input_ipa, "r") as zf:
        zf.extractall(work_dir)

    payload_dir = os.path.join(work_dir, "Payload")
    app_dirs = [d for d in os.listdir(payload_dir) if d.endswith(".app")]
    if not app_dirs:
        raise RuntimeError("Payload/*.app 디렉토리를 찾을 수 없습니다.")
    app_dir = os.path.join(payload_dir, app_dirs[0])

    info_plist_path = os.path.join(app_dir, "Info.plist")
    with open(info_plist_path, "rb") as fp:
        info = plistlib.load(fp)
    exec_name = info.get("CFBundleExecutable", "YouTube")

    # 기존 앱스토어 YouTube(EQHXZ8M8AV.com.google.ios.youtube)와 절대 충돌하지 않도록 고유 Bundle ID 부여
    info["CFBundleIdentifier"] = "com.autoshorts.youtube.ios"
    info["CFBundleDisplayName"] = "YouTube"
    with open(info_plist_path, "wb") as fp:
        plistlib.dump(info, fp)

    exec_path = os.path.join(app_dir, exec_name)
    os.chmod(exec_path, 0o755)

    # PlugIns / Extensions / Watch 폴더 제거 -> MismatchedApplicationIdentifierEntitlement 완벽 방지
    for subdir in ("PlugIns", "Extensions", "Watch", "_CodeSignature"):
        p = os.path.join(app_dir, subdir)
        if os.path.exists(p):
            shutil.rmtree(p, ignore_errors=True)

    # Frameworks 폴더 및 앱 루트에 dylib 복사
    frameworks_dir = os.path.join(app_dir, "Frameworks")
    os.makedirs(frameworks_dir, exist_ok=True)
    dylib_name = os.path.basename(dylib_path)

    target_dylib_in_app = os.path.join(app_dir, dylib_name)
    target_dylib_in_fw = os.path.join(frameworks_dir, dylib_name)
    shutil.copy2(dylib_path, target_dylib_in_app)
    shutil.copy2(dylib_path, target_dylib_in_fw)

    print(f"[2/4] {exec_name} 바이너리에 {dylib_name} 주입 중...")
    inject_lc_load_dylib(exec_path, f"@executable_path/{dylib_name}")

    # otool 검증
    otool_out = subprocess.check_output(["otool", "-L", exec_path], text=True)
    if dylib_name not in otool_out:
        raise RuntimeError("otool 검증 실패: dylib이 로드 목록에 없습니다.")
    print(f"[3/4] otool 검증 통과! YouTube-AutoShorts.ipa 패키징 중...")

    if os.path.exists(output_ipa):
        os.remove(output_ipa)

    with zipfile.ZipFile(output_ipa, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for root, dirs, files in os.walk(work_dir):
            for file in files:
                abs_path = os.path.join(root, file)
                rel_path = os.path.relpath(abs_path, work_dir)
                zout.write(abs_path, rel_path)

    shutil.rmtree(work_dir, ignore_errors=True)
    print(f"[4/4] 완성! 생성된 설치 파일: {output_ipa}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: inject_ipa.py <input.ipa> <tweak.dylib> <output.ipa>")
        sys.exit(1)
    build_injected_ipa(sys.argv[1], sys.argv[2], sys.argv[3])

