const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "ipcs", .main = main };

fn fmtKey(k: u32, buf: []u8) []u8 {
    var fb: [16]u8 = undefined;
    return std.fmt.bufPrint(buf, "0x{0:0>8}", .{k}) catch std.fmt.bufPrint(&fb, "0x00000000", .{}) catch "";
}

pub fn main(args: [][]const u8) u8 {
    _ = args;

    core.writeAll(1, "------ Shared Memory Segments --------\n");
    core.writeAll(1, "key        shmid      owner     perms     bytes     nattch\n");

    const shm_max = 256;
    var shm_ds: core.c.struct_shmid_ds = std.mem.zeroes(core.c.struct_shmid_ds);
    var idx: c_int = 0;
    while (idx < shm_max) : (idx += 1) {
        const rc = core.c.shmctl(idx, core.c.IPC_STAT, &shm_ds);
        if (rc < 0) continue;
        var line: [128]u8 = undefined;
        var kbuf: [16]u8 = undefined;
        const ks = fmtKey(@as(u32, @bitCast(shm_ds.shm_perm.__key)), &kbuf);
        _ = std.fmt.bufPrint(&line, "{s} {d:>10} {d:>10} {d:>5} {d:>10} {d:>6}\n", .{
            ks, idx, shm_ds.shm_perm.uid, shm_ds.shm_perm.mode, shm_ds.shm_segsz, shm_ds.shm_nattch,
        }) catch continue;
        core.writeAll(1, &line);
    }

    core.writeAll(1, "\n------ Semaphore Arrays --------\n");
    core.writeAll(1, "key        semid      owner     perms     nsems\n");

    idx = 0;
    while (idx < shm_max) : (idx += 1) {
        var sem_ds: core.c.struct_semid_ds = std.mem.zeroes(core.c.struct_semid_ds);
        const rc = core.c.semctl(idx, 0, core.c.IPC_STAT, &sem_ds);
        if (rc < 0) continue;
        var line: [128]u8 = undefined;
        var kbuf: [16]u8 = undefined;
        const ks = fmtKey(@as(u32, @bitCast(sem_ds.sem_perm.__key)), &kbuf);
        _ = std.fmt.bufPrint(&line, "{s} {d:>10} {d:>10} {d:>5} {d:>10}\n", .{
            ks, idx, sem_ds.sem_perm.uid, sem_ds.sem_perm.mode, sem_ds.sem_nsems,
        }) catch continue;
        core.writeAll(1, &line);
    }

    core.writeAll(1, "\n------ Message Queues --------\n");
    core.writeAll(1, "key        msqid      owner     perms     used-bytes   messages\n");

    idx = 0;
    while (idx < shm_max) : (idx += 1) {
        var msg_ds: core.c.struct_msqid_ds = std.mem.zeroes(core.c.struct_msqid_ds);
        const rc = core.c.msgctl(idx, core.c.IPC_STAT, &msg_ds);
        if (rc < 0) continue;
        var line: [128]u8 = undefined;
        var kbuf: [16]u8 = undefined;
        const ks = fmtKey(@as(u32, @bitCast(msg_ds.msg_perm.__key)), &kbuf);
        _ = std.fmt.bufPrint(&line, "{s} {d:>10} {d:>10} {d:>5} {d:>10} {d:>8}\n", .{
            ks, idx, msg_ds.msg_perm.uid, msg_ds.msg_perm.mode, msg_ds.__msg_cbytes, msg_ds.msg_qnum,
        }) catch continue;
        core.writeAll(1, &line);
    }

    return 0;
}
