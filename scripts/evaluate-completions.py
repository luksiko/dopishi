#!/usr/bin/env python3
"""Exercise the actual Swift inference client against an already running local server.

No downloads, app preferences, clipboard or user text are accessed. Cases are synthetic.
python3 scripts/evaluate-completions.py --port PORT --model /path/model.gguf --output results.json
"""
import argparse
import base64
import hashlib
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
def swift_string(value):
    """Represent arbitrary UTF-8 paths without JSON/Swift escape mismatches."""
    encoded = base64.b64encode(value.encode('utf-8')).decode('ascii')
    return f'String(decoding: Data(base64Encoded: "{encoded}")!, as: UTF8.self)'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--model', required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--baseline', action='store_true', help='Reproduce the old 200-character AX window')
    args = parser.parse_args()
    source = (ROOT / 'LangSwitcher/Sources/Services/AIInferenceEngine.swift').read_text()
    source_hash = hashlib.sha256(source.encode()).hexdigest()
    source = source.replace('self.session = URLSession(configuration: config)',
        'self.session = URLSession(configuration: config)\n'
        f'self.isRunning = true\nself.serverPort = {args.port}\n'
        f'self.currentLoadedModelPath = {swift_string(args.model)}')
    after_argument = ', afterCaret: item["after"] as? String ?? ""' if 'afterCaret: String' in source else ''
    runner = '''
    @MainActor final class AIModelManager {
        static let shared = AIModelManager()
        var activeModelPath: String? { nil }
    }
    @main struct EvaluationRunner {
        @MainActor static func main() async {
            let engine = AIInferenceEngine()
            while let line = readLine() {
                do {
                    let item = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
                    let start = Date()
                    let result = await engine.predictContinuation(context: item["before"] as! StringAFTER,
                        wordBuffer: item["buffer"] as? String ?? "", maxWords: 4,
                        customInstructions: "Keep it concise. Preserve technical terms in English.")
                    let output: [String: Any] = ["id": item["id"]!, "suggestion": result as Any? ?? NSNull(),
                        "seconds": Date().timeIntervalSince(start)]
                    print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), encoding: .utf8)!)
                } catch { fatalError("Evaluation input error: \\(error)") }
            }
        }
    }
    '''.replace('AFTER', after_argument)
    cases = json.loads((ROOT / 'evaluations/completions/cases.json').read_text())
    with tempfile.TemporaryDirectory(prefix='langswitcher-eval-') as temporary:
        path = pathlib.Path(temporary)
        (path / 'Runner.swift').write_text('import Combine\n' + source + runner)
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path / 'Runner.swift'), '-o', str(path / 'runner')], check=True)
        inputs = []
        for case in cases:
            case = dict(case)
            if args.baseline:
                # AX uses UTF-16 offsets, and expands a split surrogate at the window edge.
                encoded = case['before'].encode('utf-16-le')
                case['before'] = encoded[-400:].decode('utf-16-le', errors='ignore')
            inputs.append(json.dumps(case, ensure_ascii=False))
        result = subprocess.run([str(path / 'runner')], input='\n'.join(inputs) + '\n', text=True, capture_output=True, check=True)
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        assert len(rows) == len(cases)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({'model': args.model, 'baseline': args.baseline,
            'engine_sha256': source_hash, 'results': rows}, ensure_ascii=False, indent=2) + '\n')
        times = sorted(row['seconds'] for row in rows)
        print(json.dumps({'cases': len(rows), 'shown': sum(row['suggestion'] is not None for row in rows),
            'median_seconds': times[len(times)//2], 'p95_seconds': times[int((len(times)-1)*.95)],
            'output': str(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
