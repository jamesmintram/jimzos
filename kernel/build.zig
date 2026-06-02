const std = @import("std");

// NOTE: The `struct_defs_*.h` headers under src/arch/aarch64 are consumed by
// context.S (struct field offsets for the assembly context switch). They used
// to be regenerated here from @typeInfo(Thread)/@typeInfo(CPUFrame) at build
// time, but the std file-writing API now requires an async `Io` instance which
// is awkward to obtain in a build script. The headers are committed and the
// Thread/CPUFrame layouts are stable; regenerate them by hand if those structs
// change.

pub fn build(b: *std.Build) void {
    const want_gdb = b.option(bool, "gdb", "Build for QEMU gdb server") orelse false;

    const optimize = b.standardOptimizeOption(.{});

    // Freestanding aarch64 with FP/SIMD disabled (the -mgeneral-regs-only
    // equivalent). Kernel code is integer-only — like Linux/BSD, the kernel
    // never touches the V-registers, so it needn't save/restore them and the
    // compiler can't emit SIMD for memcpy/std.fmt. FP for EL0 will be managed
    // per-thread once userspace exists.
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .freestanding,
        .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.generic },
        .cpu_features_sub = std.Target.aarch64.featureSet(&.{ .neon, .fp_armv8 }),
    });

    // boot1_phys (the physical, MMU-off bring-up) is built as its own static
    // library so it gets its own root source file (linksection(".text.boot")
    // entry point).
    const boot1_phys_mod = b.createModule(.{
        .root_source_file = b.path("src/arch/aarch64/boot1_phys.zig"),
        .target = target,
        .optimize = optimize,
        // No .eh_frame: the kernel runs at VA 0xFFFF…, but .text.boot links at a
        // low physical address, so unwind-table PREL32 relocations overflow.
        .unwind_tables = .none,
    });
    const lib_boot1_phys = b.addLibrary(.{
        .name = "boot1_phys",
        .linkage = .static,
        .root_module = boot1_phys_mod,
    });

    const ext2_mod = b.createModule(.{
        .root_source_file = b.path("../libs/ext2/ext2.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/kernel.zig"),
        .target = target,
        .optimize = optimize,
        .unwind_tables = .none,
    });
    exe_mod.addImport("ext2", ext2_mod);

    exe_mod.addAssemblyFile(b.path("src/arch/aarch64/boot0_entry.S"));
    exe_mod.addAssemblyFile(b.path("src/arch/aarch64/exception.S"));
    exe_mod.addAssemblyFile(b.path("src/arch/aarch64/context.S"));

    exe_mod.linkLibrary(lib_boot1_phys);

    const exe = b.addExecutable(.{
        .name = "kernel8.elf",
        .root_module = exe_mod,
    });
    exe.setLinkerScript(b.path("src/arch/aarch64/linker.ld"));
    // Match the linker script's ENTRY(__start); otherwise lld defaults to
    // looking for `_start` and warns it cannot find the entry symbol.
    exe.entry = .{ .symbol_name = "__start" };

    b.installArtifact(exe);

    // Dump a flat binary + symbol files from the linked ELF.
    const run_objcopy = b.addSystemCommand(&[_][]const u8{"llvm-objcopy"});
    run_objcopy.addArtifactArg(exe);
    run_objcopy.addArgs(&[_][]const u8{ "-O", "binary", "zig-out/bin/kernel8" });

    const run_create_syms = b.addSystemCommand(&[_][]const u8{"./post.sh"});
    run_create_syms.addArtifactArg(exe);

    const dump_step = b.step("dump", "Dump symbols");
    dump_step.dependOn(&exe.step);
    dump_step.dependOn(&run_objcopy.step);
    dump_step.dependOn(&run_create_syms.step);

    // Compile the device tree (../dts/jimzos.dts -> zig-out/jimzos.dtb) with the
    // system `dtc`. Kept as its own step so a plain kernel build does not need
    // `dtc` on PATH; run with `zig build dtb`. The blob will be handed to the
    // kernel via QEMU's `-dtb` (x0 = blob address) as a follow-up.
    const run_dtc = b.addSystemCommand(&[_][]const u8{ "dtc", "-I", "dts", "-O", "dtb", "-o" });
    const dtb_file = run_dtc.addOutputFileArg("jimzos.dtb");
    run_dtc.addFileArg(b.path("../dts/jimzos.dts"));

    const install_dtb = b.addInstallFile(dtb_file, "jimzos.dtb");

    const dtb_step = b.step("dtb", "Compile the device tree (dts -> dtb)");
    dtb_step.dependOn(&install_dtb.step);

    // The default `zig build` produces the ELF, the flat binary and the dumps.
    b.getInstallStep().dependOn(&run_objcopy.step);
    b.getInstallStep().dependOn(&run_create_syms.step);

    // Run the kernel under QEMU.
    const run_qemu = b.addSystemCommand(&[_][]const u8{"qemu-system-aarch64"});
    run_qemu.addArg("-kernel");
    run_qemu.addArtifactArg(exe);
    run_qemu.addArgs(&[_][]const u8{
        "-m",         "1024",
        "-M",         "raspi3b",
        "-nographic", "-semihosting",
    });
    if (want_gdb) {
        run_qemu.addArgs(&[_][]const u8{ "-S", "-s" });
    }

    run_qemu.addArgs(&[_][]const u8{
        "-device",
        "loader,file=zig-out/bin/kernel8.elf,addr=0x1000000,force-raw=true",
    });
    run_qemu.addArgs(&[_][]const u8{
        "-device",
        "loader,file=../tools/ext2fs/data/test1.img,addr=0x2000000,force-raw=true",
    });
    // raspi3b resets to 0x0 (kernel reset stub) and does NOT pass the DTB in x0,
    // and `-dtb` would overlap the stub at 0x0 — so load the device tree at a
    // fixed free address like the other blobs. 0x3000000 is clear of them, below
    // MMIO (0x3f000000), and inside identity-mapped RAM.
    run_qemu.addArgs(&[_][]const u8{
        "-device",
        "loader,file=zig-out/jimzos.dtb,addr=0x3000000,force-raw=true",
    });
    run_qemu.step.dependOn(&install_dtb.step);

    const qemu_step = b.step("qemu", "run kernel in qemu");
    qemu_step.dependOn(b.getInstallStep());
    qemu_step.dependOn(&run_qemu.step);
}
