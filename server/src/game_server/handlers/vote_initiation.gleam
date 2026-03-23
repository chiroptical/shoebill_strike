import game
import game_server/broadcast
import game_server/handlers/abandon_vote
import game_server/handlers/strike_vote
import game_server/state.{type ServerState, ServerState}
import gleam/dict
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import protocol/types as protocol

/// Handle InitiateStrikeVote message
pub fn handle_initiate_strike_vote(
  state: ServerState,
  user_id: String,
) -> ServerState {
  case dict.get(state.connections, user_id) {
    Ok(conn_info) ->
      case conn_info.game_code {
        Some(code) ->
          case dict.get(state.games, code) {
            Ok(game_state) -> {
              // Validate: protocol.ActivePlay phase, stars > 0, no active vote
              case game_state.phase {
                protocol.ActivePlay ->
                  case game_state.strikes > 0 {
                    True ->
                      case dict.has_key(state.vote_states, code) {
                        True -> {
                          // Vote already active, ignore
                          state
                        }
                        False -> {
                          io.println(
                            "[Server] Strike vote initiated by " <> user_id,
                          )
                          // Transition to Strike phase
                          let updated_game =
                            game.transition_phase(game_state, protocol.Strike)
                          let new_games =
                            dict.insert(state.games, code, updated_game)
                          let state = ServerState(..state, games: new_games)

                          // Broadcast phase transition and game state
                          broadcast.broadcast_game_message(
                            state,
                            code,
                            protocol.GameStateUpdate(updated_game),
                          )
                          broadcast.broadcast_game_message(
                            state,
                            code,
                            protocol.PhaseTransition(protocol.Strike),
                          )

                          // Start the vote with user_ids
                          let user_ids =
                            list.map(game_state.players, fn(p) { p.user_id })
                          strike_vote.start_strike_vote(state, code, user_ids)
                        }
                      }
                    False -> {
                      broadcast.send_message(
                        state,
                        user_id,
                        protocol.ServerError("No strikes available"),
                      )
                      state
                    }
                  }
                _ -> {
                  // Not in protocol.ActivePlay, ignore
                  state
                }
              }
            }
            Error(_) -> state
          }
        None -> state
      }
    Error(_) -> state
  }
}

/// Handle CastStrikeVote message
pub fn handle_cast_strike_vote(
  state: ServerState,
  user_id: String,
  approve: Bool,
) -> ServerState {
  case dict.get(state.connections, user_id) {
    Ok(conn_info) ->
      case conn_info.game_code {
        Some(code) ->
          case dict.get(state.vote_states, code) {
            Ok(vote_state) -> {
              // Check if user is in pending list
              case list.contains(vote_state.pending, user_id) {
                True -> {
                  io.println(
                    "[Server] Vote cast by "
                    <> user_id
                    <> ": "
                    <> case approve {
                      True -> "approve"
                      False -> "reject"
                    },
                  )
                  strike_vote.cast_strike_vote(state, code, user_id, approve)
                }
                False -> {
                  // User already voted or not in vote, ignore
                  state
                }
              }
            }
            // No active vote, ignore
            Error(_) -> state
          }
        None -> state
      }
    Error(_) -> state
  }
}

/// Handle InitiateAbandonVote message
pub fn handle_initiate_abandon_vote(
  state: ServerState,
  user_id: String,
) -> ServerState {
  case dict.get(state.connections, user_id) {
    Ok(conn_info) ->
      case conn_info.game_code {
        Some(code) ->
          case dict.get(state.games, code) {
            Ok(game_state) -> {
              // Validate: Dealing, protocol.ActivePlay, or Pause phase; no active vote
              case game_state.phase {
                protocol.Dealing | protocol.ActivePlay | protocol.Pause ->
                  case dict.has_key(state.vote_states, code) {
                    True -> {
                      // Vote already active, ignore
                      state
                    }
                    False -> {
                      io.println(
                        "[Server] Abandon vote initiated by " <> user_id,
                      )
                      // Store previous phase and transition to protocol.AbandonVote
                      let updated_game =
                        protocol.Game(
                          ..game_state,
                          phase: protocol.AbandonVote,
                          abandon_vote_previous_phase: Some(game_state.phase),
                        )
                      let new_games =
                        dict.insert(state.games, code, updated_game)
                      let state = ServerState(..state, games: new_games)

                      // Broadcast phase transition and game state
                      broadcast.broadcast_game_message(
                        state,
                        code,
                        protocol.GameStateUpdate(updated_game),
                      )
                      broadcast.broadcast_game_message(
                        state,
                        code,
                        protocol.PhaseTransition(protocol.AbandonVote),
                      )

                      // Start the vote with user_ids
                      let user_ids =
                        list.map(game_state.players, fn(p) { p.user_id })
                      abandon_vote.start_abandon_vote(state, code, user_ids)
                    }
                  }
                _ -> {
                  // Not in allowed phase, ignore
                  state
                }
              }
            }
            Error(_) -> state
          }
        None -> state
      }
    Error(_) -> state
  }
}

/// Handle CastAbandonVote message
pub fn handle_cast_abandon_vote(
  state: ServerState,
  user_id: String,
  approve: Bool,
) -> ServerState {
  case dict.get(state.connections, user_id) {
    Ok(conn_info) ->
      case conn_info.game_code {
        Some(code) ->
          case dict.get(state.vote_states, code) {
            Ok(vote_state) -> {
              // Check if user is in pending list
              case list.contains(vote_state.pending, user_id) {
                True -> {
                  io.println(
                    "[Server] Abandon vote cast by "
                    <> user_id
                    <> ": "
                    <> case approve {
                      True -> "approve"
                      False -> "reject"
                    },
                  )
                  abandon_vote.cast_abandon_vote(state, code, user_id, approve)
                }
                False -> {
                  // User already voted or not in vote, ignore
                  state
                }
              }
            }
            // No active vote, ignore
            Error(_) -> state
          }
        None -> state
      }
    Error(_) -> state
  }
}
