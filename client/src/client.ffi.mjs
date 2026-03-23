import {
  Ok,
  Error as GleamError,
  toList,
} from "../gleam_stdlib/gleam.mjs";
import {
  GameCreated,
  GameJoined,
  LobbyState,
  GameStarted,
  ServerError,
  Lobby,
  Player,
  GameStateUpdate,
  CountdownTick,
  PhaseTransition,
  Game,
  GamePlayer,
  MistakeInfo,
  Dealing,
  ActivePlay,
  Pause,
  Strike,
  AbandonVote,
  StrikeVoteUpdate,
  AbandonVoteUpdate,
  EndGame,
  Win,
  Loss,
  Abandoned,
  PlayerLeft,
  YouLeft,
  GameLogEvent,
  GameEvent,
  RoundStarted,
  CardPlayed,
  MistakeDiscard,
  StrikeDiscard,
  LifeLost,
  StrikeUsed,
  PlayerDisconnected,
  PlayerReconnected,
  PlayerDisconnectedEvent,
  PlayerReconnectedEvent,
} from "../shared/protocol/types.mjs";
import { from_unix_seconds_and_nanoseconds } from "../gleam_time/gleam/time/timestamp.mjs";
import {
  Some,
  None,
} from "../gleam_stdlib/gleam/option.mjs";
import { server_message } from "./client.mjs";

let ws = null;
let dispatch = null;

function parseOutcome(outcomeStr) {
  switch (outcomeStr) {
    case "win":
      return new Win();
    case "loss":
      return new Loss();
    case "abandoned":
      return new Abandoned();
    default:
      console.warn("[Client FFI] Unknown outcome:", outcomeStr);
      return new Loss();
  }
}

function parsePhase(phaseData) {
  console.log("[Client FFI] Parsing phase:", phaseData);
  if (typeof phaseData === "object" && phaseData !== null) {
    if (phaseData.type === "end_game") {
      return new EndGame(parseOutcome(phaseData.outcome));
    }
    console.warn("[Client FFI] Unknown phase object:", phaseData);
    return new Dealing();
  }
  switch (phaseData) {
    case "dealing":
      return new Dealing();
    case "active_play":
      return new ActivePlay();
    case "pause":
      return new Pause();
    case "strike":
      return new Strike();
    case "abandon_vote":
      return new AbandonVote();
    default:
      console.warn("[Client FFI] Unknown phase:", phaseData);
      return new Dealing();
  }
}

function parseTimestamp(ms) {
  // Convert Unix milliseconds to Timestamp
  const seconds = Math.floor(ms / 1000);
  const nanos = (ms % 1000) * 1_000_000;
  return from_unix_seconds_and_nanoseconds(seconds, nanos);
}

function parseGameEventType(eventData) {
  switch (eventData.event_type) {
    case "round_started":
      return new RoundStarted(eventData.round);
    case "card_played":
      return new CardPlayed(eventData.player_nickname, eventData.card, eventData.autoplayed || false);
    case "mistake_discard":
      return new MistakeDiscard(eventData.player_nickname, eventData.card);
    case "strike_discard":
      return new StrikeDiscard(eventData.player_nickname, eventData.card);
    case "life_lost":
      return new LifeLost(eventData.lives_remaining);
    case "strike_used":
      return new StrikeUsed(eventData.strikes_remaining);
    case "player_disconnected":
      return new PlayerDisconnectedEvent(eventData.nickname);
    case "player_reconnected":
      return new PlayerReconnectedEvent(eventData.nickname);
    default:
      console.warn("[Client FFI] Unknown event type:", eventData.event_type);
      return new RoundStarted(0);
  }
}

function parseGameEvent(eventData) {
  const timestamp = parseTimestamp(eventData.timestamp);
  const eventType = parseGameEventType(eventData);
  return new GameEvent(timestamp, eventType);
}

export function connectWebSocket(dispatchFn) {
  dispatch = dispatchFn;

  // Build WebSocket URL from current location
  // Source: https://stackoverflow.com/a/6042031 (CC BY-SA 4.0)
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  const wsUrl = `${protocol}//${window.location.host}/ws`;

  console.log("[Client FFI] Connecting to WebSocket:", wsUrl);
  ws = new WebSocket(wsUrl);

  ws.onopen = function () {
    console.log("[Client FFI] WebSocket connected");
  };

  ws.onmessage = function (event) {
    console.log("[Client FFI] Received message:", event.data);
    const msg = JSON.parse(event.data);
    handleServerMessage(msg);
  };

  ws.onerror = function (error) {
    console.error("[Client FFI] WebSocket error:", error);
    console.error("[Client FFI] WebSocket readyState:", ws?.readyState);
  };

  ws.onclose = function () {
    console.log("[Client FFI] WebSocket closed");
  };
}

function handleServerMessage(msg) {
  let serverMsg;

  switch (msg.type) {
    case "game_created":
      serverMsg = new GameCreated(msg.code);
      break;

    case "game_joined":
      serverMsg = new GameJoined();
      break;

    case "lobby_state":
      const players = toList(
        msg.lobby.players.map(
          (p) =>
            new Player(p.user_id, p.nickname, p.is_ready, p.is_creator, p.is_connected ?? true)
        )
      );
      const lobby = new Lobby(msg.lobby.code, players, msg.lobby.games_played || 0);
      serverMsg = new LobbyState(lobby);
      break;

    case "game_started":
      serverMsg = new GameStarted();
      break;

    case "error":
      serverMsg = new ServerError(msg.message);
      break;

    case "game_state_update":
      console.log("[Client FFI] Parsing game_state_update:", msg.game);
      try {
        const gameData = msg.game;
        console.log("[Client FFI] Game has", gameData.players.length, "players");
        const gamePlayers = toList(
          gameData.players.map((p) => {
            console.log(
              "[Client FFI] Player",
              p.nickname,
              "has",
              p.hand.length,
              "cards, ready:",
              p.is_ready
            );
            return new GamePlayer(
              p.user_id,
              p.nickname,
              toList(p.hand),
              p.is_ready,
              p.is_connected ?? true,
              p.last_card_played != null ? new Some(p.last_card_played) : new None()
            );
          })
        );
        const phase = parsePhase(gameData.phase);
        let lastMistake;
        if (gameData.last_mistake) {
          const m = gameData.last_mistake;
          lastMistake = new Some(
            new MistakeInfo(
              m.player_nickname,
              m.played_card,
              toList(m.mistake_cards.map((mc) => [mc.nickname, mc.card]))
            )
          );
        } else {
          lastMistake = new None();
        }
        let previousPhase;
        if (gameData.abandon_vote_previous_phase) {
          previousPhase = new Some(parsePhase(gameData.abandon_vote_previous_phase));
        } else {
          previousPhase = new None();
        }
        // Parse game_start_timestamp and game_log
        const gameStartTimestamp = parseTimestamp(gameData.game_start_timestamp || 0);
        const gameLog = toList(
          (gameData.game_log || []).map((e) => parseGameEvent(e))
        );
        const gameState = new Game(
          gameData.code,
          gameData.host_user_id,
          gameData.games_played,
          gamePlayers,
          gameData.current_round,
          gameData.total_rounds,
          gameData.lives,
          gameData.strikes,
          phase,
          toList(gameData.played_cards),
          lastMistake,
          previousPhase,
          gameStartTimestamp,
          gameLog
        );
        serverMsg = new GameStateUpdate(gameState);
        console.log("[Client FFI] Successfully parsed game state with", gameData.game_log?.length || 0, "log events");
      } catch (e) {
        console.error("[Client FFI] Error parsing game_state_update:", e);
        return;
      }
      break;

    case "countdown_tick":
      serverMsg = new CountdownTick(msg.seconds);
      break;

    case "phase_transition":
      const transitionPhase = parsePhase(msg.phase);
      serverMsg = new PhaseTransition(transitionPhase);
      break;

    case "strike_vote_update":
      try {
        const votes = toList(
          msg.votes.map((v) => [v.user_id, v.approve])
        );
        const pending = toList(msg.pending);
        serverMsg = new StrikeVoteUpdate(
          votes,
          pending,
          msg.seconds_remaining
        );
      } catch (e) {
        console.error(
          "[Client FFI] Error parsing strike_vote_update:",
          e
        );
        return;
      }
      break;

    case "abandon_vote_update":
      try {
        const votes = toList(
          msg.votes.map((v) => [v.user_id, v.approve])
        );
        const pending = toList(msg.pending);
        serverMsg = new AbandonVoteUpdate(
          votes,
          pending,
          msg.seconds_remaining
        );
      } catch (e) {
        console.error(
          "[Client FFI] Error parsing abandon_vote_update:",
          e
        );
        return;
      }
      break;

    case "player_left":
      serverMsg = new PlayerLeft(
        msg.user_id,
        msg.new_host_user_id ? new Some(msg.new_host_user_id) : new None()
      );
      break;

    case "you_left":
      serverMsg = new YouLeft();
      break;

    case "game_log_event":
      try {
        const event = parseGameEvent(msg.event);
        serverMsg = new GameLogEvent(event);
        console.log("[Client FFI] Parsed game log event");
      } catch (e) {
        console.error("[Client FFI] Error parsing game_log_event:", e);
        return;
      }
      break;

    case "player_disconnected":
      serverMsg = new PlayerDisconnected(msg.user_id);
      console.log("[Client FFI] Player disconnected:", msg.user_id);
      break;

    case "player_reconnected":
      serverMsg = new PlayerReconnected(msg.user_id);
      console.log("[Client FFI] Player reconnected:", msg.user_id);
      break;

    default:
      console.warn("[Client FFI] Unknown message type:", msg.type);
      return;
  }

  // Use the helper function to create the Msg variant
  console.log("[Client FFI] Dispatching server message:", serverMsg);
  dispatch(server_message(serverMsg));
}

export function sendMessage(message) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    const jsonString = JSON.stringify(message);
    console.log("[Client FFI] Sending message:", jsonString);
    ws.send(jsonString);
  } else {
    console.error(
      "[Client FFI] Cannot send - WebSocket not ready. State:",
      ws?.readyState
    );
  }
}

export function getOrCreateUserId() {
  let userId = localStorage.getItem("shoebill_strike_user_id");
  if (userId) {
    console.log("[Client FFI] Loaded user ID from localStorage:", userId);
    return userId;
  }

  // Generate a simple UUID v4
  userId = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (
    c
  ) {
    const r = (Math.random() * 16) | 0;
    const v = c == "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });

  localStorage.setItem("shoebill_strike_user_id", userId);
  console.log("[Client FFI] Generated new user ID:", userId);
  return userId;
}

export function saveGameToStorage(code, userId, nickname) {
  const gameData = {
    code: code,
    userId: userId,
    nickname: nickname,
  };
  localStorage.setItem("shoebill_strike_game", JSON.stringify(gameData));
  console.log("[Client FFI] Saved game to localStorage:", gameData);
}

export function copyToClipboard(text) {
  navigator.clipboard.writeText(text).then(
    () => console.log("[Client FFI] Copied to clipboard:", text),
    (err) => console.error("[Client FFI] Failed to copy to clipboard:", err)
  );
}

export function clearSavedGame() {
  localStorage.removeItem("shoebill_strike_game");
  console.log("[Client FFI] Cleared saved game");
}

// Button click debounce - prevents rapid double-clicks
// Uses global event capture to intercept clicks before Lustre handlers.
// WeakMap keyed by DOM element auto-cleans when elements are removed.
const DEBOUNCE_MS = 300;
const lastClickTimes = new WeakMap();

function setupClickDebounce() {
  document.addEventListener(
    "click",
    (event) => {
      const button = event.target.closest(".btn");
      if (!button) return;

      const now = Date.now();
      const lastClick = lastClickTimes.get(button) || 0;

      if (now - lastClick < DEBOUNCE_MS) {
        event.stopPropagation();
        event.preventDefault();
        console.log("[Client FFI] Debounced rapid click");
        return;
      }

      lastClickTimes.set(button, now);
    },
    true // Use capture phase to intercept before Lustre handlers
  );
}

// Set up click debounce when DOM is ready
if (typeof window !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", setupClickDebounce);
  } else {
    setupClickDebounce();
  }
}

// Auto-scroll game log to bottom when content changes
function setupGameLogAutoScroll() {
  // Watch the entire document for any DOM changes
  const observer = new MutationObserver(() => {
    const gameLog = document.getElementById("game-log");
    if (gameLog) {
      gameLog.scrollTop = gameLog.scrollHeight;
    }
  });

  // Observe body for all changes (game-log may appear/disappear)
  observer.observe(document.body, { childList: true, subtree: true });
}

// Set up auto-scroll when the DOM is ready
if (typeof window !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", setupGameLogAutoScroll);
  } else {
    setupGameLogAutoScroll();
  }
}

export function checkSavedGame(dispatchFn) {
  setTimeout(function () {
    const savedGame = localStorage.getItem("shoebill_strike_game");
    if (savedGame) {
      console.log("[Client FFI] Found saved game in localStorage");
      try {
        const game = JSON.parse(savedGame);
        console.log(
          "[Client FFI] Attempting to rejoin game:",
          game.code,
          "with user_id:",
          game.userId
        );

        // Send join game message
        const message = {
          type: "join_game",
          code: game.code,
          user_id: game.userId,
          nickname: game.nickname,
        };

        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify(message));
        } else {
          console.warn(
            "[Client FFI] WebSocket not ready yet, cannot rejoin automatically"
          );
        }
      } catch (e) {
        console.error("[Client FFI] Failed to parse saved game:", e);
        localStorage.removeItem("shoebill_strike_game");
      }
    } else {
      console.log("[Client FFI] No saved game found");
    }
  }, 100);
}

export function dispatchAfterMs(dispatchFn, msg, ms) {
  setTimeout(() => dispatchFn(msg), ms);
}

export function getOrigin() {
  return window.location.origin;
}
