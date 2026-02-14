import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result

/// An opaque atom used as the gen_server's registered name.
pub type ServerName

/// An opaque atom used as the ETS table name.
pub type TableName

/// A registry that manages actors by key.
/// Similar to Discord's gen_registry, this allows you to look up or start actors
/// on demand, ensuring only one actor exists per key.
///
/// ## Architecture
///
/// Reki uses an ETS table for fast O(1) lookups, with an Erlang gen_server that
/// handles process lifecycle (starting new actors, cleaning up dead ones).
/// When a managed actor dies, the gen_server receives an EXIT signal and removes
/// the stale entry from ETS.
///
/// The gen_server implements the OTP supervisor protocol (`which_children`,
/// `count_children`), registers as `type: supervisor` in its child spec, and
/// properly terminates all children on shutdown.
///
/// The ETS table is owned by the gen_server. If it crashes, the BEAM
/// automatically destroys the table. When the supervisor restarts it,
/// a fresh table is created.
///
/// ## Stale entries
///
/// There's a brief window between when a process dies and when reki processes
/// the EXIT signal. During this window, `lookup` or `lookup_or_start` may
/// return a stale Subject pointing to a dead process. This is the tradeoff
/// for fast O(1) lookups.
pub opaque type Registry(key, msg) {
  Registry(server_name: ServerName, table_name: TableName)
}

/// Start the registry. You likely want to use the `supervised` function instead,
/// to add the registry to your supervision tree, but this may be useful in tests.
pub fn start(
  registry: Registry(key, msg),
) -> Result(actor.Started(Registry(key, msg)), actor.StartError) {
  start_link(registry.server_name, registry.table_name)
  |> result.map(fn(pid) { actor.Started(pid:, data: registry) })
}

/// Create a registry. Call this at the start of your program before
/// creating the supervision tree.
///
/// **Important:** Each call creates unique atoms for the server name and
/// ETS table name. Atoms are never garbage collected by the BEAM, so this
/// function must only be called a fixed number of times (e.g. once per
/// registry at app startup). Do not call `new()` dynamically in a loop
/// or on each request.
pub fn new() -> Registry(key, msg) {
  Registry(server_name: new_server_name(), table_name: new_table_name())
}

/// A specification for starting the registry under a supervisor.
///
/// The registry declares itself as a supervisor in the child spec, since it
/// manages child processes and implements the OTP supervisor protocol.
pub fn supervised(
  registry: Registry(key, msg),
) -> supervision.ChildSpecification(Registry(key, msg)) {
  supervision.supervisor(fn() { start(registry) })
}

/// Looks up an actor by key, or starts one if it doesn't exist.
///
/// This is the primary function for getting an actor from the registry. It
/// first checks ETS for an existing entry (fast O(1) lookup), and only goes
/// through the registry gen_server if the key isn't found.
///
/// In rare cases, this may return a stale Subject if a process just died but
/// reki hasn't processed the EXIT yet.
pub fn lookup_or_start(
  registry: Registry(key, msg),
  key: key,
  start_fn: fn(key) ->
    Result(actor.Started(process.Subject(msg)), actor.StartError),
) -> Result(process.Subject(msg), actor.StartError) {
  lookup_or_start_with_timeout(registry, key, start_fn, 5000)
}

/// Looks up an actor by key in the registry, without starting one if missing.
///
/// Returns `None` if no actor exists for the given key. This is a direct ETS
/// read, so it's fast but may return a stale Subject if a process just died.
///
/// Use `lookup_or_start` if you want to start an actor when the key is missing.
pub fn lookup(
  registry: Registry(key, msg),
  key: key,
) -> Option(process.Subject(msg)) {
  ets_lookup(registry.table_name, key)
}

@internal
pub fn lookup_or_start_with_timeout(
  registry: Registry(key, msg),
  key: key,
  start_fn: fn(key) ->
    Result(actor.Started(process.Subject(msg)), actor.StartError),
  timeout: Int,
) -> Result(process.Subject(msg), actor.StartError) {
  case lookup(registry, key) {
    Some(sub) -> Ok(sub)
    None -> do_start(registry, key, start_fn, timeout)
  }
}

/// Like `lookup_or_start`, but skips ETS and goes directly through
/// the gen_server. By going through the gen_server, any pending `EXIT`s
/// in the mailbox are processed first. This lets you block and synchronize
/// with the registry.
///
/// **You probably don't need this function.** It serializes all requests
/// through the gen_server, which becomes a bottleneck under load. Make
/// sure you understand exactly why you need the ordering guarantee before
/// using this. Read the docs on the `Registry` type to understand the
/// architecture and tradeoffs.
@internal
pub fn do_start(
  registry: Registry(key, msg),
  key: key,
  start_fn: fn(key) ->
    Result(actor.Started(process.Subject(msg)), actor.StartError),
  timeout: Int,
) -> Result(process.Subject(msg), actor.StartError) {
  start_child(registry.server_name, key, start_fn, timeout)
}

@internal
pub fn get_pid(registry: Registry(a, b)) -> Result(process.Pid, Nil) {
  whereis_server(registry.server_name)
}

// FFI bindings to reki_server

@external(erlang, "reki_server", "start_link")
fn start_link(
  server_name: ServerName,
  table_name: TableName,
) -> Result(process.Pid, actor.StartError)

@external(erlang, "reki_server", "start_child")
fn start_child(
  server_name: ServerName,
  key: key,
  start_fn: fn(key) ->
    Result(actor.Started(process.Subject(msg)), actor.StartError),
  timeout: Int,
) -> Result(process.Subject(msg), actor.StartError)

@external(erlang, "reki_server", "whereis_server")
fn whereis_server(server_name: ServerName) -> Result(process.Pid, Nil)

@external(erlang, "reki_server", "new_unique_atom")
fn new_server_name() -> ServerName

@external(erlang, "reki_server", "new_unique_atom")
fn new_table_name() -> TableName

@external(erlang, "reki_server", "lookup")
fn ets_lookup(table_name: TableName, key: key) -> Option(process.Subject(msg))
