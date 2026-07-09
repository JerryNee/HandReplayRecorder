#!/usr/bin/env python3
"""
Convert HandReplayRecorder .lpvt-handmotion.json files into a USDA skeleton preview.

This is a preview/bridge format, not final rig retargeting. The generated USDA
contains animated joint spheres and bone capsules in the LPVT manikin local
coordinate frame, so it can be inspected in Reality Composer Pro or loaded by
RealityKit as a reference animation.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

from pxr import Gf, Usd, UsdGeom, UsdShade, Sdf


BONE_PAIRS = [
    ("wrist", "thumbKnuckle"),
    ("thumbKnuckle", "thumbIntermediateBase"),
    ("thumbIntermediateBase", "thumbIntermediateTip"),
    ("thumbIntermediateTip", "thumbTip"),
    ("wrist", "indexFingerMetacarpal"),
    ("indexFingerMetacarpal", "indexFingerKnuckle"),
    ("indexFingerKnuckle", "indexFingerIntermediateBase"),
    ("indexFingerIntermediateBase", "indexFingerIntermediateTip"),
    ("indexFingerIntermediateTip", "indexFingerTip"),
    ("wrist", "middleFingerMetacarpal"),
    ("middleFingerMetacarpal", "middleFingerKnuckle"),
    ("middleFingerKnuckle", "middleFingerIntermediateBase"),
    ("middleFingerIntermediateBase", "middleFingerIntermediateTip"),
    ("middleFingerIntermediateTip", "middleFingerTip"),
    ("wrist", "ringFingerMetacarpal"),
    ("ringFingerMetacarpal", "ringFingerKnuckle"),
    ("ringFingerKnuckle", "ringFingerIntermediateBase"),
    ("ringFingerIntermediateBase", "ringFingerIntermediateTip"),
    ("ringFingerIntermediateTip", "ringFingerTip"),
    ("wrist", "littleFingerMetacarpal"),
    ("littleFingerMetacarpal", "littleFingerKnuckle"),
    ("littleFingerKnuckle", "littleFingerIntermediateBase"),
    ("littleFingerIntermediateBase", "littleFingerIntermediateTip"),
    ("littleFingerIntermediateTip", "littleFingerTip"),
]


def safe_name(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_]", "_", value)
    if not cleaned or cleaned[0].isdigit():
        cleaned = f"_{cleaned}"
    return cleaned


def matrix_position(matrix_payload) -> Gf.Vec3f:
    if isinstance(matrix_payload, list):
        if not matrix_payload:
            return Gf.Vec3f(0, 0, 0)
        if len(matrix_payload) == 1 and isinstance(matrix_payload[0], list):
            translation = matrix_payload[0]
            return Gf.Vec3f(float(translation[0]), float(translation[1]), float(translation[2]))
        if len(matrix_payload) == 3 and all(isinstance(value, (int, float)) for value in matrix_payload):
            return Gf.Vec3f(float(matrix_payload[0]), float(matrix_payload[1]), float(matrix_payload[2]))
    if isinstance(matrix_payload, dict):
        values = matrix_payload.get("values", [])
        if len(values) != 16:
            return Gf.Vec3f(0, 0, 0)
        return Gf.Vec3f(float(values[12]), float(values[13]), float(values[14]))
    return Gf.Vec3f(0, 0, 0)


def normalize_frames(recording: dict) -> list[dict]:
    frames = recording.get("frames", [])
    if not frames:
        return []

    joint_names = recording.get("joint_names", [])
    schema_version = int(recording.get("schema_version") or 1)
    first_frame = frames[0]

    if schema_version >= 2 and isinstance(first_frame, list):
        normalized = []
        for frame in frames:
            timestamp = float(frame[0])
            hands = []
            for hand in frame[1]:
                chirality = hand[0]
                is_tracked = bool(hand[1])
                joint_values = hand[2]
                manikin_from_joint = {}
                for index, joint_name in enumerate(joint_names):
                    if index >= len(joint_values):
                        continue
                    payload = joint_values[index]
                    if payload is None:
                        continue
                    manikin_from_joint[joint_name] = payload
                hands.append(
                    {
                        "chirality": chirality,
                        "is_tracked": is_tracked,
                        "manikin_from_joint": manikin_from_joint,
                    }
                )
            normalized.append({"timestamp": timestamp, "hands": hands})
        return normalized

    return frames


def vec_sub(a: Gf.Vec3f, b: Gf.Vec3f) -> Gf.Vec3f:
    return Gf.Vec3f(a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vec_add(a: Gf.Vec3f, b: Gf.Vec3f) -> Gf.Vec3f:
    return Gf.Vec3f(a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vec_mul(a: Gf.Vec3f, scalar: float) -> Gf.Vec3f:
    return Gf.Vec3f(a[0] * scalar, a[1] * scalar, a[2] * scalar)


def vec_length(a: Gf.Vec3f) -> float:
    return math.sqrt(float(a[0]) ** 2 + float(a[1]) ** 2 + float(a[2]) ** 2)


def vec_normalize(a: Gf.Vec3f) -> Gf.Vec3f:
    length = vec_length(a)
    if length <= 1e-8:
        return Gf.Vec3f(0, 0, 1)
    return vec_mul(a, 1.0 / length)


def quat_from_z_axis(direction: Gf.Vec3f) -> Gf.Quatf:
    source = Gf.Vec3f(0, 0, 1)
    target = vec_normalize(direction)
    dot = max(min(float(source[0] * target[0] + source[1] * target[1] + source[2] * target[2]), 1.0), -1.0)
    if dot > 0.999999:
        return Gf.Quatf(1, 0, 0, 0)
    if dot < -0.999999:
        return Gf.Quatf(0, 1, 0, 0)

    axis = Gf.Vec3f(-target[1], target[0], 0)
    axis = vec_normalize(axis)
    angle = math.acos(dot)
    half = angle * 0.5
    return Gf.Quatf(math.cos(half), axis[0] * math.sin(half), axis[1] * math.sin(half), axis[2] * math.sin(half))


def create_material(stage: Usd.Stage, path: str, color: tuple[float, float, float]) -> UsdShade.Material:
    material = UsdShade.Material.Define(stage, path)
    shader = UsdShade.Shader.Define(stage, f"{path}/PreviewSurface")
    shader.CreateIdAttr("UsdPreviewSurface")
    shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*color))
    shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.55)
    material.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), "surface")
    return material


def bind_material(prim: Usd.Prim, material: UsdShade.Material) -> None:
    UsdShade.MaterialBindingAPI(prim).Bind(material)


def sorted_hands(frame: dict) -> list[dict]:
    return sorted(frame.get("hands", []), key=lambda hand: hand.get("chirality", ""))


def build_usda(recording: dict, output_path: Path, coordinate_frame: str) -> None:
    frames = normalize_frames(recording)
    if not frames:
        raise ValueError("Recording has no frames.")

    fps = float(recording.get("nominal_frame_rate") or 60.0)
    duration = float(recording.get("duration") or frames[-1].get("timestamp", 0.0))
    end_time_code = max(1, int(round(duration * fps)))

    stage = Usd.Stage.CreateNew(str(output_path))
    stage.SetDefaultPrim(UsdGeom.Xform.Define(stage, "/LPVTHandMotion").GetPrim())
    stage.SetStartTimeCode(0)
    stage.SetEndTimeCode(end_time_code)
    stage.SetTimeCodesPerSecond(fps)
    stage.SetFramesPerSecond(fps)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)

    root = UsdGeom.Xform.Define(stage, "/LPVTHandMotion")
    root.GetPrim().SetMetadata("comment", "Generated from HandReplayRecorder JSON. Transforms are manikin-local unless another coordinate frame is selected.")

    materials_scope = UsdGeom.Scope.Define(stage, "/LPVTHandMotion/Materials")
    del materials_scope
    left_material = create_material(stage, "/LPVTHandMotion/Materials/LeftHandBlue", (0.1, 0.45, 1.0))
    right_material = create_material(stage, "/LPVTHandMotion/Materials/RightHandCyan", (0.0, 0.9, 0.75))
    bone_material = create_material(stage, "/LPVTHandMotion/Materials/BoneWhite", (0.85, 0.9, 1.0))

    joint_xforms: dict[tuple[str, str], UsdGeom.Xform] = {}
    bone_xforms: dict[tuple[str, str, str], UsdGeom.Xform] = {}

    for frame in frames:
        time_code = float(frame.get("timestamp", 0.0)) * fps
        for hand in sorted_hands(frame):
            chirality = safe_name(hand.get("chirality", "hand"))
            hand_scope_path = f"/LPVTHandMotion/{chirality}"
            UsdGeom.Xform.Define(stage, hand_scope_path)
            joints = hand.get(coordinate_frame, {})
            if not joints:
                continue

            positions = {name: matrix_position(payload) for name, payload in joints.items()}
            material = left_material if chirality == "left" else right_material

            for joint_name, pos in positions.items():
                key = (chirality, safe_name(joint_name))
                if key not in joint_xforms:
                    path = f"{hand_scope_path}/Joints/{key[1]}"
                    joint_xform = UsdGeom.Xform.Define(stage, path)
                    translate = joint_xform.AddTranslateOp()
                    sphere = UsdGeom.Sphere.Define(stage, f"{path}/Sphere")
                    sphere.CreateRadiusAttr(0.008)
                    bind_material(sphere.GetPrim(), material)
                    joint_xforms[key] = joint_xform
                    joint_xforms[(chirality, f"{key[1]}__translate")] = translate  # type: ignore[assignment]
                translate_op = joint_xforms[(chirality, f"{key[1]}__translate")]  # type: ignore[index]
                translate_op.Set(pos, time_code)

            for start_name, end_name in BONE_PAIRS:
                if start_name not in positions or end_name not in positions:
                    continue
                start = positions[start_name]
                end = positions[end_name]
                delta = vec_sub(end, start)
                length = vec_length(delta)
                if length <= 0.001:
                    continue

                start_safe = safe_name(start_name)
                end_safe = safe_name(end_name)
                key = (chirality, start_safe, end_safe)
                if key not in bone_xforms:
                    path = f"{hand_scope_path}/Bones/{start_safe}_to_{end_safe}"
                    bone_xform = UsdGeom.Xform.Define(stage, path)
                    translate = bone_xform.AddTranslateOp()
                    orient = bone_xform.AddOrientOp()
                    scale = bone_xform.AddScaleOp()
                    capsule = UsdGeom.Capsule.Define(stage, f"{path}/Capsule")
                    capsule.CreateAxisAttr("Z")
                    capsule.CreateHeightAttr(1.0)
                    capsule.CreateRadiusAttr(0.0035)
                    bind_material(capsule.GetPrim(), bone_material)
                    bone_xforms[key] = bone_xform
                    bone_xforms[(chirality, f"{start_safe}_to_{end_safe}", "translate")] = translate  # type: ignore[assignment]
                    bone_xforms[(chirality, f"{start_safe}_to_{end_safe}", "orient")] = orient  # type: ignore[assignment]
                    bone_xforms[(chirality, f"{start_safe}_to_{end_safe}", "scale")] = scale  # type: ignore[assignment]

                center = vec_mul(vec_add(start, end), 0.5)
                translate_op = bone_xforms[(chirality, f"{start_safe}_to_{end_safe}", "translate")]  # type: ignore[index]
                orient_op = bone_xforms[(chirality, f"{start_safe}_to_{end_safe}", "orient")]  # type: ignore[index]
                scale_op = bone_xforms[(chirality, f"{start_safe}_to_{end_safe}", "scale")]  # type: ignore[index]
                translate_op.Set(center, time_code)
                orient_op.Set(quat_from_z_axis(delta), time_code)
                scale_op.Set(Gf.Vec3f(1, 1, length), time_code)

    stage.GetRootLayer().Save()


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert .lpvt-handmotion.json to USDA skeleton preview animation.")
    parser.add_argument("input", type=Path, help="Input .lpvt-handmotion.json file")
    parser.add_argument("-o", "--output", type=Path, help="Output .usda path")
    parser.add_argument(
        "--frame",
        choices=["manikin_from_joint", "landmark_from_joint", "world_from_joint"],
        default="manikin_from_joint",
        help="Coordinate frame to export. Use manikin_from_joint for LPVT anchoring.",
    )
    args = parser.parse_args()

    input_path = args.input.expanduser().resolve()
    output_path = args.output.expanduser().resolve() if args.output else input_path.with_suffix(".usda")

    with input_path.open("r", encoding="utf-8") as file:
        recording = json.load(file)

    build_usda(recording, output_path, args.frame)
    print(output_path)


if __name__ == "__main__":
    main()
