# LMDB for Zig

This is a wrapper for LMDB. Includes compiling LMDB from source.

Tested with Zig 0.16.0.

## Install

Fetch the dependency:

```sh
zig fetch --save git+https://github.com/diogok/lmdb-zig
```

Then wire it into your `build.zig`:

```zig
const lmdb = b.dependency("lmdb", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("lmdb", lmdb.module("lmdb"));
```

LMDB itself is built from source by this package — no system dependency required.

## Usage

Check the full documentation at https://diogok.github.io/lmdb-zig.

```zig
// This is the directory the DB will be stored
var tmp = testing.tmpDir(.{});
defer tmp.cleanup();

// We start by creating an Environment.
// The default map size is 1 MiB; set `map_size` to the maximum size your database may grow to.
const env = try Environment.init(testing.io, tmp.dir, .{ .map_size = 1024 * 1024 * 1024 });
defer env.deinit();

// Next we get a Database handler (null is the unnamed main database;
// named databases need `.max_dbs` in the options above)
const db = try env.openDatabase(null);

// To write data, we begin a RW transaction.
// `abort` is a no-op after `commit`, so deferring it is the safe default.
var tx = try env.beginTransaction(.ReadAndWrite);
defer tx.abort();
// And use the Transaction to interact with the Database
const dbTX = tx.withDatabase(db);

// Finally, we put some data
try dbTX.put("key0", "value 0");
try dbTX.put("key1", "value 1");
try dbTX.put("key2", "value 2");
try dbTX.put("key3", "value 3");

// And commit
try tx.commit();

// Next, we start a RO transaction to read the data
var tx2 = try env.beginTransaction(.ReadOnly);
defer tx2.abort();
const dbTX2 = tx2.withDatabase(db);

// We can read values by key; a missing key yields null.
// Returned slices point into LMDB's memory map and are only valid
// until the transaction ends, so copy them if you need to keep them.
const value0 = try dbTX2.get("key0");
const missing = try dbTX2.get("nope"); // null

// We can also open a Cursor to iterate over some keys.
// (In a RW transaction, close the cursor before committing.)
var cursor = try dbTX2.openCursor();
defer cursor.deinit();

// Set the Cursor at a specific key
var mkv = try cursor.set("key1");
while (mkv) |kv| : (mkv = try cursor.next()) {
    // kv.key is the current key
    // kv.value is the current value for that key
}
```

Errors are returned as `lmdb.Error` (`error.NotFound`, `error.MapFull`, `error.AccessDenied`, ...);
nothing is logged.

## License

MIT

