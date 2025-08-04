const std = @import("std");

pub fn main() !void {
    const addr = std.net.Address.parseIp("127.0.0.1", 8080) catch unreachable;
    var server = addr.listen(.{ .reuse_address = true }) catch return;
    defer server.deinit();

    // Simple startup message
    const stdout = std.io.getStdOut().writer();
    stdout.print("Server running at http://localhost:8080\n", .{}) catch {};

    while (true) {
        const conn = server.accept() catch continue;
        _ = std.Thread.spawn(.{}, handle, .{conn}) catch {
            conn.stream.close();
            continue;
        };
    }
}

fn handle(conn: std.net.Server.Connection) void {
    defer conn.stream.close();

    var buf: [512]u8 = undefined;
    const n = conn.stream.read(&buf) catch return;
    if (n == 0) return;

    var path: []const u8 = "/";
    if (std.mem.startsWith(u8, buf[0..n], "GET /")) {
        const start = 4;
        const end = std.mem.indexOfScalarPos(u8, buf[0..n], start, ' ') orelse start;
        path = if (start == end) "/" else buf[start..end];
    }

    // Direct file serving
    if (std.mem.eql(u8, path, "/runtime.js")) {
        serve(conn.stream, "src/runtime.js", "application/javascript");
    } else {
        var fbuf: [128]u8 = undefined;
        const fpath = if (std.mem.eql(u8, path, "/"))
            "public/index.html"
        else
            std.fmt.bufPrint(&fbuf, "public{s}", .{path}) catch return;
        serve(conn.stream, fpath, mime(path));
    }
}

fn serve(stream: std.net.Stream, path: []const u8, content_type: []const u8) void {
    const file = std.fs.cwd().openFile(path, .{}) catch {
        send404(stream);
        return;
    };
    defer file.close();

    var fbuf: [2048]u8 = undefined;
    const size = file.readAll(&fbuf) catch {
        send404(stream);
        return;
    };

    var hbuf: [128]u8 = undefined;
    const header = std.fmt.bufPrint(&hbuf, "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {}\r\n\r\n", .{ content_type, size }) catch return;

    _ = stream.writeAll(header) catch {};
    _ = stream.writeAll(fbuf[0..size]) catch {};
}

fn mime(path: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, path, ".js")) "application/javascript" else if (std.mem.endsWith(u8, path, ".css")) "text/css" else "text/html";
}

fn send404(stream: std.net.Stream) void {
    const resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 19\r\n\r\n<h1>404 Not Found</h1>";
    _ = stream.writeAll(resp) catch {};
}
