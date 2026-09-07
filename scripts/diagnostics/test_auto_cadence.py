import unittest
from analyze_auto_cadence import summarize


class CadenceTests(unittest.TestCase):
    def test_export_rounding_is_not_a_pause(self):
        self.assertEqual(summarize([0, .026667, .066667, .093333], .075)['gap_count'], 0)

    def test_pause_reports_exact_display_interval(self):
        result = summarize([0, .033333, .233333, .266667], .075)
        self.assertEqual(result['gaps_seconds'], [[.033333, .233333]])
        self.assertEqual(result['gap_count'], 1)

    def test_non_increasing_timestamp_is_not_hidden(self):
        self.assertEqual(summarize([0, 0, -.01], .075)['non_increasing_pts'], 2)


if __name__ == '__main__':
    unittest.main()
