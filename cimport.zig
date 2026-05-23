/// Central C import for the entire monobash project.
/// All files should import `c` from here instead of having their own @cImport.
pub const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/utsname.h");
    @cInclude("sys/wait.h");
    @cInclude("sys/resource.h");
    @cInclude("sys/statvfs.h");
    @cInclude("sys/personality.h");
    @cInclude("sys/file.h");
    @cInclude("fcntl.h");
    @cInclude("pwd.h");
    @cInclude("grp.h");
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("signal.h");
    @cInclude("sched.h");
    @cInclude("dirent.h");
    @cInclude("time.h");
    @cInclude("termios.h");
    @cInclude("regex.h");
    @cInclude("wordexp.h");
    @cInclude("tree_sitter/api.h");
});
