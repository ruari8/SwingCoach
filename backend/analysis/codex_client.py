"""Run coach model calls through the local Codex CLI and its ChatGPT login.

Local development only: usage counts against the signed-in ChatGPT plan rather
than API billing. It implements just the `responses.parse`/`responses.create`
subset that CoachResponseBuilder uses. A public deployment must use the API.
"""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace

from openai.lib._pydantic import to_strict_json_schema


class CodexClient:
    def __init__(self, *, timeout: float = 300):
        self.timeout = timeout
        self.responses = self

    def parse(self, *, model, reasoning, instructions, input, text_format, **_):
        text = self._run(model, reasoning, instructions, input, schema=to_strict_json_schema(text_format))
        return SimpleNamespace(status="completed", output_parsed=text_format.model_validate_json(text))

    def create(self, *, model, reasoning, instructions, input, **_):
        return SimpleNamespace(status="completed", output_text=self._run(model, reasoning, instructions, input))

    def _run(self, model, reasoning, instructions, input, schema=None) -> str:
        with tempfile.TemporaryDirectory(prefix="swingcoach-codex-") as tmp:
            tmp = Path(tmp)
            parts = [{"type": "input_text", "text": input}] if isinstance(input, str) else \
                [part for message in input for part in message["content"]]
            lines, images = [instructions, ""], []
            for part in parts:
                if part["type"] == "input_text":
                    lines.append(part["text"])
                else:
                    # Codex attaches images in order; label each where it appeared.
                    image = tmp / f"image-{len(images) + 1}.jpg"
                    image.write_bytes(base64.b64decode(part["image_url"].split(",", 1)[1]))
                    images.append(str(image))
                    lines.append(f"[Attached image {len(images)}]")
            out = tmp / "out.txt"
            command = [os.getenv("SWINGCOACH_CODEX_BIN", "codex"), "exec", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config",
                       "--sandbox", "read-only", "-C", str(tmp), "-m", model,
                       "-c", f"model_reasoning_effort={reasoning['effort']}", "-o", str(out)]
            if schema is not None:
                (tmp / "schema.json").write_text(json.dumps(schema))
                command += ["--output-schema", str(tmp / "schema.json")]
            if images:
                command += ["-i", *images]
            result = subprocess.run(command + ["--", "-"], input="\n".join(lines), text=True,
                                    capture_output=True, timeout=self.timeout)
            if result.returncode != 0 or not out.is_file() or not out.read_text().strip():
                raise RuntimeError(f"codex exec failed ({result.returncode}): {result.stderr[-500:]}")
            return out.read_text().strip()
