const builtin = @import("builtin");
const std = @import("std");

const io = std.io;
const os = std.os;
const fs = std.fs;

const Builder = std.build.Builder;
const FileSource = std.build.FileSource;

const thread = @import("src/thread.zig");

pub fn write_struct_def(comptime T: type) void {
    const file = fs.cwd().createFile("src/arch/aarch64/struct_defs_" ++ @typeName(T) ++ ".h", .{}) catch unreachable;
    defer file.close();

    var writer = fs.File.writer(file);

    writer.print("// NOTE THIS FILE IS AUTO GENERATED BY BUILD.ZIG\n", .{}) catch {};

    switch (@typeInfo(T)) {
        .Struct => |StructT| {
            inline for (StructT.fields) |f| {
                //const stdout = std.io.getStdOut().writer();
                writer.print("#define {s}_{s} {}\n", .{ @typeName(T), f.name, @offsetOf(T, f.name) }) catch {};
            }

            writer.print("#define {s}__size {}\n", .{ @typeName(T), @sizeOf(T) }) catch {};
        },
        else => @compileError("Thread type not a struct"),
    }
}

pub fn build(b: *Builder) void {
    write_struct_def(thread.Thread);
    write_struct_def(thread.CPUFrame);

    const want_gdb = b.option(bool, "gdb", "Build for QEMU gdb server") orelse false;
    // const want_pty = b.option(bool, "pty", "Create a separate serial port path") orelse false;

    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("kernel8.elf", "src/kernel.zig");

    exe.addPackagePath("ext2", "../libs/ext2/ext2.zig");

    exe.addAssemblyFile("src/arch/aarch64/kernel_entry.S");
    exe.addAssemblyFile("src/arch/aarch64/kernel_pre.S");

    exe.addAssemblyFile("src/arch/aarch64/exception.S");
    exe.addAssemblyFile("src/arch/aarch64/context.S");
    exe.setBuildMode(mode);

    exe.setLinkerScriptPath(FileSource.relative("src/arch/aarch64/linker.ld"));
    // Use eabihf for freestanding arm code with hardware float support

    var features_sub = std.Target.Cpu.Feature.Set.empty;
    features_sub.addFeature(@enumToInt(std.Target.aarch64.Feature.neon));
    features_sub.addFeature(@enumToInt(std.Target.aarch64.Feature.fp_armv8));

    const target = std.zig.CrossTarget{
        .cpu_arch = .aarch64,
        .os_tag = .freestanding,
        .cpu_features_sub = features_sub,
        .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.generic },
    };

    exe.setTarget(target);

    // Dumping symbols
    const dump_step = b.step("dump", "Dump symbols");
    dump_step.dependOn(&exe.step);

    const run_objdump = b.addSystemCommand(&[_][]const u8{"llvm-objcopy"});
    run_objdump.addArtifactArg(exe);
    run_objdump.addArgs(&[_][]const u8{ "-O", "binary", "zig-out/bin/kernel8" });

    const run_create_syms = b.addSystemCommand(&[_][]const u8{"./post.sh"});
    run_create_syms.addArtifactArg(exe);

    dump_step.dependOn(&run_objdump.step);
    dump_step.dependOn(&run_create_syms.step);

    const qemu = b.step("qemu", "run kernel in qemu");

    const qemu_path = "qemu-system-aarch64";
    const run_qemu = b.addSystemCommand(&[_][]const u8{qemu_path});
    run_qemu.addArg("-kernel");
    run_qemu.addArtifactArg(exe);
    run_qemu.addArgs(&[_][]const u8{
        "-m",         "1024",
        "-M",         "raspi3b",
        "-nographic", "-semihosting",
    });
    if (want_gdb) {
        run_qemu.addArgs(&[_][]const u8{
            "-S",
            "-s",
        });
    }

    //FIXME Update this to use the output path to the elf
    run_qemu.addArgs(&[_][]const u8{
        "-device",
        "loader,file=zig-out/bin/kernel8.elf,addr=0x1000000,force-raw=true",
    });

    //FIXME: This is temporary while we test (Wonder if we can do this based on some per-test config?)
    run_qemu.addArgs(&[_][]const u8{
        "-device",
        "loader,file=../tools/ext2fs/data/test1.img,addr=0x2000000,force-raw=true",
    });

    // Can we configure a gdb option? Which would launch gdb, connect it to qemu and have it ready to go

    qemu.dependOn(b.default_step);
    qemu.dependOn(&run_objdump.step);
    qemu.dependOn(&run_create_syms.step);
    qemu.dependOn(&run_qemu.step);

    b.installArtifact(exe);

    b.default_step.dependOn(&run_objdump.step);
    b.default_step.dependOn(&run_create_syms.step);
}
