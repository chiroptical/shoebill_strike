import client/model.{type Model}
import client/msg.{
  type Msg, CastAbandonVoteClicked, CastStrikeVoteClicked, LeaveGameClicked,
  RestartGameClicked,
}
import client/views/components/actions
import client/views/components/cards
import client/views/components/players
import client/views/components/stats
import client/views/game_log
import gleam/int
import gleam/list
import gleam/option.{Some}
import icons
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import protocol/types as protocol

pub fn view_strike_phase(
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
        // Main column: Header + Other Players + Vote Section + Pile/Hand
        html.div([attribute.class("flex flex-col gap-3 lg:gap-4")], [
          players.view_game_header(game),
          players.view_other_players(game, user_id, protocol.Strike),
          actions.view_vote_section(
            "Strike Vote",
            icons.shoebill_icon("w-5 h-5 text-[#a7aec0]"),
            model.vote_status,
            game.players,
            user_id,
            CastStrikeVoteClicked(True),
            CastStrikeVoteClicked(False),
          ),
          case my_player {
            Ok(player) ->
              cards.view_pile_and_hand(Some(game.played_cards), player.hand)
            Error(_) -> element.none()
          },
        ]),
        // Reward guide: fixed toggle on mobile, absolute sidebar on lg+ (LEFT)
        stats.view_reward_guide(game, model.is_reward_guide_open),
        // Game log: fixed on mobile, absolute sidebar on lg+ (RIGHT)
        game_log.view_game_log(game),
      ]),
    ],
  )
}

pub fn view_abandon_vote_phase(
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
        // Main column: Header + Other Players + Vote Section + Pile/Hand
        html.div([attribute.class("flex flex-col gap-3 lg:gap-4")], [
          players.view_game_header(game),
          players.view_other_players(game, user_id, protocol.AbandonVote),
          actions.view_vote_section(
            "Abandon Game Vote",
            icons.exit_icon("w-5 h-5 text-gray-400"),
            model.abandon_vote_status,
            game.players,
            user_id,
            CastAbandonVoteClicked(True),
            CastAbandonVoteClicked(False),
          ),
          case my_player {
            Ok(player) ->
              cards.view_pile_and_hand(Some(game.played_cards), player.hand)
            Error(_) -> element.none()
          },
        ]),
        // Reward guide: fixed toggle on mobile, absolute sidebar on lg+ (LEFT)
        stats.view_reward_guide(game, model.is_reward_guide_open),
        // Game log: fixed on mobile, absolute sidebar on lg+ (RIGHT)
        game_log.view_game_log(game),
      ]),
    ],
  )
}

pub fn view_end_game_players(
  game: protocol.Game,
  extra_class: String,
) -> Element(Msg) {
  let class = case extra_class {
    "" -> "bg-gray-800 rounded-lg p-4 shadow-lg"
    _ -> "bg-gray-800 rounded-lg p-4 shadow-lg " <> extra_class
  }
  html.div([attribute.class(class)], [
    html.div([attribute.class("text-gray-400 text-sm mb-3")], [
      element.text("Players"),
    ]),
    html.div(
      [attribute.class("space-y-2")],
      list.map(game.players, fn(p) {
        let host_badge = case p.user_id == game.host_user_id {
          True -> " (Host)"
          False -> ""
        }
        let status_element = case p.is_connected, p.is_ready {
          False, _ ->
            html.span([attribute.class("text-red-400")], [
              element.text("Offline"),
            ])
          True, True ->
            html.span(
              [attribute.class("text-green-400 flex items-center gap-1")],
              [icons.check_icon("w-3 h-3"), element.text("Ready")],
            )
          True, False ->
            html.span([attribute.class("text-gray-400")], [
              element.text("Waiting"),
            ])
        }
        let row_opacity = case p.is_connected {
          True -> ""
          False -> " opacity-50"
        }
        html.div(
          [
            attribute.class(
              "flex justify-between items-center p-2 rounded-md bg-gray-700/50"
              <> row_opacity,
            ),
          ],
          [
            html.span([attribute.class("text-gray-100")], [
              element.text(p.nickname <> host_badge),
            ]),
            status_element,
          ],
        )
      }),
    ),
  ])
}

pub fn view_end_game(
  game: protocol.Game,
  user_id: String,
  outcome: protocol.GameOutcome,
) -> Element(Msg) {
  let my_player = list.find(game.players, fn(p) { p.user_id == user_id })
  let all_ready =
    game.players != [] && list.all(game.players, fn(p) { p.is_ready })
  let is_host = game.host_user_id == user_id
  let player_count = list.length(game.players)

  let #(outcome_text, outcome_icon, outcome_color) = case outcome {
    protocol.Win -> #(
      "Victory!",
      icons.trophy_icon("w-8 h-8 lg:w-10 lg:h-10 text-emerald-400"),
      "text-emerald-400",
    )
    protocol.Loss -> #(
      "Defeat",
      icons.skull_icon("w-8 h-8 lg:w-10 lg:h-10 text-red-400"),
      "text-red-400",
    )
    protocol.Abandoned -> #(
      "Game Abandoned",
      icons.exit_icon("w-8 h-8 lg:w-10 lg:h-10 text-gray-400"),
      "text-gray-400",
    )
  }

  let rounds_completed = case outcome {
    protocol.Win -> game.current_round
    _ -> game.current_round - 1
  }

  html.div(
    [
      attribute.class(
        "min-h-screen p-4 flex flex-col items-center gap-4 lg:justify-center",
      ),
    ],
    [
      // Outcome display - always centered at top
      html.div(
        [
          attribute.class(
            "text-center py-2 lg:py-4 flex items-center justify-center gap-2",
          ),
        ],
        [
          html.h2(
            [
              attribute.class(
                "text-2xl lg:text-3xl font-bold " <> outcome_color,
              ),
            ],
            [element.text(outcome_text)],
          ),
          outcome_icon,
        ],
      ),
      // Main content - responsive two-column on md+
      html.div(
        [
          attribute.class(
            "w-full max-w-md md:max-w-3xl lg:max-w-4xl flex flex-col md:flex-row md:gap-6 lg:gap-8",
          ),
        ],
        [
          // Left column: Stats + action buttons
          html.div([attribute.class("flex-1 flex flex-col gap-4")], [
            // Stats card
            html.div([attribute.class("bg-gray-800 rounded-lg p-4 shadow-lg")], [
              html.div([attribute.class("text-gray-400 text-sm mb-3")], [
                element.text("Final Stats"),
              ]),
              html.div([attribute.class("grid grid-cols-2 gap-3")], [
                stats.view_stat(
                  "Round",
                  int.to_string(rounds_completed)
                    <> "/"
                    <> int.to_string(game.total_rounds),
                ),
                stats.view_stat_with_icon(
                  icons.heart_icon("w-3 h-3 text-red-400"),
                  "Lives",
                  int.to_string(game.lives),
                ),
                stats.view_stat_with_icon(
                  icons.shoebill_icon("w-3 h-3 text-[#a7aec0]"),
                  "Strikes",
                  int.to_string(game.strikes),
                ),
                stats.view_stat("Games", int.to_string(game.games_played + 1)),
              ]),
            ]),
            // Player list (mobile only - shown between stats and buttons)
            view_end_game_players(game, "md:hidden"),
            // Action buttons - positioned consistently with Lobby/Game Ready button
            html.div([attribute.class("space-y-3")], [
              case my_player {
                Ok(player) -> actions.view_ready_button_in_game(player.is_ready)
                Error(_) -> element.none()
              },
              html.button(
                [
                  attribute.class("btn-secondary"),
                  event.on_click(LeaveGameClicked),
                ],
                [element.text("Leave Game")],
              ),
              case is_host {
                True -> {
                  let btn_class = case all_ready && player_count >= 2 {
                    True -> "btn-primary"
                    False -> "btn bg-gray-600 text-gray-400 cursor-not-allowed"
                  }
                  html.button(
                    [
                      attribute.class(btn_class),
                      attribute.disabled(!all_ready || player_count < 2),
                      event.on_click(RestartGameClicked),
                    ],
                    [element.text("Play Again")],
                  )
                }
                False -> element.none()
              },
            ]),
          ]),
          // Right column: Player list + game log (md+ only)
          html.div(
            [
              attribute.class(
                "flex-1 mt-4 md:mt-0 hidden md:flex flex-col gap-4",
              ),
            ],
            [
              view_end_game_players(game, ""),
              game_log.view_game_log_inline(game),
            ],
          ),
        ],
      ),
      // Mobile game log (fixed at bottom via CSS, hidden on md+)
      html.div([attribute.class("md:hidden")], [game_log.view_game_log(game)]),
    ],
  )
}
