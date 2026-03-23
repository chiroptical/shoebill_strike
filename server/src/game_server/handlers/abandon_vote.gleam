import game_server/broadcast
import game_server/state.{
  type ServerState, AbandonVoteTickMsg, ServerState, VoteState,
}
import gleam/dict
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/result
import protocol/types as protocol

/// Start an abandon vote
pub fn start_abandon_vote(
  state: ServerState,
  game_code: String,
  user_ids: List(String),
) -> ServerState {
  let vote_state =
    VoteState(game_code: game_code, votes: dict.new(), pending: user_ids)

  let state =
    ServerState(
      ..state,
      vote_states: dict.insert(state.vote_states, game_code, vote_state),
      vote_timers: dict.insert(state.vote_timers, game_code, 10),
    )

  // Broadcast initial vote update
  broadcast.broadcast_game_message(
    state,
    game_code,
    protocol.AbandonVoteUpdate([], user_ids, 10),
  )

  // Schedule first tick at 9 seconds
  case state.self_subject {
    Some(self) -> {
      process.send_after(self, 1000, AbandonVoteTickMsg(game_code, 9))
      Nil
    }
    _ -> Nil
  }

  state
}

/// Cast a vote in an abandon vote
pub fn cast_abandon_vote(
  state: ServerState,
  game_code: String,
  user_id: String,
  approve: Bool,
) -> ServerState {
  case dict.get(state.vote_states, game_code) {
    Ok(vote_state) -> {
      let new_votes = dict.insert(vote_state.votes, user_id, approve)
      let new_pending =
        list.filter(vote_state.pending, fn(uid) { uid != user_id })
      let updated_vote =
        VoteState(..vote_state, votes: new_votes, pending: new_pending)
      let state =
        ServerState(
          ..state,
          vote_states: dict.insert(state.vote_states, game_code, updated_vote),
        )

      // Get current timer seconds for the broadcast
      let seconds = dict.get(state.vote_timers, game_code) |> result.unwrap(0)

      // Broadcast updated vote state
      broadcast.broadcast_game_message(
        state,
        game_code,
        protocol.AbandonVoteUpdate(
          dict.to_list(new_votes),
          new_pending,
          seconds,
        ),
      )

      // Check if vote should resolve: any reject or all voted
      case approve {
        False -> {
          // Any single rejection cancels the vote immediately
          resolve_abandon_vote(state, game_code)
        }
        True ->
          case new_pending {
            [] -> {
              // All voted and all approved
              resolve_abandon_vote(state, game_code)
            }
            _ -> state
          }
      }
    }
    Error(_) -> state
  }
}

/// Resolve an abandon vote
pub fn resolve_abandon_vote(
  state: ServerState,
  game_code: String,
) -> ServerState {
  case dict.get(state.vote_states, game_code) {
    Ok(vote_state) -> {
      let all_approved =
        vote_state.votes
        |> dict.values
        |> list.all(fn(v) { v })

      // Clean up vote state
      let state =
        ServerState(
          ..state,
          vote_states: dict.delete(state.vote_states, game_code),
          vote_timers: dict.delete(state.vote_timers, game_code),
        )

      case all_approved {
        False -> {
          // Vote failed — return to previous phase
          io.println("[Server] Abandon vote rejected")
          case dict.get(state.games, game_code) {
            Ok(game_state) -> {
              let previous = case game_state.abandon_vote_previous_phase {
                Some(phase) -> phase
                _ -> protocol.ActivePlay
              }
              let updated_game =
                protocol.Game(
                  ..game_state,
                  phase: previous,
                  abandon_vote_previous_phase: option.None,
                )
              let new_games = dict.insert(state.games, game_code, updated_game)
              let state = ServerState(..state, games: new_games)
              broadcast.broadcast_game_message(
                state,
                game_code,
                protocol.GameStateUpdate(updated_game),
              )
              broadcast.broadcast_game_message(
                state,
                game_code,
                protocol.PhaseTransition(previous),
              )
              state
            }
            Error(_) -> state
          }
        }
        True -> {
          // Vote succeeded — transition to EndGame(Abandoned)
          io.println("[Server] Abandon vote approved — game abandoned")
          case dict.get(state.games, game_code) {
            Ok(game_state) -> {
              let updated_game =
                protocol.Game(
                  ..game_state,
                  phase: protocol.EndGame(protocol.Abandoned),
                  abandon_vote_previous_phase: option.None,
                )
              // Reset ready states for EndGame
              let updated_players =
                list.map(updated_game.players, fn(p) {
                  protocol.GamePlayer(..p, is_ready: False)
                })
              let updated_game =
                protocol.Game(..updated_game, players: updated_players)
              let new_games = dict.insert(state.games, game_code, updated_game)
              let state = ServerState(..state, games: new_games)
              broadcast.broadcast_game_message(
                state,
                game_code,
                protocol.GameStateUpdate(updated_game),
              )
              broadcast.broadcast_game_message(
                state,
                game_code,
                protocol.PhaseTransition(protocol.EndGame(protocol.Abandoned)),
              )
              state
            }
            Error(_) -> state
          }
        }
      }
    }
    Error(_) -> state
  }
}
