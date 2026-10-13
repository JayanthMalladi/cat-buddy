// Drives a running CampusCat on the CI Mac: hovers over and drags the cat, waits for a walk, and saves
// screenshots, so the app can be looked at without owning a Mac.
// Usage: swift tools/ui_check.swift <pid> <output dir>
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 3, let pid = Int(args[1]) else {
    print("usage: ui_check.swift <pid> <output dir>")
    exit(2)
}
let outDir = args[2]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

/// The cat window's bounds in global top-left coordinates (the biggest window the app owns).
func catBounds() -> CGRect? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list
        .filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid }
        .compactMap { info -> CGRect? in
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: dict as CFDictionary)
        }
        .filter { $0.height > 100 }
        .max { $0.width * $0.height < $1.width * $1.height }
}

func wait(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func shot(_ name: String, around rect: CGRect? = nil) {
    var arguments = ["-x"]
    if let r = rect {
        // Leave room above the cat for the speech bubble.
        let area = r.insetBy(dx: -160, dy: 0).union(r.offsetBy(dx: 0, dy: -170))
        arguments.append("-R\(Int(area.minX)),\(Int(area.minY)),\(Int(area.width)),\(Int(area.height))")
    }
    arguments.append("\(outDir)/\(name).png")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = arguments
    try? task.run()
    task.waitUntilExit()
    print("saved \(name).png")
}

/// A point on the cat's body: middle of the window, a bit below centre.
func catPoint(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.minY + r.height * 0.65) }

/// Moves the pointer off the cat and back onto her, and rests it there.
func hover(_ r: CGRect) {
    post(.mouseMoved, CGPoint(x: r.minX - 200, y: r.midY))
    wait(0.4)
    post(.mouseMoved, catPoint(r))
    wait(0.8)   // the app wants the pointer to rest on her for 0.4 s
}

var bounds: CGRect?
for _ in 0..<20 where bounds == nil {
    bounds = catBounds()
    if bounds == nil { wait(0.5) }
}
guard var cat = bounds else {
    print("FAIL: no cat window found")
    exit(1)
}
print("cat window at \(cat)")

wait(2)
shot("01-sleeping", around: cat)
shot("00-whole-screen")

hover(cat)
wait(1)
shot("02-waking", around: cat)
wait(4)
shot("03-first-action", around: cat)
wait(6)

// A few more random actions.
for round in 1...6 {
    cat = catBounds() ?? cat
    hover(cat)
    wait(1.5)
    shot(String(format: "%02d-reaction-%d-a", 3 + round, round), around: cat)
    wait(2)
    shot(String(format: "%02d-reaction-%d-b", 3 + round, round), around: cat)
    wait(2.5)
}

// Wait for her routine to finish so she's asleep again before the drag.
wait(20)

// Drag the cat up and to the left, then check the window really moved.
cat = catBounds() ?? cat
let start = catPoint(cat)
post(.mouseMoved, start)
wait(0.3)
post(.leftMouseDown, start)
for step in 1...30 {
    post(.leftMouseDragged, CGPoint(x: start.x - CGFloat(step) * 10, y: start.y - CGFloat(step) * 6))
    wait(0.02)
}
post(.leftMouseUp, CGPoint(x: start.x - 300, y: start.y - 180))
wait(1)
let after = catBounds() ?? cat
shot("20-after-drag-whole-screen")
let moved = hypot(after.minX - cat.minX, after.minY - cat.minY)
print("drag moved the cat by \(Int(moved)) points (expected about 350)")

// Dragging from a transparent corner of the window must not move the cat.
let corner = CGPoint(x: after.maxX - 4, y: after.minY + 4)
post(.mouseMoved, corner)
wait(0.3)
post(.leftMouseDown, corner)
for step in 1...10 { post(.leftMouseDragged, CGPoint(x: corner.x - CGFloat(step) * 10, y: corner.y)); wait(0.02) }
post(.leftMouseUp, CGPoint(x: corner.x - 100, y: corner.y))
wait(0.5)
let afterCorner = catBounds() ?? after
let cornerMoved = hypot(afterCorner.minX - after.minX, afterCorner.minY - after.minY)
print("dragging the empty corner moved the cat by \(Int(cornerMoved)) points (expected 0)")

// CI sets walkEverySeconds to 150, so a walk comes due soon after the checks above.
// Wait for her to set off on her own, then for her to stop on the other side.
post(.mouseMoved, CGPoint(x: 400, y: 5))   // off the cat
let beforeWalk = catBounds() ?? afterCorner
var walkStarted = false
var lastX = beforeWalk.minX
var stillFor = 0
for _ in 0..<180 {
    wait(1)
    guard let now = catBounds() else { continue }
    if !walkStarted && abs(now.minX - beforeWalk.minX) > 20 {
        walkStarted = true
        shot("21-walking", around: now)
    }
    stillFor = abs(now.minX - lastX) < 1 ? stillFor + 1 : 0
    lastX = now.minX
    if walkStarted && stillFor >= 3 { break }
}
let afterWalk = catBounds() ?? beforeWalk
shot("22-after-walk-whole-screen")
let walked = abs(afterWalk.minX - beforeWalk.minX)
print("the walk moved the cat by \(Int(walked)) points sideways and \(Int(abs(afterWalk.minY - beforeWalk.minY))) up or down")

var failed = false
if moved < 200 { print("FAIL: dragging the cat did not move it"); failed = true }
if cornerMoved > 1 { print("FAIL: the transparent corner caught the mouse"); failed = true }
if walked < 200 { print("FAIL: she didn't walk across the screen"); failed = true }
if abs(afterWalk.minY - beforeWalk.minY) > 1 { print("FAIL: walking moved her up or down"); failed = true }
print(failed ? "UI check failed" : "UI check passed")
exit(failed ? 1 : 0)
