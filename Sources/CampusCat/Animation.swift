import AppKit
import ImageIO

/// The cat's states. Each one has an entry with the same name in animations.json.
enum CatState: String, CaseIterable {
    case curledSleeping, stretching, yawning, curious, happy, awake, resting, walking
}

/// One entry of animations.json.
struct AnimationSpec: Decodable {
    /// Folder under Resources/Animations holding frame_000.png, frame_001.png, ...
    let folder: String
    let fps: Double
    let loop: Bool
    /// First and last frame (inclusive) to play. `end` defaults to the last frame.
    let start: Int
    let end: Int?
    /// Nudges the sprite up (positive) or down, in points, to line up ground lines.
    let offsetY: CGFloat?
}

struct Manifest: Decodable {
    /// Points per frame pixel. 0.5 means the frames are @2x art.
    let pointsPerPixel: CGFloat
    let animations: [String: AnimationSpec]

    static func load() -> Manifest {
        do {
            let data = try Data(contentsOf: Resources.url("animations.json"))
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            for state in CatState.allCases where manifest.animations[state.rawValue] == nil {
                fatalError("animations.json has no entry for \(state.rawValue)")
            }
            return manifest
        } catch {
            fatalError("Could not read animations.json: \(error)")
        }
    }

    func spec(_ state: CatState) -> AnimationSpec {
        animations[state.rawValue]!
    }
}

/// Loads decoded frames and keeps the most recently used folders in memory.
final class FrameStore {
    private var cache: [String: [CGImage]] = [:]
    private var recent: [String] = []
    private let maxFolders = 3

    func frames(for spec: AnimationSpec) -> [CGImage] {
        let all = folderFrames(spec.folder)
        guard !all.isEmpty else { return [] }
        let first = min(max(spec.start, 0), all.count - 1)
        let last = min(spec.end ?? all.count - 1, all.count - 1)
        return Array(all[first...max(first, last)])
    }

    private func folderFrames(_ folder: String) -> [CGImage] {
        recent.removeAll { $0 == folder }
        recent.append(folder)
        if let frames = cache[folder] { return frames }

        let dir = Resources.url("Animations").appendingPathComponent(folder)
        var frames: [CGImage] = []
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        while true {
            let url = dir.appendingPathComponent(String(format: "frame_%03d.png", frames.count))
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { break }
            frames.append(image)
        }
        if frames.isEmpty { NSLog("CampusCat: no frames found in \(dir.path)") }
        cache[folder] = frames
        while recent.count > maxFolders {
            cache[recent.removeFirst()] = nil
        }
        return frames
    }
}

/// Steps through frames on a layer at the animation's frame rate.
@MainActor
final class SpritePlayer: NSObject {
    private let layer: CALayer
    private var frames: [CGImage] = []
    private var index = 0
    private var loop = true
    private var timer: Timer?
    private var onFinish: (() -> Void)?

    init(layer: CALayer) {
        self.layer = layer
        super.init()
    }

    var currentImage: CGImage? {
        frames.indices.contains(index) ? frames[index] : nil
    }

    func play(_ frames: [CGImage], fps: Double, loop: Bool, onFinish: @escaping () -> Void) {
        timer?.invalidate()
        timer = nil
        self.frames = frames
        self.loop = loop
        self.onFinish = onFinish
        index = 0
        show()
        // A single looping frame is a still pose and needs no timer.
        if frames.count <= 1 && loop { return }
        let timer = Timer(timeInterval: 1.0 / max(fps, 1), target: self,
                          selector: #selector(advance), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func advance() {
        if index + 1 < frames.count {
            index += 1
            show()
        } else if loop {
            index = 0
            show()
        } else {
            timer?.invalidate()
            timer = nil
            let finish = onFinish
            onFinish = nil
            finish?()
        }
    }

    private func show() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = currentImage
        CATransaction.commit()
    }
}
