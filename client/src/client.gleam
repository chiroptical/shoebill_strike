import client/init
import client/model.{
  type Model, CreateScreen, GameScreen, HomeScreen, JoinScreen, LobbyScreen,
}
import client/msg.{type Msg}
import client/update
import client/views/components/feedback
import client/views/game
import client/views/home
import client/views/lobby
import lustre
import lustre/element.{type Element}
import lustre/element/html
import protocol/types as protocol

pub fn main() {
  let app = lustre.application(init.init, update.update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// Re-export Msg type and server_message for FFI compatibility
pub type MsgAlias =
  Msg

/// Helper function for FFI to create ServerMessage variant
pub fn server_message(server_msg: protocol.ServerMessage) -> Msg {
  msg.server_message(server_msg)
}

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    case model.screen {
      HomeScreen -> home.view_home_screen()
      CreateScreen -> home.view_create_screen(model)
      JoinScreen -> home.view_join_screen(model)
      LobbyScreen -> lobby.view_lobby_screen(model)
      GameScreen -> game.view_game_screen(model)
    },
    feedback.view_toast(model.toast),
  ])
}
