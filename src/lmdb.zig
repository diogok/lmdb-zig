const std = @import("std");
const testing = std.testing;

const c = @cImport({
    @cInclude("lmdb.h");
});

pub const Mode = enum(c_uint) {
    ReadAndWrite = 0,
    ReadOnly = 0x2000,
};

const log = std.log.scoped(.LMDB);

pub const LMDBOptions = struct {
    dir_mode: u32 = 0o600,
    max_dbs: u32 = 0,
};

pub const LMDB = struct {
    options: LMDBOptions,
    environment: ?*c.MDB_env,

    pub fn init(dir: std.fs.Dir, options: LMDBOptions) !@This() {
        var env: ?*c.MDB_env = undefined;
        var r = c.mdb_env_create(&env);
        errdefer c.mdb_env_close(env);
        if (r != 0) {
            log.err("Error creating environment: {s}.", .{c.mdb_strerror(r)});
            return error.CreateEnvError;
        }

        if (options.max_dbs > 0) {
            r = c.mdb_env_set_maxdbs(env, options.max_dbs);
        }
        if (r != 0) {
            log.err("Error setting max dbs: {s}.", .{c.mdb_strerror(r)});
            return error.SetMaxDBsError;
        }

        var buffer: [std.fs.MAX_PATH_BYTES:0]u8 = undefined;
        const realpath = try dir.realpath(".", &buffer);
        buffer[realpath.len] = 0;

        // TODO: flags
        r = c.mdb_env_open(env, @as([*c]const u8, @ptrCast(&buffer)), 0, options.dir_mode);
        if (r != 0) {
            log.err("Error opening environment: {s}.", .{c.mdb_strerror(r)});
            return error.EnvOpenError;
        }

        return .{
            .options = options,
            .environment = env,
        };
    }

    pub fn deinit(self: @This()) void {
        c.mdb_env_close(self.environment);
    }

    pub fn begin(self: @This(), mode: Mode) !Transaction {
        return try Transaction.init(self, mode);
    }

    pub fn openDatabase(self: @This(), name: ?[]const u8) !Database {
        errdefer self.deinit();
        const tx = try self.begin(.ReadAndWrite);
        const db = try tx.open(name);
        try tx.commit();
        return db;
    }
};

pub const Database = struct {
    database: c_uint,
    environment: ?*c.MDB_env,

    pub fn deinit(self: @This()) void {
        c.mdb_dbi_close(self.environment, self.database);
    }
};

pub const Transaction = struct {
    environment: ?*c.MDB_env,
    transaction: ?*c.MDB_txn,

    pub fn init(env: LMDB, mode: Mode) !@This() {
        var txn: ?*c.MDB_txn = undefined;
        const r = c.mdb_txn_begin(env.environment, null, @intFromEnum(mode), &txn);
        if (r != 0) {
            log.err("Error trasaction begin: {s}.", .{c.mdb_strerror(r)});
            return error.TransactionBeginError;
        }
        return .{
            .environment = env.environment,
            .transaction = txn,
        };
    }

    pub fn open(self: @This(), name: ?[]const u8) !Database {
        var dbi: c_uint = undefined;
        var r: c_int = 0;
        // TODO: flags
        if (name) |db| {
            r = c.mdb_dbi_open(self.transaction, @as([*c]const u8, @ptrCast(db)), 0x40000, &dbi);
        } else {
            r = c.mdb_dbi_open(self.transaction, null, 0x40000, &dbi);
        }
        if (r != 0) {
            log.err("Error open database: {s}.", .{c.mdb_strerror(r)});
            return error.DBOpenError;
        }
        const db = Database{
            .environment = self.environment,
            .database = dbi,
        };
        return db;
    }

    pub fn withDatabase(self: @This(), db: Database) DBTX {
        return DBTX{
            .environment = self.environment,
            .transaction = self.transaction,
            .database = db.database,
        };
    }

    pub fn abort(self: @This()) void {
        c.mdb_txn_abort(self.transaction);
    }

    pub fn reset(self: @This()) void {
        c.mdb_txn_reset(self.transaction);
    }

    pub fn renew(self: @This()) !void {
        const r = c.mdb_txn_renew(self.transaction);
        if (r != 0) {
            log.err("Error transaction renew: {s}.", .{c.mdb_strerror(r)});
            return error.TransactionRenewFailed;
        }
    }

    pub fn commit(self: @This()) !void {
        const r = c.mdb_txn_commit(self.transaction);
        if (r != 0) {
            log.err("Error transaction commit: {s}.", .{c.mdb_strerror(r)});
            return error.TransactionCommitFailed;
        }
    }
};

pub const DBTX = struct {
    environment: ?*c.MDB_env,
    transaction: ?*c.MDB_txn,
    database: c_uint,

    pub fn get(self: @This(), key: []const u8) ![]const u8 {
        var k = c.MDB_val{ .mv_size = key.len, .mv_data = @as(?*void, @ptrFromInt(@intFromPtr(key.ptr))) };
        var v: c.MDB_val = undefined;

        const r = c.mdb_get(self.transaction, self.database, &k, &v);
        if (r != 0) {
            if (r == c.MDB_NOTFOUND) {
                return "";
            } else {
                log.err("Error get: {s}.", .{c.mdb_strerror(r)});
                return error.GetError;
            }
        }

        const data = @as([*]const u8, @ptrCast(v.mv_data))[0..v.mv_size];
        return data;
    }

    pub fn put(self: @This(), key: []const u8, value: []const u8) !void {
        var k = c.MDB_val{ .mv_size = key.len, .mv_data = @as(?*void, @ptrFromInt(@intFromPtr(key.ptr))) };
        var v = c.MDB_val{ .mv_size = value.len, .mv_data = @as(?*void, @ptrFromInt(@intFromPtr(value.ptr))) };

        // TODO: flags
        const r = c.mdb_put(self.transaction, self.database, &k, &v, 0);
        if (r != 0) {
            log.err("Error put: {s}.", .{c.mdb_strerror(r)});
            return error.PutError;
        }
    }

    pub fn delete(self: @This(), key: []const u8) !void {
        var k = c.MDB_val{ .mv_size = key.len, .mv_data = @as(?*void, @ptrFromInt(@intFromPtr(key.ptr))) };
        var v = c.MDB_val{ .mv_size = 0, .mv_data = null };

        const r = c.mdb_del(self.transaction, self.database, &k, &v);
        if (r != 0) {
            log.err("Error delete: {s}.", .{c.mdb_strerror(r)});
            return error.DeleteError;
        }
    }

    pub fn openCursor(self: @This()) !Cursor {
        var cursor: ?*c.MDB_cursor = undefined;
        const r = c.mdb_cursor_open(self.transaction, self.database, &cursor);
        if (r != 0) {
            log.err("Error opening cursor: {s}.", .{c.mdb_strerror(r)});
            return error.CursorOpenError;
        }
        return .{
            .environment = self.environment,
            .transaction = self.transaction,
            .database = self.database,
            .cursor = cursor,
        };
    }
};

pub const KV = std.meta.Tuple(&[_]type{ []const u8, []const u8 });

pub const Cursor = struct {
    environment: ?*c.MDB_env,
    transaction: ?*c.MDB_txn,
    database: c_uint,
    cursor: ?*c.MDB_cursor,

    pub fn first(self: *@This()) !?KV {
        var k: c.MDB_val = undefined;
        var v: c.MDB_val = undefined;

        const r = c.mdb_cursor_get(self.cursor, &k, &v, c.MDB_FIRST);
        if (r != 0) {
            log.err("Error cursor set: {s}.", .{c.mdb_strerror(r)});
            return error.CursorSetError;
        }

        const key = @as([*]const u8, @ptrCast(k.mv_data))[0..k.mv_size];
        const value = @as([*]const u8, @ptrCast(v.mv_data))[0..v.mv_size];
        return .{ key, value };
    }

    pub fn set(self: *@This(), key: []const u8) !?KV {
        var k = c.MDB_val{ .mv_size = key.len, .mv_data = @as(?*void, @ptrFromInt(@intFromPtr(key.ptr))) };
        var v: c.MDB_val = undefined;

        const r = c.mdb_cursor_get(self.cursor, &k, &v, c.MDB_SET);
        if (r != 0) {
            log.err("Error cursor set: {s}.", .{c.mdb_strerror(r)});
            return error.CursorSetError;
        }

        const value = @as([*]const u8, @ptrCast(v.mv_data))[0..v.mv_size];
        return .{ key, value };
    }

    pub fn next(self: *@This()) !?KV {
        var k: c.MDB_val = undefined;
        var v: c.MDB_val = undefined;

        const r = c.mdb_cursor_get(self.cursor, &k, &v, c.MDB_NEXT);
        if (r != 0) {
            if (r == c.MDB_NOTFOUND) {
                return null;
            } else {
                log.err("Error cursor next: {s}.", .{c.mdb_strerror(r)});
                return error.CursorNextError;
            }
        }

        const key = @as([*]const u8, @ptrCast(k.mv_data))[0..k.mv_size];
        const value = @as([*]const u8, @ptrCast(v.mv_data))[0..v.mv_size];
        return .{ key, value };
    }

    pub fn deinit(self: *@This()) void {
        c.mdb_cursor_close(self.cursor);
    }
};

test "lmdb basic" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try LMDB.init(tmp.dir, .{ .max_dbs = 1 });
    defer env.deinit();
    const db = try env.openDatabase("mydb");

    const tx = try env.begin(.ReadAndWrite);
    const dbTX = tx.withDatabase(db);
    try dbTX.put("key", "value");
    try dbTX.put("key2", "value2");
    try tx.commit();

    const tx2 = try env.begin(.ReadAndWrite);
    const dbTX2 = tx2.withDatabase(db);
    try dbTX2.put("key", "value2");
    tx2.abort();

    // TODO: del

    const txDel = try env.begin(.ReadAndWrite);
    const dbTXDel = txDel.withDatabase(db);
    try dbTXDel.delete("key2");
    try txDel.commit();

    const txR = try env.begin(.ReadOnly);
    const dbTXR = txR.withDatabase(db);
    const value = try dbTXR.get("key");
    const noValue = try dbTXR.get("key2");

    try testing.expectEqualStrings("value", value);
    try testing.expectEqualStrings("", noValue);
    try txR.commit();
}

test "lmdb single null DB" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try LMDB.init(tmp.dir, .{});
    defer env.deinit();
    const db = try env.openDatabase(null);

    const tx = try env.begin(.ReadAndWrite);
    const dbTX = tx.withDatabase(db);
    try dbTX.put("key", "valueNULL");
    try tx.commit();

    const tx3 = try env.begin(.ReadOnly);
    const dbTX3 = tx3.withDatabase(db);
    const value = try dbTX3.get("key");
    try testing.expectEqualStrings("valueNULL", value);
    try tx3.commit();
}

test "lmdb cursors" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try LMDB.init(tmp.dir, .{});
    defer env.deinit();
    const db = try env.openDatabase(null);

    const tx = try env.begin(.ReadAndWrite);
    const dbTX = tx.withDatabase(db);
    try dbTX.put("key0", "value 0");
    try dbTX.put("key1", "value 1");
    try dbTX.put("key2", "value 2");
    try dbTX.put("key3", "value 3");
    try tx.commit();

    const tx2 = try env.begin(.ReadOnly);
    const dbTX2 = tx2.withDatabase(db);

    var cursor = try dbTX2.openCursor();
    defer cursor.deinit();

    var values: [3][]const u8 = undefined;
    var i: usize = 0;

    var mkv = try cursor.set("key1");
    while (mkv) |kv| {
        values[i] = kv[1];
        i += 1;
        mkv = try cursor.next();
    }

    try tx2.commit();

    try testing.expectEqualStrings("value 1", values[0]);
    try testing.expectEqualStrings("value 2", values[1]);
    try testing.expectEqualStrings("value 3", values[2]);
}