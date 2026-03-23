import client/msg.{
  type Msg, InitiateAbandonVoteClicked, ToggleReadyInGameClicked,
}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import icons
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import protocol/types as protocol

pub fn view_ready_button_in_game(is_ready: Bool) -> Element(Msg) {
  let #(button_text, button_class) = case is_ready {
    True -> #("Not Ready", "btn-ready")
    False -> #("Ready", "btn-primary")
  }

  html.div([attribute.class("w-full max-w-md")], [
    html.button(
      [attribute.class(button_class), event.on_click(ToggleReadyInGameClicked)],
      [element.text(button_text)],
    ),
  ])
}

pub fn view_ready_button_inline(is_ready: Bool) -> Element(Msg) {
  let #(button_text, button_class) = case is_ready {
    True -> #("Not Ready", "btn-ready flex-1")
    False -> #("Ready", "btn-primary flex-1")
  }

  html.button(
    [attribute.class(button_class), event.on_click(ToggleReadyInGameClicked)],
    [element.text(button_text)],
  )
}

pub fn view_abandon_button() -> Element(Msg) {
  html.button(
    [
      attribute.class("btn-abandon flex-1"),
      event.on_click(InitiateAbandonVoteClicked),
    ],
    [element.text("Abandon")],
  )
}

pub fn view_vote_section(
  title: String,
  icon: Element(Msg),
  vote_status: Option(#(List(#(String, Bool)), List(String), Int)),
  players: List(protocol.GamePlayer),
  user_id: String,
  on_approve: Msg,
  on_reject: Msg,
) -> Element(Msg) {
  html.div([attribute.class("bg-gray-800 rounded-lg p-3 shadow-lg w-full")], [
    // Title row with timer inline
    case vote_status {
      Some(#(votes, pending, seconds_remaining)) -> {
        let has_voted = list.any(votes, fn(v) { v.0 == user_id })
        let is_pending = list.contains(pending, user_id)

        // Timer color and animation based on time remaining
        let timer_class = case seconds_remaining {
          s if s <= 3 -> "text-xl font-bold text-red-400 animate-urgent"
          s if s <= 5 -> "text-xl font-bold text-yellow-400"
          _ -> "text-xl font-bold text-gray-100"
        }

        html.div([attribute.class("space-y-2")], [
          // Title with timer inline
          html.div([attribute.class("flex justify-between items-center mb-1")], [
            html.div([attribute.class("flex items-center gap-1")], [
              icon,
              html.span(
                [attribute.class("text-sm font-semibold text-gray-100")],
                [element.text(title)],
              ),
            ]),
            html.span([attribute.class(timer_class)], [
              element.text(int.to_string(seconds_remaining) <> "s"),
            ]),
          ]),
          // Vote status list
          html.div(
            [attribute.class("space-y-1")],
            list.map(players, fn(p) {
              let status_element = case
                list.find(votes, fn(v) { v.0 == p.user_id })
              {
                Ok(#(_, True)) -> icons.check_icon("w-4 h-4 text-green-400")
                Ok(#(_, False)) -> icons.cancel_icon("w-4 h-4 text-red-400")
                Error(_) ->
                  html.span([attribute.class("text-gray-400")], [
                    element.text("..."),
                  ])
              }
              html.div(
                [
                  attribute.class(
                    "flex justify-between items-center px-2 py-1 rounded bg-gray-700/50 text-sm",
                  ),
                ],
                [
                  html.span([attribute.class("text-gray-100")], [
                    element.text(p.nickname),
                  ]),
                  status_element,
                ],
              )
            }),
          ),
          // Buttons or waiting message
          case is_pending {
            True ->
              html.div([attribute.class("flex gap-2 mt-1")], [
                html.button(
                  [
                    attribute.class("btn-approve btn-small flex-1"),
                    event.on_click(on_approve),
                  ],
                  [element.text("Approve")],
                ),
                html.button(
                  [
                    attribute.class("btn-reject btn-small flex-1"),
                    event.on_click(on_reject),
                  ],
                  [element.text("Reject")],
                ),
              ])
            False ->
              case has_voted {
                True ->
                  html.div(
                    [attribute.class("text-gray-400 text-center text-sm mt-1")],
                    [element.text("Vote received!")],
                  )
                False -> element.none()
              }
          },
        ])
      }
      None ->
        html.div([attribute.class("text-center")], [
          html.div(
            [attribute.class("flex items-center justify-center gap-1 mb-2")],
            [
              icon,
              html.span(
                [attribute.class("text-sm font-semibold text-gray-100")],
                [
                  element.text(title),
                ],
              ),
            ],
          ),
          html.div([attribute.class("text-gray-400 text-sm")], [
            element.text("Waiting for vote to start..."),
          ]),
        ])
    },
  ])
}
