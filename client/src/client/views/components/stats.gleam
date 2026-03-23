import client/msg.{type Msg, ToggleRewardGuide}
import gleam/int
import gleam/list
import icons
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import protocol/types as protocol

pub fn view_stat(label: String, value: String) -> Element(Msg) {
  html.div([attribute.class("bg-gray-700/50 rounded-md p-3 text-center")], [
    html.div([attribute.class("text-gray-400 text-xs mb-1")], [
      element.text(label),
    ]),
    html.div([attribute.class("text-gray-100 text-lg font-semibold")], [
      element.text(value),
    ]),
  ])
}

pub fn view_stat_with_icon(
  icon: Element(Msg),
  label: String,
  value: String,
) -> Element(Msg) {
  html.div([attribute.class("bg-gray-700/50 rounded-md p-3 text-center")], [
    html.div(
      [
        attribute.class(
          "text-gray-400 text-xs mb-1 flex items-center justify-center gap-1",
        ),
      ],
      [icon, element.text(label)],
    ),
    html.div([attribute.class("text-gray-100 text-lg font-semibold")], [
      element.text(value),
    ]),
  ])
}

/// View the reward guide showing which rounds grant bonus lives/stars
/// Mobile: toggle button + slide-out panel at 25% from top
/// Desktop (lg+): always-visible sidebar on the left side
pub fn view_reward_guide(game: protocol.Game, is_open: Bool) -> Element(Msg) {
  let current_round = game.current_round
  let rewards = [
    #(2, "star"),
    #(3, "life"),
    #(5, "star"),
    #(6, "life"),
    #(8, "star"),
    #(9, "life"),
  ]

  // Mobile toggle button (hidden on lg+)
  let toggle_button =
    html.button(
      [
        attribute.class("reward-guide-toggle lg:hidden"),
        event.on_click(ToggleRewardGuide),
      ],
      [element.text("Rewards")],
    )

  // Panel visibility class
  let panel_class = case is_open {
    True -> "reward-guide"
    False -> "reward-guide hidden lg:block"
  }

  // Panel content
  let panel =
    html.div([attribute.class(panel_class)], [
      // Close button on mobile (top-right), "Rewards" title on desktop
      html.button(
        [
          attribute.class(
            "lg:hidden text-gray-500 hover:text-gray-300 absolute top-2 right-2",
          ),
          event.on_click(ToggleRewardGuide),
        ],
        [icons.cancel_icon("w-4 h-4")],
      ),
      html.h3(
        [
          attribute.class(
            "hidden lg:block text-sm font-semibold text-gray-400 mb-2",
          ),
        ],
        [
          element.text("Rewards"),
        ],
      ),
      // Reward list
      html.ul(
        [attribute.class("reward-guide-list")],
        list.map(rewards, fn(reward) {
          let #(round, reward_type) = reward
          let completed = current_round > round
          let reward_icon = case reward_type {
            "star" -> icons.shoebill_icon("w-4 h-4 text-[#a7aec0]")
            _ -> icons.heart_icon("w-4 h-4 text-red-400")
          }
          let check_element = case completed {
            True -> icons.check_icon("w-3 h-3 text-emerald-400")
            False -> element.none()
          }
          html.li(
            [attribute.class("reward-guide-item flex items-center gap-1")],
            [
              html.span([attribute.class("inline-block w-4")], [check_element]),
              element.text("Round " <> int.to_string(round) <> " → "),
              reward_icon,
            ],
          )
        }),
      ),
    ])

  html.div([], [toggle_button, panel])
}
