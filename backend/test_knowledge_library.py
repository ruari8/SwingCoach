"""Checks against the actual corpus and media delivery used by the viewer."""

import importlib.util
import json
from pathlib import Path
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from analysis.knowledge_library import KnowledgeLibrary

ROOT = Path(__file__).resolve().parents[1]


class KnowledgeLibraryTests(unittest.TestCase):
    def test_corpus_references_and_contrasting_cases(self):
        library = KnowledgeLibrary()
        self.assertEqual(len(library.sources), 30)
        self.assertEqual(len(library.cases), 145)
        for case in library.cases.values():
            self.assertTrue(case["evidence"])
            for evidence in case["evidence"]:
                start, end = evidence["span_seconds"]
                self.assertLess(start, end)
                self.assertLessEqual(end, library.sources[case["source_id"]]["duration_seconds"])
        ids = {c["id"] for c in library.search("steep", limit=145)}
        self.assertIn("DVI2JDpDC5Z-C01", ids)
        self.assertIn("DdL8LyFjuAL-C01", ids)
        self.assertEqual(library.search("xyznonexistent"), [])

    def test_viewer_ranges_missing_media_and_path_boundary(self):
        spec = importlib.util.spec_from_file_location("viewer", ROOT / "scripts/knowledge_viewer.py")
        viewer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(viewer)
        server = viewer.ThreadingHTTPServer(("127.0.0.1", 0), viewer.make_handler(KnowledgeLibrary()))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_port}"
        try:
            with urlopen(base + "/api/library") as response:
                catalogue = json.load(response)
            self.assertEqual(len(catalogue["cases"]), 145)
            for path in ("/media/../../backend/.env", "/backend/.env", "/media/.videos/coaching-knowledge/missing.mp4"):
                with self.assertRaises(HTTPError) as raised:
                    urlopen(base + path)
                self.assertEqual(raised.exception.code, 404)
            videos = [p for p in catalogue["available_assets"] if p.endswith(".mp4")]
            if videos:
                path = videos[0]
                request = Request(base + "/media/" + path, headers={"Range": "bytes=100-199"})
                with urlopen(request) as response:
                    self.assertEqual(response.status, 206)
                    self.assertEqual(response.read(), (ROOT / path).read_bytes()[100:200])
                with self.assertRaises(HTTPError) as raised:
                    urlopen(Request(base + "/media/" + path, headers={"Range": "bytes=999999999999-"}))
                self.assertEqual(raised.exception.code, 416)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
