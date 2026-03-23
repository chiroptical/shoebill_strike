import game_server/broadcast
import game_server/state.{
  type ServerState, CountdownTickMsg, CountdownTimer, ServerState,
}
import gleam/dict
import gleam/erlang/process
import gleam/io
import gleam/option.{None, Some}
import protocol/types.{CountdownTick}

/// Start the countdown for a game
pub fn start_countdown(state: ServerState, game_code: String) -> ServerState {
  // Broadcast initial countdown (3)
  broadcast.broadcast_game_message(state, game_code, CountdownTick(3))

  // Schedule next tick using send_after
  case state.self_subject {
    Some(self) -> {
      process.send_after(self, 1000, CountdownTickMsg(game_code, 2))
      Nil
    }
    None -> {
      io.println(
        "[Server] Warning: self_subject not set, cannot start countdown",
      )
      Nil
    }
  }

  // Store countdown timer state
  let timer = CountdownTimer(game_code: game_code, seconds_remaining: 3)
  let new_timers = dict.insert(state.countdown_timers, game_code, timer)
  ServerState(..state, countdown_timers: new_timers)
}
