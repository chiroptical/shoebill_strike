import client/model.{type Model}
import client/msg.{
  type Msg, CreateGameClicked, JoinGameClicked, ShowCreateGame, ShowHome,
  ShowJoinGame, UpdateCreateNickname, UpdateJoinCode, UpdateJoinNickname,
}
import client/views/components/feedback
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn view_home_screen() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "min-h-screen p-4 flex flex-col items-center justify-center",
      ),
    ],
    [
      html.div([attribute.class("card text-center space-y-6")], [
        html.h1([attribute.class("text-4xl font-bold text-gray-100 mb-2")], [
          element.text("Shoebill Strike"),
        ]),
        html.p([attribute.class("text-gray-400 mb-4")], [
          element.text("A cooperative card game of patience and timing"),
        ]),
        html.div([attribute.class("space-y-3")], [
          html.button(
            [attribute.class("btn-primary"), event.on_click(ShowCreateGame)],
            [element.text("Create New Game")],
          ),
          html.button(
            [attribute.class("btn-secondary"), event.on_click(ShowJoinGame)],
            [element.text("Join Game")],
          ),
        ]),
      ]),
    ],
  )
}

pub fn view_create_screen(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "min-h-screen p-4 flex flex-col items-center justify-center",
      ),
    ],
    [
      html.div([attribute.class("card space-y-4")], [
        html.h2(
          [attribute.class("text-2xl font-bold text-center text-gray-100")],
          [
            element.text("Create New Game"),
          ],
        ),
        html.input([
          attribute.class("input"),
          attribute.type_("text"),
          attribute.placeholder("Enter your nickname"),
          attribute.value(model.create_nickname),
          event.on_input(UpdateCreateNickname),
        ]),
        html.div([attribute.class("space-y-3 pt-2")], [
          html.button(
            [attribute.class("btn-primary"), event.on_click(CreateGameClicked)],
            [element.text("Create Game")],
          ),
          html.button(
            [attribute.class("btn-secondary"), event.on_click(ShowHome)],
            [element.text("Back")],
          ),
        ]),
        feedback.view_error(model.error),
      ]),
    ],
  )
}

pub fn view_join_screen(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "min-h-screen p-4 flex flex-col items-center justify-center",
      ),
    ],
    [
      html.div([attribute.class("card space-y-4")], [
        html.h2(
          [attribute.class("text-2xl font-bold text-center text-gray-100")],
          [
            element.text("Join Game"),
          ],
        ),
        html.input([
          attribute.class("input"),
          attribute.type_("text"),
          attribute.placeholder("Enter game code"),
          attribute.value(model.join_code),
          event.on_input(UpdateJoinCode),
        ]),
        html.input([
          attribute.class("input"),
          attribute.type_("text"),
          attribute.placeholder("Enter your nickname"),
          attribute.value(model.join_nickname),
          event.on_input(UpdateJoinNickname),
        ]),
        html.div([attribute.class("space-y-3 pt-2")], [
          html.button(
            [attribute.class("btn-primary"), event.on_click(JoinGameClicked)],
            [element.text("Join Game")],
          ),
          html.button(
            [attribute.class("btn-secondary"), event.on_click(ShowHome)],
            [element.text("Back")],
          ),
        ]),
        feedback.view_error(model.error),
      ]),
    ],
  )
}
