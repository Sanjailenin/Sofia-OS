# Privacy

Sofia is built to keep everything on your Mac.

**Stays on the Mac**
- Your voice. Wake-word detection, dictation and requests use Apple's on-device speech recognition. Audio is never written to disk and never sent anywhere.
- The model. Requests made at the Mac go to Ollama on localhost.
- Her voice. Replies are spoken by the Kokoro voice model running on the Mac. The installer downloads it once from the sherpa-onnx releases on GitHub; the app itself never fetches it.
- Hearing her name and your claps. The keyword spotter (downloaded with the voices) and macOS's built-in sound classifier run on the Mac and only ever see the last few seconds of microphone audio, in memory. Nothing is recorded or sent.
- Memory. Facts you ask her to remember live in `~/Library/Application Support/Sofia/memory.json`. Open it, edit it, delete it.
- Settings in the app's user defaults; keys and tokens in your macOS Keychain.
- The trigger log at `~/Library/Logs/Sofia/events.log`: what woke her (wake word, clap, hotkey, a phone message, a remote command) and the app that was in front. Never what you said. Capped at 200 KB.

**Leaves the Mac only when you set it up**
- Your own Telegram bot, through Telegram's API, for messages to and from your phone. Files and screenshots you ask for go into that chat.
- ElevenLabs, if you add a key: the sentences she speaks, for the premium voice.
- OpenAI, if you add a key: free-form messages from your phone and the tool results they need. Nothing said at the Mac goes there.

**Never**
- No telemetry, analytics, crash reporting or update checks. The app makes no connection you did not configure.
- No accounts. Nothing is stored on any server run by this project.

**Files sent to your phone** come only from the folders you allow. Hidden files, Library, SSH keys, keychains, environment files, anything named like a secret or whose first bytes look like a key, empty files and anything over 100 MB are refused.
