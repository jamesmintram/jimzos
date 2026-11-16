const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const Platform = enum { raspi3, virt };
    const PlatformConfig = struct {
        fdt_phys: usize,
        kernel_elf_phys: usize,
        kernel_elf_reserved_size: usize,
        ext2_phys: usize,
        ext2_reserved_size: usize,
        ext2_used_size: usize,
        dts: ?[]const u8,
        linker_script: []const u8,
    };
    const want_gdb = b.option(bool, "gdb", "Build for QEMU gdb server") orelse false;
    const platform = b.option(Platform, "platform", "Target platform") orelse .virt;

    const platform_config: PlatformConfig = switch (platform) {
        .raspi3 => .{
            .fdt_phys = @as(usize, 0x03000000),
            .kernel_elf_phys = @as(usize, 0x01000000),
            .kernel_elf_reserved_size = @as(usize, 0x00400000),
            .ext2_phys = @as(usize, 0x02000000),
            .ext2_reserved_size = @as(usize, 0x00040000),
            .ext2_used_size = @as(usize, 0x00010000),
            .dts = "src/arch/aarch64/platform/raspi3/jimzos.dts",
            .linker_script = "src/arch/aarch64/platform/raspi3/linker.ld",
        },
        .virt => .{
            .fdt_phys = @as(usize, 0x40000000),
            .kernel_elf_phys = @as(usize, 0x4f000000),
            .kernel_elf_reserved_size = @as(usize, 0x00400000),
            .ext2_phys = @as(usize, 0x50000000),
            .ext2_reserved_size = @as(usize, 0x00040000),
            .ext2_used_size = @as(usize, 0x00010000),
            .dts = null,
            .linker_script = "src/arch/aarch64/platform/virt/linker.ld",
        },
    };

    const optimize = b.standardOptimizeOption(.{});
    const build_options = b.addOptions();
    build_options.addOption(Platform, "platform", platform);
    build_options.addOption(usize, "fdt_phys", platform_config.fdt_phys);
    build_options.addOption(usize, "kernel_elf_phys", platform_config.kernel_elf_phys);
    build_options.addOption(usize, "kernel_elf_reserved_size", platform_config.kernel_elf_reserved_size);
    build_options.addOption(usize, "ext2_phys", platform_config.ext2_phys);
    build_options.addOption(usize, "ext2_reserved_size", platform_config.ext2_reserved_size);
    build_options.addOption(usize, "ext2_used_size", platform_config.ext2_used_size);

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
    const vm_page_mod = b.createModule(.{
        .root_source_file = b.path("src/vm/page.zig"),
        .target = target,
        .optimize = optimize,
    });
    const phys_range_mod = b.createModule(.{
        .root_source_file = b.path("src/vm/phys_range.zig"),
        .target = target,
        .optimize = optimize,
    });
    phys_range_mod.addImport("vm_page", vm_page_mod);

    const host_vm_page_mod = b.createModule(.{
        .root_source_file = b.path("src/vm/page.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    const thread_layout_mod = b.createModule(.{
        .root_source_file = b.path("src/thread.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    thread_layout_mod.addImport("vm_page", host_vm_page_mod);
    const asm_offsets_generator_mod = b.createModule(.{
        .root_source_file = b.path("tools/generate_asm_offsets.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    asm_offsets_generator_mod.addImport("thread_layout", thread_layout_mod);
    const asm_offsets_generator = b.addExecutable(.{
        .name = "generate_asm_offsets",
        .root_module = asm_offsets_generator_mod,
    });
    const run_asm_offsets_generator = b.addRunArtifact(asm_offsets_generator);
    const asm_offsets_header = run_asm_offsets_generator.addOutputFileArg("asm_offsets.h");

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
    boot1_phys_mod.addOptions("build_options", build_options);
    boot1_phys_mod.addImport("phys_range", phys_range_mod);
    boot1_phys_mod.addImport("vm_page", vm_page_mod);
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
    exe_mod.addOptions("build_options", build_options);
    exe_mod.addImport("ext2", ext2_mod);
    exe_mod.addImport("phys_range", phys_range_mod);
    exe_mod.addImport("vm_page", vm_page_mod);
    exe_mod.addIncludePath(asm_offsets_header.dirname());

    exe_mod.addAssemblyFile(b.path("src/arch/aarch64/boot0_entry.S"));
    exe_mod.addAssemblyFile(b.path("src/arch/aarch64/exception.S"));
    exe_mod.addAssemblyFile(b.path("src/arch/aarch64/context.S"));

    exe_mod.linkLibrary(lib_boot1_phys);

    const devicetree_dep = b.dependency("devicetree", .{});
    exe_mod.addImport("DeviceTree", devicetree_dep.module("DeviceTree"));

    const run_test_dtc = b.addSystemCommand(&.{ "dtc", "-I", "dts", "-O", "dtb", "-o" });
    const memory_test_dtb = run_test_dtc.addOutputFileArg("memory-test.dtb");
    run_test_dtc.addFileArg(b.path("../dts/memory-test.dts"));
    const memory_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/memory_test.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    const host_phys_range_mod = b.createModule(.{
        .root_source_file = b.path("src/vm/phys_range.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    host_phys_range_mod.addImport("vm_page", host_vm_page_mod);
    const kernel_test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    kernel_test_mod.addImport("DeviceTree", devicetree_dep.module("DeviceTree"));
    kernel_test_mod.addImport("phys_range", host_phys_range_mod);
    kernel_test_mod.addImport("vm_page", host_vm_page_mod);
    memory_test_mod.addImport("kernel_test", kernel_test_mod);
    memory_test_mod.addAnonymousImport("memory_test_dtb", .{ .root_source_file = memory_test_dtb });
    const memory_tests = b.addTest(.{ .root_module = memory_test_mod });
    const run_memory_tests = b.addRunArtifact(memory_tests);

    const page_frame_manager_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/page_frame_manager_test.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    page_frame_manager_test_mod.addImport("kernel_test", kernel_test_mod);
    const page_frame_manager_tests = b.addTest(.{ .root_module = page_frame_manager_test_mod });
    const run_page_frame_manager_tests = b.addRunArtifact(page_frame_manager_tests);

    const page_table_test_mod = b.createModule(.{
        .root_source_file = b.path("src/arch/aarch64/mmu/page_table.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    page_table_test_mod.addImport("vm_page", host_vm_page_mod);
    const page_table_tests = b.addTest(.{ .root_module = page_table_test_mod });
    const run_page_table_tests = b.addRunArtifact(page_table_tests);

    const table_editor_test_mod = b.createModule(.{
        .root_source_file = b.path("src/arch/aarch64/mmu/table_editor.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    table_editor_test_mod.addImport("phys_range", host_phys_range_mod);
    table_editor_test_mod.addImport("vm_page", host_vm_page_mod);
    const table_editor_tests = b.addTest(.{ .root_module = table_editor_test_mod });
    const run_table_editor_tests = b.addRunArtifact(table_editor_tests);

    const translation_map_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/translation_map_test.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    translation_map_test_mod.addImport("kernel_test", kernel_test_mod);
    const translation_map_tests = b.addTest(.{ .root_module = translation_map_test_mod });
    const run_translation_map_tests = b.addRunArtifact(translation_map_tests);

    const test_step = b.step("test", "Run kernel unit tests");
    test_step.dependOn(&run_memory_tests.step);
    test_step.dependOn(&run_page_frame_manager_tests.step);
    test_step.dependOn(&run_page_table_tests.step);
    test_step.dependOn(&run_table_editor_tests.step);
    test_step.dependOn(&run_translation_map_tests.step);

    const exe = b.addExecutable(.{
        .name = "kernel8.elf",
        .root_module = exe_mod,
    });
    exe.setLinkerScript(b.path(platform_config.linker_script));
    // Match the linker script's ENTRY(__start); otherwise lld defaults to
    // looking for `_start` and warns it cannot find the entry symbol.
    exe.entry = .{ .symbol_name = "__start" };

    b.installArtifact(exe);

    const check_kernel_size = CheckKernelSize.create(b, exe.getEmittedBin(), platform_config.kernel_elf_reserved_size);

    // Generate and install the flat binary, disassembly and symbol table.
    const run_objcopy = addLlvmCommand(b, "llvm-objcopy");
    run_objcopy.step.dependOn(check_kernel_size);
    run_objcopy.addFileArg(exe.getEmittedBin());
    run_objcopy.addArgs(&.{ "-O", "binary" });
    const kernel_binary = run_objcopy.addOutputFileArg("kernel8");
    const install_binary = b.addInstallBinFile(kernel_binary, "kernel8");

    const run_disassembly = addLlvmCommand(b, "llvm-objdump");
    run_disassembly.step.dependOn(check_kernel_size);
    run_disassembly.addFileArg(exe.getEmittedBin());
    run_disassembly.addArg("-d");
    const install_disassembly = b.addInstallFile(run_disassembly.captureStdOut(.{}), "dumps/kernel.S");

    const run_symbols = addLlvmCommand(b, "llvm-objdump");
    run_symbols.step.dependOn(check_kernel_size);
    run_symbols.addFileArg(exe.getEmittedBin());
    run_symbols.addArg("--syms");
    const install_symbols = b.addInstallFile(run_symbols.captureStdOut(.{}), "dumps/kernel.syms");

    const dump_step = b.step("dump", "Generate the flat binary, disassembly and symbols");
    dump_step.dependOn(&install_binary.step);
    dump_step.dependOn(&install_disassembly.step);
    dump_step.dependOn(&install_symbols.step);

    const install_dtb = if (platform_config.dts) |dts| blk: {
        const run_dtc = b.addSystemCommand(&[_][]const u8{ "dtc", "-I", "dts", "-O", "dtb", "-o" });
        const dtb_file = run_dtc.addOutputFileArg("jimzos.dtb");
        run_dtc.addFileArg(b.path(dts));
        break :blk b.addInstallFile(dtb_file, "jimzos.dtb");
    } else null;

    const dtb_step = b.step("dtb", "Compile the device tree (dts -> dtb)");
    if (install_dtb) |install| dtb_step.dependOn(&install.step);

    // The default `zig build` produces the ELF, the flat binary and the dumps.
    b.getInstallStep().dependOn(dump_step);

    // Run the kernel under QEMU.
    const run_qemu = b.addSystemCommand(&[_][]const u8{"qemu-system-aarch64"});
    run_qemu.addArgs(&.{ "-m", "1024", "-nographic", "-semihosting" });
    switch (platform) {
        .raspi3 => {
            run_qemu.addArgs(&.{ "-M", "raspi3b", "-kernel" });
            run_qemu.addArtifactArg(exe);
        },
        .virt => run_qemu.addArgs(&.{
            "-M",
            "virt,dtb-randomness=off,gic-version=3",
            "-cpu",
            "cortex-a57",
            "-smp",
            "1",
            "-device",
            "loader,file=zig-out/bin/kernel8.elf,cpu-num=0",
        }),
    }
    if (want_gdb) {
        run_qemu.addArgs(&[_][]const u8{ "-S", "-s" });
    }

    run_qemu.addArgs(&.{
        "-device",
        b.fmt("loader,file=zig-out/bin/kernel8.elf,addr=0x{x},force-raw=true", .{platform_config.kernel_elf_phys}),
    });
    run_qemu.addArgs(&.{
        "-device",
        b.fmt("loader,file=../tools/ext2fs/data/test1.img,addr=0x{x},force-raw=true", .{platform_config.ext2_phys}),
    });
    if (install_dtb) |install| {
        run_qemu.addArgs(&.{
            "-device",
            b.fmt("loader,file=zig-out/jimzos.dtb,addr=0x{x},force-raw=true", .{platform_config.fdt_phys}),
        });
        run_qemu.step.dependOn(&install.step);
    }
    run_qemu.step.dependOn(b.getInstallStep());

    const qemu_step = b.step("qemu", "run kernel in qemu");
    qemu_step.dependOn(&run_qemu.step);
}

fn addLlvmCommand(b: *std.Build, name: []const u8) *std.Build.Step.Run {
    // Homebrew's LLVM is keg-only, so its tools may not be on PATH. Check
    // both standard prefixes after PATH, using the host OS, not the target.
    const search_paths: []const []const u8 = if (builtin.os.tag == .macos)
        &.{ "/opt/homebrew/opt/llvm/bin", "/usr/local/opt/llvm/bin" }
    else
        &.{};
    const tool = b.findProgram(&.{name}, search_paths) catch {
        const message = if (builtin.os.tag == .macos)
            b.fmt(
                "Required LLVM tool '{s}' was not found.\n" ++
                    "Searched PATH, /opt/homebrew/opt/llvm/bin and /usr/local/opt/llvm/bin.\n" ++
                    "Install LLVM with `brew install llvm`, or add your LLVM bin directory to PATH.",
                .{name},
            )
        else
            b.fmt(
                "Required LLVM tool '{s}' was not found on PATH.\n" ++
                    "Install LLVM using your system package manager and add its bin directory to PATH.",
                .{name},
            );
        const run = b.addSystemCommand(&.{name});
        // Fail only steps that need this tool; `zig build test` and --help
        // must still work without LLVM installed.
        run.step.dependOn(&b.addFail(message).step);
        return run;
    };
    return b.addSystemCommand(&.{tool});
}

const CheckKernelSize = struct {
    step: std.Build.Step,
    elf: std.Build.LazyPath,
    max_size: u64,

    fn create(b: *std.Build, elf: std.Build.LazyPath, max_size: u64) *std.Build.Step {
        const check = b.allocator.create(CheckKernelSize) catch @panic("OOM");
        check.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "check kernel ELF fits boot-module reservation",
                .owner = b,
                .makeFn = make,
            }),
            .elf = elf,
            .max_size = max_size,
        };
        elf.addStepDependencies(&check.step);
        return &check.step;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
        const check: *CheckKernelSize = @fieldParentPtr("step", step);
        const b = step.owner;
        try step.singleUnchangingWatchInput(check.elf);
        const path = check.elf.getPath2(b, step);
        const stat = std.Io.Dir.cwd().statFile(b.graph.io, path, .{}) catch |err| {
            return step.fail("Unable to check kernel ELF size at '{s}': {s}", .{ path, @errorName(err) });
        };
        if (stat.size > check.max_size) {
            return step.fail("Kernel ELF is {d} bytes, exceeding its {d}-byte boot-module reservation.", .{ stat.size, check.max_size });
        }
    }
};
