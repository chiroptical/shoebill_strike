import game
import game_server/broadcast
import game_server/countdown
import game_server/event_log
import game_server/state.{type ServerState, ServerState}
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import protocol/types as protocol

/// Handle ToggleReadyInGame message
pub fn handle_toggle_ready_in_game(
  state: ServerState,
  user_id: String,
) -> ServerState {
  io.println("[Server] ToggleReadyInGame received from user " <> user_id)
  case dict.get(state.connections, user_id) {
    Ok(conn_info) ->
      case conn_info.game_code {
        Some(code) -> {
          io.println("[Server] User is in game: " <> code)
          case dict.get(state.games, code) {
            Ok(game_state) -> {
              io.println(
                "[Server] Found game with "
                <> int.to_string(list.length(game_state.players))
                <> " players",
              )
              case game.toggle_ready_in_game(game_state, user_id) {
                Ok(updated_game) -> {
                  io.println("[Server] Toggle ready successful")
                  let new_games = dict.insert(state.games, code, updated_game)
                  let state = ServerState(..state, games: new_games)

                  // Broadcast updated game state
                  io.println("[Server] Broadcasting updated game state")
                  broadcast.broadcast_game_message(
                    state,
                    code,
                    protocol.GameStateUpdate(updated_game),
                  )

                  // Check if all players are ready to start countdown or transition
                  case
                    game.all_players_ready_in_game(updated_game),
                    updated_game.phase
                  {
                    True, protocol.Dealing -> {
                      io.println(
                        "[Server] All players ready, starting countdown for game "
                        <> code,
                      )
                      countdown.start_countdown(state, code)
                    }
                    True, protocol.Pause -> {
                      // Check pause exit action BEFORE any transition
                      case game.get_pause_exit_action(updated_game) {
                        game.AutoPlayThenDeal(user_id, nickname, cards) -> {
                          // Single player has cards - apply auto-play and go to Dealing
                          io.println(
                            "[Server] Single player with cards in Pause, auto-playing for "
                            <> nickname,
                          )
                          let #(state, auto_game) =
                            perform_auto_play(
                              state,
                              code,
                              updated_game,
                              user_id,
                              nickname,
                              cards,
                            )
                          // Handle resulting phase
                          case auto_game.phase {
                            protocol.Dealing -> {
                              io.println(
                                "[Server] Auto-play completed round, dealing round "
                                <> int.to_string(auto_game.current_round),
                              )
                              let dealt_game =
                                game.deal_round(auto_game, fn(deck) {
                                  game.shuffle_deck(deck, fn(max) {
                                    int.random(max)
                                  })
                                })
                              let dealt_game =
                                event_log.log_event(
                                  state,
                                  code,
                                  dealt_game,
                                  protocol.RoundStarted(
                                    dealt_game.current_round,
                                  ),
                                )
                              let new_games =
                                dict.insert(state.games, code, dealt_game)
                              let state = ServerState(..state, games: new_games)
                              broadcast.broadcast_game_message(
                                state,
                                code,
                                protocol.GameStateUpdate(dealt_game),
                              )
                              broadcast.broadcast_game_message(
                                state,
                                code,
                                protocol.PhaseTransition(protocol.Dealing),
                              )
                              state
                            }
                            protocol.EndGame(_) as end_phase -> {
                              io.println(
                                "[Server] Auto-play after pause won the game!",
                              )
                              broadcast.broadcast_game_message(
                                state,
                                code,
                                protocol.PhaseTransition(end_phase),
                              )
                              state
                            }
                            _ -> state
                          }
                        }
                        game.CountdownThenActivePlay -> {
                          // Multiple players have cards - start countdown
                          io.println(
                            "[Server] All players ready in Pause, starting countdown for game "
                            <> code,
                          )
                          // Clear last_mistake before countdown
                          let cleared_game =
                            protocol.Game(..updated_game, last_mistake: None)
                          let new_games =
                            dict.insert(state.games, code, cleared_game)
                          let state = ServerState(..state, games: new_games)
                          broadcast.broadcast_game_message(
                            state,
                            code,
                            protocol.GameStateUpdate(cleared_game),
                          )
                          countdown.start_countdown(state, code)
                        }
                      }
                    }
                    _, _ -> {
                      io.println(
                        "[Server] Not all players ready yet or not in countdown phase",
                      )
                      state
                    }
                  }
                }
                Error(err) -> {
                  io.println("[Server] Toggle ready failed: " <> err)
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
              io.println("[Server] Game not found: " <> code)
              broadcast.send_message(
                state,
                user_id,
                protocol.ServerError("Game not found"),
              )
              state
            }
          }
        }
        None -> {
          io.println("[Server] User not in a game")
          broadcast.send_message(
            state,
            user_id,
            protocol.ServerError("Not in a game"),
          )
          state
        }
      }
    Error(_) -> {
      io.println("[Server] Connection not found for user: " <> user_id)
      state
    }
  }
}

/// Handle PlayCard message
pub fn handle_play_card(state: ServerState, user_id: String) -> ServerState {
  io.println("[Server] PlayCard received from user " <> user_id)
  case dict.get(state.connections, user_id) {
    Ok(conn_info) ->
      case conn_info.game_code {
        Some(code) ->
          case dict.get(state.games, code) {
            Ok(game_state) -> {
              // Get player info before playing (hand is sorted, first card will be played)
              let player_info =
                game_state.players
                |> list.find(fn(p) { p.user_id == user_id })
              let player_nickname =
                player_info
                |> result.map(fn(p) { p.nickname })
                |> result.unwrap("Unknown")
              // Get the card that will be played (lowest card in hand)
              let played_card =
                player_info
                |> result.map(fn(p) { p.hand })
                |> result.unwrap([])
                |> list.first
                |> result.unwrap(0)

              case game.play_card(game_state, user_id) {
                Ok(updated_game) -> {
                  io.println("[Server] Card played successfully")

                  // Log CardPlayed event
                  let updated_game =
                    event_log.log_event(
                      state,
                      code,
                      updated_game,
                      protocol.CardPlayed(player_nickname, played_card, False),
                    )

                  // Log mistake events if there was a mistake
                  let updated_game = case updated_game.last_mistake {
                    Some(mistake_info) -> {
                      // Log MistakeDiscard for each discarded card
                      let game_with_discards =
                        list.fold(
                          mistake_info.mistake_cards,
                          updated_game,
                          fn(g, card_info) {
                            let #(nick, card) = card_info
                            event_log.log_event(
                              state,
                              code,
                              g,
                              protocol.MistakeDiscard(nick, card),
                            )
                          },
                        )
                      // Log LifeLost
                      event_log.log_event(
                        state,
                        code,
                        game_with_discards,
                        protocol.LifeLost(updated_game.lives),
                      )
                    }
                    None -> updated_game
                  }

                  let new_games = dict.insert(state.games, code, updated_game)
                  let state = ServerState(..state, games: new_games)

                  // Broadcast updated game state
                  broadcast.broadcast_game_message(
                    state,
                    code,
                    protocol.GameStateUpdate(updated_game),
                  )

                  // Handle phase transitions
                  case updated_game.phase {
                    protocol.Dealing -> {
                      // Round complete — deal new cards
                      io.println(
                        "[Server] Round complete, dealing round "
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
                          code,
                          dealt_game,
                          protocol.RoundStarted(dealt_game.current_round),
                        )
                      let new_games = dict.insert(state.games, code, dealt_game)
                      let state = ServerState(..state, games: new_games)
                      broadcast.broadcast_game_message(
                        state,
                        code,
                        protocol.GameStateUpdate(dealt_game),
                      )
                      broadcast.broadcast_game_message(
                        state,
                        code,
                        protocol.PhaseTransition(protocol.Dealing),
                      )
                      state
                    }
                    protocol.Pause -> {
                      io.println("[Server] Mistake! Transitioning to Pause")
                      broadcast.broadcast_game_message(
                        state,
                        code,
                        protocol.PhaseTransition(protocol.Pause),
                      )
                      state
                    }
                    protocol.EndGame(_) as end_phase -> {
                      io.println("[Server] Game over!")
                      broadcast.broadcast_game_message(
                        state,
                        code,
                        protocol.PhaseTransition(end_phase),
                      )
                      state
                    }
                    protocol.ActivePlay -> {
                      // Check for auto-play: if only one player has cards
                      let #(state, auto_game) =
                        check_and_perform_auto_play(state, code, updated_game)
                      // Handle any phase transition from auto-play
                      case auto_game.phase {
                        protocol.Dealing -> {
                          // Auto-play completed round - deal new cards
                          io.println(
                            "[Server] Auto-play completed round, dealing round "
                            <> int.to_string(auto_game.current_round),
                          )
                          let dealt_game =
                            game.deal_round(auto_game, fn(deck) {
                              game.shuffle_deck(deck, fn(max) {
                                int.random(max)
                              })
                            })
                          let dealt_game =
                            event_log.log_event(
                              state,
                              code,
                              dealt_game,
                              protocol.RoundStarted(dealt_game.current_round),
                            )
                          let new_games =
                            dict.insert(state.games, code, dealt_game)
                          let state = ServerState(..state, games: new_games)
                          broadcast.broadcast_game_message(
                            state,
                            code,
                            protocol.GameStateUpdate(dealt_game),
                          )
                          broadcast.broadcast_game_message(
                            state,
                            code,
                            protocol.PhaseTransition(protocol.Dealing),
                          )
                          state
                        }
                        protocol.EndGame(_) as end_phase -> {
                          io.println("[Server] Auto-play won the game!")
                          broadcast.broadcast_game_message(
                            state,
                            code,
                            protocol.PhaseTransition(end_phase),
                          )
                          state
                        }
                        _ -> state
                      }
                    }
                    protocol.Strike -> state
                    protocol.AbandonVote -> state
                  }
                }
                Error(err) -> {
                  io.println("[Server] PlayCard failed: " <> err)
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

/// Check and perform auto-play if applicable
/// Auto-play triggers when exactly one player has cards and all others have 0
pub fn check_and_perform_auto_play(
  state: ServerState,
  game_code: String,
  g: protocol.Game,
) -> #(ServerState, protocol.Game) {
  case g.phase {
    protocol.ActivePlay ->
      case game.get_auto_play_candidate(g) {
        option.None -> #(state, g)
        option.Some(#(user_id, nickname, cards)) -> {
          io.println(
            "[Server] Auto-playing "
            <> int.to_string(list.length(cards))
            <> " cards for "
            <> nickname,
          )
          perform_auto_play(state, game_code, g, user_id, nickname, cards)
        }
      }
    _ -> #(state, g)
  }
}

/// Perform auto-play of all cards for a single player
pub fn perform_auto_play(
  state: ServerState,
  game_code: String,
  g: protocol.Game,
  user_id: String,
  nickname: String,
  cards: List(protocol.Card),
) -> #(ServerState, protocol.Game) {
  // Log each card as auto-played
  let game_with_logs =
    list.fold(cards, g, fn(acc, card) {
      event_log.log_event(
        state,
        game_code,
        acc,
        protocol.CardPlayed(nickname, card, True),
      )
    })

  // Apply the game state change (move all cards to pile, handle round completion)
  let final_game = game.apply_auto_play(game_with_logs, user_id)

  // Update state with final game
  let new_games = dict.insert(state.games, game_code, final_game)
  let final_state = ServerState(..state, games: new_games)

  // Broadcast final game state
  broadcast.broadcast_game_message(
    final_state,
    game_code,
    protocol.GameStateUpdate(final_game),
  )

  #(final_state, final_game)
}
