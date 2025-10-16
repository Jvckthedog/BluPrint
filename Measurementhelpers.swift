//
//  Measurementhelpers.swift
//  TakeoffApp
//
//  Created by Work on 10/10/25.
//


import CoreGraphics
import Foundation

// distance in points between two page points
func pointsDistance(_ a: CGPoint, _ b: CGPoint) -> Double {
    let dx = Double(a.x - b.x)
    let dy = Double(a.y - b.y)
    return sqrt(dx*dx + dy*dy)
}

// convert points -> drawing inches
func pointsToInches(_ points: Double) -> Double {
    return points / 72.0
}

// convert points -> real feet given feetPerInch (user scale "1 in = feetPerInch ft")
func pointsToRealFeet(_ points: Double, feetPerInch: Double) -> Double {
    let inches = pointsToInches(points)
    return inches * feetPerInch
}

// polygon area (shoelace) returns area in points^2
func polygonAreaPoints(_ pts: [CGPoint]) -> Double {
    guard pts.count >= 3 else { return 0.0 }
    var sum = 0.0
    for i in 0..<pts.count {
        let j = (i + 1) % pts.count
        sum += Double(pts[i].x * pts[j].y - pts[j].x * pts[i].y)
    }
    return abs(sum) / 2.0
}

// convert area in points^2 -> square feet, given feetPerInch
func areaPointsToSqFt(_ areaPoints: Double, feetPerInch: Double) -> Double {
    // areaPoints -> drawing square inches
    let areaSquareInches = areaPoints / (72.0 * 72.0)
    // each drawing square inch corresponds to (feetPerInch)^2 square feet
    return areaSquareInches * (feetPerInch * feetPerInch)
}

// cubic yards given area in square feet and thickness in inches
func areaSqFtToCubicYards(areaSqFt: Double, thicknessInches: Double) -> Double {
    let thicknessFeet = thicknessInches / 12.0
    let volumeCubicFeet = areaSqFt * thicknessFeet
    return volumeCubicFeet / 27.0
}