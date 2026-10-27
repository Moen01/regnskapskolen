import Foundation

/// JSON Schemas for `--json-schema`, one per puzzle kind, mirroring `Puzzle`'s decoding.
public enum PuzzleSchema {
    static func obj(_ props: [String: JSONValue], required: [String]) -> JSONValue {
        .object(["type": .string("object"), "properties": .object(props), "required": .array(required.map { .string($0) }), "additionalProperties": .bool(false)])
    }
    static let str: JSONValue = .object(["type": .string("string")])
    static let num: JSONValue = .object(["type": .string("number")])
    static let int: JSONValue = .object(["type": .string("integer")])
    static let bool: JSONValue = .object(["type": .string("boolean")])
    static func arr(_ item: JSONValue, min: Int = 1) -> JSONValue { .object(["type": .string("array"), "items": item, "minItems": .number(Double(min))]) }
    static func strEnum(_ values: [String]) -> JSONValue { .object(["type": .string("string"), "enum": .array(values.map { .string($0) })]) }

    static let law = obj(["lov": str, "paragraf": str, "tekst": str], required: ["lov", "paragraf", "tekst"])

    public static func schema(for kind: PuzzleKind) -> JSONValue {
        var props: [String: JSONValue] = [
            "id": str, "type": strEnum([kind.rawValue]), "tema": str,
            "vanskelighet": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(5)]),
            "tags": arr(str, min: 0), "tittel": str, "oppgave": str, "lov": arr(law), "forklaring": str, "status": strEnum(["utkast"]),
        ]
        var required = ["id", "type", "tema", "vanskelighet", "tags", "tittel", "oppgave", "lov", "forklaring", "status"]
        switch kind {
        case .postering:
            props["kontoer"] = arr(obj(["nr": str, "navn": str], required: ["nr", "navn"]), min: 2)
            props["fasit"] = arr(obj(["konto": str, "side": strEnum(["D", "K"]), "belop": num, "alt": arr(str, min: 0)], required: ["konto", "side", "belop"]), min: 2)
            required += ["kontoer", "fasit"]
        case .klassifiser:
            props["kategorier"] = arr(str, min: 2)
            props["elementer"] = arr(obj(["tekst": str, "svar": str, "hvorfor": str], required: ["tekst", "svar", "hvorfor"]), min: 2)
            required += ["kategorier", "elementer"]
        case .finnfeil:
            props["overskrift"] = str
            props["elementer"] = arr(obj(["tekst": str, "feil": bool, "hvorfor": str], required: ["tekst", "feil"]), min: 3)
            required += ["overskrift", "elementer"]
        case .regnut:
            props["svar"] = num; props["toleranse"] = num; props["enhet"] = str; props["hint"] = str
            required += ["svar", "toleranse", "enhet", "hint"]
        case .quiz:
            props["alternativer"] = arr(str, min: 3); props["svar"] = int
            required += ["alternativer", "svar"]
        case .sak:
            props["fra"] = str; props["melding"] = str
            props["valg"] = arr(obj(["nokkel": str, "tekst": str], required: ["nokkel", "tekst"]), min: 3)
            props["svar"] = str; props["sporsmal"] = arr(str, min: 0); props["forslag"] = str
            required += ["fra", "melding", "valg", "svar", "sporsmal", "forslag"]
        case .mva:
            props["transaksjon"] = str
            props["fasit"] = obj(["behandling": strEnum(["25", "15", "12", "0", "unntatt", "omvendt"]), "fradrag": .object(["type": .array([.string("boolean"), .string("null")])])], required: ["behandling", "fradrag"])
            required += ["transaksjon", "fasit"]
        case .frist:
            props["hendelse"] = str; props["fasit"] = str; props["hint"] = str
            props["fasitRegel"] = obj(["type": strEnum(["mva", "mva-aarlig", "amelding", "aga", "forskuddstrekk", "aarsregnskap", "aarsregnskap-fastsettes", "skattemelding"]),
                                       "termin": int, "aar": int, "maaned": int, "utbetalt": str], required: ["type"])
            required += ["hendelse", "fasit", "hint", "fasitRegel"]
        }
        return obj(props, required: required)
    }

    public static let sandboxCase: JSONValue = {
        let line = obj(["konto": str, "side": strEnum(["D", "K"]), "belop": num, "mvaKode": str], required: ["konto", "side", "belop"])
        let entry = obj(["dato": str, "tekst": str, "linjer": arr(line, min: 2)], required: ["dato", "tekst", "linjer"])
        return obj([
            "id": str, "tittel": str, "selskap": str, "beskrivelse": str,
            "vanskelighet": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(5)]),
            "lov": arr(law),
            "hendelser": arr(obj(["dato": str, "tekst": str, "hint": str], required: ["dato", "tekst"]), min: 6),
            "fasitSaldobalanse": .object(["type": .string("object"), "additionalProperties": num]),
            "fasitJournal": obj(["entries": arr(entry, min: 6)], required: ["entries"]),
        ], required: ["id", "tittel", "selskap", "beskrivelse", "vanskelighet", "lov", "hendelser", "fasitSaldobalanse", "fasitJournal"])
    }()
}
