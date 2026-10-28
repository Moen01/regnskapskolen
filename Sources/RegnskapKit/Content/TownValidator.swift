import Foundation

/// Checks the town in `Innhold/by` against the puzzles, topics and rule cards in the library.
extension ContentValidator {
    /// The longest word the 18-column dialog box can show without breaking it.
    static let townMaxWordLength = 18
    /// The map every other map must be reachable from through doors.
    static let townStartMap = "kontoret"
    static let townTrialSize = 3
    /// Accounts for VAT balances (2700–2799); a posting key that uses them assumes a VAT-registered company.
    static let vatAccounts = 2700...2799

    public static func validateTown(_ town: TownContent, library: ContentLibrary) -> [ContentProblem] {
        var problems: [ContentProblem] = []
        func report(_ id: String, _ file: String, _ messages: [String]) {
            if !messages.isEmpty { problems.append(ContentProblem(id: id, file: file, messages: messages)) }
        }

        let unreachable = unreachableMaps(town)
        let officeProblems = duplicateOfficeThemes(town, library: library)
        for map in town.kart {
            var messages = validateMap(map, in: town, library: library)
            if unreachable.contains(map.id) { messages.append("kartet nås ikke fra «\(townStartMap)» via dører") }
            messages += officeProblems[map.id] ?? []
            report("kart:\(map.id)", "kart/\(map.id).json", messages)
        }
        if town.map(townStartMap) == nil, !town.kart.isEmpty {
            report("kart:\(townStartMap)", "kart/\(townStartMap).json", ["kartet «\(townStartMap)» finnes ikke"])
        }

        // Filed once: on the second starting client, or on the first client when there is none.
        let startClients = town.klienter.filter(\.startklient)
        let startProblemOwner = startClients.count > 1 ? startClients[1].id : town.klienter.first?.id
        for client in town.klienter {
            var messages = validateClient(client, in: town, library: library)
            if startClients.count != 1, client.id == startProblemOwner {
                messages.append("nøyaktig én klient skal ha startklient: true, byen har \(startClients.count)")
            }
            report("klient:\(client.id)", "klienter/\(client.id).json", messages)
        }
        for bransje in town.bransjer {
            report("bransje:\(bransje.id)", "bransjer.json", validateBransje(bransje, library: library))
        }
        return problems
    }

    // MARK: Maps

    private static func validateMap(_ map: TownMap, in town: TownContent, library: ContentLibrary) -> [String] {
        var out: [String] = []

        // Rule 1: shape and tiles.
        if map.ruter.count != map.hoyde { out.append("kartet har \(map.ruter.count) rader, hoyde er \(map.hoyde)") }
        for (y, row) in map.ruter.enumerated() {
            if row.count != map.bredde { out.append("rad \(y) har lengde \(row.count), bredde er \(map.bredde)") }
            for ch in Set(row) where Tile(rawValue: ch) == nil { out.append("rad \(y) har ukjent rute «\(ch)»") }
        }

        // Rule 2: doors.
        for door in map.dorer {
            if map.tile(x: door.x, y: door.y) != .door { out.append("dør (\(door.x), \(door.y)) står ikke på en D-rute") }
            guard let target = town.map(door.til) else {
                out.append("dør (\(door.x), \(door.y)) fører til kartet «\(door.til)» som ikke finnes")
                continue
            }
            if target.tile(x: door.tilX, y: door.tilY)?.walkable != true {
                out.append("dør (\(door.x), \(door.y)) lander på (\(door.tilX), \(door.tilY)) i «\(target.id)», som ikke er gangbar")
            } else if target.folk.contains(where: { $0.x == door.tilX && $0.y == door.tilY }) {
                out.append("dør (\(door.x), \(door.y)) lander på en person i «\(target.id)»")
            }
        }

        // Rule 3: people.
        var taken = Set<[Int]>()
        for p in map.folk {
            if p.x < 0 || p.y < 0 || p.x >= map.bredde || p.y >= map.hoyde {
                out.append("personen «\(p.id)» står utenfor kartet på (\(p.x), \(p.y))")
            } else if !taken.insert([p.x, p.y]).inserted {
                out.append("personen «\(p.id)» står på samme rute som en annen, (\(p.x), \(p.y))")
            }
            if p.rolle == .klient, p.klient.flatMap({ town.client($0) }) == nil {
                out.append("personen «\(p.id)» peker på klienten «\(p.klient ?? "")» som ikke finnes")
            }
            if p.rolle == .fagkontor {
                if let office = p.fagkontor {
                    for tema in office.temaer where library.topic(tema) == nil { out.append("fagkontoret «\(office.id)» har ukjent tema «\(tema)»") }
                } else {
                    out.append("personen «\(p.id)» har rollen fagkontor uten fagkontor")
                }
            }
        }

        // Rule 9: word width.
        out += longWords(in: [map.navn] + map.folk.flatMap(\.tekst), where: "kartet")
        return out
    }

    /// Rule 4: breadth-first over the door graph from the start map.
    private static func unreachableMaps(_ town: TownContent) -> Set<String> {
        guard town.map(townStartMap) != nil else { return [] }
        var seen: Set<String> = [townStartMap]
        var queue = [townStartMap]
        while !queue.isEmpty {
            let id = queue.removeFirst()
            for door in town.map(id)?.dorer ?? [] where town.map(door.til) != nil && seen.insert(door.til).inserted {
                queue.append(door.til)
            }
        }
        return Set(town.kart.map(\.id)).subtracting(seen)
    }

    /// Rule 8: a topic belongs to one office only. The problem is filed on the map of the later office.
    private static func duplicateOfficeThemes(_ town: TownContent, library: ContentLibrary) -> [String: [String]] {
        var owner: [String: String] = [:]
        var out: [String: [String]] = [:]
        for map in town.kart {
            for p in map.folk {
                guard let office = p.fagkontor else { continue }
                for tema in office.temaer {
                    if let first = owner[tema], first != office.id {
                        out[map.id, default: []].append("tema «\(tema)» finnes i to fagkontor: «\(first)» og «\(office.id)»")
                    } else {
                        owner[tema] = office.id
                    }
                }
            }
        }
        return out
    }

    // MARK: Clients

    private static func validateClient(_ client: TownClient, in town: TownContent, library: ContentLibrary) -> [String] {
        var out: [String] = []
        if town.bransje(client.bransje) == nil { out.append("ukjent bransje «\(client.bransje)»") }

        let tasks = client.oppgaver + client.provesak
        for id in Set(tasks).sorted() where library.puzzle(id: id) == nil { out.append("oppgave «\(id)» finnes ikke") }
        if client.provesak.count != townTrialSize { out.append("prøvesak skal ha \(townTrialSize) oppgaver, har \(client.provesak.count)") }

        if client.mvaRegistrert != (client.mvaTermin != nil) {
            out.append("mvaTermin skal være satt hvis og bare hvis mvaRegistrert er true")
        }

        let standing = town.map(client.sted.kart)?.folk.first { $0.rolle == .klient && $0.klient == client.id && $0.x == client.sted.x && $0.y == client.sted.y }
        if standing == nil { out.append("sted (\(client.sted.kart), \(client.sted.x), \(client.sted.y)) har ingen klient-person med id «\(client.id)»") }

        // Rule 6: the answer keys assume a VAT-registered company.
        if !client.mvaRegistrert {
            var seen = Set<String>()
            for id in tasks where seen.insert(id).inserted {
                guard let puzzle = library.puzzle(id: id) else { continue }
                if puzzle.kind == .mva { out.append("oppgave «\(id)» er av typen mva, men klienten er ikke mva-registrert") }
                if case .posting(let p) = puzzle.payload, p.fasit.contains(where: { Int($0.konto).map(vatAccounts.contains) == true }) {
                    out.append("oppgave «\(id)» bruker mva-konto (2700–2799), men klienten er ikke mva-registrert")
                }
            }
        }

        let lines = client.replikker
        out += longWords(in: [client.navn] + lines.hilsen + lines.drift + lines.haug + lines.tomHaug + lines.glippetFrist, where: "klienten")
        return out
    }

    // MARK: Industries

    private static func validateBransje(_ bransje: Bransje, library: ContentLibrary) -> [String] {
        var out: [String] = []
        let cards = Set(library.rules.map(\.id))
        for id in bransje.regelkort where !cards.contains(id) { out.append("regelkort «\(id)» finnes ikke i Innhold/regler/") }
        for tema in bransje.temaer where library.topic(tema) == nil { out.append("ukjent tema «\(tema)»") }
        return out
    }

    // MARK: Text

    /// Rule 9: the dialog box is 18 columns wide, so a longer word could not be shown.
    private static func longWords(in texts: [String], where owner: String) -> [String] {
        texts.flatMap { $0.split(separator: " ") }
            .filter { $0.count > townMaxWordLength }
            .map { "ordet «\($0)» i \(owner) er lengre enn \(townMaxWordLength) tegn" }
    }
}
