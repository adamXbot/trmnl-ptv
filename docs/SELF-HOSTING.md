# Self-hosting

Two ways to produce the JSON that TRMNL reads. Both need a key from the
[Victorian transport open data portal](https://opendata.transport.vic.gov.au/dataset/gtfs-realtime).

- **Local proxy mode** — run [proxy/server.rb](../proxy/server.rb) on your own machine and point TRMNL at
  `http://localhost:9910/ptv/metro/vehicle-positions`. Data is current, but the machine and the TRMNL
  device have to be able to reach each other.
- **GitHub Actions snapshot mode** — a scheduled workflow writes `ptv-metro.json` to a public `data`
  branch in your fork, and TRMNL polls the raw GitHub URL. Nothing to keep running, but the data is
  only as fresh as the last successful workflow run.

## Local proxy mode

1. Install a Ruby matching [.ruby-version](../.ruby-version).
2. `cd proxy`
3. `bundle install`
4. Copy [proxy/.env.example](../proxy/.env.example) to `.env`, or export the variables in your shell.
5. Start the proxy: `PTV_KEY_ID=your_keyid bundle exec ruby server.rb`
6. Set the plugin's `proxyurl` custom field to `http://localhost:9910/ptv/metro/vehicle-positions`.

If the proxy does not find GTFS files at `PTV_GTFS_PATH`, it downloads the zip from
`PTV_GTFS_ZIP_URL`, unzips it into `PTV_GTFS_DOWNLOAD_ROOT`, and then locates the extracted schedule
directory automatically. By default those paths are relative to the working directory you start the
proxy from, so the schedule lands in `./data/gtfs/2`. The archive is large; the first start is slow.

## GitHub Actions snapshot mode

1. Fork the repository.
2. Keep the fork public, so TRMNL can read the raw JSON without authentication.
3. Add `PTV_KEY_ID` as a repository secret. Add `PTV_SUBSCRIPTION_KEY` instead if you want that auth path.
4. Enable GitHub Actions on the fork.
5. Run the [publish-ptv-data.yml](../.github/workflows/publish-ptv-data.yml) workflow once via `workflow_dispatch`.
6. Confirm the run creates a `data` branch containing `ptv-metro.json`, `stops.json` and `index.html`.
7. Set the plugin's `proxyurl` to `https://raw.githubusercontent.com/<your-user>/<your-repo>/data/ptv-metro.json`.

To publish the stop finder page as well, open `Settings` → `Pages`, choose `Deploy from a branch`,
select the `data` branch and the `/ (root)` folder, and save. The finder is then at
`https://<your-user>.github.io/<your-repo>/`.

Notes on Pages:

- The `data` branch will not appear in the branch dropdown until the first successful run creates it.
- If the site URL 404s immediately after saving, wait a minute or two and refresh.
- Pages is not enabled on `adamXbot/trmnl-ptv` itself, so there is no upstream finder page to use.

### Workflow permissions

The workflow pushes to the `data` branch with the built-in `GITHUB_TOKEN`, so you do not need a
personal access token. It does need contents write access:

1. Open your fork's `Settings` → `Actions` → `General`.
2. Under `Workflow permissions`, choose `Read and write permissions`.
3. Save.

If you later customise the workflow so it cannot rely on `GITHUB_TOKEN`, a fine-grained personal
access token scoped to your fork with `Contents: Read and write` will do, stored as a secret such as
`GH_PAT`. The workflow in this repository does not read `GH_PAT`.

### Publish cadence

The cron in the workflow fires every 5 minutes, and [proxy/bin/schedule_gate.rb](../proxy/bin/schedule_gate.rb)
decides whether that tick should actually generate a snapshot. As shipped:

- every 15 minutes all day (`BASE_INTERVAL_MINUTES=15`)
- every 5 minutes between 07:00 and 09:00 Melbourne time on weekdays (`PEAK_INTERVAL_MINUTES=5`)

Change the workflow's environment variables to alter that:

- `PEAK_INTERVAL_MINUTES=15` — 15 minutes all day, no peak.
- `BASE_INTERVAL_MINUTES=5` and `PEAK_INTERVAL_MINUTES=5` — 5 minutes all day.
- `PEAK_DAYS`, `PEAK_START_LOCAL`, `PEAK_END_LOCAL` — a different peak window.

A `workflow_dispatch` run sets `FORCE_RUN`, which bypasses the gate.

Snapshots are compared with volatile timestamps stripped, so the `data` branch only gains a commit
when the underlying payload meaningfully changes.

## Finding your stop ID

With the finder page published, open `https://<your-user>.github.io/<your-repo>/` and search for a
station name such as `Ringwood`. The page loads `stops.json`, filters it in the browser, and shows
the station record plus its platform stop IDs.

Running the proxy locally, the same lookup is available over HTTP:

```bash
curl "http://localhost:9910/ptv/stops/search?q=Ringwood"
```

or on the command line, without starting the server:

```bash
cd proxy && bundle exec ruby bin/find_stop.rb "Ringwood"
```

Ringwood returns, among others:

- `12235` — Ringwood Station, platform 3
- `12236` — Ringwood Station, platform 1
- `12237` — Ringwood Station, platform 2
- `vic:rail:RWD` — the station group record

Use a platform stop ID when you want one direction of travel. Use the station group ID when you want
the whole station and are happy to see both directions together.

## Plugin custom fields

Set these on the TRMNL plugin settings screen. They are declared in [src/settings.yml](../src/settings.yml).

- `proxyurl` — required. The local proxy URL or the raw snapshot URL.
- `stopid` — a platform stop ID such as `12236`, or a station group ID such as `vic:rail:RWD`.
  The templates only render departure rows once this is set.
- `routeid` — optional exact match against the live `vehicle.trip.route_id`. Leave blank unless you
  specifically want to narrow the results.
- `stalemins` — hide vehicles whose position timestamp is older than this many minutes. Defaults to
  20. In snapshot mode keep it at 20 or more, so off-peak 15-minute snapshots are not filtered out.

## Troubleshooting

No rows showing:

- Confirm `stopid` is set. The templates render nothing without it.
- Clear `routeid` first.
- Try a platform stop ID before a station group ID.
- Raise `stalemins` to 20 or 30.
- Confirm `proxyurl` points at the raw `ptv-metro.json` URL, not the stop finder page.

If the payload carries `meta.error`, the templates display the error type and message; that is an
upstream fetch or auth failure rather than a filter problem. `auth_mode` in `meta` reports which
credential the proxy used, or `missing` if neither was set.
