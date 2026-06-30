= pgvector OID Discovery — Research Notes

== The Problem

pgvector adds `vector`, `halfvec`, and `sparsevec` as user-defined types via `CREATE EXTENSION pgvector`. PostgreSQL assigns OIDs to user-defined types dynamically — they are NOT hardcoded. The actual OID depends on the order in which types were created in a given DB cluster and can differ between installations.

Standard PG built-in type OIDs (e.g., int4=23, text=25, bool=16) are fixed. pgvector OIDs are not.

The `bit` type (used for pgvector binary vectors) reuses PG's own built-in `bit` type (OID 1560), which IS fixed.

== How pgvector-java (JDBC) Solves This

pgvector-java does NOT query pg_type explicitly. Instead:

  PGvector.registerTypes(conn)

This calls `conn.unwrap(PGConnection.class).addDataType("vector", PGvector.class)` for each type. This tells the PostgreSQL JDBC driver: "when you encounter a column of type named 'vector', instantiate PGvector to handle it."

The JDBC driver's `TypeInfoCache` stores this name→class mapping. When the JDBC driver receives a RowDescription with an unknown OID, it queries pg_type to resolve the OID→name mapping *on first use*, then uses TypeInfoCache to find the handler class. This OID lookup is done lazily and internally by the driver.

== Why Vert.x Cannot Use the Same Approach

The Vert.x PG reactive client implements the PG wire protocol directly, without the JDBC `TypeInfoCache` or `PGConnection` abstraction. When the PG server sends a RowDescription, each column carries an OID integer. The decoder must immediately map OID→DataType to know how to decode the column. There is no lazy internal lookup mechanism.

== Vert.x Approach: Explicit pg_type Probe at Connection Init

Since the reactive client must know the OID before decoding rows, the only option is to query pg_type proactively.

Implementation: After authentication succeeds (in `InitPgCommandMessage.handleReadyForQuery()`), if the user opted in via `PgConnectOptions.setVectorTypeEnabled(true)`, execute:

  SELECT typname, oid FROM pg_type WHERE typname IN ('vector', 'halfvec', 'sparsevec')

Parse the result: store a `Map<String, Integer>` of typname→oid in the PgDecoder (or PgSocketConnection context). Then in `PgDecoder.decodeRowDescription()`, for each column OID that is not in the static DataType map, check the dynamic map and substitute the appropriate DataType (VECTOR, HALFVEC, SPARSEVEC).

This requires exactly one additional round-trip per connection when vector support is enabled.

== Opt-in Mechanism

Design: add `boolean vectorTypeEnabled` to `PgConnectOptions` (default: false).

Rationale: Most users don't need pgvector. Adding a pg_type round-trip unconditionally would slow every PG connection. Opt-in is consistent with how pgvector-java requires an explicit `registerTypes()` call.

The query is sent for all three dynamic types (vector, halfvec, sparsevec) in a single round-trip. If pgvector is not installed, the query returns zero rows and the feature is silently disabled.

== Encoding Parameters with Dynamic OIDs

When the user binds a `FloatVector` (or `HalfFloatVector`, `SparseFloatVector`) as a query parameter, the encoder must specify the OID in the Bind message. The OID is available from the per-connection dynamic map (set up at connection init). If vectorTypeEnabled is false, binding Vector parameters will fail (the OID is unknown). This is acceptable — the user who enables vectors opts into the full feature.

== Alternative Considered: Detect by Column Type Name

When PG sends RowDescription, it sends the column OID but NOT the type name (unlike MSSQL which embeds the type name). The Vert.x client would need to query pg_attribute/pg_type for each unknown OID to get the type name. This would be per-query overhead, worse than the per-connection probe.

== Alternative Considered: Fixed "Well-Known" OID

Some pgvector tutorials claim the OID is "usually 16385" or similar, but this is NOT reliable. The OID can be any value ≥ 16384. Hardcoding it would break on any installation where pgvector was installed in a different order.

== Bit Type: No Discovery Needed

PG's `bit` type has fixed OID 1560. It can be added to the static DataType map without any runtime discovery. The challenge is distinguishing PG's standard `bit` column (bit string for business data) from pgvector's use of `bit` for binary vectors. They use the same OID; differentiation is only possible via column metadata (type name = `bit`) — which is already available.

Note: The existing PG client may already handle `bit` partially; the vector codec should reuse/extend that handling for VARBIT/BIT columns used as pgvector binary columns.
