import gleam/dynamic
import gleam/option.{type Option}

/// A unique atom used as an ETS table name. This type has no constructors,
/// so it can only be created via FFI — giving reki full ownership of the
/// table name contract. It is separate from `process.Name` and is only
/// used for ETS operations, never for actor registration.
pub type TableIdentifier

/// A reference to an ETS table (the tid returned by ets:new/2).
/// This is a phantom type with no constructors — it can only be
/// created via the FFI.
pub type Tid

/// Creates a new named ETS table. Crashes if the name is already taken.
/// The table is owned by the calling process and will be destroyed when it dies.
@external(erlang, "reki_ets_ffi", "new")
pub fn new(table_id: TableIdentifier) -> Tid

/// Insert a key-value pair into the table.
pub fn insert(key: a, value: b, table_id: TableIdentifier) -> Result(Nil, Nil) {
  insert_ets(table_id, to_dynamic(key), to_dynamic(value))
}

/// Look up a value by key in the table, returning it as a Dynamic value.
pub fn lookup_dynamic(
  key: a,
  table_id: TableIdentifier,
) -> Option(dynamic.Dynamic) {
  lookup_ets(table_id, to_dynamic(key))
}

/// Delete a key-value pair from the table.
pub fn delete(key: a, table_id: TableIdentifier) -> Result(Nil, Nil) {
  delete_ets(table_id, to_dynamic(key))
}

/// Delete using a dynamic key (useful when you have a dynamic key from another lookup).
pub fn delete_using_dynamic(
  key: dynamic.Dynamic,
  table_id: TableIdentifier,
) -> Result(Nil, Nil) {
  delete_ets(table_id, key)
}

// Internal FFI functions

@external(erlang, "reki_ets_ffi", "insert")
fn insert_ets(
  name: TableIdentifier,
  key: dynamic.Dynamic,
  value: dynamic.Dynamic,
) -> Result(Nil, Nil)

@external(erlang, "reki_ets_ffi", "lookup")
fn lookup_ets(
  name: TableIdentifier,
  key: dynamic.Dynamic,
) -> Option(dynamic.Dynamic)

@external(erlang, "reki_ets_ffi", "delete")
fn delete_ets(name: TableIdentifier, key: dynamic.Dynamic) -> Result(Nil, Nil)

@external(erlang, "reki_ets_ffi", "to_dynamic")
fn to_dynamic(value: a) -> dynamic.Dynamic

/// Creates a unique atom for use as an ETS table name.
/// WARNING: Atoms are never garbage collected by the BEAM. Only call this
/// a fixed number of times (e.g. once per registry at app startup).
@external(erlang, "reki_ets_ffi", "new_unique_atom")
pub fn new_table_identifier() -> TableIdentifier
