const std = @import("std");
const core = @import("core.zig");

pub const meta = core.AppletMeta{ .name = "sed", .main = main };

const Alloc = std.mem.Allocator;
const ArrayList = std.ArrayList;

const CmdCode = enum(u8) {
    s, d, p, P, q, a, i, c, eq, N, n, obrace, y, w, r,
    colon, b, t, T, g, G, h, H, x, comment,
};

const AddrType = enum { none, num, last, regex, step, plus };

const Addr = struct {
    typ: AddrType,
    num: u32,
    num2: u32,
    regex_idx: u32,
};

const SedCmd = struct {
    code: CmdCode,
    negated: bool,
    addr1: Addr,
    addr2: Addr,
    regex_idx: u32,
    replacement: []const u8,
    s_global: bool,
    s_print: bool,
    s_write: bool,
    s_icase: bool,
    s_count: u32,
    s_write_file: []const u8,
    text: []const u8,
    label: []const u8,
    y_set1: []const u8,
    y_set2: []const u8,
    filename: []const u8,
    sub_cmds: []const SedCmd,
};

const RegexInfo = struct {
    buf: []u8,
    compiled: *core.c.regex_t,
    pattern: []u8,
};

const ParseResult = struct { cmds: []SedCmd, regexes: []RegexInfo };
const ProcessFileArg = struct { cmds: []const SedCmd, rx: []const RegexInfo, quiet: bool };

const ParseCtx = struct {
    input: []const u8,
    pos: usize,
};

fn makeCmd() SedCmd {
    return SedCmd{
        .code = .comment, .negated = false,
        .addr1 = Addr{ .typ = .none, .num = 0, .num2 = 0, .regex_idx = 0 },
        .addr2 = Addr{ .typ = .none, .num = 0, .num2 = 0, .regex_idx = 0 },
        .regex_idx = 0, .replacement = "", .s_global = false, .s_print = false,
        .s_write = false, .s_icase = false, .s_count = 0, .s_write_file = "",
        .text = "", .label = "", .y_set1 = "", .y_set2 = "", .filename = "",
        .sub_cmds = &.{},
    };
}

fn allocErr() noreturn { @panic("sed: out of memory"); }

fn compileRegex(pat: []const u8, ext: bool) anyerror!RegexInfo {
    var zpat: [4096:0]u8 = undefined;
    if (pat.len >= zpat.len) return error.Invalid;
    @memcpy(zpat[0..pat.len], pat);
    zpat[pat.len] = 0;
    const flags: c_int = if (ext) core.c.REG_EXTENDED else 0;
    const buf = try std.heap.page_allocator.alloc(u8, 2048);
    const compiled: *core.c.regex_t = @ptrCast(&buf[0]);
    if (core.c.regcomp(compiled, &zpat, flags) != 0) {
        std.heap.page_allocator.free(buf);
        return error.Invalid;
    }
    const pat_copy = try std.heap.page_allocator.dupe(u8, pat);
    return RegexInfo{ .buf = buf, .compiled = compiled, .pattern = pat_copy };
}

fn addRegex(regexes: *ArrayList(RegexInfo), alloc: Alloc, pat: []const u8, ext: bool) anyerror!u32 {
    const idx: u32 = @intCast(regexes.items.len);
    try regexes.append(alloc, try compileRegex(pat, ext));
    return idx;
}

fn skipSpaces(ctx: *ParseCtx) void {
    while (ctx.pos < ctx.input.len and (ctx.input[ctx.pos] == ' ' or ctx.input[ctx.pos] == '\t')) ctx.pos += 1;
}

fn parseAddr(ctx: *ParseCtx, regexes: *ArrayList(RegexInfo), alloc: Alloc, ext: bool) Addr {
    skipSpaces(ctx);
    if (ctx.pos >= ctx.input.len) return Addr{ .typ = .none, .num = 0, .num2 = 0, .regex_idx = 0 };
    if (ctx.input[ctx.pos] == '$') { ctx.pos += 1; return Addr{ .typ = .last, .num = 0, .num2 = 0, .regex_idx = 0 }; }
    if (ctx.input[ctx.pos] == '/') {
        ctx.pos += 1;
        var pat: ArrayList(u8) = .empty;
        defer pat.deinit(alloc);
        while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != '/') {
            pat.append(alloc, ctx.input[ctx.pos]) catch allocErr();
            ctx.pos += 1;
        }
        if (ctx.pos >= ctx.input.len) return Addr{ .typ = .none, .num = 0, .num2 = 0, .regex_idx = 0 };
        ctx.pos += 1;
        const ri = compileRegex(pat.items, ext) catch return Addr{ .typ = .none, .num = 0, .num2 = 0, .regex_idx = 0 };
        const idx: u32 = @intCast(regexes.items.len);
        regexes.append(alloc, ri) catch allocErr();
        return Addr{ .typ = .regex, .num = 0, .num2 = 0, .regex_idx = idx };
    }
    if (ctx.input[ctx.pos] == '%') {
        ctx.pos += 1;
        return Addr{ .typ = .regex, .num = 0, .num2 = 0, .regex_idx = std.math.maxInt(u32) };
    }
    if (ctx.pos + 1 < ctx.input.len and ctx.input[ctx.pos] == '/' and ctx.input[ctx.pos + 1] == '/') {
        ctx.pos += 2;
        return Addr{ .typ = .regex, .num = 0, .num2 = 0, .regex_idx = std.math.maxInt(u32) };
    }
    if (ctx.pos < ctx.input.len and ctx.input[ctx.pos] == '+') {
        ctx.pos += 1;
        var n: u32 = 0;
        while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] >= '0' and ctx.input[ctx.pos] <= '9') : (ctx.pos += 1) n = n * 10 + (ctx.input[ctx.pos] - '0');
        return Addr{ .typ = .plus, .num = n, .num2 = 0, .regex_idx = 0 };
    }
    if (ctx.pos < ctx.input.len and ctx.input[ctx.pos] >= '0' and ctx.input[ctx.pos] <= '9') {
        var n1: u32 = 0;
        while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] >= '0' and ctx.input[ctx.pos] <= '9') : (ctx.pos += 1) n1 = n1 * 10 + (ctx.input[ctx.pos] - '0');
        if (ctx.pos < ctx.input.len and ctx.input[ctx.pos] == '~') {
            ctx.pos += 1;
            var n2: u32 = 0;
            while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] >= '0' and ctx.input[ctx.pos] <= '9') : (ctx.pos += 1) n2 = n2 * 10 + (ctx.input[ctx.pos] - '0');
            return Addr{ .typ = .step, .num = n1, .num2 = n2, .regex_idx = 0 };
        }
        return Addr{ .typ = .num, .num = n1, .num2 = 0, .regex_idx = 0 };
    }
    return Addr{ .typ = .none, .num = 0, .num2 = 0, .regex_idx = 0 };
}

fn parseText(ctx: *ParseCtx, alloc: Alloc) []const u8 {
    var text: ArrayList(u8) = .empty;
    if (ctx.pos < ctx.input.len and ctx.input[ctx.pos] == '\\') {
        ctx.pos += 1;
        var is_cont = true;
        while (is_cont) {
            is_cont = false;
            while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] == '\n') ctx.pos += 1;
            while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != '\n' and ctx.input[ctx.pos] != ';') {
                const c = ctx.input[ctx.pos]; ctx.pos += 1;
                if (c == '\\') {
                    if (ctx.pos < ctx.input.len and ctx.input[ctx.pos] == '\n') { is_cont = true; ctx.pos += 1; break; }
                    if (ctx.pos < ctx.input.len) {
                        const next = ctx.input[ctx.pos]; ctx.pos += 1;
                        switch (next) {
                            'n' => text.append(alloc, '\n') catch allocErr(),
                            't' => text.append(alloc, '\t') catch allocErr(),
                            'r' => text.append(alloc, '\r') catch allocErr(),
                            '\\' => text.append(alloc, '\\') catch allocErr(),
                            else => { text.append(alloc, '\\') catch allocErr(); text.append(alloc, next) catch allocErr(); },
                        }
                    }
                } else text.append(alloc, c) catch allocErr();
            }
            if (is_cont) continue;
            if (text.items.len > 0 and text.getLast() == '\\' and ctx.pos < ctx.input.len and ctx.input[ctx.pos] == '\n') {
                text.items.len -= 1; is_cont = true; ctx.pos += 1;
            }
        }
    } else {
        while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] == '\n') ctx.pos += 1;
        while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != '\n' and ctx.input[ctx.pos] != ';') : (ctx.pos += 1) text.append(alloc, ctx.input[ctx.pos]) catch allocErr();
    }
    return text.items;
}

fn parseBlock(body: []const u8, regexes: *ArrayList(RegexInfo), alloc: Alloc, ext: bool) anyerror![]SedCmd {
    var cmds: ArrayList(SedCmd) = .empty;
    var ctx = ParseCtx{ .input = body, .pos = 0 };
    while (ctx.pos < body.len) {
        while (ctx.pos < body.len and (body[ctx.pos] == ';' or body[ctx.pos] == '\n')) ctx.pos += 1;
        skipSpaces(&ctx);
        if (ctx.pos >= body.len) break;
        if (body[ctx.pos] == '{') {
            ctx.pos += 1;
            var depth: u32 = 1; const s = ctx.pos;
            while (ctx.pos < body.len and depth > 0) {
                if (body[ctx.pos] == '\\') { ctx.pos += 2; continue; }
                if (body[ctx.pos] == '{') depth += 1;
                if (body[ctx.pos] == '}') { depth -= 1; if (depth == 0) break; }
                ctx.pos += 1;
            }
            const inner = body[s..ctx.pos];
            if (ctx.pos < body.len) ctx.pos += 1;
            var sc = makeCmd();
            sc.code = .obrace;
            sc.sub_cmds = try parseBlock(inner, regexes, alloc, ext);
            try cmds.append(alloc, sc);
        } else {
            try cmds.append(alloc, try parseOneCmd(&ctx, regexes, alloc, ext));
        }
    }
    return try alloc.dupe(SedCmd, cmds.items);
}

fn parseOneCmd(ctx: *ParseCtx, regexes: *ArrayList(RegexInfo), alloc: Alloc, ext: bool) anyerror!SedCmd {
    var cmd = makeCmd();
    const addr1 = parseAddr(ctx, regexes, alloc, ext);
    skipSpaces(ctx);
    var addr2: Addr = Addr{ .typ = .none, .num = 0, .num2 = 0, .regex_idx = 0 };
    if (ctx.pos < ctx.input.len and ctx.input[ctx.pos] == ',') {
        ctx.pos += 1; skipSpaces(ctx);
        addr2 = parseAddr(ctx, regexes, alloc, ext);
        skipSpaces(ctx);
    }
    if (ctx.pos < ctx.input.len and ctx.input[ctx.pos] == '!') { cmd.negated = true; ctx.pos += 1; }
    skipSpaces(ctx);
    if (ctx.pos >= ctx.input.len) return error.Invalid;
    const cmd_char = ctx.input[ctx.pos]; ctx.pos += 1;
    if (cmd_char != 's' and cmd_char != 'y') skipSpaces(ctx);
    cmd.addr1 = addr1; cmd.addr2 = addr2;

    switch (cmd_char) {
        's' => {
            cmd.code = .s;
            if (ctx.pos >= ctx.input.len) return error.Invalid;
            const delim = ctx.input[ctx.pos]; ctx.pos += 1;
            var pat: ArrayList(u8) = .empty;
            defer pat.deinit(alloc);
            var in_br: u32 = 0;
            while (ctx.pos < ctx.input.len) {
                const c = ctx.input[ctx.pos];
                if (c == '\\' and ctx.pos + 1 < ctx.input.len) {
                    ctx.pos += 1; const n = ctx.input[ctx.pos]; ctx.pos += 1;
                    try pat.append(alloc, '\\'); try pat.append(alloc, n);
                } else if (c == '[') { in_br += 1; try pat.append(alloc, c); ctx.pos += 1; }
                else if (c == ']') { if (in_br > 0) in_br -= 1; try pat.append(alloc, c); ctx.pos += 1; }
                else if (c == delim and in_br == 0) { ctx.pos += 1; break; }
                else { try pat.append(alloc, c); ctx.pos += 1; }
            }
            var esc: ArrayList(u8) = .empty;
            defer esc.deinit(alloc);
            {
                var pi: usize = 0;
                while (pi < pat.items.len) {
                    if (pat.items[pi] == '\\' and pi + 1 < pat.items.len) {
                        const n = pat.items[pi + 1];
                        switch (n) {
                            'n' => try esc.append(alloc, '\n'),
                            't' => try esc.append(alloc, '\t'),
                            'r' => try esc.append(alloc, '\r'),
                            '\\' => try esc.append(alloc, '\\'),
                            else => { try esc.append(alloc, '\\'); try esc.append(alloc, n); },
                        }
                        pi += 2;
                    } else { try esc.append(alloc, pat.items[pi]); pi += 1; }
                }
            }
            cmd.regex_idx = try addRegex(regexes, alloc, esc.items, ext);
            var repl: ArrayList(u8) = .empty;
            defer repl.deinit(alloc);
            while (ctx.pos < ctx.input.len) {
                const c = ctx.input[ctx.pos];
                if (c == '\\' and ctx.pos + 1 < ctx.input.len) {
                    ctx.pos += 1; const n = ctx.input[ctx.pos]; ctx.pos += 1;
                    if (n == delim) {
                        try repl.append(alloc, delim);
                    } else {
                        try repl.append(alloc, '\\'); try repl.append(alloc, n);
                    }
                } else if (c == delim) { ctx.pos += 1; break; } else { try repl.append(alloc, c); ctx.pos += 1; }
            }
            cmd.replacement = try alloc.dupe(u8, repl.items);
            while (ctx.pos < ctx.input.len) {
                switch (ctx.input[ctx.pos]) {
                    'g' => { cmd.s_global = true; ctx.pos += 1; },
                    'p' => { cmd.s_print = true; ctx.pos += 1; },
                    'I', 'i' => { cmd.s_icase = true; ctx.pos += 1; },
                    'w' => {
                        cmd.s_write = true; ctx.pos += 1; skipSpaces(ctx);
                        const ws = ctx.pos;
                        while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != ';' and ctx.input[ctx.pos] != '\n') ctx.pos += 1;
                        cmd.s_write_file = try alloc.dupe(u8, ctx.input[ws..ctx.pos]); break;
                    },
                    '0'...'9' => {
                        cmd.s_count = 0;
                        while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] >= '0' and ctx.input[ctx.pos] <= '9') : (ctx.pos += 1) {
                            cmd.s_count = cmd.s_count * 10 + (ctx.input[ctx.pos] - '0');
                        }
                    },
                    else => break,
                }
            }
        },
        'd' => cmd.code = .d,
        'p' => cmd.code = .p,
        'P' => cmd.code = .P,
        'q' => cmd.code = .q,
        '=' => cmd.code = .eq,
        'N' => cmd.code = .N,
        'n' => cmd.code = .n,
        'y' => {
            cmd.code = .y;
            if (ctx.pos >= ctx.input.len) return error.Invalid;
            const d = ctx.input[ctx.pos]; ctx.pos += 1; const s1 = ctx.pos;
            while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != d) { if (ctx.input[ctx.pos] == '\\') ctx.pos += 1; ctx.pos += 1; }
            if (ctx.pos >= ctx.input.len) return error.Invalid;
            cmd.y_set1 = try alloc.dupe(u8, ctx.input[s1..ctx.pos]); ctx.pos += 1; const s2 = ctx.pos;
            while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != d) { if (ctx.input[ctx.pos] == '\\') ctx.pos += 1; ctx.pos += 1; }
            cmd.y_set2 = try alloc.dupe(u8, ctx.input[s2..ctx.pos]); if (ctx.pos < ctx.input.len) ctx.pos += 1;
        },
        'a' => { cmd.code = .a; cmd.text = parseText(ctx, alloc); },
        'i' => { cmd.code = .i; cmd.text = parseText(ctx, alloc); },
        'c' => { cmd.code = .c; cmd.text = parseText(ctx, alloc); },
        'w' => { cmd.code = .w; skipSpaces(ctx); const ws = ctx.pos; while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != ';' and ctx.input[ctx.pos] != '\n') ctx.pos += 1; cmd.filename = try alloc.dupe(u8, ctx.input[ws..ctx.pos]); },
        'r' => { cmd.code = .r; skipSpaces(ctx); const ws = ctx.pos; while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != ';' and ctx.input[ctx.pos] != '\n') ctx.pos += 1; cmd.filename = try alloc.dupe(u8, ctx.input[ws..ctx.pos]); },
        ':' => { cmd.code = .colon; skipSpaces(ctx); const ws = ctx.pos; while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != ';' and ctx.input[ctx.pos] != '\n' and ctx.input[ctx.pos] != ' ') ctx.pos += 1; cmd.label = try alloc.dupe(u8, ctx.input[ws..ctx.pos]); },
        'b' => {
            cmd.code = .b; skipSpaces(ctx);
            if (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != ';' and ctx.input[ctx.pos] != '\n') {
                const ws = ctx.pos;
                while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != ';' and ctx.input[ctx.pos] != '\n' and ctx.input[ctx.pos] != ' ') ctx.pos += 1;
                cmd.label = try alloc.dupe(u8, ctx.input[ws..ctx.pos]);
            }
        },
        't' => {
            cmd.code = .t; skipSpaces(ctx);
            if (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != ';' and ctx.input[ctx.pos] != '\n') {
                const ws = ctx.pos;
                while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != ';' and ctx.input[ctx.pos] != '\n' and ctx.input[ctx.pos] != ' ') ctx.pos += 1;
                cmd.label = try alloc.dupe(u8, ctx.input[ws..ctx.pos]);
            }
        },
        'T' => {
            cmd.code = .T; skipSpaces(ctx);
            if (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != ';' and ctx.input[ctx.pos] != '\n') {
                const ws = ctx.pos;
                while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != ';' and ctx.input[ctx.pos] != '\n' and ctx.input[ctx.pos] != ' ') ctx.pos += 1;
                cmd.label = try alloc.dupe(u8, ctx.input[ws..ctx.pos]);
            }
        },
        'g' => cmd.code = .g,
        'G' => cmd.code = .G,
        'h' => cmd.code = .h,
        'H' => cmd.code = .H,
        'x' => cmd.code = .x,
        '#' => { cmd.code = .comment; while (ctx.pos < ctx.input.len and ctx.input[ctx.pos] != '\n') ctx.pos += 1; },
        '{' => {
            cmd.code = .obrace;
            var depth: u32 = 1; const s = ctx.pos;
            while (ctx.pos < ctx.input.len and depth > 0) {
                if (ctx.input[ctx.pos] == '\\') { ctx.pos += 2; continue; }
                if (ctx.input[ctx.pos] == '{') depth += 1;
                if (ctx.input[ctx.pos] == '}') { depth -= 1; if (depth == 0) break; }
                ctx.pos += 1;
            }
            cmd.sub_cmds = try parseBlock(ctx.input[s..ctx.pos], regexes, alloc, ext);
            if (ctx.pos < ctx.input.len) ctx.pos += 1;
        },
        else => return error.Invalid,
    }
    return cmd;
}

fn parseScript(input: []const u8, alloc: Alloc, ext: bool) anyerror!ParseResult {
    var cmds: ArrayList(SedCmd) = .empty;
    var regexes: ArrayList(RegexInfo) = .empty;
    var ctx = ParseCtx{ .input = input, .pos = 0 };
    while (ctx.pos < input.len) {
        while (ctx.pos < input.len and (input[ctx.pos] == ';' or input[ctx.pos] == '\n')) ctx.pos += 1;
        skipSpaces(&ctx);
        if (ctx.pos >= input.len) break;
        try cmds.append(alloc, try parseOneCmd(&ctx, &regexes, alloc, ext));
    }
    return ParseResult{ .cmds = try alloc.dupe(SedCmd, cmds.items), .regexes = try alloc.dupe(RegexInfo, regexes.items) };
}

fn addrMatches(addr: Addr, n: u32, last: bool, rx: []const RegexInfo, pat: []const u8, last_rx: u32) bool {
    switch (addr.typ) {
        .none => return true,
        .num => return n == addr.num,
        .last => return last,
        .regex => {
            const idx = if (addr.regex_idx == std.math.maxInt(u32)) last_rx else addr.regex_idx;
            if (idx >= rx.len) return false;
            var z: [65537:0]u8 = undefined;
            const l = @min(pat.len, z.len - 1);
            @memcpy(z[0..l], pat[0..l]); z[l] = 0;
            return core.c.regexec(rx[idx].compiled, &z, 0, null, 0) == 0;
        },
        .step => {
            if (n < addr.num or addr.num2 == 0) return false;
            return (n - addr.num) % addr.num2 == 0;
        },
        .plus => return false,
    }
}

fn processReplacement(repl: []const u8, line: []const u8, so: usize, eo: usize, pm: []core.c.regmatch_t, nm: c_int, alloc: Alloc) anyerror![]u8 {
    var r: ArrayList(u8) = .empty;
    var i: usize = 0; var ua = false; var un = false;
    while (i < repl.len) {
        if (repl[i] != '\\') { try r.append(alloc, repl[i]); i += 1; continue; }
        i += 1; if (i >= repl.len) { try r.append(alloc, '\\'); break; }
        const c = repl[i]; i += 1;
        switch (c) {
            '0'...'9' => {
                const n = c - '0';
                if (n == 0) {
                    try r.appendSlice(alloc, line[so..eo]);
                } else if (n < nm) {
                    const ms: usize = @as(usize, @intCast(pm[n].rm_so));
                    const me: usize = @as(usize, @intCast(pm[n].rm_eo));
                    if (me >= ms and me <= line.len) try r.appendSlice(alloc, line[ms..me]);
                }
            },
            '&' => try r.appendSlice(alloc, line[so..eo]),
            'U' => { ua = true; un = false; },
            'L' => { ua = false; un = false; },
            'u' => { un = true; },
            'l' => { un = false; },
            'E' => { ua = false; un = false; },
            'n' => try r.append(alloc, '\n'),
            't' => try r.append(alloc, '\t'),
            'r' => try r.append(alloc, '\r'),
            '\\' => try r.append(alloc, '\\'),
            else => { try r.append(alloc, '\\'); try r.append(alloc, c); },
        }
    }
    if (un or ua) {
        for (r.items, 0..) |ch, j| {
            if (un and !ua) { r.items[j] = std.ascii.toUpper(ch); un = false; if (!ua) break; }
            if (ua) r.items[j] = std.ascii.toUpper(ch);
        }
    }
    return r.items;
}

const ExecCtx = struct {
    cmds: []const SedCmd, rx: []const RegexInfo, alloc: Alloc,
    pat: ArrayList(u8), hold: ArrayList(u8),
    line_no: u32, line_idx: usize, consumed: bool,
    last_rx: u32, subd: bool, quiet: bool, ended: bool,
    pa: ?[]const u8, pr: ?[]u8,
    ra: std.DynamicBitSet, rsl: u32,
    wf: std.StringHashMap(c_int),
};

fn writeFile(ec: *ExecCtx, fnm: []const u8, data: []const u8) void {
    const gop = ec.wf.getOrPut(fnm) catch allocErr();
    if (!gop.found_existing) {
        var fb: [4096:0]u8 = undefined;
        if (fnm.len >= fb.len) return;
        @memcpy(fb[0..fnm.len], fnm); fb[fnm.len] = 0;
        const fd = core.c.open(fb[0..fnm.len :0].ptr, core.c.O_WRONLY | core.c.O_CREAT | core.c.O_APPEND, @as(c_uint, 0o644));
        if (fd < 0) return;
        gop.value_ptr.* = fd;
    }
    const fd = gop.value_ptr.*;
    _ = core.c.write(fd, data.ptr, @intCast(data.len));
    _ = core.c.write(fd, "\n", 1);
}

fn execSub(cmd: *const SedCmd, ec: *ExecCtx) void {
    const re = &ec.rx[cmd.regex_idx];
    const line = ec.pat.items; const al = ec.alloc;
    var z: [65537:0]u8 = undefined;
    const ln = @min(line.len, z.len - 1);
    @memcpy(z[0..ln], line[0..ln]); z[ln] = 0;
    var pm: [10]core.c.regmatch_t = std.mem.zeroes([10]core.c.regmatch_t);
    var off: usize = 0; var mc: u32 = 0;
    var r: ArrayList(u8) = .empty; defer r.deinit(al);
    while (off <= line.len) {
        const zo = @min(off, z.len);
        const res = core.c.regexec(re.compiled, @as([*:0]const u8, @ptrCast(&z)) + zo, 10, &pm, if (off > 0) core.c.REG_NOTBOL else 0);
        if (res != 0 or pm[0].rm_so < 0) { r.appendSlice(al, line[off..]) catch allocErr(); break; }
        const so: usize = @as(usize, @intCast(pm[0].rm_so)) + off;
        const eo: usize = @as(usize, @intCast(pm[0].rm_eo)) + off;
        mc += 1;
        if (cmd.s_count == 0 or mc == cmd.s_count) {
            r.appendSlice(al, line[off..so]) catch allocErr();
            const rpl = processReplacement(cmd.replacement, line, so, eo, &pm, 10, al) catch allocErr();
            r.appendSlice(al, rpl) catch allocErr();
            ec.subd = true;
        } else r.appendSlice(al, line[off..eo]) catch allocErr();
        if (so == eo) { if (eo < line.len) r.append(al, line[eo]) catch allocErr(); off = eo + 1; } else off = eo;
        if (!cmd.s_global) break;
    }
    ec.pat.items.len = 0; ec.pat.appendSlice(al, r.items) catch allocErr();
    if (cmd.s_print) { ec.pat.append(al, '\n') catch allocErr(); core.writeAll(1, ec.pat.items); ec.pat.items.len -= 1; }
    if (cmd.s_write and cmd.s_write_file.len > 0) writeFile(ec, cmd.s_write_file, ec.pat.items);
}

fn execOne(cmd: *const SedCmd, ec: *ExecCtx, lines: [][]const u8) bool {
    switch (cmd.code) {
        .s => execSub(cmd, ec),
        .d => { ec.pat.items.len = 0; return true; },
        .p => { ec.pat.append(ec.alloc, '\n') catch allocErr(); core.writeAll(1, ec.pat.items); ec.pat.items.len -= 1; },
        .P => {
            if (std.mem.indexOfScalar(u8, ec.pat.items, '\n')) |nl| {
                core.writeAll(1, ec.pat.items[0..nl]); core.writeAll(1, "\n");
            } else { ec.pat.append(ec.alloc, '\n') catch allocErr(); core.writeAll(1, ec.pat.items); ec.pat.items.len -= 1; }
        },
        .q => { ec.ended = true; return true; },
        .eq => { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{}\n", .{ec.line_no}) catch unreachable; core.writeAll(1, s); },
        .a => ec.pa = cmd.text,
        .i => { core.writeAll(1, cmd.text); core.writeAll(1, "\n"); },
        .c => { ec.pat.items.len = 0; ec.pat.appendSlice(ec.alloc, cmd.text) catch allocErr(); },
        .N => {
            if (ec.line_idx + 1 >= lines.len) { ec.ended = true; return true; }
            ec.pat.append(ec.alloc, '\n') catch allocErr();
            ec.line_idx += 1; ec.line_no += 1; ec.consumed = true;
            ec.pat.appendSlice(ec.alloc, lines[ec.line_idx]) catch allocErr();
        },
        .n => {
            if (!ec.quiet) { ec.pat.append(ec.alloc, '\n') catch allocErr(); core.writeAll(1, ec.pat.items); ec.pat.items.len -= 1; }
            if (ec.line_idx + 1 >= lines.len) { ec.ended = true; return true; }
            ec.line_idx += 1; ec.line_no += 1; ec.consumed = true;
            ec.pat.items.len = 0; ec.pat.appendSlice(ec.alloc, lines[ec.line_idx]) catch allocErr();
            ec.subd = false;
        },
        .y => {
            var r: ArrayList(u8) = .empty; defer r.deinit(ec.alloc);
            for (ec.pat.items) |ch| {
                if (std.mem.indexOfScalar(u8, cmd.y_set1, ch)) |pos| {
                    r.append(ec.alloc, if (pos < cmd.y_set2.len) cmd.y_set2[pos] else ch) catch allocErr();
                } else r.append(ec.alloc, ch) catch allocErr();
            }
            ec.pat.items.len = 0; ec.pat.appendSlice(ec.alloc, r.items) catch allocErr();
        },
        .w => writeFile(ec, cmd.filename, ec.pat.items),
        .r => {
            var fb: [4096:0]u8 = undefined;
            if (cmd.filename.len >= fb.len) return false;
            @memcpy(fb[0..cmd.filename.len], cmd.filename); fb[cmd.filename.len] = 0;
            const fd = core.c.open(fb[0..cmd.filename.len :0].ptr, core.c.O_RDONLY);
            if (fd < 0) return false;
            const data = core.readAll(std.heap.page_allocator, fd, 1024 * 1024) catch { _ = core.c.close(fd); return false; };
            _ = core.c.close(fd); ec.pr = data;
        },
        .g => { ec.pat.items.len = 0; ec.pat.appendSlice(ec.alloc, ec.hold.items) catch allocErr(); },
        .G => { ec.pat.append(ec.alloc, '\n') catch allocErr(); ec.pat.appendSlice(ec.alloc, ec.hold.items) catch allocErr(); },
        .h => { ec.hold.items.len = 0; ec.hold.appendSlice(ec.alloc, ec.pat.items) catch allocErr(); },
        .H => { ec.hold.append(ec.alloc, '\n') catch allocErr(); ec.hold.appendSlice(ec.alloc, ec.pat.items) catch allocErr(); },
        .x => {
            const tmp = ec.alloc.dupe(u8, ec.pat.items) catch allocErr();
            defer ec.alloc.free(tmp);
            ec.pat.items.len = 0; ec.pat.appendSlice(ec.alloc, ec.hold.items) catch allocErr();
            ec.hold.items.len = 0; ec.hold.appendSlice(ec.alloc, tmp) catch allocErr();
        },
        .obrace => {
            for (cmd.sub_cmds) |*sc| {
                if (sc.code == .colon) continue;
                if (sc.code == .obrace) {
                    var am = addrMatches(sc.addr1, ec.line_no, lines.len == ec.line_idx + 1, ec.rx, ec.pat.items, ec.last_rx);
                    if (sc.negated) am = !am;
                    if (am) {
                        for (sc.sub_cmds) |*ssc| {
                            if (execOne(ssc, ec, lines)) { ec.ended = true; break; }
                        }
                    }
                    continue;
                }
                if (sc.code == .b or sc.code == .t or sc.code == .T) {
                    var am = addrMatches(sc.addr1, ec.line_no, lines.len == ec.line_idx + 1, ec.rx, ec.pat.items, ec.last_rx);
                    if (sc.negated) am = !am;
                    if (!am) continue;
                    const sb = sc.code == .b or (sc.code == .t and ec.subd) or (sc.code == .T and !ec.subd);
                    if (!sb) continue;
                    if (sc.code == .t or sc.code == .T) ec.subd = false;
                    if (sc.label.len == 0) return true;
                    for (cmd.sub_cmds) |*lc| { if (lc.code == .colon and std.mem.eql(u8, lc.label, sc.label)) break; }
                    return false;
                }
                var am = addrMatches(sc.addr1, ec.line_no, lines.len == ec.line_idx + 1, ec.rx, ec.pat.items, ec.last_rx);
                if (am and sc.addr2.typ != .none) am = rangeMatch(sc, ec);
                if (sc.negated) am = !am;
                if (am and execOne(sc, ec, lines)) { ec.ended = true; return true; }
                if (ec.ended) return true;
            }
        },
        .colon, .comment, .b, .t, .T => {},
    }
    return false;
}

fn rangeMatch(cmd: *const SedCmd, ec: *ExecCtx) bool {
    const ridx = @intFromPtr(cmd) / @sizeOf(SedCmd);
    const last = ec.line_idx == ec.pat.items.len - 1;
    _ = last;
    if (cmd.addr2.typ == .plus) {
        if (!ec.ra.isSet(ridx)) {
            if (addrMatches(cmd.addr1, ec.line_no, ec.line_idx == ec.pat.items.len - 1, ec.rx, ec.pat.items, ec.last_rx)) {
                ec.ra.set(ridx); ec.rsl = ec.line_no; return true;
            }
            return false;
        } else {
            if (ec.line_no >= ec.rsl + cmd.addr2.num) ec.ra.unset(ridx);
            return true;
        }
    }
    if (!ec.ra.isSet(ridx)) {
        if (addrMatches(cmd.addr1, ec.line_no, ec.line_idx == ec.pat.items.len - 1, ec.rx, ec.pat.items, ec.last_rx)) {
            ec.ra.set(ridx);
            if (addrMatches(cmd.addr2, ec.line_no, ec.line_idx == ec.pat.items.len - 1, ec.rx, ec.pat.items, ec.last_rx)) ec.ra.unset(ridx);
            return true;
        }
        return false;
    } else {
        if (addrMatches(cmd.addr2, ec.line_no, ec.line_idx == ec.pat.items.len - 1, ec.rx, ec.pat.items, ec.last_rx)) ec.ra.unset(ridx);
        return true;
    }
}

fn processFile(ef: *const ProcessFileArg, lines: [][]const u8) void {
    const al = std.heap.page_allocator;
    var pat: ArrayList(u8) = .empty; defer pat.deinit(al);
    var hold: ArrayList(u8) = .empty; defer hold.deinit(al);
    var ra = std.DynamicBitSet.initEmpty(al, ef.cmds.len + 1) catch allocErr(); defer ra.deinit();
    var ec = ExecCtx{
        .cmds = ef.cmds, .rx = ef.rx, .alloc = al, .pat = pat, .hold = hold,
        .line_no = 0, .line_idx = 0, .consumed = false, .last_rx = 0,
        .subd = false, .quiet = ef.quiet, .ended = false, .pa = null, .pr = null,
        .ra = ra, .rsl = 0, .wf = std.StringHashMap(c_int).init(al),
    };
    defer {
        var it = ec.wf.iterator();
        while (it.next()) |e| _ = core.c.close(e.value_ptr.*);
        ec.wf.deinit();
    }
    while (ec.line_idx < lines.len) {
        ec.line_no += 1; ec.subd = false; ec.consumed = false; ec.ended = false;
        ec.pat.items.len = 0; ec.pat.appendSlice(al, lines[ec.line_idx]) catch allocErr();
        const last = (ec.line_idx == lines.len - 1);
        var ci: u32 = 0;
        while (ci < ef.cmds.len) : (ci += 1) {
            const cmd = &ef.cmds[ci];
            if (cmd.code == .colon) continue;
            if (cmd.code == .obrace) {
                var am = addrMatches(cmd.addr1, ec.line_no, last, ec.rx, ec.pat.items, ec.last_rx);
                if (am and cmd.addr2.typ != .none) am = rangeMatch(cmd, &ec);
                if (cmd.negated) am = !am;
                if (am) {
                    for (cmd.sub_cmds) |*sc| {
                        if (sc.code == .colon) continue;
                        if (sc.code == .b or sc.code == .t or sc.code == .T) {
                            var sam = addrMatches(sc.addr1, ec.line_no, last, ec.rx, ec.pat.items, ec.last_rx);
                            if (sc.negated) sam = !sam;
                            if (!sam) continue;
                            const sb = sc.code == .b or (sc.code == .t and ec.subd) or (sc.code == .T and !ec.subd);
                            if (!sb) continue;
                            if (sc.code == .t or sc.code == .T) ec.subd = false;
                            if (sc.label.len == 0) { ec.ended = true; break; }
                            var found = false;
                            for (cmd.sub_cmds) |*lc| { if (lc.code == .colon and std.mem.eql(u8, lc.label, sc.label)) { found = true; break; } }
                            if (!found) {
                                for (ef.cmds) |*lc| { if (lc.code == .colon and std.mem.eql(u8, lc.label, sc.label)) { found = true; break; } }
                            }
                            if (!found) ec.ended = true;
                            break;
                        }
                        if (sc.code == .obrace) {
                            var sam = addrMatches(sc.addr1, ec.line_no, last, ec.rx, ec.pat.items, ec.last_rx);
                            if (sc.negated) sam = !sam;
                            if (sam) {
                                for (sc.sub_cmds) |*ssc| { if (execOne(ssc, &ec, lines)) break; }
                            }
                            continue;
                        }
                        var sam = addrMatches(sc.addr1, ec.line_no, last, ec.rx, ec.pat.items, ec.last_rx);
                        if (sam and sc.addr2.typ != .none) sam = rangeMatch(sc, &ec);
                        if (sc.negated) sam = !sam;
                        if (sam and execOne(sc, &ec, lines)) { ec.ended = true; break; }
                        if (ec.ended) break;
                    }
                }
                if (ec.ended) break;
                continue;
            }
            if (cmd.code == .b or cmd.code == .t or cmd.code == .T) {
                var am = addrMatches(cmd.addr1, ec.line_no, last, ec.rx, ec.pat.items, ec.last_rx);
                if (am and cmd.addr2.typ != .none) am = rangeMatch(cmd, &ec);
                if (cmd.negated) am = !am;
                if (!am) continue;
                const sb = cmd.code == .b or (cmd.code == .t and ec.subd) or (cmd.code == .T and !ec.subd);
                if (!sb) continue;
                if (cmd.code == .t or cmd.code == .T) ec.subd = false;
                if (cmd.label.len == 0) break;
                // Find label and continue from there
                var found: bool = false;
                for (ef.cmds, 0..) |lc, lci| {
                    if (lc.code == .colon and std.mem.eql(u8, lc.label, cmd.label)) {
                        ci = @as(u32, @intCast(lci));
                        found = true;
                        break;
                    }
                }
                if (!found) break;
                continue;
            }
            var am = addrMatches(cmd.addr1, ec.line_no, last, ec.rx, ec.pat.items, ec.last_rx);
            if (am and cmd.addr2.typ != .none) am = rangeMatch(cmd, &ec);
            if (cmd.negated) am = !am;
            if (am and execOne(cmd, &ec, lines)) { ec.ended = true; break; }
            if (ec.ended) break;
        }
        if (!ec.quiet and !ec.ended and ec.pat.items.len > 0) {
            ec.pat.append(al, '\n') catch allocErr();
            core.writeAll(1, ec.pat.items);
            ec.pat.items.len -= 1;
        }
        if (ec.pa) |t| { core.writeAll(1, t); core.writeAll(1, "\n"); ec.pa = null; }
        if (ec.pr) |d| { core.writeAll(1, d); al.free(d); ec.pr = null; }
        if (ec.ended) break;
        if (!ec.consumed) ec.line_idx += 1;
    }
}

fn splitLines(data: []const u8, alloc: Alloc) [][]const u8 {
    if (data.len == 0) return &.{};
    var lines: ArrayList([]const u8) = .empty;
    var s: usize = 0;
    while (s < data.len) {
        const e = if (std.mem.indexOfScalar(u8, data[s..], '\n')) |nl| s + nl else data.len;
        lines.append(alloc, data[s..e]) catch allocErr();
        if (e >= data.len) break;
        s = e + 1;
    }
    return lines.items;
}

pub fn main(args: [][]const u8) u8 {
    const alloc = std.heap.page_allocator;
    var quiet = false; var ext_rx = false;
    var parts: ArrayList(u8) = .empty; defer parts.deinit(alloc);
    var i: usize = 1;
    var dash = false;
    while (i < args.len) {
        if (!dash and std.mem.eql(u8, args[i], "--")) { dash = true; i += 1; break; }
        if (!dash and args[i].len > 0 and args[i][0] == '-') {
            if (args[i].len == 1) break;
            var j: usize = 1;
            while (j < args[i].len) : (j += 1) {
                switch (args[i][j]) {
                    'n' => quiet = true,
                    'r' => ext_rx = true,
                    'i' => {},
                    'e' => {
                        if (j + 1 < args[i].len) {
                            if (parts.items.len > 0) {
                                if (parts.getLast() == '\\') { parts.items.len -= 1; } else { parts.append(alloc, '\n') catch allocErr(); }
                            }
                            parts.appendSlice(alloc, args[i][j + 1 ..]) catch allocErr();
                            j = args[i].len;
                        } else {
                            i += 1;
                            if (i >= args.len) return core.die(2, "sed: -e requires an argument\n", .{});
                            if (parts.items.len > 0) {
                                if (parts.getLast() == '\\') { parts.items.len -= 1; } else { parts.append(alloc, '\n') catch allocErr(); }
                            }
                            parts.appendSlice(alloc, args[i]) catch allocErr();
                            j = args[i].len;
                        }
                    },
                    'f' => {
                        var fnm: []const u8 = undefined;
                        if (j + 1 < args[i].len) { fnm = args[i][j + 1 ..]; j = args[i].len; }
                        else { i += 1; if (i >= args.len) return core.die(2, "sed: -f requires an argument\n", .{}); fnm = args[i]; j = args[i].len; }
                        var fb: [4096:0]u8 = undefined;
                        if (fnm.len >= fb.len) return core.die(2, "sed: filename too long\n", .{});
                        @memcpy(fb[0..fnm.len], fnm); fb[fnm.len] = 0;
                        const fd = core.c.open(fb[0..fnm.len :0].ptr, core.c.O_RDONLY);
                        if (fd < 0) return core.die(2, "sed: can't open {s}\n", .{fnm});
                        const data = core.readAll(alloc, fd, 1024 * 1024) catch return 2;
                        _ = core.c.close(fd);
                        if (parts.items.len > 0) {
                            if (parts.getLast() == '\\') { parts.items.len -= 1; } else { parts.append(alloc, '\n') catch allocErr(); }
                        }
                        parts.appendSlice(alloc, data) catch allocErr(); alloc.free(data);
                    },
                    '-' => {
                        if (std.mem.eql(u8, args[i], "--version")) { core.writeAll(1, "GNU sed version 4.8\n"); return 0; }
                        while (j < args[i].len) j += 1;
                    },
                    else => return core.die(2, "sed: unknown option -{c}\n", .{args[i][j]}),
                }
            }
            i += 1;
        } else break;
    }
    if (parts.items.len == 0) {
        if (i >= args.len) return core.die(2, "sed: missing script\n", .{});
        parts.appendSlice(alloc, args[i]) catch allocErr(); i += 1;
    }
    const files = args[i..];
    const parsed = parseScript(parts.items, alloc, ext_rx) catch { return core.die(2, "sed: parse error\n", .{}); };
    defer {
        for (parsed.regexes) |r| { core.c.regfree(r.compiled); alloc.free(r.buf); alloc.free(r.pattern); }
        alloc.free(parsed.regexes); alloc.free(parsed.cmds);
    }
    const ef = ProcessFileArg{
        .cmds = parsed.cmds, .rx = parsed.regexes, .quiet = quiet,
    };
    if (files.len == 0) {
        const d = core.readAll(alloc, 0, 1024 * 1024) catch return 0;
        defer alloc.free(d); const l = splitLines(d, alloc); defer alloc.free(l);
        processFile(&ef, l);
    } else {
        for (files) |fname| {
            if (std.mem.eql(u8, fname, "-")) {
                const d = core.readAll(alloc, 0, 1024 * 1024) catch return 0;
                defer alloc.free(d); const l = splitLines(d, alloc); defer alloc.free(l);
                processFile(&ef, l);
            } else {
                var fb: [4096:0]u8 = undefined;
                if (fname.len >= fb.len) { core.eprint("sed: filename too long: {s}\n", .{fname}); continue; }
                @memcpy(fb[0..fname.len], fname); fb[fname.len] = 0;
                const fd = core.c.open(fb[0..fname.len :0].ptr, core.c.O_RDONLY);
                if (fd < 0) { core.eprint("sed: {s}: No such file or directory\n", .{fname}); continue; }
                const d = core.readAll(alloc, fd, 1024 * 1024) catch { _ = core.c.close(fd); continue; };
                _ = core.c.close(fd); defer alloc.free(d);
                const l = splitLines(d, alloc); defer alloc.free(l);
                processFile(&ef, l);
            }
        }
    }
    return 0;
}
