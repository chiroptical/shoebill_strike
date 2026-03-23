import client/effects
import client/model.{type Model}
import client/msg.{
  type Msg, CopyShareCode, CopyShareLink, StartGameClicked, ToggleReadyClicked,
}
import client/views/components/feedback
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import icons
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import protocol/types as protocol

pub fn view_lobby_screen(model: Model) -> Element(Msg) {
  case model.current_lobby {
    Some(lobby) -> {
      let my_player =
        list.find(lobby.players, fn(p) { p.user_id == model.user_id })
      let all_ready = list.all(lobby.players, fn(p) { p.is_ready })

      html.div(
        [
          attribute.class(
            "min-h-screen p-4 lg:pb-24 flex flex-col items-center justify-start md:justify-center",
          ),
        ],
        [
          // Main container - responsive width
          html.div(
            [
              attribute.class(
                "w-full max-w-md md:max-w-3xl lg:max-w-4xl flex flex-col md:flex-row gap-4 md:gap-6 lg:gap-8",
              ),
            ],
            [
              // Left column: Game code + action buttons
              html.div([attribute.class("flex-1 flex flex-col")], [
                // Game code card
                html.div(
                  [
                    attribute.class(
                      "bg-gray-800 rounded-lg p-6 text-center shadow-lg",
                    ),
                  ],
                  [
                    html.p([attribute.class("text-gray-400 text-sm mb-2")], [
                      element.text("Game Code"),
                    ]),
                    html.div(
                      [
                        attribute.class(
                          "flex items-center justify-center gap-3",
                        ),
                      ],
                      [
                        html.span(
                          [attribute.class("text-3xl font-bold tracking-wider")],
                          [element.text(lobby.code)],
                        ),
                        html.div([attribute.class("flex flex-col gap-1")], [
                          html.button(
                            [
                              attribute.class("btn-copy"),
                              event.on_click(CopyShareCode(lobby.code)),
                            ],
                            [element.text("Copy Code")],
                          ),
                          html.button(
                            [
                              attribute.class("btn-copy"),
                              event.on_click(CopyShareLink(
                                effects.get_origin() <> "?code=" <> lobby.code,
                              )),
                            ],
                            [element.text("Copy Link")],
                          ),
                        ]),
                      ],
                    ),
                  ],
                ),
                // Action buttons - in left column on desktop for button position consistency
                case my_player {
                  Ok(player) -> {
                    let player_count = list.length(lobby.players)
                    let needs_more_players = player_count < 2

                    html.div([attribute.class("mt-4 space-y-3")], [
                      case needs_more_players {
                        True ->
                          html.p(
                            [
                              attribute.class(
                                "text-gray-500 italic text-center",
                              ),
                            ],
                            [
                              element.text(
                                "Waiting for more players to join...",
                              ),
                            ],
                          )
                        False -> {
                          let #(ready_text, button_class) = case
                            player.is_ready
                          {
                            True -> #("Not Ready", "btn-ready")
                            False -> #("Ready", "btn-primary")
                          }
                          html.button(
                            [
                              attribute.id("ready-button"),
                              attribute.class(button_class),
                              event.on_click(ToggleReadyClicked),
                            ],
                            [element.text(ready_text)],
                          )
                        }
                      },
                      case player.is_creator && all_ready {
                        True ->
                          html.button(
                            [
                              attribute.class("btn-primary"),
                              event.on_click(StartGameClicked),
                            ],
                            [element.text("Start Game")],
                          )
                        False -> element.none()
                      },
                    ])
                  }
                  Error(_) -> element.none()
                },
              ]),
              // Right column: Player list (shown first on mobile via order)
              html.div([attribute.class("flex-1 order-first md:order-last")], [
                html.div(
                  [attribute.class("bg-gray-800 rounded-lg p-4 shadow-lg")],
                  [
                    html.div(
                      [
                        attribute.class(
                          "flex justify-between items-center mb-3",
                        ),
                      ],
                      [
                        html.span([attribute.class("text-gray-400 text-sm")], [
                          element.text("Players"),
                        ]),
                        html.span([attribute.class("text-gray-400 text-sm")], [
                          element.text(
                            int.to_string(list.length(lobby.players)) <> "/4",
                          ),
                        ]),
                      ],
                    ),
                    html.div([], list.map(lobby.players, view_player)),
                  ],
                ),
              ]),
            ],
          ),
          feedback.view_error(model.error),
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
            element.text("Loading lobby..."),
          ]),
        ],
      )
  }
}

pub fn view_player(player: protocol.Player) -> Element(Msg) {
  let base_class =
    "flex items-center justify-between p-3 rounded-md bg-gray-700/50 mb-2 last:mb-0"
  let opacity_class = case player.is_connected {
    True -> ""
    False -> " opacity-50"
  }

  let host_indicator = case player.is_creator {
    True -> " (Host)"
    False -> ""
  }

  let status_element = case player.is_connected, player.is_ready {
    False, _ ->
      html.span([attribute.class("text-red-400 text-sm")], [
        element.text("Offline"),
      ])
    True, True ->
      html.span(
        [attribute.class("text-green-400 text-sm flex items-center gap-1")],
        [
          icons.check_icon("w-3 h-3"),
          element.text("Ready"),
        ],
      )
    True, False ->
      html.span([attribute.class("text-gray-500 text-sm")], [
        element.text("Waiting"),
      ])
  }

  html.div([attribute.class(base_class <> opacity_class)], [
    html.span([attribute.class("font-medium")], [
      element.text(player.nickname <> host_indicator),
    ]),
    status_element,
  ])
}
