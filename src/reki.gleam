import gleam/dynamic
import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import reki/ets

/// A registry that manages actors by key.
/// Similar to Discord's gen_registry, this allows you to look up or start actors
/// on demand, ensuring only one actor exists per key.
///
/// ## Architecture
///
/// Reki uses an ETS table for fast O(1) lookups, with a registry actor that
/// handles process lifecycle (starting new actors, cleaning up dead ones).
/// When a managed actor dies, reki receives an EXIT signal and removes the
/// stale entry from ETS.
///
/// The ETS table is owned by the registry actor. If the actor crashes, the
/// BEAM automatically destroys the table. When the supervisor restarts the
/// actor, a fresh table is created — no stale entries from a previous life.
///
/// ## Stale entries
///
/// There's a brief window between when a process dies and when reki processes
/// the EXIT signal. During this window, `lookup` or `lookup_or_start` may
/// return a stale Subject pointing to a dead process. This is the tradeoff
/// for fast O(1) lookups.
pub opaque type Registry(key, msg) {
  Registry(
    registry_name: process.Name(RegistryMessage(key, msg)),
    table_name: ets.TableIdentifier,
  )
}

pub opaque type RegistryMessage(key, msg) {
  StartIfNotExists(
    key: key,
    start_fn: fn(key) ->
      Result(actor.Started(process.Subject(msg)), actor.StartError),
    reply_to: process.Subject(Result(process.Subject(msg), actor.StartError)),
  )
  ProcessExited(pid: process.Pid)
}

@internal
pub fn get_subject(
  registry: Registry(key, msg),
) -> process.Subject(RegistryMessage(key, msg)) {
  process.named_subject(registry.registry_name)
}

fn start_registry_actor(
  registry: Registry(key, msg),
) -> Result(actor.Started(Registry(key, msg)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(_) {
    process.trap_exits(True)

    // Create a fresh ETS table owned by this actor, using the registry's
    // dedicated table name (a unique atom). When this actor dies, the BEAM
    // destroys the table automatically — no stale entries survive.
    ets.new(registry.table_name)

    let selector =
      process.new_selector()
      |> process.select(get_subject(registry))
      |> process.select_trapped_exits(fn(exit) { ProcessExited(exit.pid) })

    Ok(
      actor.initialised(registry.table_name)
      |> actor.selecting(selector)
      |> actor.returning(registry),
    )
  })
  |> actor.on_message(on_message)
  |> actor.named(registry.registry_name)
  |> actor.start
}

fn on_message(
  table_id: ets.TableIdentifier,
  message: RegistryMessage(key, msg),
) -> actor.Next(ets.TableIdentifier, RegistryMessage(key, msg)) {
  case message {
    ProcessExited(pid:) -> {
      case pdict_delete(pid) {
        Ok(key_dynamic) -> {
          let _ = ets.delete_using_dynamic(key_dynamic, table_id)
          Nil
        }
        Error(Nil) -> Nil
      }

      actor.continue(table_id)
    }

    StartIfNotExists(key:, start_fn:, reply_to:) -> {
      case ets.lookup_dynamic(key, table_id) {
        Some(subject_dynamic) -> {
          process.send(reply_to, Ok(cast_subject(subject_dynamic)))
          actor.continue(table_id)
        }
        None -> {
          process.send(reply_to, {
            use started <- result.map(start_fn(key))
            let actor.Started(pid:, data: subject) = started
            let assert Ok(Nil) = ets.insert(key, subject, table_id)
            pdict_put(pid, key)

            subject
          })

          actor.continue(table_id)
        }
      }
    }
  }
}

/// Start the registry. You likely want to use the `supervised` function instead,
/// to add the registry to your supervision tree, but this may be useful in tests.
pub fn start(
  registry: Registry(key, msg),
) -> Result(actor.Started(Registry(key, msg)), actor.StartError) {
  start_registry_actor(registry)
}

/// Create a registry. Call this at the start of your program before
/// creating the supervision tree.
///
/// **Important:** Each call creates a unique atom for the ETS table name.
/// Atoms are never garbage collected by the BEAM, so this function must
/// only be called a fixed number of times (e.g. once per registry at app
/// startup). Do not call `new()` dynamically in a loop or on each request.
pub fn new() -> Registry(key, msg) {
  Registry(
    registry_name: process.new_name("reki"),
    table_name: ets.new_table_identifier(),
  )
}

/// A specification for starting the registry under a supervisor.
pub fn supervised(
  registry: Registry(key, msg),
) -> supervision.ChildSpecification(Registry(key, msg)) {
  supervision.worker(fn() { start_registry_actor(registry) })
}

/// Looks up an actor by key, or starts one if it doesn't exist.
///
/// This is the primary function for getting an actor from the registry. It
/// first checks ETS for an existing entry (fast O(1) lookup), and only goes
/// through the registry actor if the key isn't found.
///
/// In rare cases, this may return a stale Subject if a process just died but
/// reki hasn't processed the EXIT yet. If calling the returned Subject fails,
/// retry with `lookup_or_start_slow`.
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
  case ets.lookup_dynamic(key, registry.table_name) {
    Some(subject_dynamic) -> Some(cast_subject(subject_dynamic))
    None -> None
  }
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
/// the registry actor. By going through the actor, any pending `EXIT`s
/// in the registry's mailbox are processed first. This lets you block
/// and synchronize with the registry.
///
/// **You probably don't need this function.** It serializes all requests
/// through the registry actor, which becomes a bottleneck under load. Make
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
  actor.call(get_subject(registry), timeout, fn(reply_to) {
    StartIfNotExists(key:, start_fn:, reply_to:)
  })
}

@internal
pub fn get_pid(registry: Registry(a, b)) -> Result(process.Pid, Nil) {
  get_subject(registry) |> process.subject_owner()
}

@external(erlang, "reki_ets_ffi", "cast_subject")
fn cast_subject(value: dynamic.Dynamic) -> process.Subject(msg)

@external(erlang, "reki_ets_ffi", "pdict_put")
fn pdict_put(pid: process.Pid, key: key) -> Nil

@external(erlang, "reki_ets_ffi", "pdict_delete")
fn pdict_delete(pid: process.Pid) -> Result(dynamic.Dynamic, Nil)
