import Foundation

public enum Facing: String, Codable, Sendable {
    case up, down, left, right

    /// Grid step for this direction; y grows downward.
    var delta: (dx: Int, dy: Int) {
        switch self {
        case .up: (0, -1)
        case .down: (0, 1)
        case .left: (-1, 0)
        case .right: (1, 0)
        }
    }

    init?(key: GameKey) {
        switch key {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        default: return nil
        }
    }
}

public enum WalkEvent: Hashable, Sendable {
    case moved, turned, blocked, door(Door), talk(TownPerson), nothing
}

/// The player's position on one map. Pure logic: the caller switches maps on `.door`.
public struct TownWalker: Hashable, Sendable {
    public private(set) var x: Int
    public private(set) var y: Int
    public private(set) var facing: Facing

    public init(x: Int, y: Int, facing: Facing) {
        self.x = x
        self.y = y
        self.facing = facing
    }

    public mutating func step(_ key: GameKey, on map: TownMap) -> WalkEvent {
        if let direction = Facing(key: key) { return walk(direction, on: map) }
        if key == .a { return talk(on: map) }
        return .nothing
    }

    private mutating func walk(_ direction: Facing, on map: TownMap) -> WalkEvent {
        // Like Ruby: a new direction only turns; the next press moves.
        guard direction == facing else {
            facing = direction
            return .turned
        }
        let (tx, ty) = target(distance: 1)
        guard let tile = map.tile(x: tx, y: ty), tile.walkable, person(at: tx, ty, on: map) == nil else {
            return .blocked
        }
        x = tx
        y = ty
        if let door = map.dorer.first(where: { $0.x == tx && $0.y == ty }) { return .door(door) }
        return .moved
    }

    private func talk(on map: TownMap) -> WalkEvent {
        let (fx, fy) = target(distance: 1)
        if let near = person(at: fx, fy, on: map) { return .talk(near) }
        // A counter square with a person one further in: talk across the counter.
        guard map.tile(x: fx, y: fy) == .counter else { return .nothing }
        let (bx, by) = target(distance: 2)
        if let behind = person(at: bx, by, on: map) { return .talk(behind) }
        return .nothing
    }

    private func target(distance: Int) -> (Int, Int) {
        let d = facing.delta
        return (x + d.dx * distance, y + d.dy * distance)
    }

    private func person(at px: Int, _ py: Int, on map: TownMap) -> TownPerson? {
        map.folk.first { $0.x == px && $0.y == py }
    }
}
