# Contributing

- Run `scripts/test.sh` before opening a pull request. Pure logic goes in `SofiaCore` with a test; anything touching AppKit, the microphone or the screen goes in `Sofia`.
- New Mac actions are added to `MacAction.Kind` with a validation case, a summary, a `MacRunner` case and a test. Nothing may run a shell command or an arbitrary script.
- No telemetry, no network calls the user did not configure, no secrets in code or tests. CI runs gitleaks on every push.
- Keep the code free of comments; make names say what things are.
