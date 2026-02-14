import gleam/option.{type Option}

/// A unique atom used as an ETS table name
pub type TableIdentifier(key, value)

/// A reference to an ETS table (the tid returned by ets:new/2)
pub type Tid

/// Insert a key-value pair into the table.
pub fn insert(
  table_id: TableIdentifier(key, value),
  key: key,
  value: value,
) -> Result(Nil, Nil) {
  insert_ets(table_id, key, value)
}

/// Look up a value by key in the table, returning it as a Dynamic value.
pub fn lookup_dynamic(
  table_id: TableIdentifier(key, value),
  key: key,
) -> Option(value) {
  lookup_ets(table_id, key)
}

/// Delete a key-value pair from the table.
pub fn delete(
  table_id: TableIdentifier(key, value),
  key: key,
) -> Result(Nil, Nil) {
  delete_ets(table_id, key)
}

// Public FFI

/// Creates a unique atom for use as an ETS table name.
/// WARNING: Atoms are never garbage collected by the BEAM. Only call this
/// a fixed number of times (e.g. once per registry at app startup).
@external(erlang, "reki_ets_ffi", "new_unique_atom")
pub fn new_table_identifier() -> TableIdentifier(key, value)

/// Creates a new named ETS table. Crashes if the name is already taken.
/// The table is owned by the calling process and will be destroyed when it dies.
@external(erlang, "reki_ets_ffi", "new")
pub fn new(table_id: TableIdentifier(key, value)) -> Tid

// Private FFI

@external(erlang, "reki_ets_ffi", "insert")
fn insert_ets(
  name: TableIdentifier(key, value),
  key: key,
  value: value,
) -> Result(Nil, Nil)

@external(erlang, "reki_ets_ffi", "lookup")
fn lookup_ets(name: TableIdentifier(key, value), key: key) -> Option(value)

@external(erlang, "reki_ets_ffi", "delete")
fn delete_ets(name: TableIdentifier(key, value), key: key) -> Result(Nil, Nil)
