from __future__ import annotations

import importlib.util
import io
import os
import sys
import unittest
import urllib.error
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "context-benchmark.py"
SPEC = importlib.util.spec_from_file_location("context_benchmark", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
context_benchmark = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = context_benchmark
SPEC.loader.exec_module(context_benchmark)


class JsonResponse(io.BytesIO):
    def __enter__(self) -> JsonResponse:
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()


class RequestJsonTests(unittest.TestCase):
    def test_request_omits_authorization_without_api_key(self) -> None:
        captured = []

        def open_request(request, *, timeout):
            captured.append((request, timeout))
            return JsonResponse(b'{"ok": true}')

        with patch.object(context_benchmark.urllib.request, "urlopen", open_request):
            result = context_benchmark.request_json("http://localhost/props", timeout=7)

        self.assertEqual(result, {"ok": True})
        self.assertIsNone(captured[0][0].get_header("Authorization"))
        self.assertEqual(captured[0][1], 7)

    def test_request_adds_bearer_authorization_from_api_key(self) -> None:
        captured = []

        def open_request(request, *, timeout):
            captured.append((request, timeout))
            return JsonResponse(b'{"ok": true}')

        with patch.object(context_benchmark.urllib.request, "urlopen", open_request):
            context_benchmark.request_json(
                "http://localhost/tokenize",
                {"content": "hello"},
                api_key="test-token",
            )

        request = captured[0][0]
        self.assertEqual(request.get_header("Authorization"), "Bearer test-token")
        self.assertEqual(request.get_method(), "POST")

    def test_http_error_redacts_api_key(self) -> None:
        error = urllib.error.HTTPError(
            "http://localhost/props",
            401,
            "Unauthorized",
            hdrs=None,
            fp=io.BytesIO(b'failed for test-token'),
        )

        with (
            patch.object(context_benchmark.urllib.request, "urlopen", side_effect=error),
            self.assertRaises(RuntimeError) as raised,
        ):
            context_benchmark.request_json(
                "http://localhost/props",
                api_key="test-token",
            )

        self.assertNotIn("test-token", str(raised.exception))
        self.assertIn("[redacted]", str(raised.exception))

    def test_main_reads_api_key_from_environment(self) -> None:
        responses = [
            {"default_generation_settings": {"n_ctx": 128}, "model_alias": "model"},
            {
                "choices": [
                    {
                        "message": {"content": "needle", "reasoning_content": None},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {"prompt_tokens": 10, "completion_tokens": 1},
            },
        ]

        with (
            patch.dict(os.environ, {"LLAMA_API_KEY": "test-token"}),
            patch.object(
                sys,
                "argv",
                ["context-benchmark.py", "--target-tokens", "10", "--secret", "needle"],
            ),
            patch.object(
                context_benchmark,
                "request_json",
                side_effect=responses,
            ) as request_json,
            patch.object(
                context_benchmark,
                "build_prompt",
                return_value=("prompt", 10, 1),
            ) as build_prompt,
            redirect_stdout(io.StringIO()) as stdout,
        ):
            result = context_benchmark.main()

        self.assertEqual(result, 0)
        self.assertEqual(request_json.call_args_list[0].kwargs["api_key"], "test-token")
        self.assertEqual(request_json.call_args_list[1].kwargs["api_key"], "test-token")
        build_prompt.assert_called_once_with(
            "http://127.0.0.1:18080", 10, "needle", "test-token"
        )
        self.assertNotIn("test-token", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
