import game
import game_server/broadcast
import game_server/event_log
import game_server/state.{type ServerState, ConnectionInfo, ServerState}
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import lobby
import protocol/types as protocol

/// Handle LeaveGame message
pub fn handle_leave_game(state: ServerState, user_id: String) -> ServerState {
  io.println("[Server] LeaveGame received from user " <> user_id)
  case dict.get(state.connections, user_id) {
    Ok(conn_info) ->
      case conn_info.game_code {
        Some(code) ->
          case dict.get(state.games, code) {
            Ok(game_state) -> {
              // Remove user from game
              let remaining_players =
                list.filter(game_state.players, fn(p) { p.user_id != user_id })

              // Send YouLeft to the leaving user
              broadcast.send_message(state, user_id, protocol.YouLeft)

              // Clear connection mappings for leaving user
              let updated_conn =
                ConnectionInfo(..conn_info, lobby_code: None, game_code: None)
              let state =
                ServerState(
                  ..state,
                  connections: dict.insert(
                    state.connections,
                    user_id,
                    updated_conn,
                  ),
                )

              case remaining_players {
                [] -> {
                  // No players left — clean up game and lobby
                  io.println(
                    "[Server] All players left, cleaning up game " <> code,
                  )
                  ServerState(
                    ..state,
                    games: dict.delete(state.games, code),
                    lobbies: dict.delete(state.lobbies, code),
                  )
                }
                _ -> {
                  // Check if host left, reassign if needed
                  let was_host = game_state.host_user_id == user_id
                  let new_host_user_id = case was_host {
                    True ->
                      case remaining_players {
                        [first, ..] -> first.user_id
                        [] -> ""
                      }
                    False -> game_state.host_user_id
                  }

                  let updated_game =
                    protocol.Game(
                      ..game_state,
                      players: remaining_players,
                      host_user_id: new_host_user_id,
                    )
                  let state =
                    ServerState(
                      ..state,
                      games: dict.insert(state.games, code, updated_game),
                    )

                  // Also update the lobby if it exists
                  let state = case dict.get(state.lobbies, code) {
                    Ok(lobby_state) -> {
                      let updated_lobby =
                        lobby.remove_player(lobby_state, user_id)
                      ServerState(
                        ..state,
                        lobbies: dict.insert(state.lobbies, code, updated_lobby),
                      )
                    }
                    Error(_) -> state
                  }

                  // Broadcast PlayerLeft to remaining users
                  let new_host_option = case was_host {
                    True -> Some(new_host_user_id)
                    False -> None
                  }
                  broadcast.broadcast_game_message(
                    state,
                    code,
                    protocol.PlayerLeft(user_id, new_host_option),
                  )
                  broadcast.broadcast_game_message(
                    state,
                    code,
                    protocol.GameStateUpdate(updated_game),
                  )

                  state
                }
              }
            }
            Error(_) -> {
              broadcast.send_message(
                state,
                user_id,
                protocol.ServerError("Game not found"),
              )
              state
            }
          }
        None -> {
          broadcast.send_message(
            state,
            user_id,
            protocol.ServerError("Not in a game"),
          )
          state
        }
      }
    Error(_) -> state
  }
}

/// Handle RestartGame message (host only, EndGame phase)
pub fn handle_restart_game(state: ServerState, user_id: String) -> ServerState {
  io.println("[Server] RestartGame received from user " <> user_id)
  case dict.get(state.connections, user_id) {
    Ok(conn_info) ->
      case conn_info.game_code {
        Some(code) ->
          case dict.get(state.games, code) {
            Ok(game_state) -> {
              // Validate: must be host
              case game_state.host_user_id == user_id {
                False -> {
                  broadcast.send_message(
                    state,
                    user_id,
                    protocol.ServerError("Only the host can restart"),
                  )
                  state
                }
                True ->
                  // Validate: must be in EndGame phase
                  case game_state.phase {
                    protocol.EndGame(_) -> {
                      // Validate: all players ready
                      case game.all_players_ready_in_game(game_state) {
                        False -> {
                          broadcast.send_message(
                            state,
                            user_id,
                            protocol.ServerError(
                              "All players must be ready to restart",
                            ),
                          )
                          state
                        }
                        True -> {
                          let player_count = list.length(game_state.players)
                          case player_count >= 2 && player_count <= 4 {
                            False -> {
                              broadcast.send_message(
                                state,
                                user_id,
                                protocol.ServerError(
                                  "Need 2-4 players to restart",
                                ),
                              )
                              state
                            }
                            True -> {
                              io.println("[Server] Restarting game " <> code)

                              // Convert game to lobby (to get incremented games_played)
                              let new_lobby = game.game_to_lobby(game_state)

                              // Create new game from lobby
                              let shuffle_fn = fn(deck: List(Int)) {
                                game.shuffle_deck(deck, fn(max) {
                                  int.random(max)
                                })
                              }
                              let new_game =
                                game.create_game_from_lobby(
                                  new_lobby,
                                  shuffle_fn,
                                )

                              // Reset ready states so players can see their hands before readying up
                              let new_game =
                                protocol.Game(
                                  ..new_game,
                                  players: list.map(new_game.players, fn(p) {
                                    protocol.GamePlayer(..p, is_ready: False)
                                  }),
                                )

                              // Store game in state
                              let state =
                                ServerState(
                                  ..state,
                                  games: dict.insert(
                                    state.games,
                                    code,
                                    new_game,
                                  ),
                                )

                              // Broadcast game started to all players
                              broadcast.broadcast_message(
                                state,
                                code,
                                protocol.GameStarted,
                              )

                              // Log RoundStarted event for round 1
                              let new_game =
                                event_log.log_event(
                                  state,
                                  code,
                                  new_game,
                                  protocol.RoundStarted(new_game.current_round),
                                )

                              // Update game in state with the logged event
                              let state =
                                ServerState(
                                  ..state,
                                  games: dict.insert(
                                    state.games,
                                    code,
                                    new_game,
                                  ),
                                )

                              // Broadcast game state and phase transition (stays in Dealing)
                              broadcast.broadcast_message(
                                state,
                                code,
                                protocol.GameStateUpdate(new_game),
                              )
                              broadcast.broadcast_message(
                                state,
                                code,
                                protocol.PhaseTransition(protocol.Dealing),
                              )
                              state
                            }
                          }
                        }
                      }
                    }
                    _ -> {
                      broadcast.send_message(
                        state,
                        user_id,
                        protocol.ServerError("Can only restart in End Game"),
                      )
                      state
                    }
                  }
              }
            }
            Error(_) -> {
              broadcast.send_message(
                state,
                user_id,
                protocol.ServerError("Game not found"),
              )
              state
            }
          }
        None -> {
          broadcast.send_message(
            state,
            user_id,
            protocol.ServerError("Not in a game"),
          )
          state
        }
      }
    Error(_) -> state
  }
}
