# WristChatUI

A private, bring-your-own-key AI chat client for iPhone and Apple Watch. Speaks OpenAI- and Anthropic-compatible APIs.

- **Download:** Search for **WristChatUI** on the App Store.
- **Website / Support:** <https://HaiGe120.github.io/WristChatUI/support.html>
- **Privacy Policy:** <https://HaiGe120.github.io/WristChatUI/privacy.html>

## Features

- Real Apple Watch app with native composer, dictation, and conversation history
- Multi-provider: any OpenAI- or Anthropic-compatible endpoint (OpenAI, Anthropic, MiniMax, Open WebUI, custom gateways)
- Apple Watch complications and Smart Stack widget for one-tap new chats
- Siri Shortcuts integration on iPhone and Watch
- iCloud Drive backup and restore of all conversations (opt-in)
- iOS Keychain for API keys, SwiftData for chat history, no telemetry

## Requirements

- iOS 26.0 or later (iPhone)
- watchOS 11.0 or later (Apple Watch)
- An API key for at least one OpenAI- or Anthropic-compatible provider

## Building

The project uses [xcodegen](https://github.com/yonaskolb/XcodeGen); the
`.xcodeproj` is generated from `project.yml`.

```bash
brew install xcodegen
xcodegen generate
```

For simulator work, use the wrapper script (see `AGENTS.md` for why):

```bash
scripts/sim.sh boot        # build, install, launch, screenshot
scripts/sim.sh teardown    # terminate + shut down
```

For direct `xcodebuild` against a real device, sign with your team and
archive the `WristAssistant` scheme.

## Privacy

WristChatUI does not collect analytics, telemetry, or any data on the developer's servers. API keys live in the iOS Keychain, conversations in a local SwiftData store, and the only network calls are to the endpoints you configure. See the [Privacy Policy](https://HaiGe120.github.io/WristChatUI/privacy.html).

## License

Source-available for noncommercial use. Commercial use requires prior written permission. See [LICENSE](LICENSE).
