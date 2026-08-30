//! Wrapper and utilities for interacting with LMDB.
//! You should start at Environment.

const std = @import("std");
const testing = std.testing;

const c = @import("c");

/// Errors mapped from LMDB return codes (and the errno values LMDB passes through).
pub const Error = error{
    KeyExist,
    NotFound,
    PageNotFound,
    Corrupted,
    Panic,
    VersionMismatch,
    Invalid,
    MapFull,
    DbsFull,
    ReadersFull,
    TlsFull,
    TxnFull,
    CursorFull,
    PageFull,
    MapResized,
    Incompatible,
    BadRslot,
    BadTxn,
    BadValSize,
    BadDbi,
    /// Write attempted in a read-only transaction or environment, or permission denied on disk.
    AccessDenied,
    OutOfMemory,
    InvalidArgument,
    FileNotFound,
    NoSpaceLeft,
    InputOutput,
    /// The environment is locked by another process.
    Locked,
    Busy,
    Unexpected,
};

/// Translate an LMDB return code into an Error.
fn check(rc: c_int) Error!void {
    return switch (rc) {
        0 => {},
        c.MDB_KEYEXIST => error.KeyExist,
        c.MDB_NOTFOUND => error.NotFound,
        c.MDB_PAGE_NOTFOUND => error.PageNotFound,
        c.MDB_CORRUPTED => error.Corrupted,
        c.MDB_PANIC => error.Panic,
        c.MDB_VERSION_MISMATCH => error.VersionMismatch,
        c.MDB_INVALID => error.Invalid,
        c.MDB_MAP_FULL => error.MapFull,
        c.MDB_DBS_FULL => error.DbsFull,
        c.MDB_READERS_FULL => error.ReadersFull,
        c.MDB_TLS_FULL => error.TlsFull,
        c.MDB_TXN_FULL => error.TxnFull,
        c.MDB_CURSOR_FULL => error.CursorFull,
        c.MDB_PAGE_FULL => error.PageFull,
        c.MDB_MAP_RESIZED => error.MapResized,
        c.MDB_INCOMPATIBLE => error.Incompatible,
        c.MDB_BAD_RSLOT => error.BadRslot,
        c.MDB_BAD_TXN => error.BadTxn,
        c.MDB_BAD_VALSIZE => error.BadValSize,
        c.MDB_BAD_DBI => error.BadDbi,
        @intFromEnum(std.posix.E.ACCES) => error.AccessDenied,
        @intFromEnum(std.posix.E.NOMEM) => error.OutOfMemory,
        @intFromEnum(std.posix.E.INVAL) => error.InvalidArgument,
        @intFromEnum(std.posix.E.NOENT) => error.FileNotFound,
        @intFromEnum(std.posix.E.NOSPC) => error.NoSpaceLeft,
        @intFromEnum(std.posix.E.IO) => error.InputOutput,
        @intFromEnum(std.posix.E.AGAIN) => error.Locked,
        @intFromEnum(std.posix.E.BUSY) => error.Busy,
        else => error.Unexpected,
    };
}

fn toVal(bytes: []const u8) c.MDB_val {
    return .{ .mv_size = bytes.len, .mv_data = @ptrCast(@constCast(bytes.ptr)) };
}

fn fromVal(v: c.MDB_val) []const u8 {
    return @as([*]const u8, @ptrCast(v.mv_data))[0..v.mv_size];
}

/// TransactionMode.
pub const TransactionMode = enum(c_uint) {
    ReadAndWrite = 0,
    ReadOnly = c.MDB_RDONLY,
};

/// Flags applied when opening an Environment. See the LMDB documentation of `mdb_env_open`.
pub const EnvironmentFlags = struct {
    /// Open the environment read-only. No write transactions can be started.
    read_only: bool = false,
    /// Do not flush system buffers to disk when committing (MDB_NOSYNC).
    no_sync: bool = false,
    /// Flush data but not the meta page on commit (MDB_NOMETASYNC).
    no_meta_sync: bool = false,
    /// Use a writable memory map (MDB_WRITEMAP).
    write_map: bool = false,
    /// With `write_map`, use asynchronous flushes (MDB_MAPASYNC).
    map_async: bool = false,
    /// Do not tie read-only transactions to threads (MDB_NOTLS).
    /// Required if read-only transactions may be used from a thread other than the one that began them.
    no_tls: bool = false,
    /// Do not do any locking; the caller must serialize access (MDB_NOLOCK).
    no_lock: bool = false,
    /// Turn off readahead (MDB_NORDAHEAD).
    no_read_ahead: bool = false,
    /// Do not initialize malloc'd memory before writing it to disk (MDB_NOMEMINIT).
    no_mem_init: bool = false,

    fn toC(self: EnvironmentFlags) c_uint {
        var flags: c_uint = 0;
        if (self.read_only) flags |= c.MDB_RDONLY;
        if (self.no_sync) flags |= c.MDB_NOSYNC;
        if (self.no_meta_sync) flags |= c.MDB_NOMETASYNC;
        if (self.write_map) flags |= c.MDB_WRITEMAP;
        if (self.map_async) flags |= c.MDB_MAPASYNC;
        if (self.no_tls) flags |= c.MDB_NOTLS;
        if (self.no_lock) flags |= c.MDB_NOLOCK;
        if (self.no_read_ahead) flags |= c.MDB_NORDAHEAD;
        if (self.no_mem_init) flags |= c.MDB_NOMEMINIT;
        return flags;
    }
};

/// Options when you open an environment.
pub const EnvironmentOptions = struct {
    /// UNIX permissions for the data and lock files LMDB creates inside the directory.
    file_mode: u16 = 0o600,
    /// Maximum number of named databases. Zero keeps LMDB's default, which allows none.
    max_dbs: u32 = 0,
    /// Size of the memory map in bytes; this is also the maximum size of the database.
    /// Zero keeps LMDB's default of 1 MiB, which is enough for little more than experiments.
    map_size: usize = 0,
    /// Maximum number of concurrent read-only transactions. Zero keeps LMDB's default (126).
    max_readers: u32 = 0,
    /// Environment flags.
    flags: EnvironmentFlags = .{},
};

/// To start using LMDB you need an Environment.
/// It will wrap LMDB native environment and allow you to open Databases and start Transactions.
pub const Environment = struct {
    /// Hold a reference to LMDB environment.
    environment: ?*c.MDB_env,

    /// Create and open an environment stored in `dir`.
    pub fn init(io: std.Io, dir: std.Io.Dir, options: EnvironmentOptions) !Environment {
        var env: ?*c.MDB_env = null;
        try check(c.mdb_env_create(&env));
        errdefer c.mdb_env_close(env);

        if (options.max_dbs > 0) try check(c.mdb_env_set_maxdbs(env, options.max_dbs));
        if (options.map_size > 0) try check(c.mdb_env_set_mapsize(env, options.map_size));
        if (options.max_readers > 0) try check(c.mdb_env_set_maxreaders(env, options.max_readers));

        var buffer: [std.Io.Dir.max_path_bytes:0]u8 = undefined;
        const realpath_len = try dir.realPath(io, &buffer);
        buffer[realpath_len] = 0;

        try check(c.mdb_env_open(env, @as([*c]const u8, @ptrCast(&buffer)), options.flags.toC(), options.file_mode));

        return .{ .environment = env };
    }

    /// Close the Environment. All transactions must be finished and all cursors closed before this.
    pub fn deinit(self: Environment) void {
        c.mdb_env_close(self.environment);
    }

    /// Begin a Transaction on active Environment.
    pub fn beginTransaction(self: Environment, mode: TransactionMode) Error!Transaction {
        return try Transaction.init(self, mode);
    }

    /// Open (creating if needed) a Database on this Environment, handling the initial Transaction.
    /// `null` opens the unnamed main database. Named databases require `EnvironmentOptions.max_dbs`.
    pub fn openDatabase(self: Environment, name: ?[:0]const u8) Error!Database {
        var tx = try self.beginTransaction(.ReadAndWrite);
        errdefer tx.abort();
        const db = try tx.open(name);
        try tx.commit();
        return db;
    }
};

/// Hold a reference to an open Database.
/// Should be created via Environment.openDatabase or Transaction.open.
pub const Database = struct {
    database: c.MDB_dbi,
    environment: ?*c.MDB_env,

    /// Close the database handle. Normally unnecessary: handles are cheap and live as long as the
    /// Environment. LMDB documents this as unsafe while any transaction or cursor may still use the
    /// handle, so prefer not to call it at all.
    pub fn deinit(self: Database) void {
        c.mdb_dbi_close(self.environment, self.database);
    }
};

/// Hold an open Transaction.
/// Can also be created from Environment.beginTransaction.
///
/// `commit` and `abort` both invalidate the handle; calling `abort` afterwards is a no-op,
/// so `defer tx.abort()` right after beginning a transaction is the recommended pattern.
pub const Transaction = struct {
    environment: ?*c.MDB_env,
    transaction: ?*c.MDB_txn,
    mode: TransactionMode,

    /// Begin a Transaction with given TransactionMode.
    pub fn init(env: Environment, mode: TransactionMode) Error!Transaction {
        var txn: ?*c.MDB_txn = null;
        try check(c.mdb_txn_begin(env.environment, null, @intFromEnum(mode), &txn));
        return .{
            .environment = env.environment,
            .transaction = txn,
            .mode = mode,
        };
    }

    /// Open a Database from this Transaction. `null` opens the unnamed main database.
    /// In a read-write transaction a missing named database is created; in a read-only
    /// transaction `error.NotFound` is returned instead.
    /// LMDB forbids calling this from concurrent transactions of the same process, and the
    /// handle is only usable by other transactions after this one commits.
    pub fn open(self: Transaction, name: ?[:0]const u8) Error!Database {
        var dbi: c.MDB_dbi = undefined;
        // TODO: flags
        const flags: c_uint = if (self.mode == .ReadOnly) 0 else c.MDB_CREATE;
        const cname: [*c]const u8 = if (name) |n| n.ptr else null;
        try check(c.mdb_dbi_open(self.transaction, cname, flags, &dbi));
        return .{
            .environment = self.environment,
            .database = dbi,
        };
    }

    /// Utility to work with a Database (already opened) in this Transaction.
    pub fn withDatabase(self: Transaction, db: Database) DBTX {
        return .{
            .environment = self.environment,
            .transaction = self.transaction,
            .database = db.database,
        };
    }

    /// Abort the Transaction and release its handle. No-op if already committed or aborted.
    pub fn abort(self: *Transaction) void {
        c.mdb_txn_abort(self.transaction);
        self.transaction = null;
    }

    /// Reset a read-only Transaction, releasing its snapshot but keeping the handle for `renew`.
    /// Does nothing on read-write transactions.
    pub fn reset(self: Transaction) void {
        c.mdb_txn_reset(self.transaction);
    }

    /// Renew a read-only Transaction previously `reset`, acquiring a fresh snapshot.
    pub fn renew(self: Transaction) Error!void {
        try check(c.mdb_txn_renew(self.transaction));
    }

    /// Commit the Transaction. The handle is released whether or not the commit succeeds.
    pub fn commit(self: *Transaction) Error!void {
        const rc = c.mdb_txn_commit(self.transaction);
        self.transaction = null;
        try check(rc);
    }
};

/// Utility to hold an open Database, in a Transaction.
/// Create it from Transaction.withDatabase.
pub const DBTX = struct {
    environment: ?*c.MDB_env,
    transaction: ?*c.MDB_txn,
    database: c.MDB_dbi,

    /// Get the value stored at `key`, or `null` if the key is absent.
    /// The slice points into the memory map: valid only until the transaction ends or the next write.
    pub fn get(self: DBTX, key: []const u8) Error!?[]const u8 {
        var k = toVal(key);
        var v: c.MDB_val = undefined;
        check(c.mdb_get(self.transaction, self.database, &k, &v)) catch |err| switch (err) {
            error.NotFound => return null,
            else => |e| return e,
        };
        return fromVal(v);
    }

    /// Put value on key, replacing any existing value.
    pub fn put(self: DBTX, key: []const u8, value: []const u8) Error!void {
        var k = toVal(key);
        var v = toVal(value);
        // TODO: flags
        try check(c.mdb_put(self.transaction, self.database, &k, &v, 0));
    }

    /// Delete key. Returns `error.NotFound` if the key is absent.
    pub fn delete(self: DBTX, key: []const u8) Error!void {
        var k = toVal(key);
        try check(c.mdb_del(self.transaction, self.database, &k, null));
    }

    /// Open a Cursor, for iterating over keys.
    /// In a read-write transaction the cursor must be closed with `Cursor.deinit` before the
    /// transaction ends; in a read-only transaction it must be closed explicitly, before or after.
    pub fn openCursor(self: DBTX) Error!Cursor {
        var cursor: ?*c.MDB_cursor = null;
        try check(c.mdb_cursor_open(self.transaction, self.database, &cursor));
        return .{
            .environment = self.environment,
            .transaction = self.transaction,
            .database = self.database,
            .cursor = cursor,
        };
    }
};

/// A KeyValue pair. Both slices point into the memory map; see the module docs for their lifetime.
pub const KV = struct {
    key: []const u8,
    value: []const u8,
};

/// Cursors are used for iterating over a Database.
/// You can get it from a DBTX.
pub const Cursor = struct {
    environment: ?*c.MDB_env,
    transaction: ?*c.MDB_txn,
    database: c.MDB_dbi,
    cursor: ?*c.MDB_cursor,

    fn getOp(self: Cursor, k: *c.MDB_val, op: c.MDB_cursor_op) Error!?KV {
        var v: c.MDB_val = undefined;
        check(c.mdb_cursor_get(self.cursor, k, &v, op)) catch |err| switch (err) {
            error.NotFound => return null,
            else => |e| return e,
        };
        return .{ .key = fromVal(k.*), .value = fromVal(v) };
    }

    /// Position at the first key and return it, or `null` if the Database is empty.
    pub fn first(self: *Cursor) Error!?KV {
        var k: c.MDB_val = undefined;
        return self.getOp(&k, c.MDB_FIRST);
    }

    /// Position at `key` and return it, or `null` if the key is absent.
    pub fn set(self: *Cursor, key: []const u8) Error!?KV {
        var k = toVal(key);
        return self.getOp(&k, c.MDB_SET_KEY);
    }

    /// Advance to the next key and return it, or `null` at the end.
    pub fn next(self: *Cursor) Error!?KV {
        var k: c.MDB_val = undefined;
        return self.getOp(&k, c.MDB_NEXT);
    }

    /// Close the cursor. No-op if already closed.
    pub fn deinit(self: *Cursor) void {
        c.mdb_cursor_close(self.cursor);
        self.cursor = null;
    }
};

test "lmdb basic" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.init(testing.io, tmp.dir, .{ .max_dbs = 1 });
    defer env.deinit();
    const db = try env.openDatabase("mydb");

    var tx = try env.beginTransaction(.ReadAndWrite);
    defer tx.abort();
    const dbTX = tx.withDatabase(db);
    try dbTX.put("key", "value");
    try dbTX.put("key2", "value2");
    try tx.commit();

    var tx2 = try env.beginTransaction(.ReadAndWrite);
    try tx2.withDatabase(db).put("key", "value2");
    tx2.abort();

    var txDel = try env.beginTransaction(.ReadAndWrite);
    defer txDel.abort();
    try txDel.withDatabase(db).delete("key2");
    try testing.expectError(error.NotFound, txDel.withDatabase(db).delete("missing"));
    try txDel.commit();

    var txR = try env.beginTransaction(.ReadOnly);
    defer txR.abort();
    const dbTXR = txR.withDatabase(db);
    try testing.expectEqualStrings("value", (try dbTXR.get("key")).?);
    try testing.expect((try dbTXR.get("key2")) == null);
}

test "lmdb single null DB" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.init(testing.io, tmp.dir, .{});
    defer env.deinit();
    const db = try env.openDatabase(null);

    var tx = try env.beginTransaction(.ReadAndWrite);
    defer tx.abort();
    try tx.withDatabase(db).put("key", "valueNULL");
    try tx.commit();

    var tx2 = try env.beginTransaction(.ReadOnly);
    defer tx2.abort();
    try testing.expectEqualStrings("valueNULL", (try tx2.withDatabase(db).get("key")).?);
}

test "lmdb cursors" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.init(testing.io, tmp.dir, .{});
    defer env.deinit();
    const db = try env.openDatabase(null);

    var tx = try env.beginTransaction(.ReadAndWrite);
    defer tx.abort();
    const dbTX = tx.withDatabase(db);
    try dbTX.put("key0", "value 0");
    try dbTX.put("key1", "value 1");
    try dbTX.put("key2", "value 2");
    try dbTX.put("key3", "value 3");
    try tx.commit();

    var tx2 = try env.beginTransaction(.ReadOnly);
    defer tx2.abort();
    var cursor = try tx2.withDatabase(db).openCursor();
    defer cursor.deinit();

    var values: [3][]const u8 = undefined;
    var i: usize = 0;
    var mkv = try cursor.set("key1");
    while (mkv) |kv| : (mkv = try cursor.next()) {
        values[i] = kv.value;
        i += 1;
    }
    // Compared while the transaction is still open: the slices point into the map.
    try testing.expectEqual(3, i);
    try testing.expectEqualStrings("value 1", values[0]);
    try testing.expectEqualStrings("value 2", values[1]);
    try testing.expectEqualStrings("value 3", values[2]);

    const kv0 = (try cursor.first()).?;
    try testing.expectEqualStrings("key0", kv0.key);
    try testing.expectEqualStrings("value 0", kv0.value);
    try testing.expect((try cursor.set("nope")) == null);
}

test "lmdb cursor in a write transaction is closed before commit" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.init(testing.io, tmp.dir, .{});
    defer env.deinit();
    const db = try env.openDatabase(null);

    var tx = try env.beginTransaction(.ReadAndWrite);
    defer tx.abort();
    var cursor = try tx.withDatabase(db).openCursor();
    try testing.expect((try cursor.first()) == null);
    try testing.expect((try cursor.next()) == null);
    try testing.expect((try cursor.set("nope")) == null);
    cursor.deinit();
    try tx.commit();
}

test "lmdb read-only transaction rejects writes" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.init(testing.io, tmp.dir, .{ .max_dbs = 2 });
    defer env.deinit();
    const db = try env.openDatabase(null);

    var tx = try env.beginTransaction(.ReadOnly);
    defer tx.abort();
    try testing.expectError(error.AccessDenied, tx.withDatabase(db).put("key", "value"));
    try testing.expectError(error.NotFound, tx.open("does-not-exist"));
}

test "lmdb openDatabase failure leaves the environment usable" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Default max_dbs allows no named databases.
    const env = try Environment.init(testing.io, tmp.dir, .{});
    defer env.deinit();
    try testing.expectError(error.DbsFull, env.openDatabase("named"));

    const db = try env.openDatabase(null);
    var tx = try env.beginTransaction(.ReadAndWrite);
    defer tx.abort();
    try tx.withDatabase(db).put("key", "value");
    try tx.commit();
}

test "lmdb reset and renew a read-only transaction" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.init(testing.io, tmp.dir, .{ .flags = .{ .no_tls = true } });
    defer env.deinit();
    const db = try env.openDatabase(null);

    var reader = try env.beginTransaction(.ReadOnly);
    defer reader.abort();
    try testing.expect((try reader.withDatabase(db).get("key")) == null);
    reader.reset();

    var writer = try env.beginTransaction(.ReadAndWrite);
    defer writer.abort();
    try writer.withDatabase(db).put("key", "value");
    try writer.commit();

    try reader.renew();
    try testing.expectEqualStrings("value", (try reader.withDatabase(db).get("key")).?);
}

fn fill(env: Environment, db: Database, count: usize) Error!void {
    var tx = try env.beginTransaction(.ReadAndWrite);
    defer tx.abort();
    const dbTX = tx.withDatabase(db);
    const value = [_]u8{'x'} ** 4096;
    var key: [8]u8 = undefined;
    for (0..count) |i| {
        const k = std.fmt.bufPrint(&key, "{d:0>8}", .{i}) catch unreachable;
        try dbTX.put(k, &value);
    }
    try tx.commit();
}

test "lmdb map size" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.init(testing.io, tmp.dir, .{ .map_size = 16 * 1024 * 1024 });
    defer env.deinit();
    const db = try env.openDatabase(null);
    try fill(env, db, 512);
}

test "lmdb default map size is 1 MiB" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.init(testing.io, tmp.dir, .{});
    defer env.deinit();
    const db = try env.openDatabase(null);
    try testing.expectError(error.MapFull, fill(env, db, 512));
}
