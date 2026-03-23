import client/msg.{type Msg}
import gleam/json
import lustre/effect

@external(javascript, "../client.ffi.mjs", "connectWebSocket")
pub fn connect_websocket(dispatch: fn(Msg) -> Nil) -> Nil

@external(javascript, "../client.ffi.mjs", "sendMessage")
pub fn send_message(message: json.Json) -> Nil

@external(javascript, "../client.ffi.mjs", "getOrCreateUserId")
pub fn get_or_create_user_id() -> String

@external(javascript, "../client.ffi.mjs", "saveGameToStorage")
pub fn save_game_to_storage(
  code: String,
  user_id: String,
  nickname: String,
) -> Nil

@external(javascript, "../client.ffi.mjs", "copyToClipboard")
pub fn copy_to_clipboard(text: String) -> Nil

@external(javascript, "../client.ffi.mjs", "dispatchAfterMs")
pub fn dispatch_after_ms(dispatch: fn(Msg) -> Nil, msg: Msg, ms: Int) -> Nil

@external(javascript, "../client.ffi.mjs", "getOrigin")
pub fn get_origin() -> String

@external(javascript, "../client.ffi.mjs", "clearSavedGame")
pub fn clear_saved_game() -> Nil

@external(javascript, "../client.ffi.mjs", "checkSavedGame")
pub fn check_saved_game(dispatch: fn(Msg) -> Nil) -> Nil

pub fn clear_saved_game_effect() -> effect.Effect(Msg) {
  effect.from(fn(_dispatch) { clear_saved_game() })
}
