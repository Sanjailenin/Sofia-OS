# Roadmap and known rough edges

An honest review of the first public build, with the changes that would make it faster, safer or simpler. Pull requests welcome on any of these.

## Done since 0.1.0

- 0.3.0: the project is SOFIA; users name the assistant and choose her voice in a first-run welcome window; the wake word, standby phrase, prompt, menus and Telegram replies follow the chosen name.

- Ollama's native `/api/chat` with thinking off for Mac-side turns (on for free-form phone requests), and streamed replies spoken sentence by sentence.
- Spotlight and the Shortcuts CLI run off the main actor; Keychain secrets are read once and cached.
- Pairing locks for an hour after five wrong codes; the Telegram poll backs off with jitter.
- Screen tasks (`computer_task`) with a local vision model, controls-first through the accessibility tree.
- Calendar awareness through EventKit: no entrance during a meeting, earlier battery nudge before one.
- The assistant turn, Telegram routing and the computer loop live in the core with tests against fakes.

## Efficiency

- **Spotlight queries** are built from up to six words with a content-type filter and run across all allowed roots at once. Fine for home folders; a cap on result count at the `mdfind` level (`-count` first, then query) would help very large volumes.
- **Vision model loading.** The first screen task after a while pays for loading the vision model into memory. Warming it when a task is likely (the user says "on the screen") would hide that.

## Robustness

- **Wake listener restarts.** Audio device changes stop the engine silently; the listener restarts after a second. Plugging in headphones mid-sentence still loses that sentence.
- **Model errors** surface as one spoken sentence. A retry with a smaller context when Ollama reports an out-of-memory error would help 8 GB Macs.

## Design

- **Two targets, one direction.** `SofiaCore` is pure and tested; `Sofia` touches the system. Keep it that way: anything new that can be a pure function with a test belongs in core. The state machine, the clap detector, the file policy and the command parser are the model to copy.
- **The controller** owns the voice loop; the phone channel lives in `PhoneChannel`. Standby could move out next.
- **One provider protocol** covers Ollama and OpenAI-compatible servers (LM Studio, llama.cpp, OpenAI), with streaming and a vision flag. Adding a provider is one struct.
- **Memory** is a JSON list of facts. It is deliberately simple and inspectable. If it grows, a small SQLite store with full-text search is the next step, not a vector database.

## Not yet

- **Screen reading** ("what does this say") is a short step from the computer loop: one screenshot to the vision model with the question.
- **Notarized builds.** The release is signed ad hoc. A Developer ID would remove the right-click-to-open step and the Keychain re-prompts after updates.

## Testing

87 tests cover the pure core, including the assistant turn, the Telegram router and the computer loop against fakes. Still missing: a `RemoteRunner.find` test against a temporary folder, which needs Spotlight indexing and so an integration-style test.
