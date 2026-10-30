import Foundation

/// Checks the town in `Innhold/by` against the puzzles, topics and rule cards in the library.
extension ContentValidator {
    /// The longest word the 18-column dialog box can show without breaking it.
    static let townMaxWordLength = 18
    /// The map every other map must be reachable from through doors.
    static let townStartMap = "kontoret"
    static let townTrialSize = 3
    /// The fagkontor in each district (spec Mål 2).
    static let districtOffices = 2
    /// Rule 17: the controllers at the audit desk. The sensor comes on top.
    static let auditExaminers = 4
    static let sensorMinTopics = 3
    /// Accounts for VAT balances (2700–2799); a posting key that uses them assumes a VAT-registered company.
    static let vatAccounts = 2700...2799

    public static func validateTown(_ town: TownContent, library: ContentLibrary) -> [ContentProblem] {
        var problems: [ContentProblem] = []
        func report(_ id: String, _ file: String, _ messages: [String]) {
            if !messages.isEmpty { problems.append(ContentProblem(id: id, file: file, messages: messages)) }
        }

        let unreachable = unreachableMaps(town)
        let officeProblems = duplicateOfficeThemes(town)
        let districtProblems = validateDistricts(town)
        for map in town.kart {
            var messages = validateMap(map, in: town, library: library)
            if unreachable.contains(map.id) { messages.append("kartet nås ikke fra «\(townStartMap)» via dører") }
            messages += officeProblems[map.id] ?? []
            messages += districtProblems[map.id] ?? []
            report("kart:\(map.id)", "kart/\(map.id).json", messages)
        }
        if town.map(townStartMap) == nil, !town.kart.isEmpty {
            report("kart:\(townStartMap)", "kart/\(townStartMap).json", ["kartet «\(townStartMap)» finnes ikke"])
        }

        let startClients = town.klienter.filter(\.startklient)
        for client in town.klienter {
            report("klient:\(client.id)", "klienter/\(client.id).json", validateClient(client, in: town, library: library))
        }
        // A town-level problem: it does not belong to any one client, and it must not depend on load order.
        let townIsEmpty = town.kart.isEmpty && town.klienter.isEmpty && town.bransjer.isEmpty
        if startClients.count != 1, !townIsEmpty {
            report("by:startklient", "klienter/", ["nøyaktig én klient skal ha startklient: true, byen har \(startClients.count)"])
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
            var reported = Set<Character>()
            for ch in row where Tile(rawValue: ch) == nil && reported.insert(ch).inserted { out.append("rad \(y) har ukjent rute «\(ch)»") }
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
            if p.rolle == .funn {
                // Rule 14a: a pile gives one rule card that exists.
                if let card = p.gir {
                    if !library.rules.contains(where: { $0.id == card }) { out.append("funnet «\(p.id)» gir regelkortet «\(card)» som ikke finnes") }
                } else {
                    out.append("funnet «\(p.id)» har ikke gir")
                }
            }
            if p.rolle == .sandkasse {
                out += validateSandbox(p, in: town, library: library)
            }
            if p.rolle == .kundesak {
                out += validateCase(p, in: town, library: library)
            }
            if p.rolle == .fagkontor {
                if let office = p.fagkontor {
                    out += longWords(in: [office.navn], where: "kartet")
                    for tema in office.temaer where library.topic(tema) == nil { out.append("fagkontoret «\(office.id)» har ukjent tema «\(tema)»") }
                } else {
                    out.append("personen «\(p.id)» har rollen fagkontor uten fagkontor")
                }
            }
        }

        // Rule 17: the audit desk.
        for p in map.folk { out += validateAuditDesk(p, library: library) }

        // Rule 9: word width.
        out += longWords(in: [map.navn] + map.folk.flatMap(\.tekst), where: "kartet")
        return out
    }

    /// Rule 17: a `bokettersyn` has four controllers with no shared topic and a sensor with at least
    /// three topics; no other role has them.
    private static func validateAuditDesk(_ person: TownPerson, library: ContentLibrary) -> [String] {
        guard person.rolle == .bokettersyn else {
            return person.kontrollorer != nil || person.sensor != nil ? ["personen «\(person.id)» har kontrollører eller sensor, som bare står på bokettersyn"] : []
        }
        var out: [String] = []
        let examiners = person.kontrollorer ?? []
        if examiners.count != auditExaminers { out.append("skranken «\(person.id)» skal ha \(auditExaminers) kontrollører, har \(examiners.count)") }
        guard let sensor = person.sensor else { return out + ["skranken «\(person.id)» har ingen sensor"] }
        if sensor.temaer.count < sensorMinTopics { out.append("sensoren på «\(person.id)» skal ha minst \(sensorMinTopics) temaer, har \(sensor.temaer.count)") }
        var seen = Set<String>()
        for ref in examiners + [sensor] {
            for tema in ref.temaer where library.topic(tema) == nil { out.append("«\(ref.id)» på «\(person.id)» har ukjent tema «\(tema)»") }
        }
        for ref in examiners {
            for tema in ref.temaer where !seen.insert(tema).inserted { out.append("kontrollørene på «\(person.id)» deler temaet «\(tema)»") }
        }
        out += longWords(in: (examiners + [sensor]).map(\.navn), where: "kartet")
        return out
    }

    /// Rule 14b: a sandbox person names a case that exists, and gives a month (client) or a card.
    private static func validateSandbox(_ person: TownPerson, in town: TownContent, library: ContentLibrary) -> [String] {
        var out: [String] = []
        let cases = SandboxCase.load(folder: library.root.appendingPathComponent("sandkasse"), includeGenerated: false)
        if !cases.contains(where: { $0.id == person.sandkasse }) {
            out.append("sandkassen «\(person.id)» har saken «\(person.sandkasse ?? "")» som ikke finnes")
        }
        if let id = person.klient, town.client(id) == nil { out.append("sandkassen «\(person.id)» peker på klienten «\(id)» som ikke finnes") }
        if let card = person.gir, !library.rules.contains(where: { $0.id == card }) { out.append("sandkassen «\(person.id)» gir regelkortet «\(card)» som ikke finnes") }
        if person.klient == nil && person.gir == nil { out.append("sandkassen «\(person.id)» har hverken klient eller gir") }
        return out
    }

    /// Rule 6 (text): the question or explanation names input VAT or a VAT balance account (2700–2749).
    /// 2770/2780 (payroll) are not banned here.
    private static func teachesVat(_ puzzle: Puzzle) -> Bool {
        let text = puzzle.oppgave + " " + puzzle.forklaring
        if text.range(of: "inngående mva", options: .caseInsensitive) != nil { return true }
        return text.range(of: #"(?<![0-9])27[0-4][0-9](?![0-9])"#, options: .regularExpression) != nil
    }

    /// Rule 11: a customer case names an existing client and an existing `sak` or `quiz` puzzle
    /// that is not in the client's `oppgaver` or `provesak`. A VAT task is never a case (its type is
    /// `mva`), but a quiz on the VAT topic can be one (rule 15).
    private static func validateCase(_ person: TownPerson, in town: TownContent, library: ContentLibrary) -> [String] {
        var out: [String] = []
        let client = person.klient.flatMap { town.client($0) }
        if client == nil { out.append("kundesaken «\(person.id)» peker på klienten «\(person.klient ?? "")» som ikke finnes") }
        guard let id = person.oppgave else {
            return out + ["kundesaken «\(person.id)» har ingen oppgave"]
        }
        guard let puzzle = library.puzzle(id: id) else {
            return out + ["kundesaken «\(person.id)» har oppgaven «\(id)» som ikke finnes"]
        }
        if puzzle.kind != .sak, puzzle.kind != .quiz {
            out.append("kundesaken «\(person.id)» har oppgaven «\(id)» av typen \(puzzle.kind.rawValue), ikke sak eller quiz")
        }
        // A case tells its verdict; as one of the client's bilag or trial puzzles it would give that verdict away.
        if let client, client.oppgaver.contains(id) || client.provesak.contains(id) {
            out.append("kundesaken «\(person.id)» har oppgaven «\(id)», som klienten også har som bilag eller prøvesak")
        }
        if let client, !client.mvaRegistrert, puzzle.kind == .quiz || puzzle.kind == .sak, teachesVat(puzzle) {
            out.append("kundesaken «\(person.id)» har oppgaven «\(id)» med mva i teksten, men klienten «\(client.id)» er ikke mva-registrert")
        }
        // Rule 15: the key of a VAT-topic quiz assumes a registered company.
        if let client, !client.mvaRegistrert, puzzle.tema == "mva", puzzle.kind == .quiz || puzzle.kind == .sak {
            out.append("kundesaken «\(person.id)» har oppgaven «\(id)» om mva, men klienten «\(client.id)» er ikke mva-registrert")
        }
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
    private static func duplicateOfficeThemes(_ town: TownContent) -> [String: [String]] {
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

    /// Rule 12: districts. Every map names a district; a district map has an order, an arrival square
    /// and (from the second district) the permit named like itself; no door leads past a gate.
    /// Returns the messages per map id.
    private static func validateDistricts(_ town: TownContent) -> [String: [String]] {
        var out: [String: [String]] = [:]
        func report(_ map: TownMap, _ message: String) { out[map.id, default: []].append(message) }
        let districtMaps = town.kart.filter { $0.bydel == $0.id }
        let districtIds = Set(districtMaps.map(\.id))

        for map in town.kart {
            guard let bydel = map.bydel else {
                report(map, "kartet har ingen bydel")
                continue
            }
            if !districtIds.contains(bydel) { report(map, "bydelen «\(bydel)» finnes ikke som et kart med bydel lik sin egen id") }
            guard bydel == map.id else {
                if map.rekkefolge != nil || map.ankomst != nil || map.fullmakt != nil {
                    report(map, "et innendørskart har verken rekkefolge, ankomst eller fullmakt")
                }
                continue
            }
            if map.rekkefolge == nil { report(map, "bydelskartet mangler rekkefolge") }
            if let spot = map.ankomst {
                let free = map.tile(x: spot.x, y: spot.y)?.walkable == true && !map.folk.contains { $0.x == spot.x && $0.y == spot.y }
                if !free { report(map, "ankomst (\(spot.x), \(spot.y)) er ikke en gangbar rute uten person") }
            } else {
                report(map, "bydelskartet mangler ankomst")
            }
            if let order = map.rekkefolge {
                if order == 1, map.fullmakt != nil { report(map, "bydel 1 skal ikke ha fullmakt") }
                if order != 1, map.fullmakt != map.id { report(map, "bydel \(order) skal ha fullmakt «\(map.id)»") }
            }
        }

        let ordered = districtMaps.filter { $0.rekkefolge != nil }.sorted { ($0.rekkefolge ?? 0, $0.id) < ($1.rekkefolge ?? 0, $1.id) }
        for (index, map) in ordered.enumerated() where map.rekkefolge != index + 1 {
            report(map, "rekkefolge er \(map.rekkefolge ?? 0), men skal være \(index + 1) (1…\(ordered.count) uten hull eller dubletter)")
        }

        if let office = town.map(townStartMap), let bydel = office.bydel,
           let first = districtMaps.first(where: { $0.id == bydel }), first.rekkefolge != 1 {
            report(office, "«\(townStartMap)» skal ligge i bydel 1, ikke i «\(bydel)»")
        }

        // A door between two districts must join two district maps, so no interior is a way round a gate.
        for map in town.kart {
            for door in map.dorer {
                guard let from = map.bydel, let target = town.map(door.til), let to = target.bydel, from != to,
                      districtIds.contains(from), districtIds.contains(to) else { continue }
                if from != map.id || to != target.id {
                    report(map, "dør (\(door.x), \(door.y)) til «\(target.id)» er en bakdør mellom bydelene «\(from)» og «\(to)»")
                }
            }
        }
        return out
    }

    /// Rule 13: every topic has an office, and every district has exactly `districtOffices` offices.
    /// Not part of `validateTown`: a town under construction, or the small one in the tests, does not meet it.
    public static func validateTownCoverage(_ town: TownContent, library: ContentLibrary) -> [ContentProblem] {
        guard !town.kart.isEmpty else { return [] }
        var messages: [String] = []
        let covered = Set(town.kart.flatMap(\.folk).compactMap(\.fagkontor).flatMap(\.temaer))
        let missing = library.topics.map(\.id).filter { !covered.contains($0) }
        if !missing.isEmpty { messages.append("temaer uten fagkontor: \(missing.joined(separator: ", "))") }
        for district in TownDistricts.all(in: town) where district.offices.count != districtOffices {
            messages.append("bydelen «\(district.id)» har \(district.offices.count) fagkontor, skal ha \(districtOffices)")
        }
        return messages.isEmpty ? [] : [ContentProblem(id: "by:fagkontor", file: "kart/", messages: messages)]
    }

    /// Rule 17 (coverage): exactly one audit desk in town. Kept apart from `validateTownCoverage`
    /// until the desk exists in the town's content.
    static func validateAuditCoverage(_ town: TownContent) -> [ContentProblem] {
        guard !town.kart.isEmpty else { return [] }
        let desks = town.kart.flatMap(\.folk).filter { $0.rolle == .bokettersyn }.count
        guard desks != 1 else { return [] }
        return [ContentProblem(id: "by:bokettersyn", file: "kart/", messages: ["byen skal ha nøyaktig én bokettersyn-skranke, har \(desks)"])]
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

        // Rule 16: the planner only knows the company forms below.
        if !DeadlinePlanner.skattemeldingForms.contains(client.selskapsform) {
            out.append("selskapsform skal være AS eller ENK, ikke «\(client.selskapsform)»")
        }

        // Rule 10: payroll deadlines need a pay day, and only clients with staff have one.
        if (client.ansatte > 0) != (client.lonnsdag != nil) {
            out.append("lonnsdag skal være satt hvis og bare hvis klienten har ansatte")
        } else if let day = client.lonnsdag, !(1...28).contains(day) {
            out.append("lonnsdag skal være mellom 1 og 28, ikke \(day)")
        }

        let standing = town.map(client.sted.kart)?.folk.first { $0.rolle == .klient && $0.klient == client.id && $0.x == client.sted.x && $0.y == client.sted.y }
        if standing == nil { out.append("sted (\(client.sted.kart), \(client.sted.x), \(client.sted.y)) har ingen klient-person med id «\(client.id)»") }

        // Rule 6: the answer keys assume a VAT-registered company.
        if !client.mvaRegistrert {
            var seen = Set<String>()
            for id in tasks {
                guard seen.insert(id).inserted, let puzzle = library.puzzle(id: id) else { continue }
                if puzzle.kind == .mva {
                    out.append("oppgave «\(id)» er av typen mva, men klienten er ikke mva-registrert")
                } else if case .posting(let p) = puzzle.payload, p.fasit.contains(where: { Int($0.konto).map(vatAccounts.contains) == true }) {
                    out.append("oppgave «\(id)» bruker mva-konto (2700–2799), men klienten er ikke mva-registrert")
                } else if teachesVat(puzzle) {
                    out.append("oppgave «\(id)» handler om inngående mva eller mva-konto i teksten, men klienten er ikke mva-registrert")
                }
            }
        }

        let lines = client.replikker
        if lines.oppdagetFeil.isEmpty { out.append("replikker.oppdagetFeil kan ikke være tom") }
        out += longWords(in: [client.navn] + lines.hilsen + lines.drift + lines.haug + lines.tomHaug + lines.glippetFrist + lines.oppdagetFeil, where: "klienten")
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

    /// Rule 9: no word over 18 characters. The dialog box is 36 columns wide since phase 2b, but
    /// the rule stays as it was: stricter than the box, and a short word reads better.
    private static func longWords(in texts: [String], where owner: String) -> [String] {
        texts.flatMap { $0.split(separator: " ") }
            .filter { $0.count > townMaxWordLength }
            .map { "ordet «\($0)» i \(owner) er lengre enn \(townMaxWordLength) tegn" }
    }
}
