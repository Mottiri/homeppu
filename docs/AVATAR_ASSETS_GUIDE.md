# Avatar Assets Guide

This guide explains how to add new avatar parts (hair / eyebrows / eyes / mouth).

## Requirements
- PNG with transparency
- 1024x1024 px
- File name matches the part id (e.g. `hair_03.png`)

## Folder structure
- `assets/avatars/hair/`
- `assets/avatars/eyebrows/`
- `assets/avatars/eyes/`
- `assets/avatars/mouth/`

## Add new assets
1) Place new PNGs in the matching folder.
2) Run the updater script:
```
python scripts/update_avatar_assets.py
```
3) Restart the app.

## Notes
- The script updates: `lib/core/constants/avatar_assets.dart`
- If you add a new folder, update `pubspec.yaml` under `assets:` and run `flutter pub get`.
