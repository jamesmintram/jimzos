const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .uefi,
            .abi = .none,
        }),
        .optimize = .Debug,
    });

    const exe = b.addExecutable(.{
        .name = "BOOTAA64",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    // --- `zig build run`: boot the EFI app under QEMU with edk2 firmware. ---

    // AArch64 UEFI firmware (edk2). Defaults match Arch's `edk2-aarch64`
    // package; override with -Dovmf-code=... / -Dovmf-vars=... elsewhere.
    const ovmf_code = b.option(
        []const u8,
        "ovmf-code",
        "Path to the read-only UEFI firmware image (edk2 code)",
    ) orelse "/usr/share/edk2/aarch64/QEMU_EFI.fd";
    const ovmf_vars = b.option(
        []const u8,
        "ovmf-vars",
        "Path to the UEFI NVRAM vars template (copied to a writable image)",
    ) orelse "/usr/share/edk2/aarch64/QEMU_VARS.fd";

    // Stage an ESP the firmware auto-boots from: the AArch64 removable-media
    // default path is /EFI/BOOT/BOOTAA64.efi. QEMU serves zig-out/esp as a
    // virtual FAT volume (fat:rw:).
    const stage_esp = b.addSystemCommand(&.{ "install", "-D" });
    stage_esp.addArtifactArg(exe);
    stage_esp.addArg("zig-out/esp/EFI/BOOT/BOOTAA64.efi");

    // Fresh, writable copy of the NVRAM vars each run (firmware writes to it).
    const stage_vars = b.addSystemCommand(&.{ "install", "-Dm644", ovmf_vars, "zig-out/efi-vars.fd" });

    const run_qemu = b.addSystemCommand(&.{"qemu-system-aarch64"});
    run_qemu.addArgs(&.{
        "-machine",
        "virt",
        "-cpu",
        "cortex-a57",
        "-m",
        "256",
        "-nographic",
        "-drive",
        b.fmt("if=pflash,format=raw,readonly=on,file={s}", .{ovmf_code}),
        "-drive",
        "if=pflash,format=raw,file=zig-out/efi-vars.fd",
        "-drive",
        "file=fat:rw:zig-out/esp,format=raw,media=disk",
    });
    run_qemu.step.dependOn(&stage_esp.step);
    run_qemu.step.dependOn(&stage_vars.step);

    const run_step = b.step("run", "Boot the EFI app in QEMU");
    run_step.dependOn(&run_qemu.step);
}
