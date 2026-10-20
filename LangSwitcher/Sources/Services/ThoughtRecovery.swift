import Foundation

// MARK: - Thought Recovery
//
// Span-level text recovery for sentences that mix languages and wrong layouts
// inside one line (see docs/content/en/guide/6.thought-recovery.md, ported from
// langswitcher-linux docs/ideas/thought-recovery.md).
//
// Instead of picking ONE boundary and converting everything to the right of it
// (TextConverter.findWrongLayoutBoundary), the decoder searches segmentations
// of the whole line and rewrites only the spans where the evidence is decisive:
//
//     ghbdsn, я вже зробив rjvsn але tests gflf.nm
//     → привіт, я вже зробив коміт але tests падають
//
// Pipeline
// 1. Tokenize into word / whitespace / punctuation runs and hard-classify
//    URLs, e-mails and code tokens.
// 2. Enumerate segmentations: adjacent non-whitespace tokens may merge, because
//    a period in the middle of a wrong-layout word IS a letter (ю on
//    Ukrainian-PC): "gflf" + "." + "nm" has to be recoverable as "gflf.nm" →
//    "падають". Cutting a letter run glued by `.`/`-` costs a penalty.
// 3. Candidates per segment: keep + every layout→layout conversion of the
//    enabled layouts (LayoutMapper, including the ⌥-layer chord recovery).
// 4. Score with the embedded dictionaries (LanguageWordlists), character
//    n-gram tables built from the most frequent words, and a vowel /
//    consonant-structure factor that flags impossible letter runs ("ghbdsn" =
//    six consonants, no vowels).
// 5. Two passes: the first finds the language that carries the sentence, the
//    second re-scores every candidate with that prior. This is what breaks
//    dictionary ties — a lone "z" is Polish for "with", but in a Ukrainian
//    sentence it is the wrong layout for "я".
// 6. Beam search over segmentations with a penalty per language switch, ranked
//    by the mean evidence per segment (so splitting a word into more pieces
//    cannot win by simply accumulating score).
// 7. Margin rule, applied while a segment is evaluated: a segment is rewritten
//    only when its best candidate beats the runner-up by `minMargin`.
//    Everything else keeps the original text and is reported as `.ambiguous`.
//    Code, URLs, punctuation and real foreign words survive untouched, and
//    words the user taught us via undo always win.

@MainActor
enum ThoughtRecovery {

    // MARK: - Tuning

    private enum Tuning {
        /// A dictionary hit. Beats every non-dictionary candidate, so a real
        /// word is never rewritten on n-gram evidence alone.
        static let dictionaryScore = 1.0
        /// Short dictionary words are weaker evidence: 1–3-letter entries are
        /// ambiguous ("до" is Ukrainian "to", "z" is Polish "with"), and
        /// because they are short they collect dictionary hits by accident
        /// (a fragment of a longer word is often a word on its own). Capping
        /// them keeps "lj,ht" → "добре" instead of "до" + "ре". Same rule as
        /// the ≥4-letter floor of the single-word veto in LanguageWordlists.
        static let shortWordLetters = 4
        static let shortWordScore = 0.65
        /// A word the user taught us (reverted recovery) — beats everything.
        static let learnedWordScore = 1.6
        /// Weight of the best n-gram affinity (0…1) for unknown words.
        static let ngramWeight = 0.7
        /// Impossible letter runs scale the n-gram evidence down.
        static let structurePenalty = 0.4
        static let zeroVowelPenalty = 0.3
        /// Cost of switching language between adjacent spans.
        static let switchPenalty = 0.05
        /// Sentence-language prior: a candidate written in the language that
        /// carries the sentence is boosted. Deliberately asymmetric — other
        /// languages are NOT punished, because that would push correctly typed
        /// embedded English words ("requests") into Cyrillic n-gram noise.
        static let dominantBonus = 0.3
        /// Cost of cutting inside a letter run glued by a connector (`.`/`-`).
        static let internalSplitPenalty = 0.2
        /// Reward for reading tokens joined by a word connector (`.`/`-`) as
        /// one word: real words are fewer and longer, so the merged reading
        /// wins ties and near-ties ("lzre." to "дякую" instead of "дяку" + ".").
        /// Sentence punctuation (`,` `;` `!` ...) gets no reward — there the
        /// split is the normal reading ("ghbdtn," stays "привет,").
        static let mergedBoundaryBonus = 0.12
        /// Minimum gap between the best and the runner-up candidate before a
        /// span may be rewritten at all.
        static let minMargin = 0.25
        /// Discount for reading sentence punctuation as part of a word. It
        /// keeps "сервері," from becoming "серверіб" while still allowing
        /// "phj,bd" to become "зробив".
        ///
        /// The same discount applies in the other direction to a candidate that
        /// keeps a word glued to its own punctuation. A segment scores through
        /// its letter core, so "wt," used to explain itself as well as the bare
        /// "wt" — which left a wrong-layout "wt," unrecovered, because the
        /// whole-segment reading tied with the reading that splits the comma
        /// off. Charging for the edge punctuation lets the split win, as it
        /// should.
        static let punctuationPenalty = 0.1
        /// Segments shorter than this are never rewritten automatically. The
        /// same policy as the Space auto-correction flow: a short run is too
        /// ambiguous ("z" is Polish "with", "у" is Ukrainian "at"), and a wrong
        /// guess would silently garble real text. The preview shows such spans
        /// as `.ambiguous` instead.
        ///
        /// A lone letter is the one exception, and only when the deliberately
        /// narrow rule in `loneLetterMayChange` is met. It is what recovers the
        /// single-letter words users mistype most ("z" → "я", "s" → "і" in a
        /// Ukrainian sentence) without ever guessing.
        static let minLettersToChange = 2
        /// Below this score a candidate carries no language evidence.
        static let lowEvidenceFloor = 0.15
        static let beamWidth = 8
        /// Segments are never longer than this many tokens (bounded search).
        static let maxGroupTokens = 6
        /// Words used to train each character n-gram table.
        static let ngramTrainingWords = 2500
        /// How many alternative reconstructions to report.
        static let maxAlternatives = 2
    }

    // MARK: - Span classification

    /// Segment types. The first six come from the idea document; `.correct` and
    /// `.separator` name the spans that need no decision at all.
    enum SpanKind: String, CaseIterable {
        /// Gibberish in the active layout — a point replacement fixes it.
        case wrongLayout
        /// A real word of another language (kept): "tests" in a UA sentence.
        case intentionalForeign
        /// Identifier or snippet (`user_id`, `getUser`, `v1.2`) — kept.
        case code
        /// Link or e-mail — kept.
        case url
        /// Capitalized unknown token (`Google`) — kept.
        case properName
        /// Evidence too weak either way — original kept, shown in preview.
        case ambiguous
        /// Already the right word in the sentence's language.
        case correct
        /// Whitespace / punctuation between spans.
        case separator
    }

    // MARK: - Candidates

    enum Origin: Equatable {
        case keep
        case converted(source: String, target: String)
    }

    struct Candidate {
        let text: String
        let origin: Origin
        /// Language the candidate's own script best supports (nil = none).
        let language: LanguageWordlists.Language?
        let score: Double
        /// True when the candidate is a real word of `language`, not just
        /// n-gram plausible. Dictionary evidence is the only thing allowed to
        /// override the code and cross-script protections.
        let isDictionaryWord: Bool

        var isKeep: Bool { origin == .keep }

        var targetLayoutID: String? {
            if case .converted(_, let target) = origin { return target }
            return nil
        }
    }

    struct Span {
        /// The original text of this span (keep candidate text).
        let text: String
        let kind: SpanKind
        /// The candidate the decoder decided to use.
        let chosen: Candidate
        let candidates: [Candidate]
        /// Gap between the best candidate and the runner-up.
        let margin: Double
        let letterCount: Int

        var changed: Bool { chosen.text != text }

        var targetLayoutID: String? { chosen.targetLayoutID }
    }

    struct Plan {
        let original: String
        let reconstructed: String
        let spans: [Span]
        /// Runner-up reconstructions (best first, 0…2 entries).
        let alternatives: [String]

        var isChanged: Bool { reconstructed != original }
        var changedSpans: [Span] { spans.filter { $0.changed } }

        /// Layout the keyboard should switch to after applying: the most used
        /// conversion target among the rewritten spans.
        var primaryTargetLayoutID: String? {
            var tally: [String: Int] = [:]
            for span in changedSpans {
                guard let target = span.targetLayoutID else { continue }
                tally[target, default: 0] += max(1, span.letterCount)
            }
            return tally
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .first?.key
        }

        /// Mean margin of the rewritten spans — how decisive they were.
        var confidence: Double {
            let changed = changedSpans
            guard !changed.isEmpty else { return 0 }
            return changed.reduce(0) { $0 + $1.margin } / Double(changed.count)
        }
    }

    // MARK: - Metrics (idea document MVP)

    struct Metrics {
        let sentenceCount: Int
        /// Share of sentences reconstructed exactly as expected.
        let exactMatchRate: Double
        /// Mean character-level accuracy (1 − edit distance / length).
        let characterRecoveryAccuracy: Double
        /// Share of characters rewritten in text that had to stay untouched.
        let falseReplacementRate: Double
    }

    // MARK: - Entry points

    /// Decode a line into a recovery plan. Pure function of the text, the
    /// enabled layout ids and the user's learned words.
    static func decode(
        _ text: String,
        layoutIDs: [String],
        learnedWords: Set<String> = []
    ) -> Plan {
        Decoder(layoutIDs: layoutIDs, learnedWords: learnedWords).decode(text)
    }

    /// Measure the decoder against a labelled corpus: wrong-layout input with
    /// its expected reconstruction (accuracy) and correct input that must not
    /// change (false replacements).
    static func evaluate(
        _ pairs: [(input: String, expected: String)],
        layoutIDs: [String],
        learnedWords: Set<String> = []
    ) -> Metrics {
        var exact = 0
        var accuracySum = 0.0
        var recoveryCount = 0
        var changedCharacters = 0
        var untouchedCharacters = 0

        for pair in pairs {
            let plan = decode(pair.input, layoutIDs: layoutIDs, learnedWords: learnedWords)
            if plan.reconstructed == pair.expected { exact += 1 }
            if pair.input == pair.expected {
                changedCharacters += differenceCount(plan.reconstructed, pair.input)
                untouchedCharacters += pair.input.count
            } else {
                accuracySum += characterAccuracy(plan.reconstructed, expected: pair.expected)
                recoveryCount += 1
            }
        }

        let count = pairs.count
        return Metrics(
            sentenceCount: count,
            exactMatchRate: count == 0 ? 0 : Double(exact) / Double(count),
            characterRecoveryAccuracy: recoveryCount == 0 ? 0 : accuracySum / Double(recoveryCount),
            falseReplacementRate: untouchedCharacters == 0
                ? 0
                : Double(changedCharacters) / Double(untouchedCharacters)
        )
    }

    // MARK: - Metrics helpers

    /// 1 − (edit distance / length of the expected text).
    static func characterAccuracy(_ text: String, expected: String) -> Double {
        guard !expected.isEmpty else { return text.isEmpty ? 1 : 0 }
        let distance = editDistance(Array(text), Array(expected))
        return max(0, 1 - Double(distance) / Double(expected.count))
    }

    /// Number of positions where two strings differ (a length difference counts
    /// as the extra characters).
    static func differenceCount(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        var count = abs(a.count - b.count)
        for index in 0..<min(a.count, b.count) where a[index] != b[index] {
            count += 1
        }
        return count
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    // MARK: - Decoder
    //
    // An instance holds the configuration plus the per-run state (beam states,
    // the sentence language of the current pass) so decoding stays cheap.

    @MainActor
    private final class Decoder {

        private let layoutIDs: [String]
        private let learned: Set<String>

        /// Sentence language of the current pass (nil on the first pass).
        private var dominant: LanguageWordlists.Language?

        /// Flat state list of the last beam search, needed to walk paths.
        private var states: [BeamState] = []

        init(layoutIDs: [String], learnedWords: Set<String>) {
            self.layoutIDs = layoutIDs
            self.learned = learnedWords
        }

        // MARK: Types

        private struct RawToken {
            enum Kind { case word, punct, whitespace }
            var text: String
            var kind: Kind
            var isURL = false
            var isCode = false
            var hasLetters: Bool { text.contains(where: \.isLetter) }
        }

        /// One candidate segmentation step with its decision already made.
        private struct GroupChoice {
            let range: Range<Int>
            /// Original text of the segment.
            let text: String
            let isURL: Bool
            let isCode: Bool
            let letterCount: Int
            /// Candidates, best first.
            let candidates: [Candidate]
            /// Best candidate (may differ from `applied`).
            let best: Candidate
            /// What the decoder will actually use (best when decisive, else the
            /// original text).
            let applied: Candidate
            /// Gap between the best candidate and the runner-up.
            let margin: Double

            var changed: Bool { applied.text != text }
        }

        private struct BeamState {
            let score: Double          // sum of the applied scores
            let letterGroups: Int      // segments that carry letters
            let switches: Int          // language switches between those
            let internalSplits: Int    // cuts inside a glued letter run
            let mergedBoundaries: Int  // tokens read as one word
            let language: LanguageWordlists.Language?
            let choice: GroupChoice?
            let prev: Int
            let nextToken: Int

            var normalized: Double { score / Double(max(1, letterGroups)) }

            /// Pruning/ranking criterion: mean evidence per segment, minus the
            /// structural costs and plus the merge preference. Used everywhere
            /// so the beam never keeps a path it would rank lower at the end.
            var rank: Double {
                normalized
                    - Tuning.switchPenalty * Double(switches)
                    - Tuning.internalSplitPenalty * Double(internalSplits)
                    + Tuning.mergedBoundaryBonus * Double(mergedBoundaries)
            }
        }

        // MARK: Decode

        func decode(_ text: String) -> Plan {
            let tokens = tokenize(text)

            guard tokens.contains(where: { $0.hasLetters }) else {
                return Plan(original: text, reconstructed: text, spans: [], alternatives: [])
            }

            // Pass 1 finds the language that carries the sentence, pass 2
            // re-scores every candidate with that prior. Two passes are enough
            // and they keep the result deterministic.
            let first = attempt(tokens)
            guard first.dominant != nil else { return first.plan }
            dominant = first.dominant
            return attempt(tokens).plan
        }

        /// One full decode: beam search, decisions, classification.
        private func attempt(_ tokens: [RawToken]) -> (plan: Plan, dominant: LanguageWordlists.Language?) {
            let original = tokens.map(\.text).joined()
            let finalists = beamSearch(tokens)
            guard let bestIndex = finalists.first else {
                return (Plan(original: original, reconstructed: original, spans: [], alternatives: []), nil)
            }

            let path = choices(along: bestIndex)
            let spans = classify(path)
            let reconstructed = spans.map { $0.chosen.text }.joined()

            // Alternatives: other segmentation paths from the same beam.
            var alternatives: [String] = []
            for stateIndex in finalists.dropFirst() {
                guard alternatives.count < Tuning.maxAlternatives else { break }
                let alternative = choices(along: stateIndex).map { $0.applied.text }.joined()
                guard alternative != reconstructed, !alternatives.contains(alternative) else { continue }
                alternatives.append(alternative)
            }

            return (Plan(
                original: original,
                reconstructed: reconstructed,
                spans: spans,
                alternatives: alternatives
            ), dominantLanguage(of: path))
        }

        // MARK: Beam search

        private func beamSearch(_ tokens: [RawToken]) -> [Int] {
            states = [
                BeamState(score: 0, letterGroups: 0, switches: 0, internalSplits: 0,
                          mergedBoundaries: 0, language: nil, choice: nil, prev: -1, nextToken: 0)
            ]
            // One beam per token position. A segment can span several tokens, so
            // a position may be reached from several earlier ones — the beam for
            // a position must therefore be pruned only once every earlier
            // position has been expanded (i.e. when we get there).
            var beams: [[Int]] = Array(repeating: [], count: tokens.count + 1)
            beams[0] = [0]
            let letterPunctuation = letterPunctuationBoundaries(tokens)
            let gluedStarts = gluedRunStarts(tokens).union(letterPunctuation)
            let connectorBoundaries = connectorBoundaries(tokens).union(letterPunctuation)
            let isolatedLetters = isolatedLoneLetters(tokens)

            for position in 0..<tokens.count {
                guard !beams[position].isEmpty else { continue }
                beams[position] = prune(beams[position])

                for stateIndex in beams[position] {
                    let state = states[stateIndex]
                    for end in groupEnds(from: position, tokens: tokens) {
                        let choice = groupChoice(
                            tokens[position..<end],
                            range: position..<end,
                            isIsolatedLoneLetter: isolatedLetters.contains(position) && end == position + 1
                        )

                        var switches = state.switches
                        var language = state.language
                        if choice.letterCount > 0, let chosenLanguage = choice.applied.language {
                            if let previous = state.language, previous != chosenLanguage { switches += 1 }
                            language = chosenLanguage
                        }

                        states.append(BeamState(
                            score: state.score + choice.applied.score,
                            letterGroups: state.letterGroups + (choice.letterCount > 0 ? 1 : 0),
                            switches: switches,
                            internalSplits: state.internalSplits + (gluedStarts.contains(position) ? 1 : 0),
                            mergedBoundaries: state.mergedBoundaries + mergedConnectors(from: position, to: end, boundaries: connectorBoundaries, isLexical: choice.letterCount > 0),
                            language: language,
                            choice: choice,
                            prev: stateIndex,
                            nextToken: end
                        ))
                        beams[end].append(states.count - 1)
                    }
                }
            }

            // Complete paths only (every token consumed), best first.
            return beams[tokens.count]
                .sorted(by: rankOrder)
                .prefix(Tuning.beamWidth * 2)
                .map { $0 }
        }

        /// Deterministic ordering: rank, then simpler segmentations (fewer
        /// segments = fewer cuts), then stable by state index.
        private func rankOrder(_ lhs: Int, _ rhs: Int) -> Bool {
            let a = states[lhs]
            let b = states[rhs]
            if a.rank != b.rank { return a.rank > b.rank }
            if a.internalSplits != b.internalSplits { return a.internalSplits < b.internalSplits }
            if a.letterGroups != b.letterGroups { return a.letterGroups < b.letterGroups }
            return lhs < rhs
        }

        private func prune(_ indices: [Int], limit: Int? = nil) -> [Int] {
            Array(indices.sorted(by: rankOrder).prefix(limit ?? Tuning.beamWidth))
        }

        private func choices(along stateIndex: Int) -> [GroupChoice] {
            var result: [GroupChoice] = []
            var index = stateIndex
            while let choice = states[index].choice {
                result.append(choice)
                index = states[index].prev
            }
            return result.reversed()
        }

        // MARK: Segmentation

        /// Allowed group boundaries starting at `start` (exclusive end indices):
        /// whitespace always splits, code tokens are atomic, and URLs only merge
        /// with URLs.
        private func groupEnds(from start: Int, tokens: [RawToken]) -> [Int] {
            if tokens[start].kind == .whitespace {
                var end = start
                while end < tokens.count, tokens[end].kind == .whitespace { end += 1 }
                return [end]
            }

            var ends: [Int] = []
            var end = start
            var length = 0
            while end < tokens.count, tokens[end].kind != .whitespace, length < Tuning.maxGroupTokens {
                if end > start {
                    let previous = tokens[end - 1]
                    let current = tokens[end]
                    if isAtomic(previous) { break }
                    if current.isURL != previous.isURL { break }
                }
                end += 1
                length += 1
                ends.append(end)
            }
            return ends.isEmpty ? [start + 1] : ends
        }

        /// Tokens that must not be glued to their neighbours.
        private func isAtomic(_ token: RawToken) -> Bool {
            if token.kind == .whitespace { return true }
            if token.isURL { return true }
            if token.text.allSatisfy(\.isNumber) { return true }
            return token.isCode
        }

        /// Did `token` consist only of word connectors?
        private func isConnector(_ token: RawToken) -> Bool {
            guard token.kind == .punct, !token.text.isEmpty else { return false }
            return token.text.allSatisfy { $0 == "." || $0 == "-" || $0 == "–" }
        }

        /// Token boundaries with a word connector on either side. Merging a
        /// letter segment across one of them is the normal reading of a
        /// wrong-layout word, so those merges are rewarded.
        private func connectorBoundaries(_ tokens: [RawToken]) -> Set<Int> {
            var boundaries: Set<Int> = []
            guard tokens.count > 1 else { return boundaries }
            for position in 1..<tokens.count where isConnector(tokens[position - 1]) || isConnector(tokens[position]) {
                boundaries.insert(position)
            }
            return boundaries
        }

        /// How many connector boundaries a letter segment [start, end) spans.
        private func mergedConnectors(from start: Int, to end: Int, boundaries: Set<Int>, isLexical: Bool) -> Int {
            guard isLexical, end > start + 1 else { return 0 }
            return boundaries.filter { $0 > start && $0 < end }.count
        }

        /// Segment start positions that would cut inside a letter run glued by a
        /// connector punctuation (`.`/`-` between letters). Such a character is
        /// very likely part of the word itself — on Ukrainian-PC the period key
        /// types ю — so cutting "gflf.nm" into pieces costs
        /// `internalSplitPenalty`. Runs where the connector is NOT followed by
        /// letters (a sentence period like "rjvsn.") stay free to split.
        private func gluedRunStarts(_ tokens: [RawToken]) -> Set<Int> {
            var penalized: Set<Int> = []
            var index = 0
            while index < tokens.count {
                guard tokens[index].kind != .whitespace else {
                    index += 1
                    continue
                }
                var end = index
                while end < tokens.count, tokens[end].kind != .whitespace { end += 1 }

                let isGlued = (index + 1) < end && (index + 1..<end).contains { position in
                    isConnector(tokens[position - 1]) && tokens[position].hasLetters
                }
                if isGlued {
                    for position in (index + 1)..<end { penalized.insert(position) }
                }
                index = end
            }
            return penalized
        }

        /// Token positions holding a single letter that stands alone in its
        /// whitespace-delimited run. Only such a letter may be rewritten by
        /// itself — see `loneLetterMayChange`.
        private func isolatedLoneLetters(_ tokens: [RawToken]) -> Set<Int> {
            var isolated: Set<Int> = []
            var index = 0
            while index < tokens.count {
                guard tokens[index].kind != .whitespace else {
                    index += 1
                    continue
                }
                let runStart = index
                while index < tokens.count, tokens[index].kind != .whitespace { index += 1 }

                let letterTokens = (runStart..<index).filter { tokens[$0].hasLetters }
                if letterTokens.count == 1, let only = letterTokens.first,
                   tokens[only].kind == .word, tokens[only].text.count == 1 {
                    isolated.insert(only)
                }
            }
            return isolated
        }

        /// Punctuation that is really a letter when it sits *between* two
        /// letters of one token run, because the PC layout puts a Cyrillic
        /// letter on that key: `,` types б, `;` types ж (`.` types ю and is
        /// covered by `isConnector`). So "cghj,eq" is "спробуй" and "d;t" is
        /// "вже".
        ///
        /// Only that position qualifies. A comma that ends a run ("rjvsn,") or
        /// is followed by whitespace ("сервері, cghj,eq") is sentence
        /// punctuation and keeps its normal reading — the distinction is
        /// positional, so no ordinary sentence gains or loses a cut here.
        ///
        /// Returns the boundaries around that punctuation, so the two existing
        /// mechanisms apply unchanged: crossing them merges a word (reward) and
        /// starting a segment on them cuts a word (penalty).
        private func letterPunctuationBoundaries(_ tokens: [RawToken]) -> Set<Int> {
            var boundaries: Set<Int> = []
            guard tokens.count >= 3 else { return boundaries }
            for index in 1..<(tokens.count - 1) {
                let token = tokens[index]
                guard token.kind == .punct, token.text.allSatisfy({ $0 == "," || $0 == ";" }) else { continue }
                guard tokens[index - 1].hasLetters, tokens[index + 1].hasLetters else { continue }
                boundaries.insert(index)
                boundaries.insert(index + 1)
            }
            return boundaries
        }

        // MARK: Segment evaluation

        private func groupChoice(_ tokens: ArraySlice<RawToken>, range: Range<Int>,
                                 isIsolatedLoneLetter: Bool) -> GroupChoice {
            let text = tokens.map(\.text).joined()
            let isURL = tokens.allSatisfy(\.isURL)
            let isCode = !isURL && tokens.contains(where: \.isCode)
            let letterCount = text.filter(\.isLetter).count

            var keepEvidence = evidence(for: text)
            if Self.hasEdgeSentencePunctuation(text) {
                keepEvidence = Evidence(
                    language: keepEvidence.language,
                    score: max(0, keepEvidence.score - Tuning.punctuationPenalty),
                    isDictionaryWord: keepEvidence.isDictionaryWord
                )
            }
            let keep = Candidate(text: text, origin: .keep,
                                 language: keepEvidence.language,
                                 score: keepEvidence.score,
                                 isDictionaryWord: keepEvidence.isDictionaryWord)
            var candidates: [Candidate] = [keep]

            // A lone letter that stands alone in its token run still gets
            // candidates, because it can be a decisive wrong-layout word.
            // Letters surrounded by other letters ("d;t") never do: there the
            // letter belongs to the word, and rewriting it on its own would
            // beat the merged reading that actually spells the word.
            let loneLetterEligible = isIsolatedLoneLetter && letterCount == 1 && text.count == 1

            if !isURL, layoutIDs.count >= 2,
               letterCount >= Tuning.minLettersToChange || loneLetterEligible {
                for source in layoutIDs {
                    for target in layoutIDs where target != source {
                        guard let converted = LayoutMapper.convert(text: text, from: source, to: target) else { continue }
                        guard converted != text, converted.contains(where: \.isLetter) else { continue }
                        var convertedEvidence = evidence(for: converted)

                        // Code protection is soft: a snippet-like token is only
                        // rewritten when the result is a real dictionary word
                        // (all-caps "GHBDTN" → "ПРИВІТ").
                        if isCode, !convertedEvidence.isDictionaryWord { continue }

                        // Trailing-punctuation discount (see punctuationPenalty).
                        if Self.endsWithSentencePunctuationReplaced(text, converted) {
                            convertedEvidence = Evidence(
                                language: convertedEvidence.language,
                                score: max(0, convertedEvidence.score - Tuning.punctuationPenalty),
                                isDictionaryWord: convertedEvidence.isDictionaryWord
                            )
                        }

                        // A real word of one script is never rewritten into a
                        // merely n-gram-plausible string of another script —
                        // that is what keeps "hello", "pull" and "request" safe
                        // inside a Ukrainian sentence.
                        if keepEvidence.isDictionaryWord,
                           !convertedEvidence.isDictionaryWord,
                           Self.writingScript(of: text) != Self.writingScript(of: converted) {
                            continue
                        }

                        candidates.append(Candidate(
                            text: converted,
                            origin: .converted(source: source, target: target),
                            language: convertedEvidence.language,
                            score: convertedEvidence.score,
                            isDictionaryWord: convertedEvidence.isDictionaryWord
                        ))
                    }
                }
            }

            candidates.sort { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.isKeep != rhs.isKeep { return lhs.isKeep }
                return lhs.text < rhs.text
            }
            var unique: [Candidate] = []
            var seen: Set<String> = []
            for candidate in candidates where seen.insert(candidate.text).inserted {
                unique.append(candidate)
            }

            let best = unique[0]
            let margin = unique.count > 1 ? best.score - unique[1].score : best.score

            // Decide here, once: the beam ranks paths by what will actually be
            // written, so a rejected (low-margin) candidate cannot win a path
            // and then be reverted.
            let isDecisive: Bool
            if best.isKeep || margin < Tuning.minMargin {
                isDecisive = false
            } else if letterCount < Tuning.minLettersToChange {
                isDecisive = loneLetterEligible
                    && loneLetterMayChange(text, candidate: best, dominant: dominant)
            } else {
                isDecisive = true
            }

            return GroupChoice(
                range: range,
                text: text,
                isURL: isURL,
                isCode: isCode,
                letterCount: letterCount,
                candidates: unique,
                best: best,
                applied: isDecisive ? best : keep,
                margin: margin
            )
        }

        /// The one case where a single character may be rewritten on its own: a
        /// lone lowercase Latin letter standing alone inside a sentence carried
        /// by a Cyrillic language, whose wrong-layout reading is a real word of
        /// that language — "z" → "я", "s" → "і".
        ///
        /// Deliberately narrow. Every single Latin letter is an entry in the
        /// English and Polish lists ("a", "z", "i" …), so a wider rule would
        /// turn a stray Cyrillic "у" in an English-heavy line into "e", an
        /// uppercase "S" (a size, an option) into "І", and a Polish "z" into
        /// "я". Only the wrong-layout direction — Latin letter, Cyrillic
        /// sentence, lowercase, real word of the sentence language — is safe.
        private func loneLetterMayChange(_ text: String, candidate: Candidate,
                                         dominant: LanguageWordlists.Language?) -> Bool {
            guard let dominant = dominant else { return false }
            guard Self.writingScript(of: dominant) == "cyrillic" else { return false }
            guard Self.writingScript(of: text) == "latin" else { return false }
            guard text.first?.isLowercase == true else { return false }
            guard Self.writingScript(of: candidate.text) == "cyrillic" else { return false }
            return candidate.isDictionaryWord && candidate.language == dominant
        }

        // MARK: Classification

        /// Language that carries the sentence: a letter-weighted vote over the
        /// decided candidates, restricted to the sentence's majority writing
        /// system so embedded foreign words cannot hijack it.
        private func dominantLanguage(of path: [GroupChoice]) -> LanguageWordlists.Language? {
            // Links and identifiers are not language evidence.
            let lexical = path.filter { !$0.isURL && !$0.isCode }

            var scriptWeight: [String: Int] = [:]
            for choice in lexical {
                guard let language = choice.applied.language, choice.letterCount >= 2 else { continue }
                scriptWeight[Self.writingScript(of: language), default: 0] += choice.letterCount
            }
            let rankedScripts = scriptWeight.sorted {
                $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
            }
            guard let majority = rankedScripts.first?.key else { return nil }

            var tally: [LanguageWordlists.Language: Int] = [:]
            for choice in lexical {
                guard let language = choice.applied.language, choice.letterCount >= 2 else { continue }
                guard Self.writingScript(of: language) == majority else { continue }
                // Dictionary evidence outvotes n-gram evidence.
                tally[language, default: 0] += choice.letterCount * (choice.applied.isDictionaryWord ? 2 : 1)
            }
            return tally
                .sorted { $0.value != $1.value ? $0.value > $1.value : languageOrder($0.key) < languageOrder($1.key) }
                .first?.key
        }

        private func classify(_ path: [GroupChoice]) -> [Span] {
            let dominant = dominantLanguage(of: path)
            return path.map { choice in
                Span(
                    text: choice.text,
                    kind: spanKind(choice: choice, dominant: dominant),
                    chosen: choice.applied,
                    candidates: choice.candidates,
                    margin: choice.margin,
                    letterCount: choice.letterCount
                )
            }
        }

        private func spanKind(choice: GroupChoice, dominant: LanguageWordlists.Language?) -> SpanKind {
            if choice.letterCount == 0 { return .separator }
            if choice.isURL { return .url }
            if choice.changed { return .wrongLayout }
            if choice.isCode { return .code }

            let chosen = choice.applied
            if isCapitalized(choice.text), !chosen.isDictionaryWord {
                return .properName
            }
            if let language = chosen.language {
                if language == dominant { return .correct }
                if chosen.score >= Tuning.lowEvidenceFloor { return .intentionalForeign }
            }
            return .ambiguous
        }

        private func languageOrder(_ language: LanguageWordlists.Language) -> Int {
            switch language {
            case .ukrainian: return 0
            case .russian: return 1
            case .polish: return 2
            case .english: return 3
            }
        }

        private func isCapitalized(_ text: String) -> Bool {
            guard let first = text.first(where: \.isLetter) else { return false }
            return first.isUppercase
        }

        // MARK: Evidence

        private struct Evidence {
            let language: LanguageWordlists.Language?
            let score: Double
            let isDictionaryWord: Bool
        }

        /// Language and score for a candidate text: dictionary hit first, then
        /// n-gram affinity scaled by the letter-run structure, then the
        /// sentence-language boost.
        private func evidence(for text: String) -> Evidence {
            let core = Self.wordCore(of: text)
            guard !core.isEmpty else { return Evidence(language: nil, score: 0, isDictionaryWord: false) }

            if learned.contains(core.lowercased()) {
                // The user taught us this word: strongest possible evidence, and
                // it carries no language (no prior boost, no switch cost).
                return Evidence(language: nil, score: Tuning.learnedWordScore, isDictionaryWord: false)
            }
            guard let script = LanguageWordlists.writingScript(of: core) else {
                return Evidence(language: nil, score: 0, isDictionaryWord: false)
            }

            var bestLanguage: LanguageWordlists.Language?
            var bestScore = 0.0
            var bestIsDictionaryWord = false
            for language in LanguageWordlists.languages(writing: script) {
                let isWord = LanguageWordlists.isDictionaryWord(core, language: language)
                let score: Double
                if isWord {
                    score = core.count >= Tuning.shortWordLetters
                        ? Tuning.dictionaryScore
                        : Tuning.shortWordScore
                } else {
                    let affinity = ngramAffinity(core, language: language)
                    score = Tuning.ngramWeight * affinity * structureFactor(core)
                }
                // Dictionary evidence outranks n-gram evidence, even a short
                // word's. A 1–3 letter reading scores up to `ngramWeight`
                // (0.7), which used to mask a real dictionary hit in the other
                // language (0.65). Reporting a genuine word as "not a word"
                // silently switched off the script-crossing protection below,
                // so "wt" (an English entry) could never recover to "це" even
                // though "це" is a real Ukrainian word.
                if bestIsDictionaryWord, !isWord { continue }
                if isWord, !bestIsDictionaryWord {
                    bestScore = score
                    bestLanguage = language
                    bestIsDictionaryWord = true
                    continue
                }

                // A tie means both languages explain the word equally well, so
                // the language that carries the sentence settles it. This is
                // what makes a lone "z" recover to Ukrainian "я" rather than
                // stay Polish "with" (and the reverse in Polish text).
                if score > bestScore || (score == bestScore && score > 0 && language == dominant) {
                    bestScore = score
                    bestLanguage = language
                    bestIsDictionaryWord = isWord
                }
            }

            guard let language = bestLanguage, bestScore >= Tuning.lowEvidenceFloor else {
                // Too weak to name a language, but the score still counts.
                return Evidence(language: nil, score: bestScore, isDictionaryWord: false)
            }

            let adjusted = language == dominant ? bestScore + Tuning.dominantBonus : bestScore
            return Evidence(language: language, score: adjusted, isDictionaryWord: bestIsDictionaryWord)
        }

        private func ngramAffinity(_ text: String, language: LanguageWordlists.Language) -> Double {
            let cleaned = Self.ngramCleaned(text)
            guard !cleaned.isEmpty else { return 0 }
            let characters = Array("^" + cleaned + "$")
            guard characters.count >= 3 else { return 0 }

            let table = ngramTable(for: language)
            var hits = 0
            var total = 0
            for index in 0..<(characters.count - 2) {
                total += 1
                if table.contains(String(characters[index...(index + 2)])) { hits += 1 }
            }
            return total == 0 ? 0 : Double(hits) / Double(total)
        }

        /// Impossible letter runs (a vowel-less six-consonant word) cut the
        /// n-gram evidence down: "ghbdsn" / "rjvsn" can never be real words.
        private func structureFactor(_ text: String) -> Double {
            let letters = Array(text.lowercased().filter(\.isLetter))
            guard letters.count >= 3 else { return 1.0 }

            var vowels = 0
            var run = 0
            var maxRun = 0
            for letter in letters {
                if Self.isVowel(letter) {
                    vowels += 1
                    run = 0
                } else {
                    run += 1
                    maxRun = max(maxRun, run)
                }
            }
            if maxRun >= 4 { return Tuning.structurePenalty }
            if vowels == 0 { return Tuning.zeroVowelPenalty }
            return 1.0
        }

        // MARK: N-gram tables

        private static var tables: [LanguageWordlists.Language: Set<String>] = [:]

        private func ngramTable(for language: LanguageWordlists.Language) -> Set<String> {
            if let cached = Self.tables[language] { return cached }

            var table: Set<String> = []
            for word in LanguageWordlists.topWords(language, limit: Tuning.ngramTrainingWords) {
                let cleaned = Self.ngramCleaned(word)
                guard !cleaned.isEmpty else { continue }
                let characters = Array("^" + cleaned + "$")
                guard characters.count >= 3 else { continue }
                for index in 0..<(characters.count - 2) {
                    table.insert(String(characters[index...(index + 2)]))
                }
            }
            Self.tables[language] = table
            return table
        }

        // MARK: Tokenizing

        private func tokenize(_ text: String) -> [RawToken] {
            let characters = Array(text)
            let urlRanges = Self.urlRanges(in: characters)

            var tokens: [RawToken] = []
            var index = 0
            while index < characters.count {
                let start = index
                let kind: RawToken.Kind
                if characters[index].isWhitespace {
                    kind = .whitespace
                } else if Self.isWordCharacter(characters[index]) {
                    kind = .word
                } else {
                    kind = .punct
                }
                while index < characters.count, matches(characters[index], kind: kind) { index += 1 }

                var token = RawToken(text: String(characters[start..<index]), kind: kind)
                if kind != .whitespace {
                    token.isURL = urlRanges.contains { $0.lowerBound <= start && $0.upperBound >= index }
                    if !token.isURL, kind == .word { token.isCode = Self.looksLikeCode(token.text) }
                }
                tokens.append(token)
            }
            return tokens
        }

        private func matches(_ character: Character, kind: RawToken.Kind) -> Bool {
            switch kind {
            case .whitespace: return character.isWhitespace
            case .word: return Self.isWordCharacter(character)
            case .punct: return !character.isWhitespace && !Self.isWordCharacter(character)
            }
        }

        // MARK: Static text helpers

        /// Letters, digits, underscore and apostrophes stay inside a token so
        /// "user_id", "don't" and "з'їсти" survive as single spans.
        private static func isWordCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "'" || character == "’"
        }

        /// Trimmed to the first/last letter so a trailing comma does not hide a
        /// dictionary hit ("привіт," is still "привіт").
        static func wordCore(of text: String) -> String {
            let characters = Array(text)
            guard let first = characters.firstIndex(where: \.isLetter),
                  let last = characters.lastIndex(where: \.isLetter),
                  first <= last else { return "" }
            return String(characters[first...last])
        }

        /// N-gram form: lowercase letters and inner dots (a dot inside a
        /// wrong-layout word is a letter), word connectors removed.
        private static func ngramCleaned(_ text: String) -> String {
            String(text.lowercased().filter { $0.isLetter || $0 == "." })
        }

        /// "latin" / "cyrillic" of a text, or "other" when it cannot be told
        /// (digits, punctuation, mixed scripts).
        private static func writingScript(of text: String) -> String {
            LanguageWordlists.writingScript(of: text) ?? "other"
        }

        private static func writingScript(of language: LanguageWordlists.Language) -> String {
            switch language {
            case .polish, .english: return "latin"
            case .ukrainian, .russian: return "cyrillic"
            }
        }

        private static let vowels: Set<Character> = [
            "a", "e", "i", "o", "u", "y", "ą", "ę", "ó",
            "а", "е", "є", "и", "і", "ї", "о", "у", "ю", "я", "ы", "э", "ё",
        ]

        private static func isVowel(_ character: Character) -> Bool {
            vowels.contains(character)
        }

        /// Sentence punctuation the user typed on purpose (, ; : ! ? ...).
        /// The word connectors `.` `-` and the in-word apostrophe are NOT
        /// punctuation here, because inside a wrong-layout word they are
        /// letters (on Ukrainian-PC `.` types ю and `,` types б).
        static func isSentencePunctuation(_ character: Character) -> Bool {
            guard !character.isLetter, !character.isNumber, !character.isWhitespace else { return false }
            return character != "." && character != "-" && character != "–"
                && character != "_" && character != "'" && character != "’"
        }

        /// Does the conversion end with a letter where the original had
        /// sentence punctuation? A trailing comma or question mark is normally
        /// just punctuation ("сервері," must not become "серверіб"), while an
        /// internal one is normal for a wrong-layout word ("phj,bd" is
        /// "зробив"). Only the trailing reading is discounted.
        static func endsWithSentencePunctuationReplaced(_ original: String, _ converted: String) -> Bool {
            guard let source = original.last, let target = converted.last else { return false }
            return isSentencePunctuation(source) && target.isLetter
        }

        /// Does the segment carry sentence punctuation on either edge? Such a
        /// segment explains its word no better than the bare word does, so it
        /// is worth the punctuation discount (see `punctuationPenalty`).
        static func hasEdgeSentencePunctuation(_ text: String) -> Bool {
            guard let first = text.first, let last = text.last else { return false }
            return isSentencePunctuation(first) || isSentencePunctuation(last)
        }

        /// Identifiers and snippets: underscores, digits, camelCase and
        /// SCREAMING_CASE. A wrong-layout word can be all caps too ("GHBDTN"),
        /// so callers soften this with dictionary evidence.
        static func looksLikeCode(_ text: String) -> Bool {
            if text.contains("_") { return true }
            let letters = Array(text.filter(\.isLetter))
            guard !letters.isEmpty else { return false }
            if text.contains(where: \.isNumber) { return true }
            if letters.count > 1, letters.dropFirst().contains(where: \.isUppercase) { return true }
            if letters.count >= 3, letters.allSatisfy(\.isUppercase) { return true }
            return false
        }

        // MARK: URL scanning

        private static let knownTLDs: Set<String> = [
            "com", "org", "net", "io", "dev", "app", "edu", "gov", "info", "site",
            "online", "tech", "blog", "wiki", "me", "co", "uk", "ua", "pl", "ru",
            "de", "fr", "es", "it", "nl", "se", "no", "fi", "cz", "sk", "us", "ca",
            "au", "jp", "cn", "in", "br", "ch", "at", "dk", "ee", "lt", "lv", "md",
            "by", "kz", "be", "ai", "sh", "gg", "tv", "cc", "ly", "xyz",
        ]

        private static func isURLSign(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || "-_.~:/?#[]@!$&'()*+,;=%".contains(character)
        }

        private static func isURLWordSign(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
        }

        /// Character ranges that look like links, e-mails or domains, so the
        /// decoder never "fixes" them into gibberish.
        static func urlRanges(in characters: [Character]) -> [Range<Int>] {
            var ranges: [Range<Int>] = []
            var index = 0
            while index < characters.count {
                var seed: Range<Int>?
                if characters[index] == ":", index + 2 < characters.count,
                   characters[index + 1] == "/", characters[index + 2] == "/" {
                    seed = index..<(index + 3)
                } else if characters[index] == "@" {
                    seed = index..<(index + 1)
                } else if isURLWordSign(characters[index]), index == 0 || !isURLWordSign(characters[index - 1]) {
                    var end = index
                    while end < characters.count, isURLWordSign(characters[end]) { end += 1 }
                    if hasDomainSuffix(characters, index..<end) { seed = index..<end }
                }

                guard let found = seed else {
                    index += 1
                    continue
                }
                var start = found.lowerBound
                while start > 0, isURLSign(characters[start - 1]) { start -= 1 }
                var end = found.upperBound
                while end < characters.count, isURLSign(characters[end]) { end += 1 }
                while end > start, ",.!?;:)]}\"'".contains(characters[end - 1]) { end -= 1 }

                if end - start >= 5 {
                    ranges.append(start..<end)
                    index = end
                } else {
                    index = max(found.upperBound, index + 1)
                }
            }
            return ranges
        }

        /// "github.com", "langswitcher.io/path", "example.com.ua" — a run of
        /// labels whose last one is a known TLD. Deliberately ignores "i.e" and
        /// "etc." by requiring a two-character first label.
        private static func hasDomainSuffix(_ characters: [Character], _ range: Range<Int>) -> Bool {
            let run = String(characters[range])
            let labels = run.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard labels.count >= 2, labels[0].count >= 2 else { return false }
            guard let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter) else { return false }
            guard knownTLDs.contains(tld.lowercased()) else { return false }
            return labels.dropLast().allSatisfy { !$0.isEmpty && $0.count <= 30 }
        }
    }
}
