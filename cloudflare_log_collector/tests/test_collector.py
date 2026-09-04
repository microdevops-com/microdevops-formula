import datetime as dt
import importlib.util
import json
import os
import re
import stat
import tempfile
import unittest


SCRIPT = os.path.join(
    os.path.dirname(os.path.dirname(__file__)), "files", "collector.py"
)
SPEC = importlib.util.spec_from_file_location("collector", SCRIPT)
collector_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector_module)


class FakeCollector(collector_module.Collector):
    def __init__(self, config, rows):
        super().__init__(config)
        self.rows = rows
        self.fail_dataset = None
        self.queries = []

    def api_query(self, sql, token):
        self.queries.append(sql)
        dataset = re.search(r" FROM ([a-z_]+) ", sql).group(1)
        if dataset == self.fail_dataset:
            raise collector_module.CollectorError("simulated failure")
        start, end = re.findall(r"(?:>=|<) '([^']+)'", sql)[-2:]
        limit = int(re.search(r" LIMIT (\d+)", sql).group(1))
        offset = int(re.search(r" OFFSET (\d+)", sql).group(1))
        matching = [
            row
            for row in self.rows[dataset]
            if start <= row["timestamp"] < end
        ]
        return matching[offset : offset + limit]


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        root = self.tempdir.name
        self.token_file = os.path.join(root, "token")
        with open(self.token_file, "w", encoding="utf-8") as stream:
            stream.write("test-token\n")
        os.chmod(self.token_file, stat.S_IRUSR | stat.S_IWUSR)
        self.config = {
            "api_base": "https://api.cloudflare.invalid/client/v4",
            "zone_id": "test-zone",
            "token_file": self.token_file,
            "state_file": os.path.join(root, "state.sqlite3"),
            "lock_file": os.path.join(root, "collector.lock"),
            "http_output": os.path.join(root, "http.jsonl"),
            "firewall_output": os.path.join(root, "firewall.jsonl"),
            "poll_delay_seconds": 120,
            "initial_lookback_seconds": 900,
            "overlap_seconds": 300,
            "slice_seconds": 60,
            "page_size": 1,
            "max_pages_per_slice": 10,
            "request_timeout_seconds": 1,
            "request_retries": 0,
            "dedup_retention_hours": 48,
        }
        self.target = dt.datetime(2026, 9, 4, 12, 10, tzinfo=dt.timezone.utc)
        self.rows = {
            "http_requests": [
                {
                    "timestamp": "2026-09-04T12:08:00.000000Z",
                    "client_ip": "192.0.2.10",
                    "hostname": "compx.ua",
                    "http_method": "GET",
                    "path": "/health",
                    "response_status": 200,
                    "user_agent": "collector-test",
                    "country": "UA",
                    "ray_id": "ray-http-1",
                    "cache_status": "hit",
                },
                {
                    "timestamp": "2026-09-04T12:08:30.000000Z",
                    "client_ip": "192.0.2.11",
                    "hostname": "www.compx.ua",
                    "http_method": "GET",
                    "path": "/",
                    "response_status": 200,
                    "user_agent": "collector-test",
                    "country": "UA",
                    "ray_id": "ray-http-2",
                    "cache_status": "miss",
                },
            ],
            "firewall_events": [
                {
                    "timestamp": "2026-09-04T12:09:00.000000Z",
                    "client_ip": "192.0.2.12",
                    "hostname": "compx.ua",
                    "path": "/harmless-waf-test",
                    "action": "managed_challenge",
                    "rule_id": "test-rule",
                    "rule_ref": "test-ref",
                    "source": "firewallManaged",
                    "ray_id": "ray-fw-1",
                    "country": "UA",
                }
            ],
        }

    def tearDown(self):
        self.tempdir.cleanup()

    def new_collector(self):
        instance = FakeCollector(self.config, self.rows)
        instance.validate_config()
        instance.open_database()
        return instance

    def test_pagination_and_second_run_are_duplicate_safe(self):
        instance = self.new_collector()
        token = instance.read_token()
        first = instance.collect_dataset("http_requests", token, self.target)
        self.assertEqual(first, (2, 2, 2))
        second = instance.collect_dataset("http_requests", token, self.target)
        self.assertEqual(second, (2, 0, 0))
        with open(self.config["http_output"], encoding="utf-8") as stream:
            lines = [json.loads(line) for line in stream]
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0]["ray_id"], "ray-http-1")
        self.assertNotIn("cookies", lines[0])

    def test_datasets_fail_independently(self):
        instance = self.new_collector()
        instance.fail_dataset = "http_requests"
        with self.assertRaises(collector_module.CollectorError):
            instance.collect_dataset(
                "http_requests", instance.read_token(), self.target
            )
        result = instance.collect_dataset(
            "firewall_events", instance.read_token(), self.target
        )
        self.assertEqual(result, (1, 1, 1))

    def test_insecure_token_permissions_are_rejected(self):
        os.chmod(self.token_file, 0o644)
        with self.assertRaisesRegex(
            collector_module.CollectorError, "group/other"
        ):
            self.new_collector().read_token()

    def test_query_projects_only_approved_fields(self):
        query = collector_module.Collector.build_query(
            "http_requests",
            self.target - dt.timedelta(minutes=1),
            self.target,
            100,
            0,
        )
        self.assertIn("ClientRequestPath", query)
        self.assertNotIn("ClientRequestURI", query)
        self.assertNotIn("Cookie", query)
        self.assertNotIn("Authorization", query)

    def test_sql_api_uses_documented_get_query_parameter(self):
        instance = collector_module.Collector(self.config)
        captured = {}

        def fake_request(request):
            captured["request"] = request
            return {"success": True, "result": []}

        instance.api_request = fake_request
        instance.api_query("SELECT RayID FROM http_requests LIMIT 1", "ignored")
        self.assertEqual(captured["request"].get_method(), "GET")
        self.assertIn("query=SELECT+RayID", captured["request"].full_url)

    def test_incomplete_batch_is_rolled_back_before_replay(self):
        instance = self.new_collector()
        output = self.config["http_output"]
        os.makedirs(os.path.dirname(output), exist_ok=True)
        with open(output, "wb") as stream:
            stream.write(b'{"existing":true}\n')
        file_stat = os.stat(output)
        start_offset = file_stat.st_size
        instance.connection.execute(
            """
            INSERT INTO pending_writes(output_path, device, inode, start_offset)
            VALUES (?, ?, ?, ?)
            """,
            (output, file_stat.st_dev, file_stat.st_ino, start_offset),
        )
        instance.connection.commit()
        with open(output, "ab") as stream:
            stream.write(b'{"incomplete":true}\n')
            stream.flush()
            os.fsync(stream.fileno())
        instance.recover_pending_writes()
        with open(output, "rb") as stream:
            self.assertEqual(stream.read(), b'{"existing":true}\n')
        self.assertEqual(
            instance.connection.execute("SELECT COUNT(*) FROM pending_writes").fetchone()[0],
            0,
        )

    def test_full_window_is_split_before_offset_pagination(self):
        self.config["page_size"] = 2
        self.config["min_slice_seconds"] = 30
        instance = self.new_collector()
        start = dt.datetime(2026, 9, 4, 12, 8, tzinfo=dt.timezone.utc)
        end = start + dt.timedelta(minutes=1)
        fetched, inserted = instance.collect_window(
            "http_requests", instance.read_token(), self.config["http_output"], start, end
        )
        self.assertEqual((fetched, inserted), (2, 2))
        self.assertTrue(all("OFFSET 0" in query for query in instance.queries))


if __name__ == "__main__":
    unittest.main()
