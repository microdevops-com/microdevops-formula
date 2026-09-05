#!/usr/bin/env python3
"""Incrementally collect a small Cloudflare Log Explorer projection as JSONL."""

import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


DATASETS = {
    "http_requests": {
        "timestamp_field": "EdgeStartTimestamp",
        "output": "http_output",
        "fields": (
            ("EdgeStartTimestamp", "timestamp"),
            ("ClientIP", "client_ip"),
            ("ClientRequestHost", "hostname"),
            ("ClientRequestMethod", "http_method"),
            ("ClientRequestPath", "path"),
            ("EdgeResponseStatus", "response_status"),
            ("ClientRequestUserAgent", "user_agent"),
            ("ClientCountry", "country"),
            ("RayID", "ray_id"),
            ("CacheCacheStatus", "cache_status"),
        ),
    },
    "firewall_events": {
        "timestamp_field": "Datetime",
        "output": "firewall_output",
        "fields": (
            ("Datetime", "timestamp"),
            ("ClientIP", "client_ip"),
            ("ClientRequestHost", "hostname"),
            ("ClientRequestPath", "path"),
            ("Action", "action"),
            ("RuleID", "rule_id"),
            ("Ref", "rule_ref"),
            ("Source", "source"),
            ("RayID", "ray_id"),
            ("ClientCountry", "country"),
        ),
    },
}


def utc_now():
    return dt.datetime.now(dt.timezone.utc)


def parse_timestamp(value):
    if not isinstance(value, str):
        raise ValueError("event timestamp is not a string")
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def format_timestamp(value):
    return value.astimezone(dt.timezone.utc).isoformat(timespec="microseconds").replace(
        "+00:00", "Z"
    )


class CollectorError(RuntimeError):
    pass


class Collector:
    def __init__(self, config):
        self.config = config
        self.connection = None

    def validate_config(self):
        required = (
            "api_base",
            "zone_id",
            "token_file",
            "state_file",
            "lock_file",
            "http_output",
            "firewall_output",
        )
        missing = [key for key in required if not self.config.get(key)]
        if missing:
            raise CollectorError("missing configuration: " + ", ".join(missing))

    def read_token(self):
        path = self.config["token_file"]
        try:
            mode = os.stat(path).st_mode
            if mode & 0o077:
                raise CollectorError("token file must not be accessible by group/other")
            with open(path, encoding="utf-8") as stream:
                token = stream.read().strip()
        except OSError as error:
            raise CollectorError("cannot read token file: {}".format(error)) from error
        if not token:
            raise CollectorError("token file is empty")
        return token

    def open_database(self):
        path = self.config["state_file"]
        os.makedirs(os.path.dirname(path), mode=0o750, exist_ok=True)
        self.connection = sqlite3.connect(path)
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("PRAGMA synchronous=FULL")
        self.connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS cursors (
                dataset TEXT PRIMARY KEY,
                cursor TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS events (
                event_id TEXT PRIMARY KEY,
                dataset TEXT NOT NULL,
                event_timestamp TEXT NOT NULL,
                output_path TEXT NOT NULL,
                event_json TEXT,
                written INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS events_written_idx
                ON events(written, dataset, event_timestamp);
            CREATE TABLE IF NOT EXISTS pending_writes (
                output_path TEXT PRIMARY KEY,
                device INTEGER NOT NULL,
                inode INTEGER NOT NULL,
                start_offset INTEGER NOT NULL
            );
            """
        )
        self.connection.commit()

    def recover_pending_writes(self):
        """Undo an incomplete batch before it can be replayed.

        The pending row is committed before the append. If the process dies at
        any point before the corresponding event rows are atomically marked
        written, truncating to the saved offset makes replay exact.
        """
        rows = self.connection.execute(
            "SELECT output_path, device, inode, start_offset FROM pending_writes"
        ).fetchall()
        for path, device, inode, start_offset in rows:
            try:
                current = os.stat(path)
            except FileNotFoundError as error:
                raise CollectorError(
                    "cannot recover incomplete output batch: {} is missing".format(path)
                ) from error
            if (current.st_dev, current.st_ino) != (device, inode):
                raise CollectorError(
                    "cannot recover incomplete output batch: {} was rotated".format(path)
                )
            if current.st_size < start_offset:
                raise CollectorError(
                    "cannot recover incomplete output batch: {} was truncated".format(path)
                )
            with open(path, "r+b") as stream:
                stream.truncate(start_offset)
                stream.flush()
                os.fsync(stream.fileno())
            self.connection.execute(
                "DELETE FROM pending_writes WHERE output_path = ?", (path,)
            )
        self.connection.commit()

    def get_cursor(self, dataset, target):
        row = self.connection.execute(
            "SELECT cursor FROM cursors WHERE dataset = ?", (dataset,)
        ).fetchone()
        if row:
            overlap = dt.timedelta(seconds=int(self.config["overlap_seconds"]))
            return min(parse_timestamp(row[0]) - overlap, target)
        lookback = dt.timedelta(seconds=int(self.config["initial_lookback_seconds"]))
        return target - lookback

    def set_cursor(self, dataset, cursor):
        self.connection.execute(
            """
            INSERT INTO cursors(dataset, cursor) VALUES (?, ?)
            ON CONFLICT(dataset) DO UPDATE SET cursor = excluded.cursor
            """,
            (dataset, format_timestamp(cursor)),
        )
        self.connection.commit()

    def api_query(self, sql, token):
        endpoint = "{}/zones/{}/logs/explorer/query/sql".format(
            self.config["api_base"].rstrip("/"), self.config["zone_id"]
        )
        # Cloudflare's Log Explorer API documents SQL in the `query` URL
        # parameter. Keeping it outside logs avoids ever printing the query
        # body alongside HTTP errors.
        url = endpoint + "?" + urllib.parse.urlencode({"query": sql})
        request = urllib.request.Request(
            url,
            headers={
                "Authorization": "Bearer " + token,
                "Accept": "application/json",
                "User-Agent": "microdevops-cloudflare-log-collector/1",
            },
        )
        payload = self.api_request(request)
        if not payload.get("success", False):
            raise CollectorError(
                "Cloudflare API returned an unsuccessful response: {}".format(
                    payload.get("errors", "unspecified error")
                )
            )
        result = payload.get("result")
        if not isinstance(result, list):
            raise CollectorError("Cloudflare API result is not a row list")
        return result

    def api_datasets(self, token):
        url = "{}/zones/{}/logs/explorer/datasets".format(
            self.config["api_base"].rstrip("/"), self.config["zone_id"]
        )
        request = urllib.request.Request(
            url,
            headers={
                "Authorization": "Bearer " + token,
                "Accept": "application/json",
                "User-Agent": "microdevops-cloudflare-log-collector/1",
            },
        )
        payload = self.api_request(request)
        if not payload.get("success", False):
            raise CollectorError(
                "Cloudflare datasets API returned an unsuccessful response: {}".format(
                    payload.get("errors", "unspecified error")
                )
            )
        result = payload.get("result")
        if not isinstance(result, list):
            raise CollectorError("Cloudflare datasets API result is not a list")
        return {item.get("dataset") for item in result if isinstance(item, dict)}

    def api_request(self, request):
        retries = int(self.config["request_retries"])
        timeout = int(self.config["request_timeout_seconds"])
        for attempt in range(retries + 1):
            try:
                with urllib.request.urlopen(request, timeout=timeout) as response:
                    return json.load(response)
            except urllib.error.HTTPError as error:
                retryable = error.code == 429 or 500 <= error.code < 600
                if not retryable or attempt == retries:
                    raise CollectorError(
                        "Cloudflare API HTTP error {}".format(error.code)
                    ) from error
                retry_after = error.headers.get("Retry-After")
                delay = int(retry_after) if retry_after and retry_after.isdigit() else 2**attempt
            except (urllib.error.URLError, TimeoutError) as error:
                if attempt == retries:
                    raise CollectorError("Cloudflare API request failed: {}".format(error)) from error
                delay = 2**attempt
            time.sleep(min(delay, 30))
        raise CollectorError("Cloudflare API retry loop exhausted")

    @staticmethod
    def build_query(dataset, start, end, limit, offset):
        spec = DATASETS[dataset]
        selections = ", ".join(
            '{} AS "{}"'.format(source, destination)
            for source, destination in spec["fields"]
        )
        timestamp = spec["timestamp_field"]
        return (
            'SELECT {} FROM {} WHERE Date >= \'{}\' AND Date <= \'{}\' '
            'AND {} >= \'{}\' AND {} < \'{}\' '
            'LIMIT {} OFFSET {}'.format(
                selections,
                dataset,
                start.date().isoformat(),
                end.date().isoformat(),
                timestamp,
                format_timestamp(start),
                timestamp,
                format_timestamp(end),
                int(limit),
                int(offset),
            )
        )

    @staticmethod
    def normalize_row(dataset, row):
        if not isinstance(row, dict):
            raise CollectorError("Cloudflare API returned a non-object row")
        normalized = {}
        lower_row = {str(key).lower(): value for key, value in row.items()}
        for _, destination in DATASETS[dataset]["fields"]:
            normalized[destination] = lower_row.get(destination.lower())
        normalized["timestamp"] = format_timestamp(
            parse_timestamp(normalized["timestamp"])
        )
        return normalized

    def queue_rows(self, dataset, output_path, rows):
        inserted = 0
        for row in rows:
            event = self.normalize_row(dataset, row)
            event_json = json.dumps(event, separators=(",", ":"), sort_keys=True)
            event_id = hashlib.sha256(
                (dataset + "\0" + event_json).encode("utf-8")
            ).hexdigest()
            cursor = self.connection.execute(
                """
                INSERT OR IGNORE INTO events(
                    event_id, dataset, event_timestamp, output_path, event_json, written
                ) VALUES (?, ?, ?, ?, ?, 0)
                """,
                (event_id, dataset, event["timestamp"], output_path, event_json),
            )
            inserted += cursor.rowcount
        self.connection.commit()
        return inserted

    def flush_pending(self, dataset):
        rows = self.connection.execute(
            """
            SELECT event_id, output_path, event_json FROM events
            WHERE dataset = ? AND written = 0
            ORDER BY event_timestamp, event_id
            """,
            (dataset,),
        ).fetchall()
        by_path = {}
        for row in rows:
            by_path.setdefault(row[1], []).append(row)
        for path, pending in by_path.items():
            os.makedirs(os.path.dirname(path), mode=0o750, exist_ok=True)
            with open(path, "a+b") as stream:
                file_stat = os.fstat(stream.fileno())
                start_offset = file_stat.st_size
                self.connection.execute(
                    """
                    INSERT INTO pending_writes(output_path, device, inode, start_offset)
                    VALUES (?, ?, ?, ?)
                    """,
                    (path, file_stat.st_dev, file_stat.st_ino, start_offset),
                )
                self.connection.commit()
                for _, _, event_json in pending:
                    stream.write(event_json.encode("utf-8") + b"\n")
                stream.flush()
                os.fsync(stream.fileno())
            with self.connection:
                self.connection.executemany(
                    "UPDATE events SET written = 1, event_json = NULL WHERE event_id = ?",
                    [(event_id,) for event_id, _, _ in pending],
                )
                self.connection.execute(
                    "DELETE FROM pending_writes WHERE output_path = ?", (path,)
                )
        return len(rows)

    def collect_dataset(self, dataset, token, target):
        spec = DATASETS[dataset]
        output_path = self.config[spec["output"]]
        written = self.flush_pending(dataset)
        start = self.get_cursor(dataset, target)
        slice_size = dt.timedelta(
            seconds=int(
                self.config.get("{}_slice_seconds".format(dataset), self.config["slice_seconds"])
            )
        )
        fetched = inserted = 0
        while start < target:
            end = min(start + slice_size, target)
            slice_fetched, slice_inserted = self.collect_window(
                dataset, token, output_path, start, end
            )
            fetched += slice_fetched
            inserted += slice_inserted
            written += self.flush_pending(dataset)
            self.set_cursor(dataset, end)
            start = end
        return fetched, inserted, written

    def collect_window(self, dataset, token, output_path, start, end):
        """Collect a bounded window, splitting before a full page can time out.

        Log Explorer supports OFFSET, but a very busy minute can make a second
        offset page slow enough to time out. Splitting by time retains the
        narrow-query guidance and allows the durable cursor to make progress.
        """
        page_size = int(self.config["page_size"])
        minimum = dt.timedelta(
            seconds=int(self.config.get("min_slice_seconds", 5))
        )
        try:
            rows = self.api_query(
                self.build_query(dataset, start, end, page_size, 0), token
            )
        except CollectorError:
            if end - start <= minimum:
                raise
            middle = start + (end - start) / 2
            left = self.collect_window(dataset, token, output_path, start, middle)
            right = self.collect_window(dataset, token, output_path, middle, end)
            return left[0] + right[0], left[1] + right[1]

        if len(rows) >= page_size and end - start > minimum:
            middle = start + (end - start) / 2
            left = self.collect_window(dataset, token, output_path, start, middle)
            right = self.collect_window(dataset, token, output_path, middle, end)
            return left[0] + right[0], left[1] + right[1]

        fetched = len(rows)
        inserted = self.queue_rows(dataset, output_path, rows)
        # A minimum-width window can still contain a full page. Paginate only
        # there; wider windows were recursively split above.
        offset = page_size
        max_pages = int(self.config["max_pages_per_slice"])
        for page in range(1, max_pages):
            if len(rows) < page_size:
                break
            rows = self.api_query(
                self.build_query(dataset, start, end, page_size, offset), token
            )
            fetched += len(rows)
            inserted += self.queue_rows(dataset, output_path, rows)
            offset += page_size
        else:
            raise CollectorError(
                "{} exceeded {} pages in a minimum time window".format(
                    dataset, max_pages
                )
            )
        return fetched, inserted

    def prune_deduplication_state(self):
        cutoff = utc_now() - dt.timedelta(
            hours=int(self.config["dedup_retention_hours"])
        )
        self.connection.execute(
            "DELETE FROM events WHERE written = 1 AND event_timestamp < ?",
            (format_timestamp(cutoff),),
        )
        self.connection.commit()

    def run(self):
        self.validate_config()
        token = self.read_token()
        target = utc_now() - dt.timedelta(
            seconds=int(self.config["poll_delay_seconds"])
        )
        self.open_database()
        self.recover_pending_writes()
        failed = []
        available_datasets = self.api_datasets(token)
        # Security events are usually sparse and should not wait behind a
        # high-volume HTTP backfill.
        for dataset in ("firewall_events", "http_requests"):
            if dataset not in available_datasets:
                print("{}: dataset is not enabled; skipping".format(dataset))
                continue
            try:
                fetched, inserted, written = self.collect_dataset(dataset, token, target)
                print(
                    "{}: fetched={}, new={}, written={}".format(
                        dataset, fetched, inserted, written
                    )
                )
            except Exception as error:  # keep the other dataset independent
                failed.append(dataset)
                print("{}: collection failed: {}".format(dataset, error), file=sys.stderr)
        self.prune_deduplication_state()
        if failed:
            raise CollectorError("collection failed for: " + ", ".join(failed))


@contextlib.contextmanager
def exclusive_lock(path):
    os.makedirs(os.path.dirname(path), mode=0o750, exist_ok=True)
    with open(path, "a+", encoding="utf-8") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("collector already running; skipping")
            yield False
            return
        yield True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    args = parser.parse_args()
    try:
        with open(args.config, encoding="utf-8") as stream:
            config = json.load(stream)
        with exclusive_lock(config["lock_file"]) as acquired:
            if acquired:
                Collector(config).run()
    except (OSError, ValueError, KeyError, CollectorError) as error:
        print("cloudflare-log-collector: {}".format(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
