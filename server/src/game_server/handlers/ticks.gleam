import game
import game_server/broadcast
import game_server/event_log
import game_server/handlers/abandon_vote
import game_server/handlers/game_play
import game_server/handlers/strike_vote
import game_server/state.{
  type ServerState, CountdownTickMsg, CountdownTimer, ServerState, VoteState,
}
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import protocol/types as protocol

/// Handle countdown tick message
pub fn handle_countdown_tick(
  state: ServerState,
  game_code: String,
  seconds: Int,
) -> actor.Next(ServerState, state.ServerMsg) {
  io.println(
    "[Server] Countdown tick for game "
    <> game_code
    <> ": "
    <> int.to_string(seconds),
  )

  // Broadcast the countdown tick to all players in the game
  broadcast.broadcast_game_message(
    state,
    game_code,
    protocol.CountdownTick(seconds),
  )

  case seconds {
    0 -> {
      // Transition game to protocol.ActivePlay
      let state = case dict.get(state.games, game_code) {
        Ok(game_state) -> {
          let updated_game =
            game.transition_phase(game_state, protocol.ActivePlay)
            |> fn(g) { protocol.Game(..g, last_mistake: None) }
          let new_games = dict.insert(state.games, game_code, updated_game)
          let state = ServerState(..state, games: new_games)

          // Broadcast phase transition
          broadcast.broadcast_game_message(
            state,
            game_code,
            protocol.PhaseTransition(protocol.ActivePlay),
          )

          // Remove countdown timer
          let new_timers = dict.delete(state.countdown_timers, game_code)
          let state = ServerState(..state, countdown_timers: new_timers)

          // Check for auto-play: if only one player has cards after a mistake
          let #(state, auto_game) =
            game_play.check_and_perform_auto_play(
              state,
              game_code,
              updated_game,
            )
          // Handle any phase transition from auto-play
          case auto_game.phase {
            protocol.Dealing -> {
              // Auto-play completed round - deal new cards
              io.println(
                "[Server] Auto-play completed round after pause, dealing round "
                <> int.to_string(auto_game.current_round),
              )
              let dealt_game =
                game.deal_round(auto_game, fn(deck) {
                  game.shuffle_deck(deck, fn(max) { int.random(max) })
                })
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
              io.println("[Server] Auto-play won the game after pause!")
              broadcast.broadcast_game_message(
                state,
                game_code,
                protocol.PhaseTransition(end_phase),
              )
              state
            }
            _ -> state
          }
        }
        Error(_) -> state
      }
      actor.continue(state)
    }
    n -> {
      // Schedule next tick using send_after
      case state.self_subject {
        Some(self) -> {
          process.send_after(self, 1000, CountdownTickMsg(game_code, n - 1))
          Nil
        }
        None -> Nil
      }

      // Update countdown timer state
      let timer = CountdownTimer(game_code: game_code, seconds_remaining: n)
      let new_timers = dict.insert(state.countdown_timers, game_code, timer)
      actor.continue(ServerState(..state, countdown_timers: new_timers))
    }
  }
}

/// Handle vote tick message for strike votes
pub fn handle_vote_tick(
  state: ServerState,
  game_code: String,
  seconds: Int,
) -> actor.Next(ServerState, state.ServerMsg) {
  // Only process if vote is still active
  case dict.get(state.vote_states, game_code) {
    Ok(vote_state) -> {
      // Broadcast current vote state to all players
      let votes_list = vote_state.votes |> dict.to_list
      broadcast.broadcast_game_message(
        state,
        game_code,
        protocol.StrikeVoteUpdate(votes_list, vote_state.pending, seconds),
      )

      case seconds {
        0 -> {
          // Auto-approve all pending voters
          let final_votes =
            list.fold(vote_state.pending, vote_state.votes, fn(acc, pid) {
              dict.insert(acc, pid, True)
            })
          let updated_vote =
            VoteState(..vote_state, votes: final_votes, pending: [])
          let state =
            ServerState(
              ..state,
              vote_states: dict.insert(
                state.vote_states,
                game_code,
                updated_vote,
              ),
            )
          // Broadcast final vote state showing all auto-approved
          broadcast.broadcast_game_message(
            state,
            game_code,
            protocol.StrikeVoteUpdate(dict.to_list(final_votes), [], 0),
          )
          let state = strike_vote.resolve_strike_vote(state, game_code)
          actor.continue(state)
        }
        n -> {
          // Schedule next tick
          case state.self_subject {
            Some(self) -> {
              process.send_after(
                self,
                1000,
                state.VoteTickMsg(game_code, n - 1),
              )
              Nil
            }
            None -> Nil
          }
          let new_timers = dict.insert(state.vote_timers, game_code, n)
          actor.continue(ServerState(..state, vote_timers: new_timers))
        }
      }
    }
    // Vote was already resolved (early rejection or all voted), ignore
    Error(_) -> actor.continue(state)
  }
}

/// Handle abandon vote tick message
pub fn handle_abandon_vote_tick(
  state: ServerState,
  game_code: String,
  seconds: Int,
) -> actor.Next(ServerState, state.ServerMsg) {
  // Only process if vote is still active and game is in protocol.AbandonVote phase
  case dict.get(state.vote_states, game_code) {
    Ok(vote_state) -> {
      case dict.get(state.games, game_code) {
        Ok(game_state) ->
          case game_state.phase {
            protocol.AbandonVote -> {
              // Broadcast current vote state to all players
              let votes_list = vote_state.votes |> dict.to_list
              broadcast.broadcast_game_message(
                state,
                game_code,
                protocol.AbandonVoteUpdate(
                  votes_list,
                  vote_state.pending,
                  seconds,
                ),
              )

              case seconds {
                0 -> {
                  // Auto-approve all pending voters
                  let final_votes =
                    list.fold(
                      vote_state.pending,
                      vote_state.votes,
                      fn(acc, pid) { dict.insert(acc, pid, True) },
                    )
                  let updated_vote =
                    VoteState(..vote_state, votes: final_votes, pending: [])
                  let state =
                    ServerState(
                      ..state,
                      vote_states: dict.insert(
                        state.vote_states,
                        game_code,
                        updated_vote,
                      ),
                    )
                  // Broadcast final vote state showing all auto-approved
                  broadcast.broadcast_game_message(
                    state,
                    game_code,
                    protocol.AbandonVoteUpdate(dict.to_list(final_votes), [], 0),
                  )
                  let state =
                    abandon_vote.resolve_abandon_vote(state, game_code)
                  actor.continue(state)
                }
                n -> {
                  // Schedule next tick
                  case state.self_subject {
                    Some(self) -> {
                      process.send_after(
                        self,
                        1000,
                        state.AbandonVoteTickMsg(game_code, n - 1),
                      )
                      Nil
                    }
                    None -> Nil
                  }
                  let new_timers = dict.insert(state.vote_timers, game_code, n)
                  actor.continue(ServerState(..state, vote_timers: new_timers))
                }
              }
            }
            _ -> actor.continue(state)
          }
        Error(_) -> actor.continue(state)
      }
    }
    // Vote was already resolved, ignore
    Error(_) -> actor.continue(state)
  }
}
