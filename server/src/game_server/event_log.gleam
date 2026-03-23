import game_server/broadcast
import game_server/state.{type ServerState}
import gleam/time/timestamp
import protocol/types as protocol

/// Create a game event with the current timestamp
pub fn create_event(event_type: protocol.GameEventType) -> protocol.GameEvent {
  protocol.GameEvent(timestamp: timestamp.system_time(), event_type: event_type)
}

/// Log an event to the game and broadcast it to all players
pub fn log_event(
  state: ServerState,
  game_code: String,
  game: protocol.Game,
  event_type: protocol.GameEventType,
) -> protocol.Game {
  let event = create_event(event_type)
  let updated_game = protocol.Game(..game, game_log: [event, ..game.game_log])

  // Broadcast the event to all players
  broadcast.broadcast_game_message(
    state,
    game_code,
    protocol.GameLogEvent(event),
  )

  updated_game
}
