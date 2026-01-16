import gleam/dynamic
import gleam/erlang/process
import gleam/erlang/reference
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/string
import reki/ets

/// A registry that manages actors by key.
/// Similar to Discord's gen_registry, this allows you to look up or start actors
/// on demand, ensuring only one actor exists per key.
pub opaque type Registry(key, msg) {
  Registry(
    registry_name: process.Name(RegistryMessage(key, msg)),
    ets_table_name: String,
  )
}

pub opaque type RegistryMessage(key, msg) {
  StartIfNotExists(
    key: key,
    start_fn: fn(key) ->
      Result(actor.Started(process.Subject(msg)), actor.StartError),
    reply_to: process.Subject(Result(process.Subject(msg), actor.StartError)),
  )
  ProcessExited(pid: process.Pid, reason: process.ExitReason)
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

    use ets_table <- result.map(
      ets.new(registry.ets_table_name)
      |> result.replace_error("Failed to create ETS table"),
    )

    let selector =
      process.new_selector()
      |> process.select(get_subject(registry))
      |> process.select_trapped_exits(fn(exit) {
        ProcessExited(exit.pid, exit.reason)
      })

    actor.initialised(ets_table)
    |> actor.selecting(selector)
    |> actor.returning(registry)
  })
  |> actor.on_message(on_message)
  |> actor.named(registry.registry_name)
  |> actor.start
}

fn on_message(
  ets_table: ets.Table,
  message: RegistryMessage(key, msg),
) -> actor.Next(ets.Table, RegistryMessage(key, msg)) {
  case message {
    ProcessExited(pid:) -> {
      case pdict_delete(pid) {
        Ok(key_dynamic) -> {
          let _ = ets.delete_using_dynamic(key_dynamic, ets_table)
          Nil
        }
        Error(Nil) -> Nil
      }

      actor.continue(ets_table)
    }

    StartIfNotExists(key:, start_fn:, reply_to:) -> {
      case ets.lookup_dynamic(key, ets_table) {
        Ok(subject_dynamic) -> {
          process.send(reply_to, Ok(cast_subject(subject_dynamic)))
          actor.continue(ets_table)
        }
        Error(Nil) -> {
          process.send(reply_to, {
            use started <- result.map(start_fn(key))
            let actor.Started(pid:, data: subject) = started
            let assert Ok(Nil) = ets.insert(key, subject, ets_table)
            pdict_put(pid, key)

            subject
          })

          actor.continue(ets_table)
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
pub fn new() -> Registry(key, msg) {
  let unique_id = string.inspect(reference.new())
  Registry(
    registry_name: process.new_name("reki@" <> unique_id),
    ets_table_name: "reki@" <> unique_id,
  )
}

/// A specification for starting the registry under a supervisor.
pub fn supervised(registry: Registry(key, msg)) {
  supervision.worker(fn() { start_registry_actor(registry) })
}

@internal
pub fn get_pid(registry: Registry(a, b)) {
  get_subject(registry) |> process.subject_owner()
}

/// Looks up an actor by key in the registry, or starts it if it doesn't exist.
/// This function ensures that only one actor exists per key, even if called
/// concurrently from multiple processes.
/// Lookups are synchronous via ETS, so no timeout is needed for existing entries.
/// When starting a new actor, a default timeout of 5000ms is used.
pub fn lookup_or_start(
  registry: Registry(key, msg),
  key: key,
  start_fn: fn(key) ->
    Result(actor.Started(process.Subject(msg)), actor.StartError),
) -> Result(process.Subject(msg), actor.StartError) {
  case ets.lookup_by_name(registry.ets_table_name, key) {
    Ok(subject_dynamic) -> Ok(cast_subject(subject_dynamic))
    Error(Nil) ->
      actor.call(get_subject(registry), 5000, fn(reply_to) {
        StartIfNotExists(key:, start_fn:, reply_to:)
      })
  }
}

@external(erlang, "reki_ets_ffi", "cast_subject")
fn cast_subject(value: dynamic.Dynamic) -> process.Subject(msg)

@external(erlang, "reki_ets_ffi", "pdict_put")
fn pdict_put(pid: process.Pid, key: key) -> Nil

@external(erlang, "reki_ets_ffi", "pdict_delete")
fn pdict_delete(pid: process.Pid) -> Result(dynamic.Dynamic, Nil)
