import client/msg.{type Msg}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import protocol/types as protocol

pub fn view_card(card: protocol.Card) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "bg-gray-700 rounded-lg shadow-md p-1.5 lg:p-2 w-[2.5rem] lg:w-[3rem] text-center font-bold text-base lg:text-lg text-gray-100",
      ),
    ],
    [element.text(int.to_string(card))],
  )
}

/// Combined pile and hand view - side by side for compact mobile layout
/// Pass Some(played_cards) to show pile, None to hide it
pub fn view_pile_and_hand(
  played_cards: Option(List(protocol.Card)),
  hand: List(protocol.Card),
) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "bg-gray-800 rounded-lg p-3 lg:p-4 shadow-lg w-full flex gap-3 lg:gap-4",
      ),
    ],
    [
      // Pile section (left) - only shown when played_cards is Some
      case played_cards {
        Some(cards) -> {
          let top_card = list.last(cards)
          html.div([attribute.class("flex flex-col w-16 lg:w-20")], [
            html.div(
              [
                attribute.class(
                  "text-gray-400 text-xs lg:text-sm mb-1 text-center",
                ),
              ],
              [element.text("Pile")],
            ),
            // Card container - fills remaining height and centers card
            html.div(
              [attribute.class("flex-1 flex items-center justify-center")],
              [
                case top_card {
                  Ok(card) ->
                    html.div(
                      [
                        attribute.class(
                          "bg-emerald-700 rounded-lg shadow-md p-3 lg:p-4 min-w-[3rem] lg:min-w-[3.5rem] text-center font-bold text-xl lg:text-2xl text-white",
                        ),
                      ],
                      [element.text(int.to_string(card))],
                    )
                  Error(_) ->
                    html.div(
                      [
                        attribute.class(
                          "bg-gray-700 rounded-lg shadow-md p-3 lg:p-4 min-w-[3rem] lg:min-w-[3.5rem] text-center font-bold text-xl lg:text-2xl text-gray-500",
                        ),
                      ],
                      [element.text("-")],
                    )
                },
              ],
            ),
          ])
        }
        None -> element.none()
      },
      // Divider - only shown when pile is shown
      case played_cards {
        Some(_) ->
          html.div([attribute.class("w-px bg-gray-600 self-stretch")], [])
        None -> element.none()
      },
      // Hand section - responsive grid with more columns on larger screens
      html.div([attribute.class("flex-1")], [
        html.div([attribute.class("text-gray-400 text-xs lg:text-sm mb-1")], [
          element.text("Your Hand"),
        ]),
        html.div(
          [attribute.class("hand-grid h-[8rem] lg:h-[10rem]")],
          list.map(hand, fn(card) { view_card(card) }),
        ),
      ]),
    ],
  )
}
