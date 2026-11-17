import Foundation
import FoundationModels

// Bench (fork-009): Apple's on-device model as the nightly judge, against
// Claude's verdicts. Set A: today's candidates with full evidence and
// Claude's decisions on them. Set B: the verdict memory (452 pairs judged by
// Claude over the past runs), rebuilt with the evidence it kept (count, one
// example). Build: swiftc -O -o bench apple_judge.swift. Usage:
// bench <dream dir> <judge_prompt.md> <out.json> [limitB] [offsetB]
// (an offset skips set A). Score with score_judge.py <out.json>.

@Generable
struct Verdict {
    @Guide(description: "One short sentence explaining the verdict.")
    var reason: String
    @Guide(description: "The verdict.", .anyOf(["dictionary", "grammar", "rewrite", "one_off", "unsure"]))
    var verdict: String
    @Guide(description: "Confidence in the verdict, 0 to 1.", .range(0.0...1.0))
    var probability: Double
}

let args = CommandLine.arguments
let dream = URL(fileURLWithPath: args[1])
let basePrompt = try String(contentsOfFile: args[2], encoding: .utf8)
let limitB = args.count > 4 ? Int(args[4])! : Int.max
let offsetB = args.count > 5 ? Int(args[5])! : -1
let instructions = basePrompt
    .replacingOccurrences(of: "The JSON on stdin lists candidates.", with: "The prompt is one candidate, as JSON.")
    .components(separatedBy: "Set `judge` to").first! + "Answer with one verdict for this candidate."

func json(_ url: URL) throws -> Any { try JSONSerialization.jsonObject(with: Data(contentsOf: url)) }

struct Item { let set: String; let id: String; let wrong: String; let right: String; let count: Int; let candidate: [String: Any]; let claude: String; let claudeP: Double }
var items: [Item] = []
let cands = (try json(dream.appendingPathComponent("candidates.json")) as! [String: Any])["candidates"] as! [[String: Any]]
let dec = (try json(dream.appendingPathComponent("decisions-claude.json")) as! [String: Any])["structured_output"] as! [String: Any]
let byID = Dictionary(uniqueKeysWithValues: (dec["decisions"] as! [[String: Any]]).map { ($0["id"] as! String, $0) })
for c in cands where offsetB < 0 {
    guard let d = byID[c["id"] as! String] else { continue }
    items.append(Item(set: "A", id: c["id"] as! String, wrong: c["wrong"] as! String, right: c["right"] as! String, count: c["count"] as! Int, candidate: c, claude: d["verdict"] as! String, claudeP: d["probability"] as! Double))
}
let memory = (try json(dream.appendingPathComponent("verdicts.json")) as! [String: Any])["entries"] as! [String: [String: Any]]
let todayKeys = Set(cands.map { "\($0["wrong"]!)→\($0["right"]!)" })
for (key, e) in memory.sorted(by: { $0.key < $1.key }).filter({ ($0.value["verdict"] as! String) != "removed" && $0.value["wrong"] != nil && !todayKeys.contains($0.key) }).dropFirst(max(0, offsetB)) {
    if items.filter({ $0.set == "B" }).count >= limitB { break }
    var example: [String: String] = [:]
    if let ex = e["example"] as? String {
        let parts = ex.components(separatedBy: " → ")
        if parts.count == 2 { example = ["pasted": parts[0], "final": parts[1]] }
    }
    let c: [String: Any] = ["id": key, "wrong": e["wrong"]!, "right": e["right"]!, "count": e["count"]!, "examples": example.isEmpty ? [] : [example]]
    items.append(Item(set: "B", id: key, wrong: e["wrong"] as! String, right: e["right"] as! String, count: e["count"] as! Int, candidate: c, claude: e["verdict"] as! String, claudeP: (e["probability"] as? Double) ?? 0))
}

let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
print("availability:", model.availability, "· fr supported:", model.supportsLocale(Locale(identifier: "fr_FR")), "· items:", items.count)
guard case .available = model.availability else { exit(1) }

var out: [[String: Any]] = []
let start = Date()
for (n, item) in items.enumerated() {
    let session = LanguageModelSession(model: model, instructions: instructions)
    let prompt = String(data: try JSONSerialization.data(withJSONObject: item.candidate, options: [.sortedKeys]), encoding: .utf8)!
    let t = Date()
    var row: [String: Any] = ["set": item.set, "id": item.id, "wrong": item.wrong, "right": item.right, "count": item.count, "claude": item.claude, "claudeP": item.claudeP]
    do {
        let r = try await session.respond(to: prompt, generating: Verdict.self)
        row["apple"] = r.content.verdict; row["appleP"] = r.content.probability; row["reason"] = r.content.reason
    } catch {
        row["error"] = String(describing: error).prefix(120)
    }
    row["seconds"] = Date().timeIntervalSince(t)
    out.append(row)
    if n % 25 == 0 { print("\(n)/\(items.count) · \(Int(Date().timeIntervalSince(start))) s") }
}
try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: args[3]))
print("done in \(Int(Date().timeIntervalSince(start))) s")
