import Foundation

/// A district of the town: one outdoor map (`bydel == id`) and the interiors that name it.
public struct TownDistrict: Hashable, Sendable, Identifiable {
    public let id: String
    public let navn: String
    public let rekkefolge: Int
    public let ankomst: TownSpot
    /// The permit that opens the gate; `nil` for the first district.
    public let fullmakt: String?
    /// The fagkontor on every map of the district.
    public let offices: [FagkontorRef]
}

/// Districts are read from the map files, so a new district is a new map file and nothing else.
public enum TownDistricts {
    /// Every district, in the order the player meets them. A district map without `rekkefolge` or
    /// `ankomst` is left out; the validator reports it.
    public static func all(in content: TownContent) -> [TownDistrict] {
        content.kart.compactMap { map -> TownDistrict? in
            guard map.bydel == map.id, let order = map.rekkefolge, let arrival = map.ankomst else { return nil }
            let offices = content.kart.filter { $0.bydel == map.id }.flatMap(\.folk).compactMap(\.fagkontor)
            return TownDistrict(id: map.id, navn: map.navn, rekkefolge: order, ankomst: arrival, fullmakt: map.fullmakt, offices: offices)
        }.sorted { ($0.rekkefolge, $0.id) < ($1.rekkefolge, $1.id) }
    }

    public static func district(of mapId: String, in content: TownContent) -> TownDistrict? {
        guard let bydel = content.map(mapId)?.bydel else { return nil }
        return all(in: content).first { $0.id == bydel }
    }

    /// A map outside every district is open (content from phase 2b). A district is open when it has
    /// no permit or the player holds it.
    public static func isOpen(_ mapId: String, content: TownContent, fullmakter: Set<String>) -> Bool {
        guard let permit = district(of: mapId, in: content)?.fullmakt else { return true }
        return fullmakter.contains(permit)
    }

    /// The permits the badges earn. District n (above 1) gives its permit when every office of
    /// district n - 1 that is ready has its badge. An office still under construction is not required,
    /// so the player is never locked out by content that is missing.
    public static func earned(content: TownContent, badges: Set<String>, regions: [Region]) -> Set<String> {
        let districts = all(in: content)
        var result = Set<String>()
        for (previous, next) in zip(districts, districts.dropFirst()) {
            guard let permit = next.fullmakt else { continue }
            let required = previous.offices.filter { TownTrials.fagkontorReady($0, regions: regions) }
            if required.allSatisfy({ badges.contains(TownTrials.badgeKey($0)) }) { result.insert(permit) }
        }
        return result
    }
}
