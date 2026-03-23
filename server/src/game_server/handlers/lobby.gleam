import game
import game_server/broadcast
import game_server/event_log
import game_server/handlers/connection
import game_server/helpers
import game_server/state.{type ServerState, ServerState}
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import lobby
import protocol/types as protocol

/// Handle CreateGame message
pub fn handle_create_game(
  state: ServerState,
  user_id: String,
  nickname: String,
) -> ServerState {
  io.println(
    "[Server] Creating game for user "
    <> user_id
    <> " (nickname: "
    <> nickname
    <> ")",
  )
  // Generate a unique code
  let code = helpers.generate_unique_code(state.lobbies)
  let new_lobby = lobby.create_lobby(code, user_id, nickname)
  let new_lobbies = dict.insert(state.lobbies, code, new_lobby)

  // Update connection info
  let state = ServerState(..state, lobbies: new_lobbies)
  let state = helpers.update_player_lobby(state, user_id, code)

  // Send response to creator
  io.println("[Server] Game created with code: " <> code)
  broadcast.send_message(state, user_id, protocol.GameCreated(code))
  // Broadcast lobby state to all players (including creator)
  broadcast.broadcast_lobby_state(state, code)

  state
}

/// Handle JoinGame message
pub fn handle_join_game(
  state: ServerState,
  user_id: String,
  code: String,
  nickname: String,
) -> ServerState {
  io.println(
    "[Server] User "
    <> user_id
    <> " joining game "
    <> code
    <> " (nickname: "
    <> nickname
    <> ")",
  )
  case dict.get(state.lobbies, code) {
    Ok(lobby_state) -> {
      // Check if this is a reconnection (user_id already exists)
      let is_reconnection =
        lobby_state.players
        |> list.any(fn(p) { p.user_id == user_id })

      case lobby.add_player(lobby_state, user_id, nickname) {
        Ok(updated_lobby) -> {
          case is_reconnection {
            True ->
              io.println(
                "[Server] User reconnected. Lobby has "
                <> int.to_string(list.length(updated_lobby.players))
                <> " players",
              )
            False ->
              io.println(
                "[Server] New user added. Lobby now has "
                <> int.to_string(list.length(updated_lobby.players))
                <> " players",
              )
          }

          let new_lobbies = dict.insert(state.lobbies, code, updated_lobby)
          let state = ServerState(..state, lobbies: new_lobbies)
          let state = helpers.update_player_lobby(state, user_id, code)

          // Send GameJoined confirmation (client already knows their user_id)
          broadcast.send_message(state, user_id, protocol.GameJoined)

          // Broadcast updated lobby state to all players
          broadcast.broadcast_lobby_state(state, code)

          // Handle reconnection - broadcast reconnection message and game state
          let state = case is_reconnection {
            True -> {
              // Broadcast PlayerReconnected to lobby players
              broadcast.broadcast_message(
                state,
                code,
                protocol.PlayerReconnected(user_id),
              )
              connection.handle_game_reconnection(state, code, user_id)
            }
            False -> state
          }

          state
        }
        Error(err) -> {
          io.println("[Server] Failed to add user: " <> err)
          broadcast.send_message(state, user_id, protocol.ServerError(err))
          state
        }
      }
    }
    Error(_) -> {
      io.println("[Server] Lobby not found: " <> code)
      broadcast.send_message(
        state,
        user_id,
        protocol.ServerError("Lobby not found"),
      )
      state
    }
  }
}

/// Handle ToggleReady message
pub fn handle_toggle_ready(state: ServerState, user_id: String) -> ServerState {
  case dict.get(state.connections, user_id) {
    Ok(conn_info) ->
      case conn_info.lobby_code {
        Some(code) ->
          case dict.get(state.lobbies, code) {
            Ok(lobby_state) -> {
              case lobby.toggle_ready(lobby_state, user_id) {
                Ok(updated_lobby) -> {
                  let new_lobbies =
                    dict.insert(state.lobbies, code, updated_lobby)
                  let state = ServerState(..state, lobbies: new_lobbies)

                  // Broadcast updated lobby state
                  broadcast.broadcast_lobby_state(state, code)

                  state
                }
                Error(err) -> {
                  broadcast.send_message(
                    state,
                    user_id,
                    protocol.ServerError(err),
                  )
                  state
                }
              }
            }
            Error(_) -> {
              broadcast.send_message(
                state,
                user_id,
                protocol.ServerError("Lobby not found"),
              )
              state
            }
          }
        None -> {
          broadcast.send_message(
            state,
            user_id,
            protocol.ServerError("Not in a lobby"),
          )
          state
        }
      }
    Error(_) -> state
  }
}

/// Handle StartGame message
pub fn handle_start_game(state: ServerState, user_id: String) -> ServerState {
  case dict.get(state.connections, user_id) {
    Ok(conn_info) ->
      case conn_info.lobby_code {
        Some(code) ->
          case dict.get(state.lobbies, code) {
            Ok(lobby_state) -> {
              case lobby.can_start_game(lobby_state, user_id) {
                True -> {
                  io.println("[Server] Starting game from lobby: " <> code)
                  io.println(
                    "[Server] Lobby has "
                    <> int.to_string(list.length(lobby_state.players))
                    <> " players",
                  )

                  // Create game from lobby
                  let shuffle_fn = fn(deck: List(Int)) {
                    game.shuffle_deck(deck, fn(max) { int.random(max) })
                  }
                  let new_game =
                    game.create_game_from_lobby(lobby_state, shuffle_fn)

                  io.println(
                    "[Server] Game created with "
                    <> int.to_string(new_game.lives)
                    <> " lives, "
                    <> int.to_string(new_game.strikes)
                    <> " stars",
                  )

                  // Log each player's hand size
                  list.each(new_game.players, fn(p) {
                    io.println(
                      "[Server] Player "
                      <> p.nickname
                      <> " has "
                      <> int.to_string(list.length(p.hand))
                      <> " card(s)",
                    )
                  })

                  // Store game in state temporarily for connection updates
                  let new_games = dict.insert(state.games, code, new_game)
                  let state = ServerState(..state, games: new_games)

                  // Update all players' connection info with game_code
                  let state =
                    lobby_state.players
                    |> list.fold(state, fn(acc_state, p) {
                      helpers.update_player_game(acc_state, p.user_id, code)
                    })

                  // Broadcast game started to all players (for screen transition)
                  broadcast.broadcast_message(state, code, protocol.GameStarted)

                  // Log RoundStarted event for round 1
                  let new_game =
                    event_log.log_event(
                      state,
                      code,
                      new_game,
                      protocol.RoundStarted(new_game.current_round),
                    )

                  // Update game in state with the logged event
                  let new_games = dict.insert(state.games, code, new_game)
                  let state = ServerState(..state, games: new_games)

                  // Broadcast initial game state to all players
                  broadcast.broadcast_game_message(
                    state,
                    code,
                    protocol.GameStateUpdate(new_game),
                  )

                  state
                }
                False -> {
                  broadcast.send_message(
                    state,
                    user_id,
                    protocol.ServerError(
                      "Cannot start game: not creator or not all players ready",
                    ),
                  )
                  state
                }
              }
            }
            Error(_) -> {
              broadcast.send_message(
                state,
                user_id,
                protocol.ServerError("Lobby not found"),
              )
              state
            }
          }
        None -> {
          broadcast.send_message(
            state,
            user_id,
            protocol.ServerError("Not in a lobby"),
          )
          state
        }
      }
    Error(_) -> state
  }
}
