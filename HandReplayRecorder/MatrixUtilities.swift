import Foundation
import simd

func translationMatrix(_ translation: SIMD3<Float>) -> simd_float4x4 {
    var matrix = matrix_identity_float4x4
    matrix.columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1)
    return matrix
}

func position(from matrix: simd_float4x4) -> SIMD3<Float> {
    SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
}

func interpolatedTranslationMatrix(
    _ lhs: simd_float4x4,
    _ rhs: simd_float4x4,
    t: Float
) -> simd_float4x4 {
    translationMatrix(simd_mix(position(from: lhs), position(from: rhs), SIMD3<Float>(repeating: t)))
}

func clampedInterpolationFactor(
    currentTime: TimeInterval,
    start: TimeInterval,
    end: TimeInterval
) -> Float {
    guard end > start else { return 0 }
    let value = (currentTime - start) / (end - start)
    return Float(min(max(value, 0), 1))
}
