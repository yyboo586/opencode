---
name: db-dialect-adapter
description: Abstract SQL dialect differences between MySQL and PostgreSQL-compatible databases using a Dialect interface + Executor wrapper pattern for Go database/sql projects. Includes SQL difference checklist and migration strategy.
---

# Database Dialect Adapter Pattern

A Go pattern for abstracting SQL syntax differences between databases (e.g., MySQL ↔ openGauss/PostgreSQL) without using ORM. Enables a single codebase to support multiple databases by wrapping `database/sql` with a dialect-aware layer.

## When to Activate

- Migrating between MySQL and PostgreSQL-compatible databases (openGauss, PostgreSQL, etc.)
- Adding multi-database support to an existing service
- Writing a new Go service that needs to support both MySQL and PostgreSQL-compatible databases
- Refactoring raw SQL code to reduce database coupling

## Core Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌──────────────────┐
│   Business      │ ──> │  Executor    │ ──> │  Dialect (interface) │
│   Code          │     │  (sql.DB +   │     │  MySQLDialect     │
│   (uses ? only) │     │   Dialect)   │     │  OpenGaussDialect  │
└─────────────────┘     └──────────────┘     └──────────────────┘
                                │
                         ┌──────┴──────┐
                         │ QueryBuilder │
                         │ (chain API)  │
                         └─────────────┘
```

### Principle

Business code writes SQL with `?` placeholders only — the Executor transparently converts them to the target database's format at runtime. No `if mysql { ... } else { ... }` in business logic.

## Dialect Interface

```go
type Dialect interface {
    // Driver returns the driver name for sql.Open.
    Driver() string

    // ConvertQuery converts ? placeholders and backtick identifiers
    // to the target database format.
    // MySQL:      ?  stays ?,  `  stays `
    // openGauss:  ?  → $N,     `  → "
    ConvertQuery(query string) string

    // BuildPagination returns the database-specific pagination clause
    // and its parameters. Use ? placeholders for ConvertQuery to renumber.
    BuildPagination(offset, limit int) (clause string, args []interface{})

    // EstimateRowCountQuery returns a table row count estimate query.
    // MySQL:      information_schema.tables
    // openGauss:  pg_class.reltuples
    EstimateRowCountQuery(schema, table string) string

    // ParseTimeString parses a driver-returned time string.
    // MySQL:      "2006-01-02 15:04:05"
    // openGauss:  RFC3339 "2006-01-02T15:04:05Z"
    ParseTimeString(s string) time.Time

    // IsDuplicateKey checks if err is a duplicate key error (unique index violation).
    // MySQL: Error 1062 (ER_DUP_ENTRY)
    // openGauss: PgError Code "23505" (unique_violation)
    IsDuplicateKey(err error) bool

    // CreatePartitionSQL returns DDL for creating a range partition.
    // MySQL/TiDB: ALTER TABLE t ADD PARTITION (PARTITION p VALUES LESS THAN (toValue))
    // openGauss:  CREATE TABLE p PARTITION OF t FOR VALUES FROM (fromValue) TO (toValue)
    CreatePartitionSQL(table, partitionName string, fromValue, toValue int64) string

    // ListPartitionsSQL returns a query for listing existing partition names of a table.
    // MySQL/TiDB: SELECT PARTITION_NAME FROM information_schema.PARTITIONS WHERE ...
    // openGauss:  SELECT c.relname FROM pg_inherits i JOIN pg_class c ... WHERE p.relname = ?
    ListPartitionsSQL(table string) string
}
```

### Extension Rule

When a new SQL difference is discovered, add a method to `Dialect` and implement it in both concrete types. The interface is the contract — both databases must support all methods.

## Executor: Transparent SQL Wrapper

```go
type Executor struct {
    db      *sql.DB
    dialect Dialect
}

// newExecutor creates an Executor with explicit injection (for testing).
// Package-private — tests use this directly.
func newExecutor(db *sql.DB, d Dialect) *Executor {
    return &Executor{db: db, dialect: d}
}

// NewFromDriver is the production entry point.
// Configures connection pool — applies defaults when parameters ≤ 0:
//   maxOpenConns=50, maxIdleConns=10, connMaxLife=30min.
func NewFromDriver(driver, source string, maxOpenConns, maxIdleConns int, connMaxLife time.Duration) (*Executor, error) {
    // Creates appropriate dialect based on driver:
    //   "mysql" → MySQLDialect
    //   "pgx"   → OpenGaussDialect
}

// Exec executes INSERT/UPDATE/DELETE with placeholder conversion.
func (e *Executor) Exec(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
    return e.db.ExecContext(ctx, e.dialect.ConvertQuery(query), args...)
}

// Query executes a SELECT query with placeholder conversion.
func (e *Executor) Query(ctx context.Context, query string, args ...interface{}) (*sql.Rows, error) {
    return e.db.QueryContext(ctx, e.dialect.ConvertQuery(query), args...)
}

// QueryRow executes a single-row query with placeholder conversion.
func (e *Executor) QueryRow(ctx context.Context, query string, args ...interface{}) *sql.Row {
    return e.db.QueryRowContext(ctx, e.dialect.ConvertQuery(query), args...)
}

// Close closes the database connection.
func (e *Executor) Close() error {
    return e.db.Close()
}

// Ping checks if the database connection is available.
func (e *Executor) Ping(ctx context.Context) error {
    return e.db.PingContext(ctx)
}

// RawDB returns the underlying *sql.DB.
// Use for: data dictionary queries that don't need SQL conversion (?→$N).
// Note: callers manage connection and transaction handling.
func (e *Executor) RawDB() *sql.DB {
    return e.db
}

// QueryBuilder returns a chain-style query builder for dynamic WHERE + pagination.
func (e *Executor) QueryBuilder(ctx context.Context) *QueryBuilder {
    return &QueryBuilder{executor: e, ctx: ctx}
}

// ParseTime parses a database-returned time string.
func (e *Executor) ParseTime(s string) time.Time {
    return e.dialect.ParseTimeString(s)
}

// IsDuplicateKey checks if err is a duplicate key error (unique index violation).
// Delegates to Dialect to abstract MySQL Error 1062 vs openGauss PgError 23505.
func (e *Executor) IsDuplicateKey(err error) bool {
    return e.dialect.IsDuplicateKey(err)
}

// ListPartitions queries existing partition names for a table via dialect-generated SQL.
func (e *Executor) ListPartitions(ctx context.Context, table string) ([]string, error) { ... }

// CreatePartition creates a range partition via dialect-generated DDL.
func (e *Executor) CreatePartition(ctx context.Context, table, partitionName string, from, to int64) error { ... }
```

## QueryBuilder: Dynamic Query Construction

For queries with dynamic WHERE conditions + pagination, a chain-style builder avoids manual string concatenation:

```go
type QueryBuilder struct {
    ctx        context.Context
    executor   *Executor
    columns    string
    table      string
    schema     string
    conditions []string
    args       []interface{}
    orderBy    string
    offset     int
    limit      int
    hasLimit   bool
}

func (b *QueryBuilder) Select(columns string) *QueryBuilder { ... }
func (b *QueryBuilder) From(table string, schema ...string) *QueryBuilder { ... }
func (b *QueryBuilder) Where(condition string, args ...interface{}) *QueryBuilder { ... }
func (b *QueryBuilder) OrderBy(order string) *QueryBuilder { ... }
func (b *QueryBuilder) Limit(offset, limit int) *QueryBuilder { ... }

// Query builds and executes the SELECT, returning *sql.Rows.
func (b *QueryBuilder) Query() (*sql.Rows, error) { ... }

// QueryRow builds and executes the SELECT, returning *sql.Row.
func (b *QueryBuilder) QueryRow() (*sql.Row, error) { ... }

// Count returns row count: estimation (via dialect) when no WHERE,
// exact COUNT(*) otherwise. Uses COALESCE(COUNT(*), 0) to handle
// openGauss column-store returning NULL for empty tables.
func (b *QueryBuilder) Count() (int32, error) { ... }

// String returns the generated SQL and args for debugging.
func (b *QueryBuilder) String() (string, error) { ... }
```

Internal `buildQuery()` assembles the SQL and invokes `dialect.BuildPagination()` for dialect-aware pagination.

### Key Design Detail: Placeholder Strategy

`BuildPagination` uses `?` placeholders (not `$N`), so `ConvertQuery` can renumber all `?` in order — including both WHERE parameters and pagination parameters. This avoids the "offset 3" bug where handwritten `$N` numbering conflicts with WHERE parameters.

```go
// MySQL
func (d *MySQLDialect) BuildPagination(offset, limit int) (string, []interface{}) {
    return "LIMIT ?, ?", []interface{}{offset, limit}
}

// openGauss — note: uses ? not $N
func (d *OpenGaussDialect) BuildPagination(offset, limit int) (string, []interface{}) {
    return "LIMIT ? OFFSET ?", []interface{}{limit, offset}
}
```

## SQL Dialect Differences

| Category | MySQL | openGauss / PostgreSQL | Dialect Method |
|----------|-------|----------------------|----------------|
| Placeholder | `?` | `$1, $2, ...` | `ConvertQuery` |
| Identifier quote | `` `id` `` | `"id"` | `ConvertQuery` |
| Pagination | `LIMIT offset, count` | `LIMIT n OFFSET m` | `BuildPagination` |
| Time format | `"2006-01-02 15:04:05"` | RFC3339 `"2006-01-02T15:04:05Z"` | `ParseTimeString` |
| Row count estimate | `information_schema.tables.table_rows` | `pg_class.reltuples` | `EstimateRowCountQuery` |
| Auto-increment DDL | `AUTO_INCREMENT` | `BIGSERIAL / IDENTITY` | DDL scripts |
| **Auto-increment INSERT** | `VALUES (null, ...)` works | `VALUES (null, ...)` → NOT NULL error | Must use `DEFAULT` in SQL |
| Schema visibility | Default `public`, no prefix needed | Must `SET search_path` or use schema prefix | Init script |
| Driver import | `github.com/go-sql-driver/mysql` | `github.com/jackc/pgx/v5/stdlib` | `Driver()` |
| Duplicate key error | Error 1062 (`ER_DUP_ENTRY`) | PgError Code `23505` (`unique_violation`) | `IsDuplicateKey` |
| Partition DDL | `ALTER TABLE t ADD PARTITION (PARTITION p VALUES LESS THAN (v))` | `CREATE TABLE p PARTITION OF t FOR VALUES FROM (f) TO (t)` | `CreatePartitionSQL` |
| List partitions | `information_schema.PARTITIONS` | `pg_inherits` JOIN `pg_class` | `ListPartitionsSQL` |

### Important: INSERT NULL vs DEFAULT

The `VALUES (null, ...)` for auto-increment columns works in MySQL but violates NOT NULL in PostgreSQL/openGauss. This is a **semantic difference** that the Dialect layer cannot transparently convert (it would need to parse SQL AST). Fix by changing the business SQL:

```sql
-- MySQL (works)
INSERT INTO t (id, name) VALUES (null, 'test');

-- openGauss (must use DEFAULT)
INSERT INTO t (id, name) VALUES (DEFAULT, 'test');
```

## Migration Workflow

### Phase A: Test Baseline
1. Derive integration tests per `integration-test-guide` skill
2. Run tests on source database → establish baseline

### Phase B: Dialect Implementation
1. Analyze project SQL inventory → identify actual dialect differences
2. Implement `Dialect` interface based on identified differences (skip unused methods, add new ones if needed)
3. Implement `Executor` wrapper (including `NewFromDriver` for production)
4. Implement `QueryBuilder` for dynamic queries (if needed)
5. Refactor business code: replace `*sql.DB` with `*Executor`, use `?` only
6. Run integration tests (Phase A) on source and target databases → fix semantic dialect differences uncovered by failures

## Best Practices

**DO:**
- Keep all SQL in business code using `?` placeholders only
- Use `Executor` as the single database handle throughout the service
- Use `NewFromDriver` as the production entry point with explicit pool config
- Add methods to `Dialect` interface when new differences surface
- Test both dialects with the same integration test suite
- Write unit tests first (ConvertQuery, BuildPagination) before integration tests

**DON'T:**
- Put `if mysql { ... } else { ... }` in business code
- Hand-write `$N` placeholders in SQL strings
- Assume feature parity — test each operation on both databases
- Skip the baseline phase (Phase A) — without passing tests on MySQL first, you can't tell if failures are pre-existing or migration-introduced
- Forget `SET search_path` / schema prefix in openGauss init scripts
- Use `RawDB()` for regular queries — only use it when you need to bypass dialect conversion