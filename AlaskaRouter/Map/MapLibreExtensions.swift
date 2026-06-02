//
//  MapLibreExtensions.swift
//  AlaskaRouter
//
//  Created by Mark Lifshits on 02/06/2026.
//
import MapLibreSwiftUI

extension CameraState {
    public var currentZoom: Double? {
        switch self {
        case let .centered(
            onCoordinate: coordinate,
            zoom: zoom,
            pitch: pitch,
            pitchRange: pitchRange,
            direction: direction
        ):
            return zoom

        case let .trackingUserLocation(zoom: zoom, pitch: _, pitchRange: _, direction: _):
            return zoom
        case let .trackingUserLocationWithHeading(zoom: zoom, pitch: _, pitchRange: _):
            return zoom
        case let .trackingUserLocationWithCourse(zoom: zoom, pitch: _, pitchRange: _):
            return zoom
        case let .rect(boundingBox: boundingBox, edgePadding: edgePadding):
            assertionFailure("Finding current zoom unsupported")
            return nil
        case let .showcase(shapeCollection: shapeCollection, edgePadding: edgePadding):
            assertionFailure("Finding current zoom unsupported")
            return nil
        }
    }
}
