= Vector Type Support Plan (Issue #1526)

== Context

Databases are adding native vector types for AI embedding workloads. This plan introduces a
unified Vector type hierarchy in `io.vertx.sqlclient.data` and wires it into PostgreSQL
(pgvector), MySQL 8.4+, MariaDB 11.7+, SQL Server 2025, and Oracle 23ai. DB2 is excluded
per the issue.

Full research references: `Vector types research.md` and `pgvector OID research.md` in the
repo root.

---

== Phase 1 — Vector type hierarchy in `io.vertx.sqlclient`

=== 1a. Base interface

`io.vertx.sqlclient.data.Vector` — a plain interface (project targets Java 11; sealed classes
are Java 17+).

[source,java]
----
public interface Vector {
  int dimension();  // total number of dimensions (Langchain4j singular convention)
}
----

No `equals`/`hashCode` on the interface — not justified by current use cases.

=== 1b. Concrete types

All classes live in `io.vertx.sqlclient.data`. Factory methods named `create(...)` (Vert.x
standard). No defensive copies anywhere — callers and codecs both trust the array is not
mutated externally.

==== `FloatVector` — float32, the dominant type

Covers: PG `vector`, MySQL `VECTOR`, MariaDB `VECTOR`, MSSQL `VECTOR(float32)`, Oracle
`VECTOR_FLOAT32`.

Lazy conversion: exactly one of `textValue` or `floatValues` is set at construction; the
other is computed on demand. Not thread-safe — consistent with Vert.x conventions.

[source,java]
----
public final class FloatVector implements Vector {
  public static FloatVector create(String text)     // stores text; zero parsing upfront
  public static FloatVector create(float[] values)  // stores reference directly
  public static FloatVector create(double[] values) // converts lossy to float[], stores ref

  public float[]  toFloatArray()   // returns internal array, or parses text lazily
  public double[] toDoubleArray()  // converts from internal float[]
  public int      dimension()
  // toString(): "[x,y,z]" — no spaces; computed lazily from float[]
}
----

==== `HalfFloatVector` — float16

Covers: PG `halfvec`, MSSQL `VECTOR(float16)`.

Internally stored as `float[]` (Java 11 has no native float16; precision is
float16-constrained).

[source,java]
----
public final class HalfFloatVector implements Vector {
  public static HalfFloatVector create(String text)
  public static HalfFloatVector create(float[] values) // stores reference

  public float[] toFloatArray()
  public int     dimension()
  // toString(): "[x,y,z]"
}
----

==== `DoubleVector` — float64

Covers: Oracle `VECTOR_FLOAT64`.

[source,java]
----
public final class DoubleVector implements Vector {
  public static DoubleVector create(String text)
  public static DoubleVector create(double[] values) // stores reference
  public static DoubleVector create(float[] values)  // widens to double[], stores ref

  public double[] toDoubleArray()
  public float[]  toFloatArray()  // lossy
  public int      dimension()
  // toString(): "[x,y,z]"
}
----

==== `ByteVector` — int8

Covers: Oracle `VECTOR_INT8`.

[source,java]
----
public final class ByteVector implements Vector {
  public static ByteVector create(String text)
  public static ByteVector create(byte[] values) // stores reference

  public byte[] toByteArray()
  public int    dimension()
  // toString(): "[x,y,z]"
}
----

==== `BitVector` — bit/binary

Covers: PG `bit` (binary vector), Oracle `VECTOR_BINARY`.

Bits are packed: 8 bits per byte, MSB first.

[source,java]
----
public final class BitVector implements Vector {
  public static BitVector create(boolean[] bits)
  public static BitVector create(byte[] packedBits, int bitLength) // stores reference

  public boolean[] toBooleanArray()
  public byte[]    toPackedByteArray() // returns internal array
  public int       dimension()         // number of bits
  // toString(): binary digit string "10101010..." (PG text format for bit type)
}
----

==== `SparseFloatVector` — sparse float32

Covers: PG `sparsevec`, Oracle `SparseFloatArray` (client-side sparse binding).

[source,java]
----
public final class SparseFloatVector implements Vector {
  public static SparseFloatVector create(int dimensions, int[] indices, float[] values)
  // stores references — no copies

  public int     dimension()  // total dimensions (including zeros)
  public int[]   indices()    // zero-based, ascending, non-zero positions
  public float[] values()     // non-zero values at those indices
  // toString(): "{1:v1,2:v2,...}/dimensions" — PG text format, 1-based indices
}
----

==== `SparseDoubleVector` — sparse float64

Covers: Oracle `SparseDoubleArray`.

[source,java]
----
public final class SparseDoubleVector implements Vector {
  public static SparseDoubleVector create(int dimensions, int[] indices, double[] values)
  // same accessor pattern as SparseFloatVector
}
----

==== `SparseByteVector` — sparse int8

Covers: Oracle `SparseByteArray`.

[source,java]
----
public final class SparseByteVector implements Vector {
  public static SparseByteVector create(int dimensions, int[] indices, byte[] values)
  // same accessor pattern
}
----

=== 1c. `NullValue` additions

Add constants: `NullValue.FloatVector`, `NullValue.HalfFloatVector`, `NullValue.DoubleVector`,
`NullValue.ByteVector`, `NullValue.BitVector`, etc.

=== 1d. Module

`io.vertx.sqlclient.data` is already exported in
`vertx-sql-client/src/main/java/module-info.java`; no change needed.

---

== Phase 2 — PostgreSQL (`vertx-pg-client`)

=== 2a. `PgConnectOptions`

Add field + accessors following the `useLayer7Proxy` pattern:

[source,java]
----
private boolean vectorTypeEnabled = false;
public PgConnectOptions setVectorTypeEnabled(boolean enabled)
public boolean isVectorTypeEnabled()
----

Update all copy constructors, `equals()`, `hashCode()`.

=== 2b. Post-auth dynamic OID discovery

`InitPgCommandMessage.handleReadyForQuery()` — after the UTF-8 check, if `vectorTypeEnabled`:

[source,sql]
----
SELECT typname, oid FROM pg_type WHERE typname IN ('vector', 'halfvec', 'sparsevec')
----

Parse the result into a `Map<String, Integer>` (typname→oid). Call
`pgDecoder.setVectorOids(map)`. Then complete the connection future. If pgvector is not
installed, zero rows are returned and the map is empty (feature silently skipped).

The `bit` type (OID 1560) is fixed and requires no discovery.

=== 2c. `PgDecoder` — dynamic OID resolution

Add `Map<Integer, DataType> dynamicOidMap = Collections.emptyMap()` field and
`setVectorOids(Map<String,Integer>)` setter that builds the reverse map.

In `decodeRowDescription()` at the `DataType.valueOf(typeOID)` call:

[source,java]
----
DataType dataType = DataType.valueOf(typeOID);
if (dataType == DataType.UNKNOWN) {
  dataType = dynamicOidMap.getOrDefault(typeOID, DataType.UNKNOWN);
}
----

=== 2d. `DataType` enum — new entries

All with sentinel OID -1 (never in oidToDataType static map; matched only via dynamic
lookup):

[source,java]
----
VECTOR(-1, true, FloatVector.class, JDBCType.OTHER, ...),
HALFVEC(-1, true, HalfFloatVector.class, JDBCType.OTHER, ...),
SPARSEVEC(-1, true, SparseFloatVector.class, JDBCType.OTHER, ...),
// BIT already exists or needs to be extended for vector usage
----

Static initialization:

[source,java]
----
encodingTypeToDataType.put(FloatVector.class,       VECTOR);
encodingTypeToDataType.put(HalfFloatVector.class,   HALFVEC);
encodingTypeToDataType.put(SparseFloatVector.class, SPARSEVEC);
encodingTypeToDataType.put(BitVector.class,         BIT);  // or existing BIT entry
----

=== 2e. `DataTypeCodec` — new codecs

*`vector` (FloatVector), binary, big-endian:*

* Decode: read int16 dims, skip int16 reserved, read dims×float32 → `FloatVector.create(floatArr)`
* Encode: write int16 dims, int16 0, dims×float32

*`halfvec` (HalfFloatVector), binary, big-endian:*

* Decode: read int16 dims, skip int16, read dims×uint16 → convert each uint16 to float32
  using IEEE 754 half-precision → `HalfFloatVector.create(floatArr)`
* Encode: reverse (float32 → uint16 half-precision)
* Note: half-float conversion requires manual bit manipulation on Java 11
  (sign=bit15, exponent=bits14-10, mantissa=bits9-0)

*`sparsevec` (SparseFloatVector), binary, big-endian:*

* Decode: read int32 dims, int32 nnz, skip int32 reserved, read nnz×int32 indices,
  nnz×float32 values → `SparseFloatVector.create(dims, indices, values)`
* Encode: reverse

*Text decoding for all types:*

* `FloatVector` / `HalfFloatVector`: `FloatVector.create(text)` / `HalfFloatVector.create(text)`
* `SparseFloatVector`: parse `{1:0.5,100:-0.25}/65535` format
* `BitVector`: parse binary digit string

---

== Phase 3 — MySQL / MariaDB (`vertx-mysql-client`)

Both MySQL 8.4+ and MariaDB 11.7+ support a single `VECTOR` type: float32, little-endian.

=== 3a. Column type constant

`ColumnDefinition.java`: add `public static final short MYSQL_TYPE_VECTOR = 242;`
(0xF2 — verify during implementation against MySQL connector/J 8.4+.)

=== 3b. `DataType` enum

Add `VECTOR(MYSQL_TYPE_VECTOR, FloatVector.class, JDBCType.OTHER)`.
Add to `COLUMN_TYPE_TO_DATA_TYPE_MAPPING`.

=== 3c. Codec

*Binary decode* (most common path): raw blob bytes, no header — dimension count = byte length / 4.
Read each 4-byte group as little-endian float32 → `FloatVector.create(floatArr)`.

*Text decode*: `FloatVector.create(text)` (text arrives as `[0.1,0.2,0.3]` via
`VECTOR_TO_STRING()`).

*Binary encode*: send raw little-endian float32 bytes (no header) as BLOB binding.

*Text encode*: `v.toString()` — user must wrap in `STRING_TO_VECTOR(?)` in SQL.

---

== Phase 4 — SQL Server 2025 (`vertx-mssql-client`)

SQL Server 2025 VECTOR uses TDS feature extension 0x0E. Two sub-types: FLOAT32 (4 bytes/elem)
and FLOAT16 (2 bytes/elem).

=== TDS wire format investigation needed

The exact TDS token must be confirmed from mssql-jdbc source before implementation. Based on
research it's a feature extension (0x0E) that may require connection-level negotiation. The
Vert.x MSSQL client may need to add a feature negotiation step.

If the wire format is a binary blob:

* FLOAT32: read bytes as float32 (verify endianness)
* FLOAT16: read bytes as uint16 half-precision, convert to float32

Column metadata will indicate FLOAT32 vs FLOAT16, enabling the codec to return `FloatVector`
vs `HalfFloatVector`.

*Files:* `vertx-mssql-client/src/main/java/io/vertx/mssqlclient/impl/codec/DataType.java`
(or column descriptor — TBD after TDS investigation).

---

== Phase 5 — Oracle 23ai (`vertx-oracle-client`)

Oracle's JDBC driver handles all wire protocol details. Vert.x wraps JDBC results.

=== 5a. Value reading — `Helper.convertSqlValue()`

Oracle JDBC returns primitive arrays for vector columns. Add before the `byte[]` → `Buffer`
case:

[source,java]
----
if (value instanceof float[])  return FloatVector.create((float[]) value);
if (value instanceof double[]) return DoubleVector.create((double[]) value);
// byte[] ambiguity: VECTOR_INT8 vs VECTOR_BINARY vs raw BLOB
// Resolve via VectorMetaData from column descriptor (see 5b)
----

The `byte[]` ambiguity must be resolved via `OracleResultSetMetaData.getVectorMetaData(col)`.

=== 5b. Column descriptor — `OracleColumnDesc`

Oracle JDBC reports VECTOR columns via `ResultSetMetaData`. The `OracleColumnDesc` must:

* Detect OracleType.VECTOR, VECTOR_INT8, VECTOR_FLOAT32, VECTOR_FLOAT64, VECTOR_BINARY
* Set `JDBCType.OTHER` and store the vector sub-type for use in `convertSqlValue`

`VectorMetaData` provides `type()`, `length()`, `arrayClass()`, `isSparse()`. Pass this
down to the row reader so `convertSqlValue` knows which array class to request.

=== 5c. Parameter binding — `OraclePreparedQueryCommand.adaptType()`

Oracle JDBC requires `setObject(idx, array, OracleType.*)` — cannot use `setObject(idx,
array)` alone.

[source,java]
----
if (value instanceof FloatVector v)
  return adaptedValue(v.toFloatArray(), OracleType.VECTOR_FLOAT32);
if (value instanceof DoubleVector v)
  return adaptedValue(v.toDoubleArray(), OracleType.VECTOR_FLOAT64);
if (value instanceof ByteVector v)
  return adaptedValue(v.toByteArray(), OracleType.VECTOR_INT8);
if (value instanceof BitVector v)
  return adaptedValue(v.toPackedByteArray(), OracleType.VECTOR_BINARY);
if (value instanceof SparseFloatVector sv)
  return SparseFloatArray.of(sv.dimension(), sv.indices(), sv.values());
----

The `adaptedValue` helper must pass the OracleType to the subsequent `setObject` call.

---

== Phase 6 — TCK Tests

=== Container infrastructure

The project uses `GenericContainer` (raw testcontainers API) in `ExternalResource` JUnit 4
rules — NOT testcontainers database modules.

==== New: `ContainerPgVectorRule`

*File:* `vertx-pg-client/src/test/java/io/vertx/tests/pgclient/junit/ContainerPgVectorRule.java`

Extends `ExternalResource`. Uses `pgvector/pgvector:pg17` Docker image (pgvector
pre-installed). Mounts `create-postgres-vector.sql` to `/docker-entrypoint-initdb.d/`.

Init SQL (`vertx-pg-client/src/test/resources/create-postgres-vector.sql`):

[source,sql]
----
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS vertx_test_vector (id SERIAL PRIMARY KEY, emb vector(3), notes TEXT);
INSERT INTO vertx_test_vector (emb, notes) VALUES ('[0.1,0.2,0.3]', 'float32');
INSERT INTO vertx_test_vector (emb, notes) VALUES (NULL, 'null');

CREATE TABLE IF NOT EXISTS vertx_test_halfvec (id SERIAL PRIMARY KEY, emb halfvec(3));
INSERT INTO vertx_test_halfvec (emb) VALUES ('[0.1,0.2,0.3]');

CREATE TABLE IF NOT EXISTS vertx_test_sparsevec (id SERIAL PRIMARY KEY, emb sparsevec(10));
INSERT INTO vertx_test_sparsevec (emb) VALUES ('{1:0.5,5:-0.25}/10');

CREATE TABLE IF NOT EXISTS vertx_test_bitvec (id SERIAL PRIMARY KEY, emb bit(8));
INSERT INTO vertx_test_bitvec (emb) VALUES (B'10110100');
----

==== MySQL/MariaDB

Add vector DDL to existing `init.sql`. MySQL 8.4 via `-Dtesting.mysql.database.version=8.4`.

[source,sql]
----
CREATE TABLE IF NOT EXISTS vertx_test_vector (
  id INT PRIMARY KEY AUTO_INCREMENT, emb VECTOR(3), notes VARCHAR(255));
INSERT INTO vertx_test_vector (emb, notes) VALUES (STRING_TO_VECTOR('[0.1,0.2,0.3]'), 'float32');
INSERT INTO vertx_test_vector (emb, notes) VALUES (NULL, 'null');
----

==== MSSQL

Existing `MSSQLRule` supports SQL Server 2025 via system property. Add DDL to init SQL
(executed via `execInContainer`+sqlcmd):

[source,sql]
----
CREATE TABLE vertx_test_vector (id INT PRIMARY KEY, emb VECTOR(3), notes NVARCHAR(255));
INSERT INTO vertx_test_vector VALUES (1, '[0.1,2.0,30.0]', N'float32');
CREATE TABLE vertx_test_vector_f16 (id INT PRIMARY KEY, emb VECTOR(3, FLOAT16));
INSERT INTO vertx_test_vector_f16 VALUES (1, '[0.1,2.0,30.0]');
----

==== Oracle

Existing `OracleRule` uses `gvenzl/oracle-free:23-slim-faststart`. Add DDL to init SQL:

[source,sql]
----
CREATE TABLE vertx_test_vector_f32 (id NUMBER PRIMARY KEY, emb VECTOR(3, FLOAT32));
INSERT INTO vertx_test_vector_f32 VALUES (1, '[0.1,0.2,0.3]');
CREATE TABLE vertx_test_vector_f64 (id NUMBER PRIMARY KEY, emb VECTOR(3, FLOAT64));
INSERT INTO vertx_test_vector_f64 VALUES (1, '[0.1,0.2,0.3]');
CREATE TABLE vertx_test_vector_i8  (id NUMBER PRIMARY KEY, emb VECTOR(3, INT8));
INSERT INTO vertx_test_vector_i8   VALUES (1, '[1,2,3]');
----

=== TCK base class

*File:* `vertx-sql-client/src/test/java/io/vertx/tests/sqlclient/tck/VectorDataTypeTestBase.java`

Abstract method: `initConnector()`.

Common test methods:

* `testDecodeFloatVector()` — SELECT pre-seeded row; assert `row.getValue(0)` instanceof
  `FloatVector`; compare via `Arrays.equals(v.toFloatArray(), expected)`
* `testEncodeFloatVector()` — INSERT with `Tuple.of(FloatVector.create(...))`, SELECT back,
  verify round-trip
* `testNullVector()` — SELECT null row, assert `null`

=== Database-specific test children

[cols="1,2,2"]
|===
| Class | Inherits common tests | Adds

| `PgVectorDataTypeTest`
| FloatVector
| `testDecodeHalfVec()`, `testDecodeSparseVec()`, `testDecodeBitVec()`

| `MySQLVectorDataTypeTest`
| FloatVector
| (MySQL only has float32)

| `MSSQLVectorDataTypeTest`
| FloatVector
| `testDecodeFloat16Vec()`

| `OracleVectorDataTypeTest`
| FloatVector
| `testDecodeFloat64()`, `testDecodeInt8()`, `testDecodeSparse()`
|===

All use `@RunWith(VertxUnitRunner.class)` and `TestContext` for async assertions.

---

== Files Changed (summary)

=== New — core

* `vertx-sql-client/src/main/java/io/vertx/sqlclient/data/Vector.java` (interface)
* `vertx-sql-client/src/main/java/io/vertx/sqlclient/data/FloatVector.java`
* `vertx-sql-client/src/main/java/io/vertx/sqlclient/data/HalfFloatVector.java`
* `vertx-sql-client/src/main/java/io/vertx/sqlclient/data/DoubleVector.java`
* `vertx-sql-client/src/main/java/io/vertx/sqlclient/data/ByteVector.java`
* `vertx-sql-client/src/main/java/io/vertx/sqlclient/data/BitVector.java`
* `vertx-sql-client/src/main/java/io/vertx/sqlclient/data/SparseFloatVector.java`
* `vertx-sql-client/src/main/java/io/vertx/sqlclient/data/SparseDoubleVector.java`
* `vertx-sql-client/src/main/java/io/vertx/sqlclient/data/SparseByteVector.java`

=== New — tests

* `vertx-sql-client/src/test/java/io/vertx/tests/sqlclient/tck/VectorDataTypeTestBase.java`
* `vertx-pg-client/src/test/java/io/vertx/tests/pgclient/junit/ContainerPgVectorRule.java`
* `vertx-pg-client/src/test/resources/create-postgres-vector.sql`
* `vertx-pg-client/src/test/java/io/vertx/tests/pgclient/tck/PgVectorDataTypeTest.java`
* `vertx-mysql-client/src/test/java/io/vertx/tests/mysqlclient/tck/MySQLVectorDataTypeTest.java`
* `vertx-mssql-client/src/test/java/io/vertx/tests/mssqlclient/tck/MSSQLVectorDataTypeTest.java`
* `vertx-oracle-client/src/test/java/io/vertx/tests/oracleclient/tck/OracleVectorDataTypeTest.java`

=== Modified — core

* `vertx-sql-client/src/main/java/io/vertx/sqlclient/data/NullValue.java`

=== Modified — PG

* `vertx-pg-client/src/main/java/io/vertx/pgclient/PgConnectOptions.java`
* `vertx-pg-client/src/main/java/io/vertx/pgclient/impl/codec/InitPgCommandMessage.java`
* `vertx-pg-client/src/main/java/io/vertx/pgclient/impl/codec/PgDecoder.java`
* `vertx-pg-client/src/main/java/io/vertx/pgclient/impl/codec/DataType.java`
* `vertx-pg-client/src/main/java/io/vertx/pgclient/impl/codec/DataTypeCodec.java`

=== Modified — MySQL

* `vertx-mysql-client/src/main/java/io/vertx/mysqlclient/impl/protocol/ColumnDefinition.java`
* `vertx-mysql-client/src/main/java/io/vertx/mysqlclient/impl/datatype/DataType.java`
* `vertx-mysql-client/src/main/java/io/vertx/mysqlclient/impl/datatype/DataTypeCodec.java`
* `vertx-mysql-client/src/test/resources/init.sql`

=== Modified — MSSQL

* `vertx-mssql-client/src/main/java/io/vertx/mssqlclient/impl/codec/DataType.java`
  (and/or column descriptor — TBD after TDS wire format investigation)
* `vertx-mssql-client/src/test/resources/init.sql`

=== Modified — Oracle

* `vertx-oracle-client/src/main/java/io/vertx/oracleclient/impl/Helper.java`
* `vertx-oracle-client/src/main/java/io/vertx/oracleclient/impl/OracleColumnDesc.java`
* `vertx-oracle-client/src/main/java/io/vertx/oracleclient/impl/commands/OraclePreparedQueryCommand.java`
* Oracle init SQL resource

---

== Open items (investigate before or during implementation)

1. *MSSQL TDS wire format*: Inspect `microsoft/mssql-jdbc` source for `ServerDTVImpl` or
   similar to understand exactly how VECTOR is encoded/decoded. Does float16 need
   connection-level feature negotiation?

2. *MariaDB VECTOR column type constant*: Verify whether MariaDB uses the same 242 (0xF2)
   as MySQL or a different value. Check `mariadb-connector-j` source.

3. *Half-float bit manipulation*: Implement IEEE 754 half-precision ↔ float conversion for PG
   `halfvec` binary encoding. Java 11 requires manual bit manipulation
   (sign=bit15, exponent=bits14-10, mantissa=bits9-0).

4. *Oracle byte[] ambiguity*: Distinguish `VECTOR_INT8` (byte[]) from `VECTOR_BINARY`
   (byte[]) from raw BLOB (byte[]) in `convertSqlValue()`. Use VectorMetaData from the
   column descriptor.

5. *Oracle sparse classpath*: Confirm `oracle.sql.VECTOR.SparseFloatArray` is accessible on
   the classpath in `vertx-oracle-client`.

6. *PG `bit` column*: Verify if the existing `DataType.BIT` entry in the PG client already
   decodes bit-type columns. If so, ensure its decode produces `BitVector` (may be a
   breaking change from current behavior — discuss before changing).

---

== Verification

[source,bash]
----
mvn test-compile
mvn test -pl vertx-pg-client -am -Dtest=PgVectorDataTypeTest
mvn test -pl vertx-mysql-client -am -Dtest=MySQLVectorDataTypeTest
mvn test -pl vertx-mssql-client -am -Dtest=MSSQLVectorDataTypeTest
mvn test -pl vertx-oracle-client -am -Dtest=OracleVectorDataTypeTest
mvn spotless:check
----
