#!/usr/bin/env python3
import json
import selectors
import subprocess
import sys
import time


def main() -> int:
    process = subprocess.Popen(
        ["codex", "-s", "read-only", "-a", "untrusted", "app-server"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")

    def send(payload):
        process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        process.stdin.flush()

    def read_response(response_id, timeout):
        deadline = time.time() + timeout
        stderr_tail = []
        while time.time() < deadline:
            events = selector.select(deadline - time.time())
            if not events:
                break
            for key, _ in events:
                line = key.fileobj.readline()
                if not line:
                    continue
                if key.data == "stderr":
                    stderr_tail.append(line.strip())
                    stderr_tail = stderr_tail[-10:]
                    continue
                message = json.loads(line)
                if message.get("id") == response_id:
                    return message
        raise TimeoutError(f"timed out waiting for id {response_id}; stderr={stderr_tail}")

    try:
        send({"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "codexhud-probe", "version": "0.1.0"}}})
        read_response(1, 12)
        send({"method": "initialized", "params": {}})
        send({"id": 2, "method": "account/rateLimits/read", "params": {}})
        limits = read_response(2, 8)
        rate_limits = limits["result"]["rateLimits"]
        primary = rate_limits.get("primary")
        secondary = rate_limits.get("secondary")
        if not primary or not secondary:
            raise RuntimeError(f"missing primary/secondary windows: {json.dumps(limits)}")
        print(json.dumps({
            "primary": primary,
            "secondary": secondary,
            "planType": rate_limits.get("planType"),
        }, indent=2, sort_keys=True))
        return 0
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()


if __name__ == "__main__":
    sys.exit(main())
