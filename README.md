# HandReplayRecorder

Standalone visionOS prototype for recording Apple Vision Pro hand tracking data relative to the LPVT manikin.

The repo includes a minimal local `RealityKitContent` package with only the LPVT simulator reference object and the `AnchorToTrack` / `Landmark` coordinate structure needed by this recorder. It does not vendor the full LPVT asset package.

## Workflow

1. Open `HandReplayRecorder.xcodeproj`.
2. Run the `HandReplayRecorder` scheme on a physical Apple Vision Pro.
3. Tap `Open Space`.
4. Tap `Find Manikin` and look at the LPVT simulator until the app reports that the manikin is found.
5. Tap `Lock Manikin Anchor`.
6. Tap `Record`, perform the hand motion, then tap `Stop`.
7. Tap `Play` to replay the recorded virtual hand relative to the locked `AnchorToTrack`. Replay renders realistic skinned hand meshes (WebXR `generic-hand` models, Apache-2.0, see `THIRD_PARTY_LICENSES.md`) driven by the recorded joint positions; if the models fail to load it falls back to a procedural low-poly hand.
8. Tap `Export` to write a `.lpvt-handmotion.json` file to the app Documents folder, then use `Share Export`.

The simulator can build and open the app shell, but it cannot provide real hand tracking or object tracking data.

## Export

The exported JSON (schema v2) stores:

- `manikin_from_joint` only — the LPVT-local joint positions needed for replay and import.
- Joint positions as compact `[x, y, z]` arrays in the shared `joint_names` order (0.1 mm precision).
- Frames as `[timestamp, hands]` arrays instead of repeated per-joint dictionaries.
- Adaptive keyframe thinning on export: static poses collapse to fewer frames, but motion is preserved at up to 60 Hz and never sparser than 40 Hz equivalent spacing.

In-app recording and playback still use the full 60 Hz capture. Thinning applies only to the exported file, so replay smoothness in the app is unchanged.

Future LPVT import should attach a replay/hand rig entity under `AnchorToTrack` and drive it from `manikin_from_joint`, not from recording-time world coordinates.

## Convert JSON to USDA Preview

Use the converter script for a quick animated skeleton preview:

```sh
python3 Tools/convert_lpvt_handmotion_to_usda.py /path/to/LPVT-HandMotion.lpvt-handmotion.json \
  -o /path/to/LPVT-HandMotion.usda
```

The default export uses `manikin_from_joint`, which is the right coordinate frame for anchoring under LPVT `AnchorToTrack`.

This produces animated joint spheres and bone capsules. It is not final hand-model retargeting.

## Precision

This tool reproduces ARKit-estimated hand poses. It is useful for prototyping and animation reference, but it is not a millimeter-accurate medical motion-capture system.
