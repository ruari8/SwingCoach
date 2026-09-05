"""Build the playground against the current production player and pager."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[3] / "SwingCoach"
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
source = (root / "LibraryView.swift").read_text()
start = source.index("struct PlaybackChromeView<")
end = source.index("struct SwingPlaybackView:", start)
(out / "PlaybackChromeView.swift").write_text(
    "// Generated from production by sync-player.py.\n"
    "import SwiftUI\nimport AVKit\nimport UIKit\n\n" + source[start:end]
)
for name in ["SwingVideoPlayer.swift", "PlaybackTransportGesture.swift", "SwingReviewPager.swift"]:
    (out / name).write_text((root / name).read_text())
