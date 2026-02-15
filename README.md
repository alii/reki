# reki

A Gleam actor registry that manages actors by key, similar to Discord's [gen_registry](https://github.com/discord/gen_registry) in Elixir. It provides a way to look up or start actors on demand ensuring only one actor exists per key, while automatically cleaning up dead processes.

## Installation

```sh
gleam add reki
```

## Usage

```gleam
import gleam/erlang/process
import gleam/list
import gleam/option
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

  // You can also lookup without starting
  case reki.lookup(channels, "general") {
    option.Some(channel) -> process.send(channel, Publish("Found it!"))
    option.None -> {
      // channel not found ...
      todo
    }
  }
}
```

## How it works

Like gen_registry, reki is an Erlang gen_server that stores `{key, subject}` mappings in ETS for fast O(1) lookups. The gen_server serializes "lookup or start" operations to prevent races when multiple processes request the same key simultaneously.

- **Fast reads**: Existing actors are looked up directly from ETS, bypassing the gen_server
- **Automatic cleanup**: The registry links to child processes and traps exits, removing entries from ETS when they die
- **Concurrent safety**: Start operations are serialized through the gen_server
