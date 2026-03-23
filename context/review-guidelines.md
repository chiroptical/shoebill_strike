# Self-Review Guidelines

Guidelines for writing and reviewing code in Shoebill Strike codebase. These principles prioritize long-term readability and correctness over short-term convenience.

## Audience

These guidelines assume the reader is:
- Future-you in 6 months
- Engineers familiar with functional programming and dependency injection

Standard FP patterns (Result chaining, `use`, injected functions) don't need explanation. Domain-specific decisions do.

## Core Philosophy

**Parse, don't validate.** Use the type system to make illegal states unrepresentable. Push validation to system boundaries and work with strong types internally. See [Parse, Don't Validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/) for the full treatment.

**Every guideline is a trade-off.** These principles are heuristics, not laws. Each section includes trade-offs to consider. The goal is to make you *think* about the decision, not to prescribe an answer.

---

## 1. Extract Common Patterns (DRY as Trade-off)

**Guideline:** 3-4 repetitions is a signal to *consider* extraction, not an automatic trigger.

**The actual test:** Does extraction increase readability?

**Worthwhile extraction:**
- Names a meaningful concept
- Callers become simpler and clearer
- You can understand the caller without reading the helper's implementation

**Shallow extraction (avoid):**
- Needs flags, options, or callbacks to handle variations
- Callers still need to understand helper internals
- Just relocates code without simplifying reasoning

**Example of shallow extraction:**
```gleam
// 4 similar-but-different handlers might tempt you to write:
fn send_player_message(
  model: Model,
  message_type: String,
  extra_fields: List(#(String, Json)),
  state_update: Option(fn(Model) -> Model),
  side_effect: Option(Effect(Msg))
) -> #(Model, Effect(Msg))

// This is shallow: 5 parameters, optional callbacks, callers still
// need to understand all variations. No readability gain.
// Keep the 4 handlers separate.
```

**Ask yourself:** Is this abstraction deep (hides complexity) or shallow (just moves code around)?

---

## 2. Types Over Magic Defaults

**Guideline:** If a function has a catch-all case that "can't happen," use a type that eliminates it.

**Why:** The compiler enforces exhaustiveness. No dead code, no impossible defaults.

**Example:**
```gleam
// Before: magic default for impossible case
pub fn get_game_config(player_count: Int) -> #(Int, Int, Int) {
  case player_count {
    2 -> #(2, 1, 12)
    3 -> #(3, 1, 10)
    4 -> #(4, 1, 8)
    _ -> #(2, 1, 12)  // Why does this exist?
  }
}

// After: impossible case eliminated
pub type PlayerCount { Two Three Four }

pub fn get_game_config(player_count: PlayerCount) -> #(Int, Int, Int) {
  case player_count {
    Two -> #(2, 1, 12)
    Three -> #(3, 1, 10)
    Four -> #(4, 1, 8)
  }
}
```

**Questions to ask:**
- Does this type decrease the chance of bugs?
- Does it increase readability?
- Does it remove magic defaults?

If yes to any, consider a stronger type.

**Trade-offs:**
- Some constraints require dependent types (Gleam doesn't have these). Example: "list of length N" or "integer between 1 and 100" can't be enforced at compile time.
- Excessive enum variants can make pattern matching verbose. If you'd have 20 variants, reconsider.
- Types shared across module boundaries add coupling. Sometimes a simpler type with runtime validation at the boundary is pragmatic.

**Ask:** Can Gleam's type system actually express this constraint? If not, runtime validation may be the best option.

---

## 3. Parse, Don't Validate

**Guideline:** If a function's first action is validating or looking up an input, require the validated form as the parameter instead.

**Why:** Eliminates a nesting level. Makes preconditions explicit in the type signature. Callers can't forget to validate.

**Example:**
```gleam
// Before: validates inside
fn do_play_card(game: Game, user_id: String) -> Result(Game, String) {
  case get_game_player(game, user_id) {
    Error(_) -> Error("Player not found")
    Ok(player) ->
      case player.hand {
        // ... nested logic
      }
  }
}

// After: require validated input
fn do_play_card(game: Game, player: GamePlayer) -> Result(Game, String) {
  case player.hand {
    [] -> Error("Player has no cards")
    [lowest, ..rest] -> {
      // ... flatter logic
    }
  }
}
```

**Where does parsing live?**

Parsing happens at system boundaries (handlers). Domain logic receives validated types.

```
┌─────────────────────────────────────────────────┐
│  System Boundary (Handlers)                     │
│  - WebSocket handler                            │
│  - HTTP handler                                 │
│  - FFI boundary                                 │
│                                                 │
│  Parse here: JSON/strings → validated types     │
│  Return errors to client if invalid             │
└─────────────────────────────────────────────────┘
                      │
                      │ Validated types only
                      ▼
┌─────────────────────────────────────────────────┐
│  Internal Domain Logic                          │
│  - game.gleam                                   │
│  - lobby.gleam                                  │
│                                                 │
│  No parsing, no validation                      │
│  Functions receive strong types                 │
└─────────────────────────────────────────────────┘
```

**Trade-offs:**
- Parsing at boundaries can be expensive if the validated type requires significant computation. Sometimes lazy validation is pragmatic.
- Deeply nested validated types can make handler code verbose. Balance type safety with handler readability.
- When domain logic needs to construct new state (not just transform input), new invariants emerge mid-flow. These require validation where they arise, not just at boundaries.

**Ask:** Is this validation happening at a natural boundary, or am I contorting the code to push it upstream?

---

## 4. Data Structures Enforce Invariants

**Guideline:** Choose data structures whose shape makes illegal states unrepresentable.

**Why:** The structure itself prevents bugs. No defensive code needed.

| Need | Data Structure |
|------|----------------|
| Ordering only | List |
| Keyed access only | Dict |
| Uniqueness only | Set |
| Keyed access + ordering | Ordered Map |
| Uniqueness + ordering | Ordered Set |

**Example:**
```gleam
// Before: player could appear twice (bug possible)
type MistakeBuffer = List(#(UserId, Card, Timestamp))

// After: duplicate entries impossible by construction
type MistakeBuffer = Dict(UserId, #(Card, Timestamp))
```

This isn't about O(n) vs O(1). With 2-4 players, performance is irrelevant. It's about correctness.

**Trade-offs:**
- The "right" data structure might not exist in Gleam's standard library. Implementing or importing a dependency adds complexity.
- Some invariants are contextual. A `Dict` prevents duplicate keys globally, but what if duplicates are invalid only within a subset? The structure might not match the constraint.
- Ordered data structures may have worse performance characteristics. Usually irrelevant at small scale, but worth noting.

**Ask:** Does a data structure that enforces this invariant exist and is it worth the dependency/complexity?

---

## 5. Comments: Don't Speculate

**Guideline:** Delete comments that restate what code does. Keep comments that explain why. Never speculate about what you can't control.

**Pointless (restates the code):**
```gleam
/// Create a deck of cards from 1 to 100
pub fn create_deck() -> List(Card) {
  range_list(1, 100)
}
```

**Useful (names a concept the reader might not know):**
```gleam
/// Shuffle using Fisher-Yates algorithm
pub fn shuffle_deck(deck: List(Card), random_fn: fn(Int) -> Int) -> List(Card) {
```

**Dangerous (speculates about injected dependency):**
```gleam
/// random_fn takes an upper bound and returns a random int from 0 to upper_bound-1
pub fn shuffle_deck(deck: List(Card), random_fn: fn(Int) -> Int) -> List(Card) {
```

The type `fn(Int) -> Int` accepts *any* function. The comment makes promises the type system can't enforce. If someone passes a different function, the comment is a lie. **Don't document what you don't control.**

**Delete:**
- Restating the function name
- Speculating about injected dependencies
- Explaining standard FP patterns (audience knows them)

**Keep:**
- Algorithm names (Fisher-Yates, etc.)
- Domain-specific business rules ("Shoebill Strike rules require X")
- Historical context ("we do X because Y broke in production")

---

## 6. Reduce Nesting

**Guideline:** Deep nesting harms readability. Multiple tools are available; pick what fits.

| Tool | Pros | Cons |
|------|------|------|
| `use` | Flattens Result/Option chains | Forces error type unification |
| Extract functions | Names sub-operations, testable | Can fragment logic if overdone |
| Restructure inputs | Eliminates validation nesting | Pushes complexity to handlers |

**The goal is readability, not dogmatic use of any technique.**

`use` may require introducing a unified error type. Sometimes extracting a named function is cleaner than adding a wrapper type. Use judgment.

---

## 7. Private Trust, Public Defense

**Guideline:**
- Private helpers can trust their callers
- Public functions encode preconditions in types or return Result/Option

**Private (trust the caller):**
```gleam
// Called only from shuffle_deck with guaranteed valid indices
fn swap(arr: List(#(Int, Card)), i: Int, j: Int) -> List(#(Int, Card)) {
  // Can trust i and j are valid
}
```

**Public (defend the boundary):**
```gleam
// Caller might pass anything
pub fn get_game_player(game: Game, user_id: String) -> Result(GamePlayer, Nil) {
  // Must handle missing player
}

// Or better: require the validated type (parse, don't validate)
pub fn do_play_card(game: Game, player: GamePlayer) -> Result(Game, String)
```

**Trade-offs:**
- Module boundaries aren't always clean. A "private" helper might be called from multiple places within the module, some of which have weaker guarantees.
- Gleam's module system means "public" might mean "public to other modules in this package" not "public to external consumers." Calibrate defensiveness accordingly.
- Over-trusting private code can make refactoring dangerous. If you reorganize callers, assumptions may break silently.

**Ask:** How many places call this function, and do they all uphold the same invariants?

---

## 8. Trust But Verify (Error Handling)

**Guideline:** Private functions trust callers, but verify assumptions will catch bugs during development.

These are complementary, not contradictory:

| Concept | Meaning |
|---------|---------|
| **Trust** | Don't burden APIs with Result/Option for "impossible" cases |
| **Verify** | Use `let assert` so violated assumptions crash loudly in dev |

**Sensible default vs. placeholder:**

| Type | Example | Action |
|------|---------|--------|
| Sensible default | Empty list, None, 0 for sum | `result.unwrap(default)` is fine |
| Placeholder for "impossible" | `0` for Card (invalid value) | `let assert Ok(x) = ...` to crash |

A "sensible default" is semantically valid and produces correct behavior. A placeholder hides bugs - crash instead.

**Ask:**
- Is this an unlikely bug? Crash to catch it in dev/playtesting.
- Does a default make semantic sense? Use it.
- Should the caller decide? Return Result.

---

## 9. Boolean Blindness

**Guideline:** Booleans that leak to callers are suspect. Internal computation is fine.

| Context | Boolean OK? |
|---------|-------------|
| Internal to a function (intermediate computation) | Fine |
| Returns to caller | Suspect |
| Struct field | Suspect |
| Function parameter | Suspect |

**Why:** `True` and `False` carry no meaning without context. Callers must interpret.

**Hierarchy:**
1. **Best:** Semantic type (`ReadyState`, `Vote`, `Visibility`)
2. **Acceptable:** `is_x` function return consumed immediately
3. **Suspect:** `is_x` struct field (persists, checked repeatedly)
4. **Bad:** Unnamed boolean parameter

**Ask:** Could this expand to a third state?
- `is_ready: Bool` → `Ready | NotReady | Away`
- `is_connected: Bool` → `Connected | Disconnected | Reconnecting`
- `approve: Bool` → `Approve | Reject | Abstain`

Booleans lock you into two states. Semantic types are extensible.

**FFI exception:** In `.mjs` files, JavaScript primitives are unavoidable. Convert to semantic types as early as possible when crossing back into Gleam.

---

## 10. Minimal FFI

**Guideline:** FFI should be a thin adapter layer. Logic lives in Gleam.

| FFI (`.mjs`) | Gleam |
|--------------|-------|
| WebSocket connection setup | Message parsing/handling |
| DOM interop | All business logic |
| localStorage access | State management |
| Browser APIs | Type conversions |

**Why:** Gleam gives you type safety. JavaScript doesn't. Minimize the surface area where bugs can hide.

**Trade-offs:**
- Some browser APIs are awkward to wrap cleanly. Forcing Gleam types onto inherently dynamic JS APIs can create leaky abstractions.
- Performance-critical code might be faster in JS. Usually not relevant, but worth considering for hot paths.
- Complex async patterns (cancellation, racing) may be simpler to express in JS than in Gleam's effect system.

**Ask:** Is the Gleam version genuinely better, or am I adding a layer just to say "it's in Gleam"?

---

## 11. Types Must Earn Their Place

**Guideline:** Add wrapper types and enums when they provide value. The count doesn't matter; each type must justify itself.

**Questions to ask:**
- Are we eliminating possible bugs? (e.g., `PlayerCount` prevents invalid counts)
- Are we increasing readability? (e.g., `Role` clearer than `is_creator: Bool`)
- Are we preventing API misuse? (e.g., newtypes prevent parameter ordering errors)

If no to all three, skip the wrapper.

**Example - justified newtypes:**
```gleam
// Easy to mix up
fn create_player(id: String, user_id: String, nickname: String)

// Newtypes prevent mistakes
type PlayerId { PlayerId(String) }
type UserId { UserId(String) }
type Nickname { Nickname(String) }

fn create_player(id: PlayerId, user_id: UserId, nickname: Nickname)
```

50 types that each prevent bugs is fine. 5 types that add ceremony without benefit is too many.

---

## Summary Checklist

When reviewing code, ask:

- [ ] Is there a repeated pattern? Does extracting it *increase* readability, or just relocate code?
- [ ] Are there magic defaults for "impossible" cases? Can a type eliminate them, or is the constraint beyond Gleam's type system?
- [ ] Is the function validating inputs it could require as stronger types? Or would pushing validation upstream contort the code?
- [ ] Does the data structure prevent illegal states? Does such a structure exist without excessive complexity?
- [ ] Do comments explain *why*? Are any speculating about things we don't control?
- [ ] Is nesting depth reasonable?
- [ ] Does parsing happen at handlers, with domain logic receiving validated types? Are there mid-flow invariants that need validation where they arise?
- [ ] For private code: trust caller, but verify with `let assert` for unlikely bugs? How many callers, and do they all uphold the invariants?
- [ ] Are there booleans leaking to callers? Could they become a third state?
- [ ] Is FFI code minimal? Or is the Gleam wrapper adding complexity without benefit?
- [ ] Does each type earn its place (prevents bugs, increases readability, clarifies API)?

**Every guideline is a trade-off.** Apply judgment, not rules.
