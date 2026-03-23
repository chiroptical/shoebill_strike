import client/model.{type ToastState, ToastHidden, ToastHiding, ToastShowing}
import client/msg.{type Msg}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import protocol/types as protocol

pub fn view_toast(toast: ToastState) -> Element(Msg) {
  case toast {
    ToastHidden -> element.none()
    ToastShowing(msg) | ToastHiding(msg) -> {
      let animation_class = case toast {
        ToastShowing(_) -> "animate-toast-in"
        ToastHiding(_) -> "animate-toast-out"
        ToastHidden -> ""
      }
      html.div(
        [
          attribute.class(
            "fixed bottom-6 left-1/2 bg-gray-800 text-white px-4 py-2 rounded-lg shadow-lg z-50 border border-gray-700 "
            <> animation_class,
          ),
        ],
        [element.text(msg)],
      )
    }
  }
}

pub fn view_error(error: Option(String)) -> Element(Msg) {
  case error {
    Some(message) ->
      html.div([attribute.class("error-message")], [element.text(message)])
    None -> element.none()
  }
}

pub fn view_countdown(seconds: Int) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "fixed inset-0 bg-black/50 flex items-center justify-center z-50",
      ),
    ],
    [view_breathing_countdown(seconds)],
  )
}

// Breathing countdown: 3=start inhale, 2=peak inhale, 1=exhale
fn view_breathing_countdown(seconds: Int) -> Element(Msg) {
  let #(text, scale_class) = case seconds {
    3 -> #("Breathe in...", "scale-100 opacity-80")
    2 -> #("Breathe in...", "scale-125 opacity-100")
    _ -> #("Breathe out...", "scale-100 opacity-70")
  }

  html.div([attribute.class("flex flex-col items-center gap-6")], [
    html.div(
      [
        attribute.class(
          "text-2xl text-emerald-300 transition-all duration-700 "
          <> scale_class,
        ),
      ],
      [element.text(text)],
    ),
    html.div([attribute.class("text-6xl font-bold text-white")], [
      element.text(int.to_string(seconds)),
    ]),
  ])
}

pub fn view_mistake_info(info: protocol.MistakeInfo) -> Element(Msg) {
  // Group cards by player nickname
  let grouped =
    list.group(info.mistake_cards, fn(pair) { pair.0 })
    |> dict.to_list
  let discards =
    list.map(grouped, fn(entry) {
      let #(nickname, cards) = entry
      let sorted_cards =
        cards
        |> list.map(fn(c) { c.1 })
        |> list.sort(int.compare)
      let card_strings = list.map(sorted_cards, int.to_string)
      nickname <> " had " <> string.join(card_strings, ", ")
    })
    |> string.join("; ")

  html.div(
    [
      attribute.class(
        "bg-red-900/30 border border-red-500/50 rounded-lg px-3 py-2 w-full text-center",
      ),
    ],
    [
      html.div([attribute.class("text-red-300 text-sm font-medium")], [
        element.text(
          "Life Lost! "
          <> info.player_nickname
          <> " played "
          <> int.to_string(info.played_card),
        ),
      ]),
      html.div([attribute.class("text-gray-400 text-xs")], [
        element.text(discards),
      ]),
    ],
  )
}
