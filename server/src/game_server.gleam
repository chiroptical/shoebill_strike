import game_server/actor as game_actor
import game_server/state.{type ServerMsg, type ServerState}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/time/timestamp

/// Start the server actor (re-export from actor module)
pub fn start() -> Result(Subject(ServerMsg), actor.StartError) {
  game_actor.start()
}

/// Adjust timestamp for user latency. Currently returns timestamp unchanged.
/// TODO: Implement latency compensation using ping/pong measurement.
pub fn adjust_timestamp_for_latency(
  ts: timestamp.Timestamp,
  _user_id: String,
  _state: ServerState,
) -> timestamp.Timestamp {
  ts
}
