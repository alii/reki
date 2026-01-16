# reki

A Gleam actor registry that manages actors by key, similar to Discord's [gen_registry](https://github.com/discord/gen_registry) in Elixir. It provides a way to look up or start actors on demand ensuring only one actor exists per key, while automatically cleaning up dead processes.

## Installation

Add to your `gleam.toml` as a git dependency:

```toml
[dependencies]
reki = { git = "git@github.com:alii/reki.git", ref = "<commit hash>" }
```

## Usage

```gleam
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import reki

pub type ChannelMsg {
  Subscribe(process.Subject(String))
  Publish(String)
}

pub type ChannelState {
  ChannelState(name: String, subscribers: List(process.Subject(String)))
}

fn start_channel(name: String) {
  actor.new(ChannelState(name:, subscribers: []))
  |> actor.on_message(fn(state, msg) {
    println("Channel" <> state.name <> " received message: " <> inspect(msg))

    case msg {
      Subscribe(sub) ->
        actor.continue(ChannelState(..state, subscribers: [sub, ..state.subscribers]))
      Publish(text) -> {
        list.each(state.subscribers, process.send(_, text))
        actor.continue(state)
      }
    }
  })
  |> actor.start
}

pub fn main() {
  let channels = reki.new()

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(reki.supervised(channels))
    |> supervisor.start

  let assert Ok(general) =
    reki.lookup_or_start(channels, "general", start_channel)

  let inbox = process.new_subject()
  process.send(general, Subscribe(inbox))

  process.send(general, Publish("Hello!"))

  let assert Ok(same_channel) =
    reki.lookup_or_start(channels, "general", start_channel)

  process.send(same_channel, Publish("Also hello!"))
}
```

## How it works

Like gen_registry, reki stores `{key, subject}` mappings in ETS for fast O(1) lookups that bypass the registry actor. The registry actor serializes "lookup or start" operations to prevent races when multiple processes request the same key simultaneously.

- **Fast reads**: Existing actors are looked up directly from ETS
- **Direct spawning**: Workers are spawned directly by the registry (like gen_registry)
- **Automatic cleanup**: The registry monitors actors and removes them from ETS when they die
- **Concurrent safety**: Start operations are serialized through the registry actor
