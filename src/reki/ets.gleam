import gleam/dynamic
import gleam/option.{type Option}

/// An ETS table handle. Tables are named and accessed by their atom name.
/// The name is typically shared with the registry actor's process name,
/// so the table is owned by and dies with the actor.
pub opaque type Table {
  Table(name: dynamic.Dynamic)
}

/// Create a new named ETS table. The name should be an atom (e.g. a process.Name).
/// The table is owned by the calling process and will be destroyed when it dies.
pub fn new(name: name) -> Result(Table, Nil) {
  let name_dynamic = to_dynamic(name)
  case new_table(name_dynamic) {
    Ok(_) -> Ok(Table(name_dynamic))
    Error(e) -> Error(e)
  }
}

/// Create a table handle from an existing name, without creating a new table.
/// This is used to access a table that was already created by another process
/// (e.g. the registry actor).
@internal
pub fn from_name(name: name) -> Table {
  Table(to_dynamic(name))
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
fn new_table(name: dynamic.Dynamic) -> Result(dynamic.Dynamic, Nil)

@external(erlang, "reki_ets_ffi", "insert")
fn insert_ets(
  name: dynamic.Dynamic,
  key: dynamic.Dynamic,
  value: dynamic.Dynamic,
) -> Result(Nil, Nil)

@external(erlang, "reki_ets_ffi", "lookup")
fn lookup_ets(
  name: dynamic.Dynamic,
  key: dynamic.Dynamic,
) -> Option(dynamic.Dynamic)

@external(erlang, "reki_ets_ffi", "delete")
fn delete_ets(name: dynamic.Dynamic, key: dynamic.Dynamic) -> Result(Nil, Nil)

@external(erlang, "reki_ets_ffi", "to_dynamic")
fn to_dynamic(value: a) -> dynamic.Dynamic
