import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
CHECKER = ROOT_DIR / "scripts" / "check_benchmark_drift.py"


class BenchmarkDriftTests(unittest.TestCase):
    def test_repository_readme_matches_canonical_benchmarks(self):
        completed = subprocess.run(
            ["python3", str(CHECKER)],
            cwd=ROOT_DIR,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_changed_performance_value_is_reported_as_drift(self):
        readme = (ROOT_DIR / "README.md").read_text(encoding="utf-8")
        changed = readme.replace(
            "| **Stock `Q4_K_M` (Baseline)** | 32K / FP16 KV | 12.27 tok/s |",
            "| **Stock `Q4_K_M` (Baseline)** | 32K / FP16 KV | 12.28 tok/s |",
            1,
        )

        with tempfile.TemporaryDirectory() as directory:
            changed_readme = Path(directory) / "README.md"
            changed_readme.write_text(changed, encoding="utf-8")
            completed = subprocess.run(
                ["python3", str(CHECKER), "--readme", str(changed_readme)],
                cwd=ROOT_DIR,
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(completed.returncode, 1)
        self.assertIn("Optimization Stages", completed.stderr)


if __name__ == "__main__":
    unittest.main()
