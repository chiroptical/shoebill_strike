# Shoebill Strike - Game Rules Breakdown

## Overview
Shoebill Strike is a cooperative card game where players work together to play numbered
cards (1-100) in ascending order without communication. Players must develop a
shared sense of timing to know when to play their cards.

The core challenge: with no communication allowed, players must "feel" when it's
the right moment to play their card. Lower cards should be played sooner, but
how soon? That intuition is what makes the game unique.

## Setup Configuration

| Players | Starting Cards | Lives | Strikes | Total Rounds |
|---------|----------------|-------|----------------|--------------|
| 2       | 1              | 2     | 1              | 12           |
| 3       | 1              | 3     | 1              | 10           |
| 4       | 1              | 4     | 1              | 8            |

- **Player count:** 2-4 players required (cannot start or restart with fewer than 2)
- **Round:** Each round N, every player receives N cards (Round 1 = 1 card each, Round 5 = 5 cards each, etc.)

## Level Completion Rewards

| Completed Level | Reward          |
|-----------------|-----------------|
| 2               | 1 Strike |
| 3               | 1 Life          |
| 5               | 1 Strike |
| 6               | 1 Life          |
| 8               | 1 Strike |
| 9               | 1 Life          |

## State Transitions

```mermaid
stateDiagram-v2
    [*] --> GameSetup: Host starts game

    GameSetup --> Dealing: Initialize complete

    Dealing --> ActivePlay: Countdown complete

    ActivePlay --> Dealing: Round complete\n(lives > 0, rounds remain)
    ActivePlay --> EndGame: Round complete\n(final round = win)
    ActivePlay --> EndGame: Lives = 0 (loss)
    ActivePlay --> Pause: Mistake\n(lives > 0, cards remain)
    ActivePlay --> Strike: Player initiates vote
    ActivePlay --> AbandonVote: Player initiates vote
    Dealing --> AbandonVote: Player initiates vote

    Pause --> ActivePlay: All players ready\n(countdown if multiple have cards)
    Pause --> Dealing: All players ready\n(auto-play if single player has cards)
    Pause --> AbandonVote: Player initiates vote

    Strike --> Pause: Vote resolved\n(cards remain, regroup)
    Strike --> Dealing: Vote success\n(cards exhausted, rounds remain)
    Strike --> EndGame: Vote success\n(cards exhausted, final round = win)

    AbandonVote --> EndGame: Vote success (abandoned)
    AbandonVote --> Dealing: Vote failure\n(return to previous)
    AbandonVote --> ActivePlay: Vote failure\n(return to previous)
    AbandonVote --> Pause: Vote failure\n(return to previous)

    EndGame --> Dealing: Host restarts\n(ready states reset)
    EndGame --> [*]: All players leave
```

## Game Phases

### 0. Game Setup Phase (server-side only)
**Purpose:** Initialize game configuration based on current player count

**Note:** This phase is not visible to clients. It exists to clarify server state transitions. Clients transition directly from Lobby/EndGame to Dealing.

**Entry:**
- Host starts game from lobby, OR
- Host restarts game from End Game Phase (all players ready)

**Actions:**
- Count current players
- Compute lives and strikes based on player count (see Setup Configuration)
- Set round to 1
- Shuffle fresh deck (1-100)
- Immediately transition to Dealing Phase

**State:**
- Player count
- Lives (computed)
- Strikes (computed)
- Current round (1)
- Shuffled deck

### 1. Dealing Phase
**Purpose:** Prepare players for the current round

**Actions:**
- Deal each player N cards (where N = current round number)
- Players receive cards face-down and view them privately
- Display ready button for each player
- Wait for all players to indicate readiness
- Once all ready, send latency ping to all players before countdown
- Show countdown (3-2-1)
- During countdown: ready button disabled, server ignores unready requests
- Transition to Active Play Phase

**State:**
- Current round number
- Cards dealt to each player
- Ready status for each player
- Lives remaining
- Strikes remaining

### 2. Active Play Phase
**Purpose:** Play cards in ascending order

**Actions:**
- Players place one hand on table to focus (ceremonial start)
- Players can only play their lowest card
- Any player can play at any time
- Cards must be played in ascending order on central stack
- No communication about card values allowed
- Monitor for mistakes (played card is higher than another player's lowest card)
- Simultaneous plays: server uses latency compensation to resolve (see Mistake Detection)

**Mistake Detection (with Latency Resolution):**
- When a card is played that appears out of order, server enters MistakeResolution:
  1. Start buffer timer: `min(max(player_latencies) / 2, 500ms)`, default 300ms if no data
  2. Collect PlayCard messages in Dict keyed by `user_id` (deduplicates naturally)
  3. Block vote initiation (strike, abandon) during buffer window
  4. Ignore duplicate PlayCard from same user
  5. When timer expires:
     - Adjust timestamps: `effective_time = server_receive_time - (latency / 2)` (default latency: 25ms)
     - Tiebreaker for identical adjusted timestamps: FIFO (original arrival order)
     - Sort cards by adjusted timestamps
  6. Check if adjusted order is valid (ascending)
- If adjusted order is valid:
  - Apply all cards in adjusted order
  - Check if any player has card < new pile top
    - If yes → still a mistake (those players should have played)
    - If no → continue ActivePlay, check Round Completion
- If adjusted order invalid OR remaining lower cards exist:
  - Discard all cards lower than pile top
  - Lose one life (regardless of how many cards discarded)
  - If lives reach zero → End Game Phase (loss)
  - If all cards exhausted → check Round Completion (see below)
  - Otherwise → Pause Phase
- PlayCard messages during Pause phase → rejected

**Strike Usage:**
- Any player can initiate a strike vote
- Transitions to Strike Phase for voting

**Round Completion (all cards exhausted):**
- Apply reward milestones if applicable (bonus lives/stars)
- If final round completed → End Game Phase (win)
- Otherwise → increment round, transition to Dealing Phase

### 3. Pause Phase
**Purpose:** Recover from a mistake or regroup after strike vote

**Actions:**
- Display what went wrong (which card was played out of order) if after mistake
- Show remaining lives
- Display ready button for each player
- Wait for all players to indicate readiness
- Once all ready:
  - If only one player has cards → auto-play their cards, advance to Dealing (next round)
  - If multiple players have cards → send latency ping, show countdown (3-2-1), transition to Active Play
- During countdown: ready button disabled, server ignores unready requests

**State:**
- Lives remaining (already decremented during Mistake Detection)
- Cards still in each player's hand
- Current round number
- Ready status for each player

### 4. Strike Phase
**Purpose:** Collective vote to use a strike

**Entry:**
- Any player can initiate a strike vote during Active Play
- Requires at least one strike available
- Only one vote can be active at a time; server ignores duplicate initiation requests

**Actions:**
- Display voting UI to all players
- Each player votes: approve or reject
- 10-second countdown timer starts when phase begins
- Wait for all players to cast votes or timer expiration
- Players who haven't voted when timer expires default to approve

**Vote Success (all approve):**
- Strike is consumed
- Each player with cards discards their lowest card simultaneously
- Players with no cards remaining discard nothing
- Discarded cards are revealed to all players
- If all cards exhausted → check Round Completion (same logic as Active Play)
- Otherwise → Pause Phase (ready states reset, regroup before resuming)

**Vote Failure (any reject):**
- Strike is NOT consumed
- No cards are discarded
- Transition to Pause Phase (ready states reset, regroup before resuming)

**State:**
- Votes cast by each player (persisted across disconnection)
- Players who have not yet voted
- Vote timer remaining (starts at 10 seconds)
- Strikes remaining (decremented only on success)

**Reconnection:**
- Player's vote is preserved if they disconnect after voting
- Reconnecting player receives current vote state (who voted, time remaining)
- If player hasn't voted yet, they can still vote after reconnecting

### 5. Abandon Vote Phase
**Purpose:** Allow players to abandon the match (e.g., if a player permanently disconnects)

**Entry:**
- Any player can initiate an abandon vote
- Can be initiated from: Dealing, ActivePlay, or Pause phases
- Cannot be initiated during: Strike, AbandonVote, or EndGame phases
- Only one vote can be active at a time; server ignores duplicate initiation requests

**Actions:**
- Display voting UI to all players
- Each player votes: approve or reject
- 10-second countdown timer starts when phase begins
- Wait for all players to cast votes or timer expiration
- Players who haven't voted when timer expires default to approve

**Vote Success (all approve):**
- Transition to End Game Phase (abandoned)

**Vote Failure (any reject):**
- Return to previous phase (Dealing, ActivePlay, or Pause)

**State:**
- Votes cast by each player (persisted across disconnection)
- Players who have not yet voted
- Vote timer remaining (starts at 10 seconds)
- Previous phase (to return to on failure)

**Reconnection:**
- Player's vote is preserved if they disconnect after voting
- Reconnecting player receives current vote state (who voted, time remaining)
- If player hasn't voted yet, they can still vote after reconnecting

### 6. End Game Phase
**Purpose:** Show final game outcome

**Win Condition:**
- All rounds completed successfully
- Display victory message

**Loss Condition:**
- Team runs out of lives (reaches 0)
- Display defeat message

**Abandoned Condition:**
- Abandon vote passed
- Display abandoned message

**Actions:**
- Show final statistics (rounds completed, cards played, etc.)
- Display ready button for each player (similar to lobby)
- Display leave game button for each player
- When all remaining players are ready, host can start new game
- Starting new game transitions to Game Setup Phase (recomputes config for current player count)

**Leave Game (only available in End Game Phase):**
- Player is removed from the game/lobby and purged from server
- If host leaves, assign new host randomly from remaining players
- If all players leave, game is cleaned up

**Join Game (available in End Game Phase):**
- Game code remains shareable
- New players can join using the game code (same as lobby)
- Allows refilling slots after players leave
- Must have 2-4 players to restart

**State:**
- Game outcome (win/loss/abandoned)
- Ready status for each player
- Final game statistics
- Game code (still active for joining)

## Game Log
The game maintains a timestamped log of events for player reference. The log is displayed on all game phases and helps players understand what happened.

**Event Types:**
- **Round Started:** "Round N started"
- **Card Played:** "Alice played 42"
- **Mistake Discard:** "Mistake! Bob forced to discard 15"
- **Strike Used:** "Strike used! N remaining"
- **Strike Discard:** "Carol discarded 7 (star)"
- **Life Lost:** "Life lost! N remaining"

**Display Format:**
- Timestamps shown as seconds since game start (e.g., "12.50s")
- Events sorted chronologically
- Log clears on game restart

**Wire Format:**
- `game_start_timestamp` stored on Game type (set when game created from lobby)
- `game_log: List(GameEvent)` stored on Game type (newest first)
- Full log included in `GameStateUpdate` (for join/reconnect)
- Incremental `GameLogEvent` broadcast during play

## Key Rules

1. **No Communication:** Players cannot verbally or non-verbally signal card values
2. **No Turn Order:** Any player can play at any time
3. **Lowest Card Only:** Players can only play their lowest card
4. **Ascending Only:** Cards must be played in strictly ascending order
5. **Shared Lives:** The team shares a pool of lives
6. **Card Range:** Cards are numbered 1-100
7. **Strikes:** Limited resource for collective discarding of lowest cards
8. **Round Complete:** When all cards are exhausted (played or discarded), advance to next round or end game

