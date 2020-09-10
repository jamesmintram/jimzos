const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;

pub const aarch64 = @import("target/aarch64.zig");

pub fn build(b: *Builder) void {
    const want_gdb = b.option(bool, "gdb", "Build for QEMU gdb server") orelse false;
    const want_pty = b.option(bool, "pty", "Create a separate serial port path") orelse false;

    const mode = b.standardReleaseOptions();
    
    const exe = b.addExecutable("kernel8.elf", "src/kernel.zig");
    exe.addAssemblyFile("src/arch/aarch64/head.S");
    exe.addAssemblyFile("src/arch/aarch64/crt0.S");
    exe.setBuildMode(mode);

    exe.setLinkerScriptPath("src/arch/aarch64/linker.ld");
    // Use eabihf for freestanding arm code with hardware float support


    

    var features_sub = std.Target.Cpu.Feature.Set.empty;
    features_sub.addFeature(@enumToInt(std.Target.aarch64.Feature.neon));

    const target = std.zig.CrossTarget{
        .cpu_arch = .aarch64,
        .os_tag = .freestanding,
        .cpu_features_sub = features_sub,
        .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.cortex_a53 },
        // .cpu_model = .{ 
        //     .explicit = &std.Target.aarch64.cpu.generic
        // }
    };

    exe.setTarget(target);


    const dump_step = b.step("dump", "Dump symbols");
    dump_step.dependOn(&exe.step);

    // const qemu = b.step("qemu", "run kernel in qemu");

    // const qemu_path = if (builtin.os == builtin.Os.windows) "C:/Program Files/qemu/qemu-system-aarch64.exe" else "qemu-system-aarch64";
    // const run_qemu = b.addSystemCommand([][]const u8 { qemu_path });
    // run_qemu.addArg("-kernel");
    // run_qemu.addArtifactArg(exe);
    // run_qemu.addArgs([][]const u8{
    //     "-m",
    //     "256",
    //     "-M",
    //     "raspi3",
    //     "-serial",
    //     if (want_pty) "pty" else "stdio",
    // });
    // if (want_gdb) {
    //     run_qemu.addArgs([][]const u8{
    //         "-S",
    //         "-s",
    //     });
    // }
    // qemu.dependOn(&run_qemu.step);

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
