= Vector Types Research — Database-by-Database Reference

== PostgreSQL (pgvector extension)

pgvector adds four distinct types to pg_type. OIDs are dynamic (assigned at `CREATE EXTENSION` time).

=== vector (float32)

* pg_type.typname: `vector`
* Storage: 4 bytes per element + 8 bytes overhead
* Max dimensions: 2,000
* Wire format (binary, big-endian):
  - int16: dimension count
  - int16: reserved (must be 0)
  - float32 × dim: elements
* Text format: `[0.1,0.2,0.3]` (no spaces)

=== halfvec (float16)

* pg_type.typname: `halfvec`
* Storage: 2 bytes per element + 8 bytes overhead
* Max dimensions: 4,000
* Wire format (binary, big-endian):
  - int16: dimension count
  - int16: reserved (must be 0)
  - uint16 × dim: IEEE 754 half-precision elements
* Text format: `[0.1,0.2,0.3]`
* Note: pgvector-java uses text-only for halfvec because Java < 20 lacks native Float16 support

=== sparsevec (sparse float32)

* pg_type.typname: `sparsevec`
* Storage: 12 bytes overhead + 8 bytes per non-zero element
* Max dimensions: no documented limit (millions possible)
* Wire format (binary, big-endian):
  - int32: total dimensions
  - int32: nnz (non-zero count)
  - int32: reserved (must be 0)
  - int32 × nnz: zero-based indices in ascending order
  - float32 × nnz: corresponding values
* Text format: `{1:0.5,100:-0.25}/65535` (1-based indices in text)
* Constraints: indices must be sorted, unique, in range; values must be non-zero, finite

=== bit (binary vector)

* pg_type.typname: `bit`
* This REUSES the standard PG `bit` type (OID 1560 — fixed, not dynamic)
* Storage: ceil(n/8) bytes + 4 bytes overhead
* Max dimensions: 64,000
* Wire format (binary):
  - int32: bit length
  - byte × ceil(length/8): packed bits, MSB first
* Text format: `10101010` (binary digits, no brackets)

=== OID discovery

Standard PG types: OIDs are fixed and known at compile time.

pgvector extension types (vector, halfvec, sparsevec): OIDs are assigned dynamically at extension creation time. They cannot be hardcoded. Query:

  SELECT typname, oid FROM pg_type WHERE typname IN ('vector', 'halfvec', 'sparsevec')

The `bit` type OID is fixed (1560) and already known to PG clients.

pgvector-java uses `PGConnection.addDataType("vector", PGvector.class)` which registers a name→class mapping in the JDBC driver's TypeInfoCache. The JDBC driver resolves OIDs lazily during query execution. Reactive (non-JDBC) clients must query pg_type explicitly.

---

== MySQL 8.4+ / MariaDB 11.7+

=== vector (float32 only)

Both MySQL and MariaDB support only one vector type.

* MySQL column type ID: 242 (0xF2), constant `FIELD_TYPE_VECTOR`
* MariaDB: same binary format, exact column type constant TBD (verify vs MySQL)
* Storage: 4 bytes per element, little-endian IEEE 754 float32
* Max dimensions: 16,383 (MySQL 8.4 limit)
* Wire format (binary protocol): raw float32 bytes, little-endian, no header
* Text format: `[0.1,0.2,0.3]` via `STRING_TO_VECTOR()`/`VECTOR_TO_STRING()`

Wire decoding: read the blob bytes, interpret as little-endian float32 array. No dimension header in the wire payload — dimension count is inferred from byte length / 4.

Binding parameters (text protocol): use SQL function `STRING_TO_VECTOR('[0.1,0.2,0.3]')`. The Vert.x codec sends the raw string; users write the SQL with the wrapper function.

Binding parameters (binary protocol): send raw float32 bytes directly as BLOB-type binding.

---

== SQL Server 2025

=== VECTOR with FLOAT32 (default)

* TDS: Uses TDS feature extension 0x0E (not a standard type token)
* Storage: 4 bytes per element
* Max dimensions: 1,998 (float32)
* JDBC class: `microsoft.sql.Vector`
* Wire: binary float32, 4 bytes per element
* Default: VECTOR(n) with no type qualifier defaults to FLOAT32

=== VECTOR with FLOAT16

* Same TDS type, distinguished by metadata
* Storage: 2 bytes per element
* Max dimensions: 3,996 (float16)
* JDBC class: same `microsoft.sql.Vector` but with `VectorDimensionType.FLOAT16`
* Wire: binary float16 (half-precision), 2 bytes per element
* Requires JDBC connection property `vectorTypeSupport=v2` for binary float16 protocol
* Without v2: float16 vectors fall back to varchar(max) JSON string

Java representation: both FLOAT32 and FLOAT16 use `Float[]` in the mssql-jdbc driver (float16 is expanded to float32 on read).

Constructor pattern in mssql-jdbc:
  new Vector(dims, VectorDimensionType.FLOAT32, floatArray)
  new Vector(dims, VectorDimensionType.FLOAT16, floatArray)

Or with bytes-per-dimension (scale):
  new Vector(dims, 4 /* FLOAT32 */, floatArray)
  new Vector(dims, 2 /* FLOAT16 */, floatArray)

Column metadata exposes the base type. Vert.x should preserve this to allow round-trip fidelity.

---

== Oracle 23ai

Oracle has the most comprehensive vector support with 5 distinct type constants.

=== VECTOR_INT8

* SQL type: `VECTOR(n, INT8)`
* OracleTypes constant: -106
* Java default array: `byte[]`
* Storage: 1 byte per element, signed 8-bit integer

=== VECTOR_FLOAT32

* SQL type: `VECTOR(n, FLOAT32)`
* OracleTypes constant: -104
* Java default array: `float[]`
* Storage: 4 bytes per element, IEEE 754 single-precision

=== VECTOR_FLOAT64

* SQL type: `VECTOR(n, FLOAT64)`
* OracleTypes constant: -103
* Java default array: `double[]`
* Storage: 8 bytes per element, IEEE 754 double-precision

=== VECTOR_BINARY

* SQL type: `VECTOR(n, BINARY)`
* OracleTypes constant: -102
* Java default array: `byte[]` (bit-packed, MSB order, 8 bits per byte)
* Available since Oracle 23.6
* Logical representation: boolean[]

=== VECTOR (wildcard)

* SQL type: `VECTOR(*)` — accepts any sub-type
* OracleTypes constant: -105
* No fixed Java mapping; use VectorMetaData.arrayClass() to determine correct type

=== JDBC read/write requirements

Reading: `resultSet.getObject(col)` has NO default VECTOR mapping.
Must use: `resultSet.getObject(col, float[].class)` or `resultSet.getObject(col, VECTOR.class)`.
Alternative: set connection property `oracle.jdbc.vectorDefaultGetObjectType=String`.

Writing: `setObject(idx, array)` without SQLType is NOT supported.
Must use: `setObject(idx, floatArray, OracleType.VECTOR_FLOAT32)`.

Vert.x oracle-client workaround: the Oracle client calls JDBC setObject internally via adaptType(). It must detect Vector instances and call setObject with the appropriate OracleType.

=== Sparse vectors (SparseArray — read only?)

Available since Oracle 23.8. No sparse storage column type — sparse is a CLIENT-SIDE OPTIMIZATION for binding large vectors with few non-zero values.

Interfaces: `SparseFloatArray`, `SparseDoubleArray`, `SparseByteArray`, `SparseBooleanArray` (all nested in `oracle.sql.VECTOR`).

Constructor: `SparseFloatArray.of(int length, int[] indices, float[] values)`

Retrieval: `resultSet.getObject(col, SparseFloatArray.class)` — the DB returns the full vector but the JDBC driver converts it to sparse form.

For Vert.x oracle-client: sparse binding can be supported by accepting `SparseFloatVector` and binding the corresponding indices+values. However, this is complex and may be deferred.

=== VectorMetaData

Available via `OracleResultSetMetaData.getVectorMetaData(columnIndex)`.
Methods: `length()` (dims or -1 for wildcard), `type()` (OracleType), `arrayClass()`, `isSparse()`.

Vert.x uses `ResultSetMetaData` in `OracleColumnDesc` — VectorMetaData should be accessible there.

---

== Summary Matrix

| Feature         | PG vector | PG halfvec | PG sparsevec | PG bit | MySQL | MariaDB | MSSQL float32 | MSSQL float16 | Oracle INT8 | Oracle FLOAT32 | Oracle FLOAT64 | Oracle BINARY |
|-----------------|-----------|------------|--------------|--------|-------|---------|---------------|---------------|-------------|----------------|----------------|---------------|
| Java type       | float[]   | float[]    | sparse       | byte[] | float[]| float[] | float[]       | float[]       | byte[]      | float[]        | double[]       | byte[]        |
| Wire endianness | big       | big        | big          | big    | little| little  | little        | little        | -           | -              | -              | -             |
| Vert.x class    | FloatVector | HalfFloatVector | SparseFloatVector | BitVector | FloatVector | FloatVector | FloatVector | HalfFloatVector | ByteVector | FloatVector | DoubleVector | BitVector |
| OID/type fixed? | NO        | NO         | NO           | YES(1560) | 242 | TBD   | TDS 0x0E      | TDS 0x0E      | OracleTypes | OracleTypes    | OracleTypes    | OracleTypes   |
