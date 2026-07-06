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
7. Tap `Play` to replay the recorded virtual hand relative to the locked `AnchorToTrack`.
8. Tap `Export` to write a `.lpvt-handmotion.json` file to the app Documents folder, then use `Share Export`.

The simulator can build and open the app shell, but it cannot provide real hand tracking or object tracking data.

## Export

The exported JSON stores:

- TRS transforms as `[[translation_xyz], [rotation_xyzw]]`, not full 4x4 matrices.
- Joint transforms in the predefined `joint_names` array order, so joint names are stored once instead of repeated on every frame.
- `world_from_joint` data for debugging, `manikin_from_joint` data relative to LPVT `AnchorToTrack`, and optional `landmark_from_joint` data if the loaded asset exposes a `Landmark` entity.

Floating-point values are truncated to 4 decimal places to keep files smaller while retaining animation-scale motion detail.

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
