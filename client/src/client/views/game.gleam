import client/model.{type Model}
import client/msg.{
  type Msg, InitiateAbandonVoteClicked, InitiateStrikeClicked, PlayCardClicked,
}
import client/views/components/actions
import client/views/components/cards
import client/views/components/feedback
import client/views/components/players
import client/views/components/stats
import client/views/game_log
import client/views/game_phases
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import protocol/types as protocol

pub fn view_game_screen(model: Model) -> Element(Msg) {
  case model.current_game {
    Some(game) -> {
      let user_id = model.user_id
      let phase_view = case game.phase {
        protocol.Dealing -> view_dealing_phase(model, game, user_id)
        protocol.ActivePlay -> view_active_play(model)
        protocol.Pause -> view_pause_phase(model, game, user_id)
        protocol.Strike -> game_phases.view_strike_phase(model, game, user_id)
        protocol.AbandonVote ->
          game_phases.view_abandon_vote_phase(model, game, user_id)
        protocol.EndGame(outcome) ->
          game_phases.view_end_game(game, user_id, outcome)
      }
      // Wrapper provides bottom padding for fixed mobile game log
      html.div([attribute.class("game-screen-wrapper")], [phase_view])
    }
    None ->
      html.div([attribute.class("screen active")], [
        element.text("Loading game..."),
      ])
  }
}

pub fn view_dealing_phase(
  model: Model,
  game: protocol.Game,
  user_id: String,
) -> Element(Msg) {
  let my_player =
    game.players
    |> list.find(fn(p) { p.user_id == user_id })

  html.div(
    [
      attribute.class(
        "min-h-screen pt-5 pb-3 px-2 lg:pt-3 lg:px-4 lg:pb-24 flex flex-col items-center lg:justify-center",
      ),
    ],
    [
      // Content wrapper with relative positioning for sidebars
      html.div([attribute.class("relative w-full max-w-md lg:w-[34rem]")], [
        // Main column: Header + Other Players + Pile/Hand + Buttons
        html.div([attribute.class("flex flex-col gap-3 lg:gap-4")], [
          players.view_game_header(game),
          players.view_other_players(game, user_id, protocol.Dealing),
          case my_player {
            Ok(player) -> cards.view_pile_and_hand(None, player.hand)
            Error(_) -> element.none()
          },
          html.div([attribute.class("flex gap-2")], [
            case model.countdown {
              Some(_) -> element.none()
              None ->
                case my_player {
                  Ok(player) ->
                    actions.view_ready_button_inline(player.is_ready)
                  Error(_) -> element.none()
                }
            },
            actions.view_abandon_button(),
          ]),
        ]),
        // Reward guide: fixed toggle on mobile, absolute sidebar on lg+ (LEFT)
        stats.view_reward_guide(game, model.is_reward_guide_open),
        // Game log: fixed on mobile, absolute sidebar on lg+ (RIGHT)
        game_log.view_game_log(game),
      ]),
      case model.countdown {
        Some(seconds) -> feedback.view_countdown(seconds)
        None -> element.none()
      },
    ],
  )
}

pub fn view_pause_phase(
  model: Model,
  game: protocol.Game,
  user_id: String,
) -> Element(Msg) {
  let my_player =
    game.players
    |> list.find(fn(p) { p.user_id == user_id })

  html.div(
    [
      attribute.class(
        "min-h-screen pt-5 pb-3 px-2 lg:pt-3 lg:px-4 lg:pb-24 flex flex-col items-center lg:justify-center",
      ),
    ],
    [
      // Content wrapper with relative positioning for sidebars
      html.div([attribute.class("relative w-full max-w-md lg:w-[34rem]")], [
        // Main column: Header + Other Players + Pile/Hand + Buttons + Mistake Info
        html.div([attribute.class("flex flex-col gap-3 lg:gap-4")], [
          players.view_game_header(game),
          players.view_other_players(game, user_id, protocol.Pause),
          case my_player {
            Ok(player) ->
              cards.view_pile_and_hand(Some(game.played_cards), player.hand)
            Error(_) -> element.none()
          },
          html.div([attribute.class("flex gap-2")], [
            case model.countdown {
              Some(_) -> element.none()
              None ->
                case my_player {
                  Ok(player) ->
                    case player.hand {
                      [] ->
                        // Auto-ready: player has no cards, show disabled indicator
                        html.button(
                          [
                            attribute.class(
                              "btn bg-gray-600 text-gray-400 cursor-not-allowed flex-1",
                            ),
                            attribute.disabled(True),
                          ],
                          [element.text("Ready")],
                        )
                      _ -> actions.view_ready_button_inline(player.is_ready)
                    }
                  Error(_) -> element.none()
                }
            },
            actions.view_abandon_button(),
          ]),
          case game.last_mistake {
            Some(info) -> feedback.view_mistake_info(info)
            None -> element.none()
          },
        ]),
        // Reward guide: fixed toggle on mobile, absolute sidebar on lg+ (LEFT)
        stats.view_reward_guide(game, model.is_reward_guide_open),
        // Game log: fixed on mobile, absolute sidebar on lg+ (RIGHT)
        game_log.view_game_log(game),
      ]),
      case model.countdown {
        Some(seconds) -> feedback.view_countdown(seconds)
        None -> element.none()
      },
    ],
  )
}

pub fn view_active_play(model: Model) -> Element(Msg) {
  case model.current_game {
    Some(game) -> {
      let user_id = model.user_id
      let my_player =
        game.players
        |> list.find(fn(p) { p.user_id == user_id })

      let has_cards = case my_player {
        Ok(player) -> player.hand != []
        Error(_) -> False
      }

      let play_button_class = case has_cards {
        True -> "btn-primary"
        False -> "btn bg-gray-600 text-gray-400 cursor-not-allowed"
      }

      html.div(
        [
          attribute.class(
            "min-h-screen pt-5 pb-3 px-2 lg:pt-3 lg:px-4 lg:pb-24 flex flex-col items-center lg:justify-center",
          ),
        ],
        [
          // Content wrapper with relative positioning for sidebars
          html.div([attribute.class("relative w-full max-w-md lg:w-[34rem]")], [
            // Main column: Header + Other Players + Pile/Hand + Buttons
            html.div([attribute.class("flex flex-col gap-3 lg:gap-4")], [
              players.view_game_header(game),
              players.view_other_players(game, user_id, protocol.ActivePlay),
              case my_player {
                Ok(player) ->
                  cards.view_pile_and_hand(Some(game.played_cards), player.hand)
                Error(_) ->
                  cards.view_pile_and_hand(Some(game.played_cards), [])
              },
              // Buttons: Play on top, Star + Abandon below
              html.div([attribute.class("space-y-2")], [
                html.button(
                  [
                    attribute.class(play_button_class),
                    attribute.disabled(!has_cards),
                    event.on_click(PlayCardClicked),
                  ],
                  [element.text("Play")],
                ),
                html.div([attribute.class("flex gap-2")], [
                  case game.strikes > 0 {
                    True ->
                      html.button(
                        [
                          attribute.class("btn-strike flex-1"),
                          event.on_click(InitiateStrikeClicked),
                        ],
                        [element.text("Strike")],
                      )
                    False -> element.none()
                  },
                  html.button(
                    [
                      attribute.class("btn-abandon flex-1"),
                      event.on_click(InitiateAbandonVoteClicked),
                    ],
                    [element.text("Abandon")],
                  ),
                ]),
              ]),
            ]),
            // Reward guide: fixed toggle on mobile, absolute sidebar on lg+ (LEFT)
            stats.view_reward_guide(game, model.is_reward_guide_open),
            // Game log: fixed on mobile, absolute sidebar on lg+ (RIGHT)
            game_log.view_game_log(game),
          ]),
        ],
      )
    }
    None ->
      html.div(
        [
          attribute.class(
            "min-h-screen p-4 flex flex-col items-center justify-center",
          ),
        ],
        [
          html.p([attribute.class("text-gray-400")], [
            element.text("Loading game..."),
          ]),
        ],
      )
  }
}
