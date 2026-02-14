/// A unique atom used as an ETS table name. This type has no constructors,
/// so it can only be created via FFI — giving reki full ownership of the
/// table name contract. It is separate from `process.Name` and is only
/// used for ETS operations, never for actor registration.
pub type TableReference

@external(erlang, "reki_ets_ffi", "new_unique_atom")
pub fn new_table_reference() -> TableReference
