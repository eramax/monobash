const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "fdisk", .main = main };

const PartType = struct { id: u8, name: []const u8 };

const part_types = [_]PartType{
    .{ .id = 0x00, .name = "Empty" },
    .{ .id = 0x01, .name = "FAT12" },
    .{ .id = 0x04, .name = "FAT16 <32M" },
    .{ .id = 0x05, .name = "Extended" },
    .{ .id = 0x06, .name = "FAT16" },
    .{ .id = 0x07, .name = "HPFS/NTFS/exFAT" },
    .{ .id = 0x08, .name = "AIX" },
    .{ .id = 0x09, .name = "AIX bootable" },
    .{ .id = 0x0a, .name = "OS/2 Boot Manager" },
    .{ .id = 0x0b, .name = "W95 FAT32" },
    .{ .id = 0x0c, .name = "W95 FAT32 (LBA)" },
    .{ .id = 0x0e, .name = "W95 FAT16 (LBA)" },
    .{ .id = 0x0f, .name = "W95 Ext'd (LBA)" },
    .{ .id = 0x11, .name = "Hidden FAT12" },
    .{ .id = 0x12, .name = "Compaq diagnostics" },
    .{ .id = 0x14, .name = "Hidden FAT16 <32M" },
    .{ .id = 0x16, .name = "Hidden FAT16" },
    .{ .id = 0x17, .name = "Hidden HPFS/NTFS" },
    .{ .id = 0x1b, .name = "Hidden W95 FAT32" },
    .{ .id = 0x1c, .name = "Hidden W95 FAT32 (LBA)" },
    .{ .id = 0x1e, .name = "Hidden W95 FAT16 (LBA)" },
    .{ .id = 0x27, .name = "Windows RE" },
    .{ .id = 0x39, .name = "Plan 9" },
    .{ .id = 0x3c, .name = "PartitionMagic" },
    .{ .id = 0x42, .name = "Linux swap" },
    .{ .id = 0x43, .name = "Linux native" },
    .{ .id = 0x44, .name = "GoBack" },
    .{ .id = 0x4d, .name = "QNX4.x" },
    .{ .id = 0x4e, .name = "QNX4.x 2nd" },
    .{ .id = 0x4f, .name = "QNX4.x 3rd" },
    .{ .id = 0x50, .name = "OnTrack DM" },
    .{ .id = 0x51, .name = "OnTrack DM6 Aux1" },
    .{ .id = 0x52, .name = "CP/M" },
    .{ .id = 0x53, .name = "OnTrack DM6 Aux3" },
    .{ .id = 0x54, .name = "OnTrackDM6" },
    .{ .id = 0x55, .name = "EZ-Drive" },
    .{ .id = 0x56, .name = "Golden Bow" },
    .{ .id = 0x5c, .name = "Priam Edisk" },
    .{ .id = 0x61, .name = "SpeedStor" },
    .{ .id = 0x63, .name = "GNU HURD or SysV" },
    .{ .id = 0x64, .name = "Novell Netware" },
    .{ .id = 0x65, .name = "Novell Netware" },
    .{ .id = 0x70, .name = "DiskSecure Multi" },
    .{ .id = 0x75, .name = "PC/IX" },
    .{ .id = 0x80, .name = "Old Minix" },
    .{ .id = 0x81, .name = "Minix / old Linux" },
    .{ .id = 0x82, .name = "Linux swap / Solaris" },
    .{ .id = 0x83, .name = "Linux" },
    .{ .id = 0x84, .name = "OS/2 hidden" },
    .{ .id = 0x85, .name = "Linux extended" },
    .{ .id = 0x86, .name = "NTFS volume set" },
    .{ .id = 0x87, .name = "NTFS volume set" },
    .{ .id = 0x8e, .name = "Linux LVM" },
    .{ .id = 0x93, .name = "Amoeba" },
    .{ .id = 0x94, .name = "Amoeba BBT" },
    .{ .id = 0x9f, .name = "BSD/OS" },
    .{ .id = 0xa0, .name = "Thinkpad hibernation" },
    .{ .id = 0xa5, .name = "FreeBSD" },
    .{ .id = 0xa6, .name = "OpenBSD" },
    .{ .id = 0xa7, .name = "NeXTSTEP" },
    .{ .id = 0xa8, .name = "Darwin UFS" },
    .{ .id = 0xa9, .name = "NetBSD" },
    .{ .id = 0xab, .name = "Darwin boot" },
    .{ .id = 0xaf, .name = "macOS/HFS+" },
    .{ .id = 0xb7, .name = "BSDI fs" },
    .{ .id = 0xb8, .name = "BSDI swap" },
    .{ .id = 0xbb, .name = "Boot Wizard hidden" },
    .{ .id = 0xbc, .name = "Acronis FAT32 LBA" },
    .{ .id = 0xbe, .name = "Solaris boot" },
    .{ .id = 0xbf, .name = "Solaris" },
    .{ .id = 0xc1, .name = "DRDOS/sec (FAT12)" },
    .{ .id = 0xc4, .name = "DRDOS/sec (FAT16)" },
    .{ .id = 0xc6, .name = "DRDOS/sec (FAT16)" },
    .{ .id = 0xc7, .name = "Syrinx" },
    .{ .id = 0xda, .name = "Non-FS data" },
    .{ .id = 0xdb, .name = "CP/M / CTOS" },
    .{ .id = 0xde, .name = "Dell Utility" },
    .{ .id = 0xdf, .name = "BootIt" },
    .{ .id = 0xe1, .name = "DOS access" },
    .{ .id = 0xe3, .name = "DOS R/O" },
    .{ .id = 0xe4, .name = "SpeedStor" },
    .{ .id = 0xea, .name = "Rufus alignment" },
    .{ .id = 0xeb, .name = "BeOS fs" },
    .{ .id = 0xee, .name = "GPT protective" },
    .{ .id = 0xef, .name = "EFI System" },
    .{ .id = 0xf0, .name = "Linux/PA-RISC boot" },
    .{ .id = 0xf1, .name = "SpeedStor" },
    .{ .id = 0xf2, .name = "DOS secondary" },
    .{ .id = 0xf4, .name = "SpeedStor" },
    .{ .id = 0xfb, .name = "VMware VMFS" },
    .{ .id = 0xfc, .name = "VMware VMKCORE" },
    .{ .id = 0xfd, .name = "Linux raid autodetect" },
    .{ .id = 0xfe, .name = "LANstep" },
    .{ .id = 0xff, .name = "BBT" },
};

fn partTypeName(id: u8) []const u8 {
    for (part_types) |pt| {
        if (pt.id == id) return pt.name;
    }
    return "Unknown";
}

fn formatSectors(sectors: u32, buf: *[32]u8) []const u8 {
    const bytes = @as(u64, sectors) * 512;
    if (bytes < 1024) return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch "?";
    if (bytes < 1024 * 1024) return std.fmt.bufPrint(buf, "{d}K", .{@as(u64, @intCast(bytes / 1024))}) catch "?";
    if (bytes < 1024 * 1024 * 1024) return std.fmt.bufPrint(buf, "{d}M", .{@as(u64, @intCast(bytes / (1024 * 1024)))}) catch "?";
    return std.fmt.bufPrint(buf, "{d}G", .{@as(u64, @intCast(bytes / (1024 * 1024 * 1024)))}) catch "?";
}

fn listTable(device: []const u8) u8 {
    var path_buf: [4096:0]u8 = undefined;
    const dev_path = if (std.mem.startsWith(u8, device, "/dev/")) device else blk: {
        const p = std.fmt.bufPrint(&path_buf, "/dev/{s}", .{device}) catch return 1;
        @memcpy(path_buf[0..p.len], p);
        path_buf[p.len] = 0;
        break :blk path_buf[0..p.len :0];
    };

    const fd = core.c.open(dev_path.ptr, core.c.O_RDONLY);
    if (fd < 0) return core.die(1, "fdisk: cannot open {s}\n", .{dev_path});
    defer _ = core.c.close(fd);

    var mbr: [512]u8 = undefined;
    const n = core.c.read(fd, &mbr, mbr.len);
    if (n < 512) return core.die(1, "fdisk: cannot read MBR from {s}\n", .{dev_path});

    // Check MBR signature
    if (mbr[510] != 0x55 or mbr[511] != 0xAA) return core.die(1, "fdisk: no valid MBR signature on {s}\n", .{dev_path});

    var disk_buf: [4096]u8 = undefined;
    const disk_name = std.fs.path.basename(dev_path);
    const hdr = std.fmt.bufPrint(&disk_buf, "\nDisk {s}: {d} sectors\n\n", .{ dev_path, @as(u32, @intCast(n)) }) catch return 1;
    core.writeAll(1, hdr);

    core.writeAll(1, "Device       Boot    Start      End  Sectors  Size Id Type\n");

    const entries = mbr[446..510];
    var part_num: usize = 0;
    var i: usize = 0;
    while (i < 64) : (i += 16) {
        part_num += 1;
        const status = entries[i];
        const part_type = entries[i + 4];
        const start_lba = std.mem.readInt(u32, entries[i + 8 ..][0..4], .little);
        const sector_count = std.mem.readInt(u32, entries[i + 12 ..][0..4], .little);

        if (part_type == 0x00 and status == 0) continue;

        const boot_str = if (status & 0x80 != 0) "*" else " ";
        const end_lba = start_lba + sector_count;

        var size_buf: [32]u8 = undefined;
        const size_str = formatSectors(sector_count, &size_buf);

        var line: [256]u8 = undefined;
        const out = std.fmt.bufPrint(&line, "{s}{d:4}  {s}  {d:8} {d:8} {d:8} {s:>4} {x:0>2} {s}\n", .{
            disk_name, part_num, boot_str, start_lba, end_lba, sector_count, size_str, part_type, partTypeName(part_type),
        }) catch continue;
        core.writeAll(1, out);
    }

    return 0;
}

pub fn main(args: [][]const u8) u8 {
    if (args.len < 2) return core.die(1, "fdisk: usage: fdisk -l DEVICE\n", .{});

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-l")) {
            i += 1;
            if (i >= args.len) return core.die(1, "fdisk: usage: fdisk -l DEVICE\n", .{});
            return listTable(args[i]);
        } else {
            return core.die(1, "fdisk: invalid option '{s}'\n", .{arg});
        }
    }

    return core.die(1, "fdisk: usage: fdisk -l DEVICE\n", .{});
}
