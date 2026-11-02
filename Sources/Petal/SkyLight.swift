import Foundation
import PetalCore

// Private SkyLight calls. There is no public API for Spaces; WhichSpace and
// Spaceman use the same three. They need no permissions.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") private func CGSGetActiveSpace(_ cid: Int32) -> Int
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?

enum SkyLight {
    static func read() -> (snapshot: SpacesSnapshot, activeID: Int) {
        let cid = CGSMainConnectionID()
        return (Spaces.parse(CGSCopyManagedDisplaySpaces(cid) as? [Any]), CGSGetActiveSpace(cid))
    }
}
