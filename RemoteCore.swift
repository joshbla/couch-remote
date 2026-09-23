import AppKit

enum RemoteAction: String, CaseIterable {
    case leftClick, rightClick, space, enter, escape, fn, command, g, h, a, d, volumeUp, volumeDown
    case precision, pause, none, tab, backspace, leftArrow, rightArrow, upArrow, downArrow, f, m

    var title: String {
        switch self {
        case .leftClick: return "Left click / drag"
        case .rightClick: return "Right click"
        case .space: return "Space"
        case .enter: return "Return / Enter"
        case .escape: return "Escape"
        case .fn: return "Fn / Globe"
        case .command: return "Command (hold to switch apps)"
        case .g: return "G"
        case .h: return "H"
        case .a: return "A"
        case .d: return "D"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .precision: return "Slow pointer (hold)"
        case .pause: return "Pause / resume remote"
        case .none: return "Unassigned"
        case .tab: return "Tab"
        case .backspace: return "Backspace"
        case .leftArrow: return "Left arrow"
        case .rightArrow: return "Right arrow"
        case .upArrow: return "Up arrow"
        case .downArrow: return "Down arrow"
        case .f: return "F"
        case .m: return "M"
        }
    }

    var keyCode: CGKeyCode? {
        switch self {
        case .space: return 49
        case .enter: return 36
        case .escape: return 53
        case .fn: return 63
        case .command: return 55
        case .g: return 5
        case .h: return 4
        case .a: return 0
        case .d: return 2
        case .tab: return 48
        case .backspace: return 51
        case .leftArrow: return 123
        case .rightArrow: return 124
        case .upArrow: return 126
        case .downArrow: return 125
        case .f: return 3
        case .m: return 46
        default: return nil
        }
    }

    var repeats: Bool {
        switch self {
        case .g, .h, .a, .d, .volumeUp, .volumeDown, .backspace,
             .leftArrow, .rightArrow, .upArrow, .downArrow: return true
        default: return false
        }
    }
}

struct Binding {
    let input: String
    let title: String
    let initial: RemoteAction
}

let bindings: [Binding] = [
    Binding(input: "a", title: "A · bottom face button", initial: .leftClick),
    Binding(input: "b", title: "B · right face button", initial: .rightClick),
    Binding(input: "x", title: "X · left face button", initial: .space),
    Binding(input: "y", title: "Y · top face button", initial: .enter),
    Binding(input: "lb", title: "LB · left shoulder", initial: .a),
    Binding(input: "rb", title: "RB · right shoulder", initial: .d),
    Binding(input: "up", title: "D-pad up", initial: .volumeUp),
    Binding(input: "down", title: "D-pad down", initial: .volumeDown),
    Binding(input: "left", title: "D-pad left", initial: .g),
    Binding(input: "right", title: "D-pad right", initial: .h),
    Binding(input: "leftStick", title: "Press left stick", initial: .command),
    Binding(input: "rightStick", title: "Press right stick", initial: .tab),
    Binding(input: "lt", title: "LT · left trigger", initial: .precision),
    Binding(input: "rt", title: "RT · right trigger", initial: .fn),
    Binding(input: "options", title: "Select / View", initial: .escape),
    Binding(input: "menu", title: "Start / Menu", initial: .pause),
]

func stickVelocity(x: Double, y: Double, deadZone: Double = 0.16) -> CGPoint {
    let magnitude = hypot(x, y)
    guard magnitude > deadZone else { return .zero }
    let strength = pow((min(magnitude, 1) - deadZone) / (1 - deadZone), 1.65)
    return CGPoint(x: x / magnitude * strength, y: y / magnitude * strength)
}

func nearestVisiblePoint(_ point: CGPoint, screens: [CGRect]) -> CGPoint {
    guard !screens.isEmpty else { return point }
    if screens.contains(where: { $0.contains(point) }) { return point }
    let candidates = screens.map { rect in
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX - 1),
                y: min(max(point.y, rect.minY), rect.maxY - 1))
    }
    return candidates.min(by: {
        hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y)
    })!
}

/// Shared actions stay down until every physical button assigned to them is released.
struct ActionState {
    private(set) var held: Set<RemoteAction> = []

    mutating func update(_ next: Set<RemoteAction>) -> (released: Set<RemoteAction>, pressed: Set<RemoteAction>) {
        let change = (released: held.subtracting(next), pressed: next.subtracting(held))
        held = next
        return change
    }
}

func keyboardFlags(for action: RemoteAction, down: Bool, commandHeld: Bool) -> CGEventFlags {
    var flags: CGEventFlags = commandHeld ? .maskCommand : []
    if action == .fn && down { flags.insert(.maskSecondaryFn) }
    return flags
}

func runSelfTests() {
    precondition(stickVelocity(x: 0.1, y: -0.1) == .zero)
    precondition(stickVelocity(x: 1, y: 0) == CGPoint(x: 1, y: 0))
    let diagonal = stickVelocity(x: 1, y: 1)
    precondition(abs(hypot(diagonal.x, diagonal.y) - 1) < 0.00001)
    let fine = stickVelocity(x: 0.25, y: 0)
    precondition(fine.x > 0 && fine.x < 0.1)
    let screens = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: -100, y: 0, width: 100, height: 100)]
    precondition(nearestVisiblePoint(CGPoint(x: -50, y: 30), screens: screens) == CGPoint(x: -50, y: 30))
    precondition(nearestVisiblePoint(CGPoint(x: 150, y: 130), screens: screens) == CGPoint(x: 99, y: 99))
    var state = ActionState()
    precondition(state.update([.leftClick]).pressed == [.leftClick])
    precondition(state.update([.leftClick]).released.isEmpty)
    precondition(state.update([]).released == [.leftClick])
    precondition(!RemoteAction.space.repeats && !RemoteAction.command.repeats && RemoteAction.volumeUp.repeats)
    precondition(Set(bindings.map(\.input)).count == bindings.count)
    precondition(bindings.first(where: { $0.input == "leftStick" })?.initial == .command)
    precondition(bindings.first(where: { $0.input == "rightStick" })?.initial == .tab)
    precondition(bindings.first(where: { $0.input == "rt" })?.initial == .fn)
    precondition(bindings.first(where: { $0.input == "lb" })?.initial == .a)
    precondition(bindings.first(where: { $0.input == "left" })?.initial == .g)
    precondition(keyboardFlags(for: .tab, down: true, commandHeld: true).contains(.maskCommand))
    precondition(keyboardFlags(for: .tab, down: false, commandHeld: true).contains(.maskCommand))
    precondition(!keyboardFlags(for: .command, down: false, commandHeld: false).contains(.maskCommand))
    for action in RemoteAction.allCases {
        if let keyCode = action.keyCode {
            precondition(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) != nil)
        }
    }
    print("Passed: dead zone, precision curve, diagonal speed, multiple displays, action ownership, release cleanup, repeat policy, bindings, keyboard events.")
}
