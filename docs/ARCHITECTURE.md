# Architecture

## Why there is a proxy at all

TRMNL plugins are Liquid templates rendered against a JSON URL. The PTV metro `vehicle-positions`
endpoint returns a [GTFS Realtime](https://gtfs.org/documentation/realtime/reference/) Protocol
Buffers payload. Liquid cannot decode protobuf, so something has to sit between the feed and the
device. That something is [proxy/server.rb](../proxy/server.rb).

The proxy also does work the templates could not do even with JSON: the realtime feed identifies
things by ID, and turning `route_id` and `stop_id` into a route name, a headsign, a stop name and a
platform code requires the static GTFS schedule.

## The pipeline

1. Fetch the metro vehicle-positions feed, sending `KeyId` or `Ocp-Apim-Subscription-Key`.
2. Decode the protobuf `FeedMessage` and normalise its keys to strings.
3. Enrich each entity against the static GTFS schedule loaded from `PTV_GTFS_PATH`.
4. Build display rows: scheduled departures for the requested stop, each enriched with live status
   where a live vehicle matches the same trip.
5. Emit JSON.

Steps 1–5 are shared between the long-running server and the one-shot CI snapshot generator; both
call the same `PtvSnapshotGenerator`.

`proxy/bin/` holds the one-shot entry points:

| Script | Purpose |
| --- | --- |
| [generate_snapshot.rb](../proxy/bin/generate_snapshot.rb) | Write one `ptv-metro.json` to a path. |
| [generate_stop_index.rb](../proxy/bin/generate_stop_index.rb) | Write `stops.json` for the stop finder page. |
| [schedule_gate.rb](../proxy/bin/schedule_gate.rb) | Decide whether this cron tick should generate a snapshot. |
| [snapshot_changed.rb](../proxy/bin/snapshot_changed.rb) | Compare two snapshots with volatile fields stripped. |
| [find_stop.rb](../proxy/bin/find_stop.rb) | Command-line stop lookup. |

## Payload shape

The templates read four top-level keys.

```json
{
  "header": { "gtfs_realtime_version": "2.0", "timestamp": 1784841043 },
  "entity": [ { "id": "...", "vehicle": { "trip": { "route_id": "...", "trip_id": "..." } } } ],
  "rows": [ { "route_id": "...", "route_name": "...", "headsign": "...",
              "stop_id": "...", "station_id": "...", "stop_name": "...",
              "platform_code": "...", "status_text": "On time" } ],
  "meta": { "source": "ptv-metro-vehicle-positions", "fetched_at": "...",
            "source_mode": "github_action", "auth_mode": "key_id",
            "upstream_url": "...", "cache_ttl_seconds": 30 }
}
```

`entity` is the decoded GTFS Realtime feed. `rows` is the pre-joined departure list the templates
actually iterate over — they match `row.stop_id` or `row.station_id` against the plugin's `stopid`
field. `meta` is provenance.

On failure the same structure comes back with an empty `entity`, no `rows`, and an
`meta.error` object carrying `type` and `message`. The templates render that text, so a broken feed
shows a reason rather than an empty table.

## Proxy endpoints

| Endpoint | Returns |
| --- | --- |
| `GET /health` | `ok`, `fetched_at`, `gtfs_path`, `auth_mode`, `source_mode` |
| `GET /ptv/metro/vehicle-positions` | The payload above, served from a short-lived cache |
| `GET /ptv/stops/search?q=Ringwood` | `query`, `matches`, `gtfs_path` |

Responses are cached for `PTV_CACHE_TTL_SECONDS` (default 30) to stay within the PTV rate limits.

## Environment variables

| Variable | Purpose |
| --- | --- |
| `PTV_KEY_ID` | Sent as the `KeyId` header. Preferred. |
| `PTV_SUBSCRIPTION_KEY` | Sent as `Ocp-Apim-Subscription-Key`. Alternate auth path. |
| `PORT` | Proxy listen port. Defaults to `9910`. |
| `PTV_CACHE_TTL_SECONDS` | Response cache lifetime. Defaults to `30`. |
| `PTV_METRO_VEHICLE_POSITIONS_URL` | Override the upstream feed URL. |
| `PTV_GTFS_PATH` | Local static GTFS folder. Defaults to `./data/gtfs/2`. |
| `PTV_GTFS_ZIP_URL` | Where to download the GTFS archive from. |
| `PTV_GTFS_DOWNLOAD_ROOT` | Where that archive is unpacked. |
| `PTV_SOURCE_MODE` | Recorded in `meta.source_mode`; the workflow sets `github_action`. |
| `BASE_INTERVAL_MINUTES` | Snapshot cadence outside the peak window. |
| `PEAK_INTERVAL_MINUTES` | Snapshot cadence inside the peak window. |
| `PEAK_START_LOCAL` / `PEAK_END_LOCAL` | Melbourne local peak window bounds. |
| `PEAK_DAYS` | Comma-separated day keys such as `mon,tue,wed,thu,fri`. |
| `FORCE_RUN` | Bypass the schedule gate. Set by `workflow_dispatch` runs. |

## Templates

[src/](../src) holds one Liquid file per TRMNL layout — `full`, `half_horizontal`, `half_vertical`
and `quadrant` — plus [settings.yml](../src/settings.yml), which declares the custom fields. All four
apply the same filtering: rows are shown only when `stopid` is set and matches either `row.stop_id`
or `row.station_id`, optionally narrowed by `routeid`, with anything older than `stalemins` dropped.

## Bundle separation

The root [Gemfile](../Gemfile) carries only `trmnl_preview`, the gem that provides the `trmnlp`
command. [proxy/Gemfile](../proxy/Gemfile) carries `google-protobuf` and `rake`. They are kept apart
so the protobuf native extension cannot interfere with the plugin preview tooling.

[proxy/.bundle/config](../proxy/.bundle/config) sets `BUNDLE_FORCE_RUBY_PLATFORM: "true"` and a
local `vendor/bundle-arm64` path, which helps on Apple Silicon. The workflow overrides both, forcing
the precompiled platform gem and a separate `vendor/bundle-ci` path.

## Scope

This targets the metro train vehicle-positions feed. A true stop-departures plugin would mean
calling a PTV departures endpoint and reshaping that response instead; the template layer would
largely carry over, since it already renders scheduled rows.
