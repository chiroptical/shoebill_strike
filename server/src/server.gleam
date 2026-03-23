import config
import game_server
import game_server/state.{
  type ServerMsg, ClientConnected, ClientDisconnected, ClientMsg,
}
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import mist
import protocol/encoders
import protocol/types as protocol
import simplifile

pub fn main() {
  let port = config.get_port()
  let host = config.get_host()

  // Start the server actor
  let assert Ok(server_subject) = game_server.start()

  // Start the HTTP server with WebSocket support
  let assert Ok(_) =
    mist.new(handle_request(_, server_subject))
    |> mist.bind(host)
    |> mist.port(port)
    |> mist.start

  io.println("Server started on http://" <> host <> ":" <> int.to_string(port))

  // Keep the application running
  process.sleep_forever()
}

fn handle_request(
  req: Request(mist.Connection),
  server_subject: process.Subject(ServerMsg),
) -> Response(mist.ResponseData) {
  case request.path_segments(req) {
    ["ws"] -> {
      // Handle WebSocket upgrade
      mist.websocket(
        request: req,
        on_init: fn(_conn) { websocket_init(server_subject) },
        on_close: fn(state) { websocket_close(state, server_subject) },
        handler: fn(state, msg, conn) {
          websocket_handler(state, msg, conn, server_subject)
        },
      )
    }
    _ -> {
      // Serve static files
      serve_static(req)
    }
  }
}

/// Serve static files from priv/static
/// For SPA routes (paths without file extensions), falls back to index.html
fn serve_static(req: Request(mist.Connection)) -> Response(mist.ResponseData) {
  let path = case request.path_segments(req) {
    [] -> "index.html"
    segments -> segments |> list_join("/")
  }

  let file_path = "priv/static/" <> path

  case simplifile.read(file_path) {
    Ok(content) -> {
      let content_type = get_content_type(path)

      response.new(200)
      |> response.set_header("content-type", content_type)
      |> response.set_body(mist.Bytes(bytes_tree.from_string(content)))
    }
    Error(_) -> {
      // For SPA routes (no file extension), serve index.html
      // For actual static files (with extension), return 404
      case has_file_extension(path) {
        True -> {
          response.new(404)
          |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
        }
        False -> {
          case simplifile.read("priv/static/index.html") {
            Ok(content) -> {
              response.new(200)
              |> response.set_header("content-type", "text/html")
              |> response.set_body(mist.Bytes(bytes_tree.from_string(content)))
            }
            Error(_) -> {
              response.new(404)
              |> response.set_body(
                mist.Bytes(bytes_tree.from_string("Not found")),
              )
            }
          }
        }
      }
    }
  }
}

fn has_file_extension(path: String) -> Bool {
  let parts = string.split(path, "/")
  case list.last(parts) {
    Ok(filename) -> string.contains(filename, ".")
    Error(_) -> False
  }
}

fn list_join(list: List(String), separator: String) -> String {
  case list {
    [] -> ""
    [single] -> single
    [first, ..rest] -> first <> separator <> list_join(rest, separator)
  }
}

fn get_content_type(path: String) -> String {
  case string.ends_with(path, ".html") {
    True -> "text/html"
    False ->
      case string.ends_with(path, ".js") {
        True -> "application/javascript"
        False ->
          case string.ends_with(path, ".css") {
            True -> "text/css"
            False -> "application/octet-stream"
          }
      }
  }
}

/// WebSocket initialization
fn websocket_init(
  server_subject: process.Subject(ServerMsg),
) -> #(WsState, option.Option(process.Selector(protocol.ServerMessage))) {
  let self_subject = process.new_subject()

  // Create a selector to listen for server messages
  let selector = process.select(process.new_selector(), self_subject)

  #(
    WsState(user_id: option.None, server: server_subject, self: self_subject),
    option.Some(selector),
  )
}

/// WebSocket close handler
fn websocket_close(
  state: WsState,
  server_subject: process.Subject(ServerMsg),
) -> Nil {
  // Only send disconnect if we know the user_id
  case state.user_id {
    option.Some(uid) -> process.send(server_subject, ClientDisconnected(uid))
    option.None -> Nil
  }
}

/// WebSocket message handler
fn websocket_handler(
  state: WsState,
  msg: mist.WebsocketMessage(protocol.ServerMessage),
  conn: mist.WebsocketConnection,
  _server_subject: process.Subject(ServerMsg),
) -> mist.Next(WsState, protocol.ServerMessage) {
  case msg {
    mist.Text(text) -> {
      // Parse the JSON message - first decode to get message type
      let type_decoder = {
        use msg_type <- decode.field("type", decode.string)
        decode.success(msg_type)
      }

      // Parse message and potentially extract user_id
      let result = case json.parse(from: text, using: type_decoder) {
        Ok("create_game") -> {
          let decoder = {
            use user_id <- decode.field("user_id", decode.string)
            use nickname <- decode.field("nickname", decode.string)
            decode.success(#(user_id, protocol.CreateGame(user_id, nickname)))
          }
          case json.parse(from: text, using: decoder) {
            Ok(#(uid, msg)) -> Ok(#(option.Some(uid), msg))
            Error(e) -> Error(e)
          }
        }
        Ok("join_game") -> {
          let decoder = {
            use code <- decode.field("code", decode.string)
            use user_id <- decode.field("user_id", decode.string)
            use nickname <- decode.field("nickname", decode.string)
            decode.success(#(
              user_id,
              protocol.JoinGame(code, user_id, nickname),
            ))
          }
          case json.parse(from: text, using: decoder) {
            Ok(#(uid, msg)) -> Ok(#(option.Some(uid), msg))
            Error(e) -> Error(e)
          }
        }
        Ok("toggle_ready") -> Ok(#(option.None, protocol.ToggleReady))
        Ok("start_game") -> Ok(#(option.None, protocol.StartGame))
        Ok("toggle_ready_in_game") ->
          Ok(#(option.None, protocol.ToggleReadyInGame))
        Ok("play_card") -> Ok(#(option.None, protocol.PlayCard))
        Ok("initiate_strike_vote") ->
          Ok(#(option.None, protocol.InitiateStrikeVote))
        Ok("cast_strike_vote") -> {
          let decoder = {
            use approve <- decode.field("approve", decode.bool)
            decode.success(protocol.CastStrikeVote(approve))
          }
          case json.parse(from: text, using: decoder) {
            Ok(msg) -> Ok(#(option.None, msg))
            Error(e) -> Error(e)
          }
        }
        Ok("initiate_abandon_vote") ->
          Ok(#(option.None, protocol.InitiateAbandonVote))
        Ok("cast_abandon_vote") -> {
          let decoder = {
            use approve <- decode.field("approve", decode.bool)
            decode.success(protocol.CastAbandonVote(approve))
          }
          case json.parse(from: text, using: decoder) {
            Ok(msg) -> Ok(#(option.None, msg))
            Error(e) -> Error(e)
          }
        }
        Ok("leave_game") -> Ok(#(option.None, protocol.LeaveGame))
        Ok("restart_game") -> Ok(#(option.None, protocol.RestartGame))
        Ok(unknown) -> {
          io.println("[Server] Unknown message type: " <> unknown)
          Error(json.UnexpectedByte(""))
        }
        Error(e) -> Error(e)
      }

      case result {
        Ok(#(maybe_uid, client_msg)) -> {
          // If this message contains a user_id, register/update with server
          let state = case maybe_uid {
            option.Some(uid) -> {
              // Register with server (will update Subject if already registered)
              process.send(state.server, ClientConnected(state.self, uid))
              WsState(..state, user_id: option.Some(uid))
            }
            option.None -> state
          }

          // Send message to server (only if we have a user_id)
          case state.user_id {
            option.Some(uid) -> {
              process.send(state.server, ClientMsg(uid, client_msg))
            }
            option.None -> {
              io.println(
                "[Server] Received message before user_id was set, ignoring",
              )
            }
          }
          mist.continue(state)
        }
        Error(_) -> mist.continue(state)
      }
    }
    mist.Binary(_) -> mist.continue(state)
    mist.Custom(server_msg) -> {
      // Received a message from the server actor - send it to the client
      let json_msg =
        encoders.encode_server_message(server_msg)
        |> json.to_string

      case mist.send_text_frame(conn, json_msg) {
        Ok(_) -> Nil
        Error(_) -> Nil
      }
      mist.continue(state)
    }
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

/// WebSocket state
type WsState {
  WsState(
    user_id: option.Option(String),
    server: process.Subject(ServerMsg),
    self: process.Subject(protocol.ServerMessage),
  )
}
