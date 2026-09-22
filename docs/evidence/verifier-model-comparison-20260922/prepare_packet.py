"""Construct selected historical reviewer inputs; no network or model calls."""
import copy
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent
PREVIOUS = EVIDENCE / "question-reliability-release-20260922"
SELECTIONS = [
    ("bus_multiple_supported", "pipeline-adaptive-capture.json", 5, 2, False, None),
    ("semicolon_multiple_defensible", "pipeline-capture-v2.json", 11, 0, False, None),
    ("fuel_unique_control", "pipeline-capture-v2.json", 2, 3, True, "30 mpg"),
    ("paint_feedback", "pipeline-capture-v2.json", 2, 2, True, "10 liters"),
    ("population_feedback", "pipeline-capture-v2.json", 2, 4, True, "15%"),
    ("weighted_grade_control", "pipeline-capture-v2.json", 14, 3, True, "78.4"),
]
GOLD = {
    "bus_multiple_supported": {
        "defect": "multiple_supported_choices", "required_decision": "reject",
        "counterexamples": ["At25 rides, individual tickets cost25*2.50=$62.50, exceeding the$60 pass.",
                            "At26 rides, tickets cost26*2.50=$65, also exceeding the$60 pass.",
                            "The stem asks how many rides make the pass cheaper, not the minimum number. Both25 and26 answer the literal question."],
        "forbidden_repairs": ["Do not insert minimum, first, become, or break-even wording."]},
    "semicolon_multiple_defensible": {
        "defect": "multiple_defensible_choices", "required_decision": "reject",
        "counterexamples": ["The semicolon-before-however sentence is grammatical.",
                            "The sentence with comma-however-semicolon is also defensible: however can be a parenthetical adjunct at the end of the first independent clause, followed by a semicolon joining the next independent clause.",
                            "The conjunction-and choice is additionally style-sensitive; the known standard however answer is not uniquely licensed merely because it is the conventional textbook pattern."],
        "forbidden_repairs": ["Do not assume the question explicitly asks for however to begin the second clause or for one house-style punctuation rule."]},
    "fuel_unique_control": {
        "defect": None, "required_decision": "retain",
        "counterexamples": ["240 miles/8 gallons=30 mpg;28,32,1920 do not answer the requested rate.",
                            "1920 is240*8, a product with wrong operation/units; do not claim it is a valid miles-per-gallon rate."]},
    "paint_feedback": {
        "defect": "historical_feedback_only", "required_decision": "retain_with_sound_feedback",
        "counterexamples": ["The blue:white ratio3:2 gives white=15*(2/3)=10 liters.",
                            "15:9 reduces to5:3, not1:1;15:6 reduces to5:2;15:22.5 reduces to2:3.",
                            "2/3 is the correct blue-to-white conversion factor;3/2 is its inverse.",
                            "Feedback may simply state why a distractor fails; it must not invent a calculation that does not produce the cited distractor."]},
    "population_feedback": {
        "defect": "historical_feedback_only", "required_decision": "retain_with_sound_feedback",
        "counterexamples": ["The increase is92,000-80,000=12,000;12,000/80,000=15%.",
                            "12,000/92,000≈13.043%, not17.4%;12,000/12,000=100%, not17.4%.",
                            "12% and17.4% are incorrect here; unexplained numerical choices need not be assigned an invented mistake."]},
    "weighted_grade_control": {
        "defect": None, "required_decision": "retain",
        "counterexamples": ["0.30*84+0.70*76=25.2+53.2=78.4.",
                            "80.0 is the equally weighted mean(84+76)/2, not the30/70 weighted mean.",
                            "82.4 would result from80/20 weighting;79.2 from40/60 weighting; neither is the stated weighting."]},
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    cases = []
    for index, (case_id, filename, call_index, item_index, eligible, answer) in enumerate(SELECTIONS):
        path = PREVIOUS / filename
        capture = json.loads(path.read_text())
        call = capture["calls"][call_index]
        raw = call["request"]["messages"][0]["content"][0]["text"]
        payload = json.loads(raw[raw.index("{"):raw.rindex("}") + 1])
        item = next(row for row in payload["items"] if row["index"] == item_index)
        solution = next(row for row in payload["independentSolutions"] if row["index"] == item_index)
        assert set(item["choices"]) == {row["choice"] for row in solution["choices"]}
        cases.append({"case_id": case_id, "batch": index // 3, "local_index": index % 3,
                      "source": {"path": str(path.relative_to(EVIDENCE.parent.parent)), "sha256": sha(path),
                                 "call_index": call_index, "item_index": item_index},
                      "historical_item": copy.deepcopy(item), "historical_independent_solution": copy.deepcopy(solution),
                      "gold": {"eligible": eligible, "answer": answer, **GOLD[case_id]}})
    packet = {
        "status": "draft_pending_independent_gold_review_and_parent_freeze",
        "scope": "Six selected historical questions; same model-independent inputs in both arms. Cases are reused diagnostics, not unseen holdouts. The two bad questions must be rejected; all four valid questions need exact keys plus sound main/all-choice feedback.",
        "input_transform": "Select exact historical item/solver objects; change only their top-level index to the batch-local index. Preserve exact prompt, choices, their order, reason/judgment bytes and metadata. Use identical explicit mixed-topic scope in each arm, empty source/coverage context. No original author key/explanation, historical reviewer output, gold or counterexamples enter model input.",
        "historical_solver_warning": "These are actual prior model judgments, not newly synthesized declarations or current independent confirmation. Some known false solver statements remain unchanged, deliberately testing the reviewer's ability to check them.",
        "prospective_criteria": {
            "planned_calls": 4, "items_per_call": 3, "items_per_arm": 6,
            "operational": "All4 responses end_turn within75s read bound, strict JSON/native schema/exact local index and feedback coverage, no retry/truncation/repair.",
            "bad_items": "2/2 valid:false with legitimate exact batch identity; a coverage/format failure or difficulty exclusion earns no semantic detection credit.",
            "valid_items": "4/4 valid:true, exact supported keys, difficulty independently assessed (inventory floor separate), all main/per-choice feedback sound and within bounds.",
            "manual": "Independently audit all final main/per-choice feedback and all retained assumptions, even for excluded rows. Any material uncertainty fails full content qualification. No after-output relabeling.",
            "rejection_reason_limit": "Current reviewer negative format supplies no explanation. A correctly indexed negative proves matching disposition, not that the model explicitly identified our intended counterexample; do not claim an independently observed defect-specific rationale.",
            "comparison": "Report paired item decisions and feedback errors. Full candidate qualification requires all6 content/decision passes and all operational checks. Report no improvement if both pass. This component trial never establishes full worker yield or broad model superiority."},
        "cases": cases,
    }
    path = HERE / "controls-draft.json"
    with path.open("x") as output:
        json.dump(packet, output, indent=2, ensure_ascii=False)
        output.write("\n")
    print(json.dumps({"packet_sha256": sha(path), "cases": len(cases), "provider_calls": 0}))


if __name__ == "__main__":
    main()
