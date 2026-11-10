# Security

## Model

The model decides what to do; the app decides what is allowed. Every Mac action goes through a fixed list (`MacAction`) and is validated on its parameters before it runs. There is no shell execution, no arbitrary AppleScript, and no file is ever opened by a path the model made up if it looks like a program or script. Tool results are treated as data, and the prompt says so.

Screen control and typing refuse to act while a password manager, a terminal, a script editor, Shortcuts or System Settings is in front, so text on a web page cannot talk the model into running commands.

Remote commands from the phone are parsed deterministically; only free-form messages reach a model. Only one paired Telegram chat is answered, paired with a one-time code shown in Settings, and only from a private chat, never a group. Remote access has an off switch ("stop remote") and a rate limit. Files downloaded from the phone are marked as internet downloads, so Gatekeeper checks them like any other download.

The voice engine libraries are checked against SHA-256 sums built into the app before they are loaded, then loaded from a private copy, so a swapped library cannot borrow Sofia's microphone, Accessibility or Screen Recording permissions. The installer checks every download against a pinned SHA-256 or, for Ollama, its developer signature.

Files sent off the Mac pass `FilePolicy`: allowed roots only, symlinks resolved first, hidden paths and off-limits folders refused, secret-looking names and contents refused, size caps.

Keys and tokens are stored in the macOS Keychain under the app's own service name. Nothing is logged that contains them.

## Reporting

Open a private security advisory on the repository, or email the maintainers listed in the repository profile. Please do not file public issues for vulnerabilities. You will get an answer within a week.

## Out of scope

Behaviour of Ollama, Telegram, ElevenLabs or OpenAI themselves; a Mac that is already compromised; a user granting the paired chat to someone else.
