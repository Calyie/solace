# The app

Flutter, one code base for iOS, Android, macOS, Windows and Linux. `lib/core` holds the logic (formats shared
character for character with the training pipeline, the encrypted store, safety rules, the transfer file, deep work
mode, plans, questionnaires, sessions); `lib/ui` the screens; `test/` the unit, widget and screenshot tests.

```sh
flutter test
flutter analyze
dart run tool/full_mode_key.dart
flutter build <platform> --release --dart-define-from-file=<secrets>/therapist_full_mode_key.json
```

See the repository's README and docs/ for the design, security and configuration.

Fonts (`assets/fonts`, SIL Open Font License 1.1, each licence beside its files): Inter and Newsreader came from
google/fonts at commit `7af0d90b4d532ffa4b041937b560c6df4e7b1e95` (`ofl/inter/Inter[opsz,wght].ttf` as
`Inter-Variable.ttf`, SHA-256 `29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031`;
`ofl/newsreader/Newsreader[opsz,wght].ttf` as `Newsreader-Variable.ttf`, SHA-256
`8a08d13f8a6c0d51be379a60af84f945f65369a67e509ee3c3bdcc421254d7c1`). Figtree Regular and Bold remain only for the
PDF exports.
