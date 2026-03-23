# Task 1: Latency Compensation Implementation Plan

## Overview

Implement ping/pong latency measurement and latency-compensated mistake resolution to handle simultaneous card plays fairly across different network conditions.

---

## Subtasks (11 steps)

### Step 1: Add Protocol Types for Ping/Pong [S]
**Files:**
- `shared/src/protocol/types.gleam` - Add `PongServer(token: String)` to ClientMessage, `PingClient(token: String)` to ServerMessage
- `shared/src/protocol/decoders.gleam` - Add decoder for `"pong_server"`
- `shared/src/protocol/encoders.gleam` - Add encoder for `PingClient`

**Verify:** `cd shared && gleam build`

---

### Step 2: Add Server WebSocket Handler for PongServer [S]
**Files:**
- `server/src/server.gleam` - Add case for `"pong_server"` message type, forward to actor

**Verify:** Server compiles, sending `{"type": "pong_server", "token": "test"}` doesn't crash

---

### Step 3: Add Client Handler for PingClient [S]
**Files:**
- `client/src/client.ffi.mjs` - Add case `"ping_client"` that creates PingClient
- `client/src/client/server_messages.gleam` - Handle `PingClient(token)`, send back `PongServer(token)`

**Verify:** Client receives PingClient and echoes PongServer

---

### Step 4: Add Latency State to ServerState [S]
**Files:**
- `server/src/game_server/state.gleam` - Add `player_latencies: Dict(String, Float)`, `ping_key: BitArray`
- `server/src/game_server/actor.gleam` - Initialize fields, generate key with `casper.new_key()`

**Verify:** Server starts without errors

---

### Step 5: Implement Ping/Pong Latency Calculation [M]
**Files:**
- NEW: `server/src/game_server/latency.gleam`
  - `create_ping_token(key: BitArray, timestamp_ms: Int) -> String` - encrypt timestamp, base64 encode
  - `calculate_latency(key: BitArray, token: String) -> Result(Float, Nil)` - grab current time FIRST, then decrypt, compute delta
  - `send_pings_to_game(state, game_code) -> Nil`
  - `const default_latency = 25.0`
- `server/src/game_server/actor.gleam` - Handle `PongServer(token)`, update `player_latencies`

**Implementation:**
```gleam
import casper
import gleam/bit_array
import gleam/int
import gleam/result

pub fn create_ping_token(key: BitArray, timestamp_ms: Int) -> String {
  timestamp_ms
  |> int.to_string
  |> bit_array.from_string
  |> casper.encrypt(key)
  |> bit_array.base64_encode(True)
}

pub fn calculate_latency(key: BitArray, token: String) -> Result(Float, Nil) {
  let now = get_current_time_ms()  // grab time FIRST
  use encrypted <- result.try(bit_array.base64_decode(token))
  use decrypted <- result.try(casper.decrypt(encrypted, key))
  use timestamp_str <- result.try(bit_array.to_string(decrypted))
  use ping_time <- result.try(int.parse(timestamp_str))
  Ok(int.to_float(now - ping_time))
}
```

**Verify:** Unit test for token roundtrip. Integration test showing latency updates.

---

### Step 6: Send Pings Before Countdown [S]
**Files:**
- `server/src/game_server/countdown.gleam` - Call `latency.send_pings_to_game()` before countdown
- `server/src/game_server/handlers/game_play.gleam` - Same for Pause phase exit

**Latency sampling:** Use most recent latency value (not running average). With 8-12+ samples per player (one per round, plus extras from mistakes), we have sufficient data. Recent values better reflect current network conditions.

**Verify:** Players receive PingClient before CountdownTick(3)

---

### Step 7: Add MistakeResolutionState Type [S]
**Files:**
- `server/src/game_server/state.gleam`:
  ```gleam
  pub type BufferedCard {
    BufferedCard(user_id: String, card: Int, server_receive_time: Int)
  }

  pub type MistakeResolutionState {
    MistakeResolutionState(
      game_code: String,
      trigger_card: Int,
      trigger_user_id: String,
      trigger_time: Int,
      buffered_cards: Dict(String, BufferedCard),
    )
  }
  ```
- Add `MistakeResolutionMsg(game_code: String)` to ServerMsg
- Add `mistake_resolutions: Dict(String, MistakeResolutionState)` to ServerState

**Note:** No `arrival_order` field needed - use `server_receive_time` as FIFO tiebreaker when adjusted timestamps are equal.

**Verify:** Types compile

---

### Step 8: Calculate Buffer Window Duration [S]
**Files:**
- `server/src/game_server/latency.gleam`:
  ```gleam
  pub fn get_buffer_window_ms(state: ServerState, game_code: String) -> Int
  // Returns min(max(latencies) / 2, 250), default 250 if no data
  ```

**Verify:** Unit tests:
- Empty latencies -> 250ms (default)
- All 50ms -> 25ms
- One 1000ms, others 50ms -> 250ms (capped)
- All 400ms -> 200ms

---

### Step 9: Modify PlayCard to Detect and Buffer [L]
**Files:**
- `shared/src/game.gleam` - Add `check_potential_mistake(game, user_id) -> Option(List(String))`
- `server/src/game_server/handlers/game_play.gleam`:
  - Check for potential mistake before applying
  - If potential mistake + no active resolution: create MistakeResolutionState, schedule timer
  - If active resolution: add to buffered_cards (ignore duplicates via Dict keying)

**Cards arriving after buffer expires:**
- If no mistake detected and game stays in ActivePlay: process normally (could trigger new resolution)
- If mistake detected and game transitions to Pause: reject the card (per architecture: "PlayCard during Pause phase -> rejected")

**Verify:** Normal play works. Potential mistakes enter buffering.

---

### Step 10: Implement Latency-Adjusted Resolution [L]
**Files:**
- NEW: `server/src/game_server/handlers/mistake_resolution.gleam`:
  ```gleam
  pub fn resolve_mistake(state: ServerState, game_code: String) -> ServerState

  fn adjust_timestamp(server_time: Int, latency_ms: Float) -> Float
  // effective_time = server_time - min(latency / 2, 250)

  fn sort_by_adjusted_time(cards: List(BufferedCard), latencies: Dict) -> List(BufferedCard)
  // Sort by adjusted time, use server_receive_time as FIFO tiebreaker for equal adjusted times

  fn is_valid_ascending(cards: List(Int), pile_top: Int) -> Bool
  ```
- `server/src/game_server/handlers/ticks.gleam` - Add handler for `MistakeResolutionMsg`

**Verify:** Unit tests with edge cases (see below)

---

### Step 11: Block Votes During Resolution [S]
**Files:**
- `server/src/game_server/handlers/vote_initiation.gleam`:
  - In `handle_initiate_strike_vote`: check if resolution active, ignore if so
  - Same for `handle_initiate_abandon_vote`

**Verify:** Cannot initiate vote while resolution active

---

## Edge Cases for Latency Adjustment

**Buffer window formula:** `min(max(latencies) / 2, 250ms)`, default 250ms if no latency data

**Latency adjustment formula:** `effective_time = server_receive_time - min(latency / 2, 250ms)`
- Each player's latency reduction is capped at 250ms
- A player with 1000ms latency gets 250ms reduction (not 500ms)

### Example 1: Simple Reordering (Still a Mistake)
```
Latencies: Alice=100ms, Bob=50ms
Buffer window: min(100/2, 250) = 50ms

Server receives:
  t=0ms:  Alice plays 45 (latency: 100ms)  <- triggers buffer
  t=50ms: Bob plays 42 (latency: 50ms)     <- arrives within buffer

Adjusted times:
  Alice: 0 - (100/2) = -50ms
  Bob: 50 - (50/2) = 25ms

Sorted by adjusted time: [Alice 45 @ -50ms, Bob 42 @ 25ms]
Card order: [45, 42]
Result: NOT ascending (45 > 42) -> MISTAKE
  Alice played 45 before Bob played 42, but 45 > 42 is wrong order.
```

### Example 2: Latency Compensation Saves the Day
```
Server receives (pile top = 40):
  t=0ms:   Bob plays 45 (latency: 20ms)     <- server sees this first
  t=5ms:   Alice plays 42 (latency: 200ms)  <- server sees this second

Without compensation: Bob@0ms, Alice@5ms -> [45, 42] -> MISTAKE (45 > 42)

With compensation:
  Bob: 0 - 10 = -10ms
  Alice: 5 - 100 = -95ms (Alice clicked way earlier!)
  Sorted: [Alice 42 @ -95ms, Bob 45 @ -10ms]
  Card order: [42, 45]
Result: VALID ascending (42 < 45) -> NO MISTAKE!
  Alice's high latency made her card arrive later, but she actually clicked first.
```

### Example 3: Tie-breaker with FIFO
```
Latencies: Alice=100ms, Bob=200ms
Buffer window: min(200/2, 250) = 100ms

Server receives:
  t=0ms:   Alice plays 45 (latency: 100ms)
  t=50ms:  Bob plays 50 (latency: 200ms)

Adjusted times:
  Alice: 0 - 50 = -50ms
  Bob: 50 - 100 = -50ms (TIE!)

Tiebreaker: FIFO (server_receive_time)
  Alice arrived at t=0ms
  Bob arrived at t=50ms

Sorted: [Alice 45, Bob 50]
Card order: [45, 50]
Result: Valid ascending -> NO MISTAKE
```

### Example 4: High Latency Player (1000ms) - Both Caps Apply
```
Latencies: [20ms, 30ms, 40ms, 1000ms]
Buffer window: min(1000/2, 250) = 250ms (CAPPED)

Server receives:
  t=0ms:   Player D plays 80 (latency: 1000ms)  <- triggers buffer
  t=100ms: Player A plays 30 (latency: 20ms)
  t=200ms: Player B plays 40 (latency: 30ms)
  t=300ms: Player C plays 50 (latency: 40ms)    <- OUTSIDE buffer window!

Only cards within 250ms buffer: D, A, B
Player C's card arrives at 300ms > 250ms, NOT included.

Latency reductions (each capped at 250ms):
  D: min(1000/2, 250) = 250ms reduction (CAPPED, not 500ms)
  A: min(20/2, 250) = 10ms reduction
  B: min(30/2, 250) = 15ms reduction

Adjusted times:
  D: 0 - 250 = -250ms
  A: 100 - 10 = 90ms
  B: 200 - 15 = 185ms

Sorted: [D(80) @ -250ms, A(30) @ 90ms, B(40) @ 185ms]
Card order: [80, 30, 40]
Result: NOT ascending (80 > 30) -> MISTAKE
  D's card is out of order even with maximum compensation.
  Cards 30, 40 discarded. Life lost. Pause phase.
  Player C's card (50) still in hand for next round.
```

### Example 5: Remaining Lower Cards After Valid Buffer
```
Pile top: 25
Latencies: Alice=50ms, Bob=50ms, Carol=50ms
Buffer window: min(50/2, 250) = 25ms

Server receives:
  t=0ms:  Alice plays 30 (latency: 50ms)  <- triggers buffer
  t=20ms: Bob plays 35 (latency: 50ms)    <- within buffer

Carol still has card 28 in hand (didn't play).

Adjusted times:
  Alice: 0 - 25 = -25ms
  Bob: 20 - 25 = -5ms

Sorted: [Alice 30, Bob 35]
Card order: [30, 35]
Ascending check: VALID (30 < 35)

BUT: After applying cards, pile top = 35
Carol has 28 < 30 (Alice's card that was just played)

Result: MISTAKE - Carol should have played 28 before Alice played 30
  Carol's 28 is discarded. Life lost. Pause phase.
```

### Example 6: Duplicate Protection
```
Server receives:
  t=0ms:   Alice plays 40 (triggers buffer)
  t=20ms:  Alice plays 40 again (WebSocket retry/duplicate)
  t=50ms:  Bob plays 38

Buffer uses Dict keyed by user_id:
  After t=0ms:  {Alice: BufferedCard("alice", 40, 0)}
  After t=20ms: {Alice: BufferedCard("alice", 40, 0)}  <- duplicate ignored!
  After t=50ms: {Alice: ..., Bob: BufferedCard("bob", 38, 50)}

Resolution proceeds with exactly 2 cards: Alice's 40 and Bob's 38.
```

### Example 7: Card Arrives After Buffer Expires
```
Latencies: Alice=50ms, Bob=300ms
Buffer window: min(300/2, 250) = 150ms

Server receives:
  t=0ms:   Alice plays 45 (latency: 50ms)  <- triggers buffer
  t=200ms: Bob plays 42 (latency: 300ms)   <- arrives AFTER 150ms buffer!

At t=150ms, buffer expires with only Alice's card.
Resolution: Just [Alice 45]. No other cards to check order against.
Alice's 45 is applied to pile.

Then at t=200ms, Bob's PlayCard arrives.
Server sees Bob has 42 < pile top (now 45).
This triggers a NEW potential mistake check.

Result: Bob's card triggers new resolution.
```

---

## Key Files Summary

| File | Changes |
|------|---------|
| `shared/src/protocol/types.gleam` | Add PingClient, PongServer |
| `shared/src/protocol/decoders.gleam` | Decode pong_server |
| `shared/src/protocol/encoders.gleam` | Encode PingClient |
| `server/src/server.gleam` | Handle pong_server WebSocket message |
| `server/src/game_server/state.gleam` | Add latencies, ping_key, MistakeResolutionState |
| `server/src/game_server/actor.gleam` | Handle PongServer, init latencies and key |
| `server/src/game_server/latency.gleam` | NEW: token creation, latency calc, buffer window |
| `server/src/game_server/countdown.gleam` | Send pings before countdown |
| `server/src/game_server/handlers/game_play.gleam` | Buffer potential mistakes |
| `server/src/game_server/handlers/mistake_resolution.gleam` | NEW: latency-adjusted resolution |
| `server/src/game_server/handlers/ticks.gleam` | Handle MistakeResolutionMsg |
| `server/src/game_server/handlers/vote_initiation.gleam` | Block votes during resolution |
| `client/src/client.ffi.mjs` | Parse ping_client |
| `client/src/client/server_messages.gleam` | Echo PongServer |

---

## Verification

1. **Unit tests:** Token roundtrip, buffer window calculation, adjusted timestamp sorting
2. **Integration test:** Create game, ready up, observe PingClient/PongServer exchange
3. **Manual test:** Two browser tabs, simulate simultaneous plays, verify latency compensation works
4. **Edge case test:** High latency player (throttle network in DevTools)

---

## Design Decisions

### Encryption
Use [casper](https://github.com/chiroptical/casper) for token encryption. Generate key at actor startup with `casper.new_key()`, store in `ServerState.ping_key`.

### Latency Sampling
Use most recent latency value rather than running average:
- Network conditions change; recent values are more accurate
- 8-12+ samples per player is sufficient data
- Simpler implementation

### FIFO Tiebreaker
When adjusted timestamps are equal, use `server_receive_time` directly as tiebreaker. No separate `arrival_order` counter needed.

### Cards After Buffer
- During ActivePlay: process normally, may trigger new resolution
- During Pause: reject (per existing architecture)

### UI Display
Don't display latency in the UI - adds technical clutter without gameplay benefit. Use debug logging if needed for testing.
