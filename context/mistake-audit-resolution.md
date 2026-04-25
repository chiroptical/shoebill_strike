# Task 1a: Mistake Audit Resolution

## Overview

Implement a buffering window when potential mistakes are detected, allowing
near-simultaneous card plays to be captured and resolved together. Cards are
resolved in server-receive order (FIFO).

---

## Subtasks (5 steps)

### Step 1: Add MistakeResolutionState Type [S]
**Files:**
- `shared/src/protocol.gleam`:
  ```gleam
  pub type BufferedCard {
    BufferedCard(user_id: String, card: Int, server_receive_time: Int)
  }

  pub type MistakeResolutionState {
    MistakeResolutionState(buffered_cards: Dict(String, BufferedCard))
  }
  ```
- Add `mistake_resolution: Option(MistakeResolutionState)` field to `Game` type
- Add `ResolveMistake(game_code: String)` to ServerMsg (timer message, sent via `process.send_after`)
- Add JSON encoding/decoding for new types

**Notes:**
- `buffered_cards` is keyed by `user_id` to naturally deduplicate (one card per player)
- The triggering card is added to `buffered_cards` when creating the state; during resolution, sort by `server_receive_time` to determine order

**Verify:** Types compile

---

### Step 2: Add Helper to Detect Mistakes [S]
**Files:**
- `shared/src/game.gleam` - Add function:
  ```gleam
  /// Check if another player has a card lower than this user's lowest card.
  pub fn other_player_has_lower_card(game: Game, user_id: String) -> Bool
  ```

**Logic:**
- Find the user's lowest card
- Check if any other player has a card lower than this
- Return `True` if so, `False` otherwise
- `True` should short circuit the function

**Verify:** Unit tests for various scenarios

---

### Step 3: Calculate Buffer Window Duration [S]
**Files:**
- NEW: `server/src/game_server/mistake_resolution.gleam`:
  ```gleam
  pub const buffer_window_ms: Int = 250
  ```

**Note:** This is a fixed value for now.

**Verify:** Module compiles

---

### Step 4: Modify PlayCard to Detect and Buffer [L]
**Files:**
- `server/src/game_server/handlers/game_play.gleam`:
  - When a card is played, call `other_player_has_lower_card`
  - Check `game.mistake_resolution`
  - If `True` AND no existing resolution (`None`):
    1. Create `MistakeResolutionState` with triggering card in `buffered_cards`
    2. Set `game.mistake_resolution` to `Some(resolution)`
    3. Schedule `ResolveMistake` via `process.send_after(buffer_window_ms)`
  - If resolution exists (`Some(resolution)`):
    1. Add card to `resolution.buffered_cards` (Dict keying ignores duplicates)

**Cards arriving after buffer expires:**
- If no mistake detected and game stays in ActivePlay: process normally (could trigger new resolution)
- If mistake detected and game transitions to Pause: reject the card (per architecture)

**Card Ownership During Buffering:**
- Cards remain in players' hands during the buffer window
- The `BufferedCard` records the intent to play, not the removal
- Cards are removed from hands only during resolution (Step 5)
- This means duplicate PlayCard messages are handled via Dict keying, not by "card no longer in hand"

**Verify:** Normal play works. Mistakes trigger buffering.

---

### Step 5: Implement FIFO Resolution [L]
**Files:**
- `server/src/game_server/mistake_resolution.gleam`:
  ```gleam
  pub fn resolve_mistake(state: ServerState, game_code: String) -> ServerState

  fn sort_by_server_time(cards: List(BufferedCard)) -> List(BufferedCard)
  // Sort by server_receive_time (FIFO order)

  fn is_valid_ascending(cards: List(Int), pile_top: Int) -> Bool
  ```
- `server/src/game_server/handlers/ticks.gleam` - Add handler for `ResolveMistake`

**Resolution Logic:**
1. Retrieve `game.mistake_resolution` and set it back to `None`
2. Sort all buffered cards by `server_receive_time` (FIFO)
3. Check if cards are in valid ascending order from pile top
4. If valid:
   - Apply all cards in order
   - Check if any remaining player has card < new pile top
   - If yes → mistake (discard those cards, lose life, Pause)
   - If no → continue ActivePlay
5. If invalid:
   - Discard all cards lower than pile top
   - Lose one life
   - Transition to Pause (or EndGame if lives = 0)

**Display Info for Audit:**
When resolving, sort `buffered_cards` by `server_receive_time`. The first card's time is the baseline.

Delta between cards: `card.server_receive_time - first_card.server_receive_time`

This allows displaying messages like:
- "Alice played 45 at +0ms"
- "Bob played 42 at +35ms"
- "Cards arrived within 35ms of each other"

**Verify:** Unit tests with edge cases (see below)

---

### Step 6: Block Votes During Resolution [S]
**Files:**
- `server/src/game_server/handlers/vote_initiation.gleam`:
  - In `handle_initiate_strike_vote`: check if resolution active, ignore if so
  - Same for `handle_initiate_abandon_vote`

**Verify:** Cannot initiate vote while resolution active

---

## Edge Cases

### Example 1: Simple Mistake (FIFO Order)
```
Server receives:
  t=0ms:   Alice plays 45  <- triggers buffer
  t=35ms:  Bob plays 42    <- arrives within buffer

Sorted by server time: [Alice 45 @ 0ms, Bob 42 @ 35ms]
Card order: [45, 42]
Result: NOT ascending (45 > 42) -> MISTAKE
  Cards 42 discarded. Life lost. Pause phase.

Audit display: "Alice played 45 at +0ms, Bob played 42 at +35ms (delta: 35ms)"
```

### Example 2: Valid Simultaneous Plays
```
Server receives:
  t=0ms:   Alice plays 30  <- triggers buffer
  t=20ms:  Bob plays 35    <- arrives within buffer

Sorted: [Alice 30 @ 0ms, Bob 35 @ 20ms]
Card order: [30, 35]
Result: Valid ascending -> NO MISTAKE
  Both cards applied.
```

### Example 3: Remaining Lower Cards After Valid Buffer
```
Pile top: 25
Server receives:
  t=0ms:   Alice plays 30  <- triggers buffer
  t=20ms:  Bob plays 35    <- within buffer

Carol still has card 28 in hand.

Sorted: [Alice 30, Bob 35]
Ascending check: VALID

BUT: After applying cards, pile top = 35
Carol has 28 < 30 (Alice's card)

Result: MISTAKE - Carol should have played 28 before Alice played 30
  Carol's 28 discarded. Life lost. Pause phase.
```

### Example 4: Duplicate Protection
```
Server receives:
  t=0ms:   Alice plays 40 (triggers buffer)
  t=20ms:  Alice plays 40 again (WebSocket retry/duplicate)
  t=50ms:  Bob plays 38

Buffer uses Dict keyed by user_id:
  After t=0ms:  {Alice: BufferedCard(..., 40, 0)}
  After t=20ms: {Alice: BufferedCard(..., 40, 0)}  <- duplicate ignored!
  After t=50ms: {Alice: ..., Bob: BufferedCard(..., 38, 50)}

Resolution proceeds with exactly 2 cards.
```

### Example 5: Card Arrives After Buffer Expires
```
Buffer window: 250ms

Server receives:
  t=0ms:   Alice plays 45  <- triggers buffer
  t=300ms: Bob plays 42    <- arrives AFTER 250ms buffer!

At t=250ms, buffer expires with only Alice's card.
Resolution: Just [Alice 45]. Applied to pile.

At t=300ms, Bob's PlayCard arrives.
Server sees Bob has 42 < pile top (now 45).
This triggers a NEW mistake check (and potentially a new buffer window).
```

---

## Key Files Summary

| File | Changes |
|------|---------|
| `shared/src/protocol.gleam` | Add BufferedCard, MistakeResolutionState types; add `mistake_resolution` field to Game; add encoding/decoding |
| `server/src/game_server/state.gleam` | Add ResolveMistake to ServerMsg |
| `shared/src/game.gleam` | Add other_player_has_lower_card |
| `server/src/game_server/mistake_resolution.gleam` | NEW: buffer window, FIFO resolution |
| `server/src/game_server/handlers/game_play.gleam` | Buffer mistakes |
| `server/src/game_server/handlers/ticks.gleam` | Handle ResolveMistake |
| `server/src/game_server/handlers/vote_initiation.gleam` | Block votes during resolution |

---

## Verification

1. **Unit tests:** other_player_has_lower_card, FIFO sorting, ascending validation
2. **Integration test:** Two players, simultaneous plays, verify buffering occurs
3. **Manual test:** Observe audit info (time deltas) in resolution
4. **Edge case test:** Duplicate cards, cards after buffer expires

---

## Next Step

After this is working, proceed to [latency-compensation.md](latency-compensation.md) to add ping/pong latency measurement and latency-adjusted resolution timestamps.
