import envoy
import gleam/int
import gleam/result

const default_port = 8000

const default_host = "127.0.0.1"

/// Get server port from PORT environment variable, defaults to 8000
pub fn get_port() -> Int {
  envoy.get("PORT")
  |> result.try(int.parse)
  |> result.unwrap(default_port)
}

/// Get server host from HOST environment variable, defaults to 127.0.0.1
pub fn get_host() -> String {
  envoy.get("HOST")
  |> result.unwrap(default_host)
}
