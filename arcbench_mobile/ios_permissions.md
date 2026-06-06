# iOS Permissions Setup

After running `flutter create .` in the arcbench_mobile directory, add these to `ios/Runner/Info.plist`:

```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>ArcBench uses speech recognition to let you dictate coding prompts.</string>
<key>NSMicrophoneUsageDescription</key>
<string>ArcBench needs microphone access for voice input.</string>
```

For Tailscale network access, add to Info.plist:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>ArcBench connects to your desktop over Tailscale VPN.</string>
```
