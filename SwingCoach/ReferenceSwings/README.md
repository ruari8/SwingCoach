# Local reference swing fixtures

Reference videos in this directory are local development inputs. MP4 files are
ignored by Git and must never be committed or redistributed through this public
repository.

The current Library fixture path recognizes these filenames:

- `DaB3eJ3gAcv_1.mp4`
- `DaBMIbhpel9_1.mp4`
- `DaD04inv5-Z_1.mp4`

When present during an Xcode build, the synchronized project folder includes
them in the app bundle. `SwingLibrary` copies them into app-owned storage and
shows them under Reference swings. A clean checkout simply has no reference
entries.

Use only footage you are permitted to keep locally. Do not use these files as
portable test dependencies; clean-clone and CI checks must skip the optional
reference route or supply separately authorized fixtures.
