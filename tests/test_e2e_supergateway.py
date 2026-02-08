import json
import os
import unittest
import urllib.error
import urllib.request


def _post_json(url: str, payload: dict, headers: dict, timeout: int = 10) -> tuple[int, dict, str]:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read().decode("utf-8")
        return response.status, dict(response.headers), body


def _parse_response_body(body: str) -> dict:
    stripped = body.lstrip()
    if stripped.startswith("{"):
        return json.loads(stripped)
    for line in body.splitlines():
        if line.startswith("data: "):
            return json.loads(line[len("data: "):])
    raise AssertionError(f"Unable to parse response body: {body!r}")


class TestSupergatewayE2E(unittest.TestCase):
    def test_supergateway_endpoints(self) -> None:
        url = os.getenv("SUPERGATEWAY_URL", "http://127.0.0.1:8084/mcp")
        base_headers = {
            "accept": "application/json, text/event-stream",
            "content-type": "application/json",
        }

        init_payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": {"name": "e2e-client", "version": "0.1.0"},
            },
        }

        status, init_headers, init_body = _post_json(url, init_payload, base_headers)
        self.assertEqual(status, 200, f"Unexpected init status: {status}, body={init_body}")
        init_response = _parse_response_body(init_body)
        self.assertIn("result", init_response, f"Init response missing result: {init_response}")

        session_id = init_headers.get("mcp-session-id")
        self.assertTrue(session_id, "Missing mcp-session-id header from initialize")

        headers = dict(base_headers)
        headers["mcp-session-id"] = session_id
        if init_headers.get("mcp-protocol-version"):
            headers["mcp-protocol-version"] = init_headers["mcp-protocol-version"]

        init_notification = {
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": {},
        }
        notify_status, _, notify_body = _post_json(url, init_notification, headers)
        self.assertEqual(
            notify_status,
            202,
            f"Unexpected initialized notification status: {notify_status}, body={notify_body}",
        )

        tools_list = {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
        tools_status, _, tools_body = _post_json(url, tools_list, headers)
        self.assertEqual(
            tools_status,
            200,
            f"Unexpected tools/list status: {tools_status}, body={tools_body}",
        )
        tools_response = _parse_response_body(tools_body)
        tool_names = {tool["name"] for tool in tools_response["result"]["tools"]}
        self.assertIn("run_command", tool_names)
        self.assertIn("show_security_rules", tool_names)

        echo_shell = {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "run_command", "arguments": {"command": "echo $SHELL"}},
        }
        echo_status, _, echo_body = _post_json(url, echo_shell, headers)
        self.assertEqual(
            echo_status,
            200,
            f"Unexpected run_command echo status: {echo_status}, body={echo_body}",
        )
        echo_response = _parse_response_body(echo_body)
        echo_text = "\n".join(item["text"] for item in echo_response["result"]["content"])
        self.assertIn("Command completed with return code: 0", echo_text)

        list_dir = {
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {"name": "run_command", "arguments": {"command": "ls -l"}},
        }
        ls_status, _, ls_body = _post_json(url, list_dir, headers)
        self.assertEqual(
            ls_status,
            200,
            f"Unexpected run_command ls status: {ls_status}, body={ls_body}",
        )
        ls_response = _parse_response_body(ls_body)
        ls_text = "\n".join(item["text"] for item in ls_response["result"]["content"])
        self.assertIn("Command completed with return code: 0", ls_text)

        security_call = {
            "jsonrpc": "2.0",
            "id": 5,
            "method": "tools/call",
            "params": {"name": "show_security_rules", "arguments": {}},
        }
        security_status, _, security_body = _post_json(url, security_call, headers)
        self.assertEqual(
            security_status,
            200,
            f"Unexpected show_security_rules status: {security_status}, body={security_body}",
        )
        security_response = _parse_response_body(security_body)
        security_text = "\n".join(item["text"] for item in security_response["result"]["content"])
        self.assertIn("Security Configuration", security_text)


if __name__ == "__main__":
    unittest.main()
