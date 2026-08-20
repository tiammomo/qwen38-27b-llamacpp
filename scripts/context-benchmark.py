#!/usr/bin/env python3
"""Run a deterministic long-context needle-retrieval benchmark."""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request


def request_json(url: str, payload: dict | None = None, timeout: int = 30) -> dict:
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="GET" if data is None else "POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} from {url}: {body[:2000]}") from exc


def tokenize(base_url: str, content: str) -> int:
    response = request_json(
        f"{base_url}/tokenize",
        {"content": content, "add_special": False},
        timeout=300,
    )
    return len(response["tokens"])


def build_prompt(base_url: str, target_tokens: int, secret: str) -> tuple[str, int, int]:
    header = (
        "这是一个长上下文记忆测试。你必须记住下一行，后面的记录都与答案无关。\n"
        f"关键密钥：{secret}\n"
        "无关记录开始：\n"
    )
    footer = (
        "\n无关记录结束。\n"
        "问题：开头给出的关键密钥是什么？只输出完整密钥，不要解释。"
    )

    sample_lines = "".join(
        f"无关记录{i:06d}：蓝色石头位于虚构仓库，编号与答案无关。\n"
        for i in range(256)
    )
    fixed_tokens = tokenize(base_url, header + footer)
    sample_tokens = tokenize(base_url, header + sample_lines + footer) - fixed_tokens
    tokens_per_line = max(sample_tokens / 256, 1)
    line_count = max(1, int((target_tokens - fixed_tokens) / tokens_per_line))

    prompt = ""
    prompt_tokens = 0
    for _ in range(5):
        filler = "".join(
            f"无关记录{i:06d}：蓝色石头位于虚构仓库，编号与答案无关。\n"
            for i in range(line_count)
        )
        prompt = header + filler + footer
        prompt_tokens = tokenize(base_url, prompt)
        delta = target_tokens - prompt_tokens
        if abs(delta) <= max(64, int(tokens_per_line * 2)):
            break
        line_count = max(1, line_count + int(delta / tokens_per_line))

    return prompt, prompt_tokens, line_count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:18080")
    parser.add_argument("--target-tokens", type=int, required=True)
    parser.add_argument("--secret", required=True)
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()

    props = request_json(f"{args.base_url}/props", timeout=10)
    context_size = props["default_generation_settings"]["n_ctx"]
    model_id = props["model_alias"]
    if args.target_tokens >= context_size:
        raise SystemExit(
            f"target tokens {args.target_tokens} must be below context size {context_size}"
        )

    print(
        f"Building approximately {args.target_tokens} prompt tokens for context {context_size}...",
        file=sys.stderr,
        flush=True,
    )
    build_started = time.monotonic()
    prompt, direct_prompt_tokens, line_count = build_prompt(
        args.base_url, args.target_tokens, args.secret
    )
    build_seconds = time.monotonic() - build_started

    print(
        f"Submitting {direct_prompt_tokens} direct tokens ({line_count} filler lines)...",
        file=sys.stderr,
        flush=True,
    )
    inference_started = time.monotonic()
    response = request_json(
        f"{args.base_url}/v1/chat/completions",
        {
            "model": model_id,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 32,
            "temperature": 0,
            "chat_template_kwargs": {"enable_thinking": False},
        },
        timeout=args.timeout,
    )
    inference_seconds = time.monotonic() - inference_started

    choice = response["choices"][0]
    answer = choice["message"].get("content") or ""
    result = {
        "context_size": context_size,
        "model": model_id,
        "target_tokens": args.target_tokens,
        "direct_prompt_tokens": direct_prompt_tokens,
        "api_prompt_tokens": response.get("usage", {}).get("prompt_tokens"),
        "completion_tokens": response.get("usage", {}).get("completion_tokens"),
        "filler_lines": line_count,
        "build_seconds": round(build_seconds, 3),
        "inference_seconds": round(inference_seconds, 3),
        "finish_reason": choice.get("finish_reason"),
        "answer": answer,
        "expected": args.secret,
        "needle_retrieval_passed": args.secret in answer,
        "timings": response.get("timings"),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["needle_retrieval_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
