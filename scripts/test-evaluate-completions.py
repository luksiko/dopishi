#!/usr/bin/env python3
"""Check the evaluator's Swift path encoding without models or an inference server."""
import json
import pathlib
import runpy
import subprocess
import unittest


class EvaluationPathTests(unittest.TestCase):
    def test_generated_swift_preserves_unicode_quotes_and_backslashes(self):
        module = runpy.run_path(str(pathlib.Path(__file__).with_name('evaluate-completions.py')))
        paths = ['/tmp/Модели/нейросеть.gguf', '/tmp/Models/"quoted".gguf',
                 '/tmp/Models/back\\slash.gguf', '/tmp/Models/\\(interpolation).gguf',
                 '/tmp/Models/line\nbreak.gguf']
        expressions = ', '.join(module['swift_string'](path) for path in paths)
        source = ('import Foundation\nlet paths = [' + expressions + ']\n'
                  'print(String(decoding: try JSONSerialization.data(withJSONObject: paths), as: UTF8.self))')
        result = subprocess.run(['xcrun', 'swift', '-'], input=source, text=True,
                                capture_output=True, check=True)
        self.assertEqual(json.loads(result.stdout), paths)


if __name__ == '__main__':
    unittest.main()
