const std = @import("std");

pub fn main() !void {
    const address = std.net.Address.parseIp("127.0.0.1", 8080) catch unreachable;
    var server = address.listen(.{
        .reuse_address = true,
        .reuse_port = false,
    }) catch return;
    defer server.deinit();

    _ = std.posix.write(1, "Server at http://localhost:8080 (async + hot reload)\n") catch {};

    while (true) {
        const connection = server.accept() catch continue;
        _ = std.Thread.spawn(.{}, handleRequest, .{connection}) catch {
            connection.stream.close();
            continue;
        };
    }
}

fn handleRequest(connection: std.net.Server.Connection) void {
    defer connection.stream.close();

    var buf: [256]u8 = undefined;
    const n = connection.stream.read(&buf) catch return;
    if (n < 14) return;

    const path_start: usize = 4;
    var path_end: usize = path_start;
    while (path_end < n and buf[path_end] != ' ') path_end += 1;
    const path = buf[path_start..path_end];

    if (pathMatch(path, "/hot-reload")) {
        serveHotReload(connection.stream);
        return;
    }

    // Root path
    if (path.len == 1 and path[0] == '/') {
        serveFileWithReload(connection.stream, "public/index.html", "text/html");
        return;
    }

    // Try to serve files directly (e.g., /styles.css)
    if (std.mem.containsAtLeast(u8, path, 1, ".")) {
        const mime = if (std.mem.endsWith(u8, path, ".css")) "text/css" else if (std.mem.endsWith(u8, path, ".js")) "application/javascript" else if (std.mem.endsWith(u8, path, ".html")) "text/html" else "application/octet-stream";

        var tmp: [128]u8 = undefined;
        const file_path = std.fmt.bufPrint(&tmp, "public{s}", .{path}) catch {
            send404(connection.stream);
            return;
        };
        serveFileWithReload(connection.stream, file_path, mime);
        return;
    }

    // No extension? Assume .html in /public
    var tmp: [128]u8 = undefined;
    const html_path = std.fmt.bufPrint(&tmp, "public{s}.html", .{path}) catch {
        send404(connection.stream);
        return;
    };
    serveFileWithReload(connection.stream, html_path, "text/html");
}

fn serveHotReload(stream: std.net.Stream) void {
    const response =
        \\HTTP/1.1 200 OK
        \\Content-Type: text/event-stream
        \\Cache-Control: no-cache
        \\Connection: keep-alive
        \\
        \\data: {"type":"connected"}
        \\
        \\
    ;
    _ = stream.writeAll(response) catch {};

    var last_check: i64 = getLatestModTime();
    var counter: u32 = 0;

    while (counter < 300) { // ~5 min connection
        std.time.sleep(2 * 1000 * 1000 * 1000); // check every 2s

        const current_time = getLatestModTime();
        if (current_time > last_check) {
            const reload_msg = "data: {\"type\":\"reload\"}\n\n";
            _ = stream.writeAll(reload_msg) catch break;
            last_check = current_time;
        } else {
            const heartbeat = "data: {\"type\":\"ping\"}\n\n";
            _ = stream.writeAll(heartbeat) catch break;
        }

        counter += 1;
    }
}

fn serveFileWithReload(stream: std.net.Stream, filepath: []const u8, mime: []const u8) void {
    const file = std.fs.cwd().openFile(filepath, .{}) catch {
        send404(stream);
        return;
    };
    defer file.close();

    var content: [4096]u8 = undefined;
    const size = file.readAll(&content) catch {
        send404(stream);
        return;
    };

    if (pathMatch(mime, "text/html")) {
        serveHtmlWithReload(stream, content[0..size]);
    } else {
        serveFile(stream, content[0..size], mime);
    }
}

fn serveHtmlWithReload(stream: std.net.Stream, html_content: []const u8) void {
    const hot_reload_script =
        \\<script>
        \\const es = new EventSource('/hot-reload');
        \\es.onmessage = e => {
        \\  const data = JSON.parse(e.data);
        \\  if (data.type === 'reload') location.reload();
        \\};
        \\</script>
    ;

    var response: [8192]u8 = undefined;
    var pos: usize = 0;

    const status = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: ";
    copyBytes(&response, &pos, status);

    const new_size = html_content.len + hot_reload_script.len;
    var size_str: [16]u8 = undefined;
    const size_len = numberToString(new_size, &size_str);
    copyBytes(&response, &pos, size_str[0..size_len]);
    copyBytes(&response, &pos, "\r\n\r\n");

    copyBytes(&response, &pos, html_content);
    copyBytes(&response, &pos, hot_reload_script);

    _ = stream.writeAll(response[0..pos]) catch {};
}

fn serveFile(stream: std.net.Stream, content: []const u8, mime: []const u8) void {
    var response: [8192]u8 = undefined;
    var pos: usize = 0;

    copyBytes(&response, &pos, "HTTP/1.1 200 OK\r\nContent-Type: ");
    copyBytes(&response, &pos, mime);
    copyBytes(&response, &pos, "\r\nContent-Length: ");

    var size_str: [16]u8 = undefined;
    const size_len = numberToString(content.len, &size_str);
    copyBytes(&response, &pos, size_str[0..size_len]);
    copyBytes(&response, &pos, "\r\n\r\n");

    copyBytes(&response, &pos, content);
    _ = stream.writeAll(response[0..pos]) catch {};
}

fn getLatestModTime() i64 {
    const files = [_][]const u8{ "public/index.html", "public/about.html", "public/styles.css", "public/custom.js", "src/runtime.js" };
    var latest: i64 = 0;
    for (files) |file| {
        const mod = getFileModTime(file);
        if (mod > latest) latest = mod;
    }
    return latest;
}

fn getFileModTime(filepath: []const u8) i64 {
    const file = std.fs.cwd().openFile(filepath, .{}) catch return 0;
    defer file.close();
    const stat = file.stat() catch return 0;
    return @intCast(stat.mtime);
}

fn pathMatch(path: []const u8, target: []const u8) bool {
    if (path.len != target.len) return false;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] != target[i]) return false;
    }
    return true;
}

fn send404(stream: std.net.Stream) void {
    const response = "HTTP/1.1 404 Not Found\r\nContent-Length: 19\r\n\r\n<h1>404 Not Found</h1>";
    _ = stream.writeAll(response) catch {};
}

fn copyBytes(dest: []u8, pos: *usize, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dest[pos.* + i] = src[i];
    }
    pos.* += src.len;
}

fn numberToString(num: usize, buf: []u8) usize {
    if (num == 0) {
        buf[0] = '0';
        return 1;
    }
    var n = num;
    var len: usize = 0;
    while (n > 0) {
        buf[len] = @intCast('0' + (n % 10));
        n /= 10;
        len += 1;
    }
    var i: usize = 0;
    while (i < len / 2) : (i += 1) {
        const tmp = buf[i];
        buf[i] = buf[len - 1 - i];
        buf[len - 1 - i] = tmp;
    }
    return len;
}
