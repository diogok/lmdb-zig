# LMDB for Zig

This is a wrapper for LMDB. Includes compiling LMDB from source.

Tested with Zig 0.13.0.

## Usage

Check the full documentation at [https://diogok.github.io/lmdb-zig/docs/].

```zig
// This is the directory the DB will be stored
var tmp = testing.tmpDir(.{});
defer tmp.cleanup();

// We start by creating an Environment
const env = try Environment.init(tmp.dir, .{});
defer env.deinit();

// Next we get a Database handler
const db = try env.openDatabase(null);

// To write data, we begin a RW transaction
const tx = try env.beginTransaction(.ReadAndWrite);
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
const tx2 = try env.beginTransaction(.ReadOnly);
const dbTX2 = tx2.withDatabase(db);

// We can read values by key
const value0 = dbTX1.get("key0");

// We can also open a Cursor to iterate over some keys
var cursor = try dbTX2.openCursor();
defer cursor.deinit();

// Set the Cursor at a specific key
var mkv = try cursor.set("key1");
while (mkv) |kv| {
	// kv[0] is the current key
	// kv[1] is the current value for that key
    mkv = try cursor.next();
}

// We still release the RO Transaction
try tx2.commit();
```

## License

MIT

