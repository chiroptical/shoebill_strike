import game
import game_server/broadcast
import game_server/event_log
import game_server/state.{type ServerState, ServerState, VoteState, VoteTickMsg}
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/result
import protocol/types as protocol

/// Start a strike vote
pub fn start_strike_vote(
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
    protocol.StrikeVoteUpdate([], user_ids, 10),
  )

  // Schedule first tick at 9 seconds
  case state.self_subject {
    Some(self) -> {
      process.send_after(self, 1000, VoteTickMsg(game_code, 9))
      Nil
    }
    _ -> Nil
  }

  state
}

/// Cast a vote in a strike vote
pub fn cast_strike_vote(
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
        protocol.StrikeVoteUpdate(dict.to_list(new_votes), new_pending, seconds),
      )

      // Check if vote should resolve: any reject or all voted
      case approve {
        False -> {
          // Any single rejection cancels the vote immediately
          resolve_strike_vote(state, game_code)
        }
        True ->
          case new_pending {
            [] -> {
              // All voted and all approved
              resolve_strike_vote(state, game_code)
            }
            _ -> state
          }
      }
    }
    Error(_) -> state
  }
}

/// Resolve a strike vote
pub fn resolve_strike_vote(state: ServerState, game_code: String) -> ServerState {
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
          // Vote failed — go to Pause for regrouping
          io.println("[Server] Strike vote rejected")
          case dict.get(state.games, game_code) {
            Ok(game_state) -> {
              let updated_game =
                game_state
                |> game.transition_phase(protocol.Pause)
                |> game.reset_ready_states
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
                protocol.PhaseTransition(protocol.Pause),
              )
              state
            }
            Error(_) -> state
          }
        }
        True -> {
          // Vote succeeded — apply strike
          io.println("[Server] Strike vote approved")
          case dict.get(state.games, game_code) {
            Ok(game_state) -> {
              // Get discards before applying for the broadcast
              let discards = game.get_strike_discards(game_state)
              io.println(
                "[Server] Strike discards: "
                <> int.to_string(list.length(discards))
                <> " cards",
              )

              case game.apply_strike(game_state) {
                Ok(updated_game) -> {
                  // Log StrikeUsed event first
                  let updated_game =
                    event_log.log_event(
                      state,
                      game_code,
                      updated_game,
                      protocol.StrikeUsed(updated_game.strikes),
                    )
                  // Log StrikeDiscard events for each discarded card
                  let updated_game =
                    list.fold(discards, updated_game, fn(g, discard) {
                      let #(nick, card) = discard
                      event_log.log_event(
                        state,
                        game_code,
                        g,
                        protocol.StrikeDiscard(nick, card),
                      )
                    })

                  let new_games =
                    dict.insert(state.games, game_code, updated_game)
                  let state = ServerState(..state, games: new_games)

                  // Broadcast updated game state
                  broadcast.broadcast_game_message(
                    state,
                    game_code,
                    protocol.GameStateUpdate(updated_game),
                  )

                  // Handle phase transition after strike
                  handle_post_strike(state, game_code, updated_game)
                }
                Error(err) -> {
                  io.println("[Server] Error applying strike: " <> err)
                  state
                }
              }
            }
            Error(_) -> state
          }
        }
      }
    }
    Error(_) -> state
  }
}

/// Handle phase transitions after a successful strike
pub fn handle_post_strike(
  state: ServerState,
  game_code: String,
  updated_game: protocol.Game,
) -> ServerState {
  case updated_game.phase {
    protocol.Dealing -> {
      // Round complete — deal new cards
      io.println(
        "[Server] Round complete after strike, dealing round "
        <> int.to_string(updated_game.current_round),
      )
      let dealt_game =
        game.deal_round(updated_game, fn(deck) {
          game.shuffle_deck(deck, fn(max) { int.random(max) })
        })
      // Log RoundStarted event
      let dealt_game =
        event_log.log_event(
          state,
          game_code,
          dealt_game,
          protocol.RoundStarted(dealt_game.current_round),
        )
      let new_games = dict.insert(state.games, game_code, dealt_game)
      let state = ServerState(..state, games: new_games)
      broadcast.broadcast_game_message(
        state,
        game_code,
        protocol.GameStateUpdate(dealt_game),
      )
      broadcast.broadcast_game_message(
        state,
        game_code,
        protocol.PhaseTransition(protocol.Dealing),
      )
      state
    }
    protocol.EndGame(_) as end_phase -> {
      io.println("[Server] Game won after strike!")
      broadcast.broadcast_game_message(
        state,
        game_code,
        protocol.PhaseTransition(end_phase),
      )
      state
    }
    protocol.ActivePlay -> {
      // Transition to Pause for regrouping (auto-play check happens on Pause exit)
      io.println("[Server] Strike used, transitioning to Pause")
      let paused_game =
        updated_game
        |> game.transition_phase(protocol.Pause)
        |> game.reset_ready_states
      let new_games = dict.insert(state.games, game_code, paused_game)
      let state = ServerState(..state, games: new_games)
      broadcast.broadcast_game_message(
        state,
        game_code,
        protocol.GameStateUpdate(paused_game),
      )
      broadcast.broadcast_game_message(
        state,
        game_code,
        protocol.PhaseTransition(protocol.Pause),
      )
      state
    }
    _ -> state
  }
}
