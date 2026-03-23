import client/msg.{type Msg}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import icons
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import protocol/types as protocol

pub fn view_game_header(game: protocol.Game) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "bg-gray-800 rounded-lg px-4 py-2 lg:px-6 lg:py-3 shadow-lg w-full flex justify-between items-center",
      ),
    ],
    [
      html.div([attribute.class("text-center")], [
        html.span([attribute.class("text-gray-400 text-xs lg:text-sm")], [
          element.text("Round "),
        ]),
        html.span(
          [attribute.class("text-gray-100 text-lg lg:text-xl font-bold")],
          [
            element.text(int.to_string(game.current_round)),
          ],
        ),
      ]),
      html.div([attribute.class("text-center flex items-center gap-1")], [
        icons.heart_icon("w-4 h-4 lg:w-5 lg:h-5 text-red-400"),
        html.span(
          [attribute.class("text-gray-100 text-lg lg:text-xl font-bold")],
          [
            element.text(int.to_string(game.lives)),
          ],
        ),
      ]),
      html.div([attribute.class("text-center flex items-center gap-1")], [
        icons.shoebill_icon("w-4 h-4 lg:w-5 lg:h-5 text-[#a7aec0]"),
        html.span(
          [attribute.class("text-gray-100 text-lg lg:text-xl font-bold")],
          [
            element.text(int.to_string(game.strikes)),
          ],
        ),
      ]),
    ],
  )
}

pub fn view_other_players(
  game: protocol.Game,
  my_user_id: String,
  phase: protocol.Phase,
) -> Element(Msg) {
  let other_players =
    game.players
    |> list.filter(fn(p) { p.user_id != my_user_id })

  html.div(
    [attribute.class("bg-gray-800 rounded-lg p-3 lg:p-4 shadow-lg w-full")],
    [
      html.div([attribute.class("text-gray-400 text-xs lg:text-sm mb-2")], [
        element.text("Other Players"),
      ]),
      html.div(
        [attribute.class("other-players-grid")],
        list.map(other_players, view_other_player(_, phase)),
      ),
    ],
  )
}

pub fn view_other_player(
  player: protocol.GamePlayer,
  phase: protocol.Phase,
) -> Element(Msg) {
  let card_count = list.length(player.hand)

  let opacity_class = case player.is_connected {
    True -> ""
    False -> " opacity-50"
  }

  let offline_indicator = case player.is_connected {
    True -> element.none()
    False -> icons.unplugged_icon("w-3 h-3 text-red-400 inline ml-1")
  }

  let last_card_text = case player.last_card_played {
    Some(card) -> int.to_string(card)
    None -> "-"
  }

  // Compact view for ActivePlay - card count is the focus
  case phase {
    protocol.ActivePlay -> {
      html.div(
        [
          attribute.class("bg-gray-700/50 rounded-lg p-2" <> opacity_class),
        ],
        [
          html.div(
            [
              attribute.class(
                "text-xs text-gray-400 truncate flex items-center",
              ),
            ],
            [element.text(player.nickname), offline_indicator],
          ),
          html.div([attribute.class("flex justify-between text-xs")], [
            html.span([attribute.class("text-gray-400")], [
              element.text("Cards:"),
            ]),
            html.span([attribute.class("text-gray-100")], [
              element.text(int.to_string(card_count)),
            ]),
          ]),
          html.div([attribute.class("flex justify-between text-xs")], [
            html.span([attribute.class("text-gray-400")], [
              element.text("Last:"),
            ]),
            html.span([attribute.class("text-gray-100")], [
              element.text(last_card_text),
            ]),
          ]),
        ],
      )
    }
    _ -> {
      // Full view for other phases - includes ready status next to nickname
      let ready_indicator = case phase {
        protocol.Dealing | protocol.Pause | protocol.EndGame(_) ->
          case player.is_ready {
            True -> icons.check_icon("w-3 h-3 text-green-400 inline ml-1")
            False ->
              icons.nothing_to_say_icon("w-3 h-3 text-gray-400 inline ml-1")
          }
        _ -> element.none()
      }

      html.div(
        [
          attribute.class("bg-gray-700/50 rounded-lg p-2" <> opacity_class),
        ],
        [
          html.div(
            [
              attribute.class(
                "text-xs text-gray-400 truncate flex items-center",
              ),
            ],
            [
              element.text(player.nickname),
              offline_indicator,
              ready_indicator,
            ],
          ),
          html.div([attribute.class("flex justify-between text-xs")], [
            html.span([attribute.class("text-gray-400")], [
              element.text("Cards:"),
            ]),
            html.span([attribute.class("text-gray-100")], [
              element.text(int.to_string(card_count)),
            ]),
          ]),
          html.div([attribute.class("flex justify-between text-xs")], [
            html.span([attribute.class("text-gray-400")], [
              element.text("Last:"),
            ]),
            html.span([attribute.class("text-gray-100")], [
              element.text(last_card_text),
            ]),
          ]),
        ],
      )
    }
  }
}
