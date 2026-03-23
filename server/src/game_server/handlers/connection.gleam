import game_server/broadcast
import game_server/helpers
import game_server/state.{type ServerState, ServerState}
import gleam/dict
import gleam/list
import gleam/result
import gleam/time/timestamp
import protocol/types as protocol

/// Mark a player as disconnected in a lobby and broadcast to others
pub fn mark_player_disconnected_in_lobby(
  state: ServerState,
  lobby_code: String,
  user_id: String,
) -> ServerState {
  case dict.get(state.lobbies, lobby_code) {
    Ok(lobby_state) -> {
      let updated_players =
        list.map(lobby_state.players, fn(p) {
          case p.user_id == user_id {
            True -> protocol.Player(..p, is_connected: False)
            False -> p
          }
        })
      let updated_lobby =
        protocol.Lobby(..lobby_state, players: updated_players)
      let state =
        ServerState(
          ..state,
          lobbies: dict.insert(state.lobbies, lobby_code, updated_lobby),
        )
      // Broadcast PlayerDisconnected to remaining players
      broadcast.broadcast_message(
        state,
        lobby_code,
        protocol.PlayerDisconnected(user_id),
      )
      state
    }
    Error(_) -> state
  }
}

/// Mark a player as disconnected in a game and broadcast to others
pub fn mark_player_disconnected_in_game(
  state: ServerState,
  game_code: String,
  user_id: String,
) -> ServerState {
  case dict.get(state.games, game_code) {
    Ok(game_state) -> {
      // Find player nickname for logging
      let nickname =
        list.find(game_state.players, fn(p) { p.user_id == user_id })
        |> result.map(fn(p) { p.nickname })
        |> result.unwrap(user_id)

      let updated_players =
        list.map(game_state.players, fn(p) {
          case p.user_id == user_id {
            True -> protocol.GamePlayer(..p, is_connected: False)
            False -> p
          }
        })
      let updated_game = protocol.Game(..game_state, players: updated_players)

      // Log the disconnection event
      let event =
        protocol.GameEvent(
          timestamp.system_time(),
          protocol.PlayerDisconnectedEvent(nickname),
        )
      let updated_game =
        protocol.Game(..updated_game, game_log: [event, ..updated_game.game_log])

      let state =
        ServerState(
          ..state,
          games: dict.insert(state.games, game_code, updated_game),
        )
      // Broadcast PlayerDisconnected and log event to remaining players
      broadcast.broadcast_game_message(
        state,
        game_code,
        protocol.PlayerDisconnected(user_id),
      )
      broadcast.broadcast_game_message(
        state,
        game_code,
        protocol.GameLogEvent(event),
      )
      state
    }
    Error(_) -> state
  }
}

/// Mark a player as reconnected in a game and broadcast to others
pub fn mark_player_reconnected_in_game(
  state: ServerState,
  game_code: String,
  user_id: String,
) -> ServerState {
  case dict.get(state.games, game_code) {
    Ok(game_state) -> {
      // Find player nickname for logging
      let nickname =
        list.find(game_state.players, fn(p) { p.user_id == user_id })
        |> result.map(fn(p) { p.nickname })
        |> result.unwrap(user_id)

      let updated_players =
        list.map(game_state.players, fn(p) {
          case p.user_id == user_id {
            True -> protocol.GamePlayer(..p, is_connected: True)
            False -> p
          }
        })
      let updated_game = protocol.Game(..game_state, players: updated_players)

      // Log the reconnection event
      let event =
        protocol.GameEvent(
          timestamp.system_time(),
          protocol.PlayerReconnectedEvent(nickname),
        )
      let updated_game =
        protocol.Game(..updated_game, game_log: [event, ..updated_game.game_log])

      let state =
        ServerState(
          ..state,
          games: dict.insert(state.games, game_code, updated_game),
        )
      // Broadcast PlayerReconnected and log event to all players
      broadcast.broadcast_game_message(
        state,
        game_code,
        protocol.PlayerReconnected(user_id),
      )
      broadcast.broadcast_game_message(
        state,
        game_code,
        protocol.GameLogEvent(event),
      )
      state
    }
    Error(_) -> state
  }
}

/// Handle game reconnection: send current game state and vote state to reconnecting user
pub fn handle_game_reconnection(
  state: ServerState,
  game_code: String,
  user_id: String,
) -> ServerState {
  case dict.get(state.games, game_code) {
    Ok(_game_state) -> {
      // Update connection with game_code
      let state = helpers.update_player_game(state, user_id, game_code)

      // Mark player as reconnected and broadcast to others
      let state = mark_player_reconnected_in_game(state, game_code, user_id)

      // Re-fetch game state after updating it
      case dict.get(state.games, game_code) {
        Ok(updated_game_state) -> {
          // Send current game state to reconnecting user
          broadcast.send_message(
            state,
            user_id,
            protocol.GameStateUpdate(updated_game_state),
          )

          // Send vote state if there's an active vote
          case dict.get(state.vote_states, game_code) {
            Ok(vote_state) -> {
              let seconds =
                dict.get(state.vote_timers, game_code) |> result.unwrap(0)
              let vote_msg = case updated_game_state.phase {
                protocol.AbandonVote ->
                  protocol.AbandonVoteUpdate(
                    dict.to_list(vote_state.votes),
                    vote_state.pending,
                    seconds,
                  )
                _ ->
                  protocol.StrikeVoteUpdate(
                    dict.to_list(vote_state.votes),
                    vote_state.pending,
                    seconds,
                  )
              }
              broadcast.send_message(state, user_id, vote_msg)
              state
            }
            Error(_) -> state
          }
        }
        Error(_) -> state
      }
    }
    Error(_) -> state
  }
}
