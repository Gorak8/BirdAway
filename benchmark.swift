import Foundation

struct AudioDevice {
    let uid: String
}

let N = 2000
let M = 2000
let before = (0..<N).map { AudioDevice(uid: "device-\($0)") }
let after = (N/2..<N+M/2).map { AudioDevice(uid: "device-\($0)") }

// Array approach
let start1 = DispatchTime.now()
var missing1 = 0
for old in before where !after.contains(where: { $0.uid == old.uid }) {
    missing1 += 1
}
let end1 = DispatchTime.now()
let time1 = Double(end1.uptimeNanoseconds - start1.uptimeNanoseconds) / 1_000_000

// Set approach
let start2 = DispatchTime.now()
var missing2 = 0
let afterUIDs = Set(after.map { $0.uid })
for old in before where !afterUIDs.contains(old.uid) {
    missing2 += 1
}
let end2 = DispatchTime.now()
let time2 = Double(end2.uptimeNanoseconds - start2.uptimeNanoseconds) / 1_000_000

print("Array approach: \(time1) ms, missing: \(missing1)")
print("Set approach: \(time2) ms, missing: \(missing2)")
