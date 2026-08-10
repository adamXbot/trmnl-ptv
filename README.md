<div align="center">

<img src="plugin-icon.svg" alt="" width="120">

# trmnl-ptv

A TRMNL plugin that shows Melbourne metro train departures, with a Ruby proxy that turns the PTV GTFS Realtime feed into JSON the plugin can read.

[![Project status](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2FadamXbot%2F.github%2Fmain%2Fbadges%2Ftrmnl-ptv.json)](https://github.com/adamXbot/.github/blob/main/STATUS.md#trmnl-ptv)
[![Licence](https://img.shields.io/github/license/adamXbot/trmnl-ptv?label=licence)](LICENSE)
[![Publish](https://img.shields.io/github/actions/workflow/status/adamXbot/trmnl-ptv/publish-ptv-data.yml?branch=main&label=publish)](https://github.com/adamXbot/trmnl-ptv/actions/workflows/publish-ptv-data.yml)

</div>

<!-- disclosure:start -->
> [!WARNING]
> **Pre-1.0 — no stable release yet.** Anything can change in any release, including a patch: APIs, CLI flags, config keys, file formats, and data already on disk. Keep your own backups.
> **Project status.** The badge above is generated from [the adamXbot status list](https://github.com/adamXbot/.github/blob/main/STATUS.md), which says what I promise for this project and every other one.
<!-- disclosure:end -->

> [!CAUTION]
> **The published snapshot is stale.** The `Publish PTV Snapshot` workflow is currently disabled and its last runs failed, so the [`data` branch](https://github.com/adamXbot/trmnl-ptv/tree/data) has not been updated since 2026-07-24. Anything reading `ptv-metro.json` from this repository is reading old data. [PR #2](https://github.com/adamXbot/trmnl-ptv/pull/2) covers the download retry; the rest needs an owner action on GitHub Actions billing. Run the local proxy if you want current departures.

---

## Overview

TRMNL plugins are Liquid templates rendered against a JSON URL. Public Transport Victoria publishes its realtime feed as GTFS Realtime protobuf, which Liquid cannot parse, so a plugin cannot point at the PTV endpoint directly.

This repository is the two halves that close that gap. `src/` holds the plugin templates for all four TRMNL layouts. `proxy/` holds a Ruby service that fetches the metro vehicle-positions feed, decodes the protobuf, joins it against the static GTFS timetable, and returns JSON shaped for those templates.

It is aimed at someone who owns a TRMNL device, wants a Melbourne departure board on it, and is willing to get a free PTV Open Data key and run a small Ruby process or a scheduled GitHub Actions job.

## What it does

- **Decodes the protobuf feed into JSON.** The plugin polls the proxy rather than the PTV endpoint, because `google-protobuf` decoding has to happen somewhere Liquid is not.
- **Joins live vehicles to the static timetable.** Live positions alone give you a `route_id` and a `stop_id`. Loading the static GTFS schedule turns those into a route name, a headsign, a stop name and a platform code.
- **Reports punctuality against the schedule.** Each row carries a status such as `On time` or `2 min delayed`, derived from the scheduled departure time for that trip and stop.
- **Falls back to the timetable when there is no live match.** A stop with no vehicle currently reporting still shows its next scheduled departures rather than an empty table.
- **Treats `stopid` as a platform or a station.** A platform ID such as `12236` gives you one direction; a station group ID such as `vic:rail:RWD` gives you the whole station.
- **Bootstraps its own schedule data.** If the static GTFS directory is missing, the proxy downloads and unzips the published GTFS archive and locates the extracted schedule folder itself.
- **Surfaces upstream failures.** When a fetch fails the payload still returns, carrying the error type and message under `meta.error`, and the templates render that instead of an unexplained blank screen.

## Get it

You need a free key from the [Victorian transport open data portal](https://opendata.transport.vic.gov.au/dataset/gtfs-realtime), set as `PTV_KEY_ID` (or `PTV_SUBSCRIPTION_KEY`).

**Run the proxy on your own machine** — current data, but the machine has to stay up:

```bash
cd proxy
cp .env.example .env   # then set PTV_KEY_ID
bundle install
PTV_KEY_ID=your_keyid bundle exec ruby server.rb
```

Then set the plugin's `proxyurl` field to `http://localhost:9910/ptv/metro/vehicle-positions`.

**Publish snapshots from a fork** — nothing to keep running, but the data is only as fresh as the last workflow run. Fork the repository, add `PTV_KEY_ID` as a repository secret, run the `Publish PTV Snapshot` workflow, and point `proxyurl` at the raw `ptv-metro.json` URL on your fork's `data` branch.

Both paths, including the GitHub Pages stop finder and the plugin's custom fields, are written up in [docs/SELF-HOSTING.md](docs/SELF-HOSTING.md).

## Docs

There is no documentation site. Everything lives in the repository:

- [docs/SELF-HOSTING.md](docs/SELF-HOSTING.md) — full setup for both modes, finding your stop ID, plugin filters, publish cadence, troubleshooting.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the pipeline fits together, the JSON payload shape, proxy endpoints, environment variables.
- [CONTRIBUTING.md](CONTRIBUTING.md) — local development and how to run the tests.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: the plugin preview and the proxy are deliberately separate Bundler bundles, so the protobuf dependency cannot interfere with the TRMNL preview tooling.

There is no test workflow. `proxy/test/` holds three plain-Ruby test files that you run individually:

```bash
cd proxy && bundle install
bundle exec ruby test/stop_lookup_test.rb
```

The only workflow in the repository is `Publish PTV Snapshot`, which generates and pushes the `data` branch. It does not run the tests.

## Licence

MIT — see [LICENSE](LICENSE).
