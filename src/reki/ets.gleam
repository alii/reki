import gleam/dynamic
import gleam/option.{type Option}

/// A unique atom used as an ETS table name. This type has no constructors,
/// so it can only be created via FFI — giving reki full ownership of the
/// table name contract. It is separate from `process.Name` and is only
/// used for ETS operations, never for actor registration.
pub type TableIdentifier

@external(erlang, "reki_ets_ffi", "new_unique_atom")
pub fn new_table_identifier() -> TableIdentifier

/// An ETS table handle. Tables are named and accessed by their atom name.
/// The name is typically shared with the registry actor's process name,
/// so the table is owned by and dies with the actor.
pub type Table {
  Table(name: TableIdentifier)
}

/// Create a new named ETS table. The name should be a dynamic atom value
/// (e.g. from `new_unique_atom`).
/// The table is owned by the calling process and will be destroyed when it dies.
pub fn new(name: TableIdentifier) -> Result(Table, Nil) {
  case new_table(name) {
    Ok(_) -> Ok(Table(name))
    Error(e) -> Error(e)
  }
}

/// Insert a key-value pair into the table.
pub fn insert(key: a, value: b, table: Table) -> Result(Nil, Nil) {
  insert_ets(table.name, to_dynamic(key), to_dynamic(value))
}

/// Look up a value by key in the table, returning it as a Dynamic value.
pub fn lookup_dynamic(key: a, table: Table) -> Option(dynamic.Dynamic) {
  lookup_ets(table.name, to_dynamic(key))
}

/// Delete a key-value pair from the table.
pub fn delete(key: a, table: Table) -> Result(Nil, Nil) {
  delete_ets(table.name, to_dynamic(key))
}

/// Delete using a dynamic key (useful when you have a dynamic key from another lookup).
pub fn delete_using_dynamic(
  key: dynamic.Dynamic,
  table: Table,
) -> Result(Nil, Nil) {
  delete_ets(table.name, key)
}

// Internal FFI functions

@external(erlang, "reki_ets_ffi", "new")
fn new_table(name: TableIdentifier) -> Result(dynamic.Dynamic, Nil)

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
