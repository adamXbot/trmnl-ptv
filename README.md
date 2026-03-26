# trmnl-ptv-victoria

A starter TRMNL plugin for Public Transport Victoria using the PTV GTFS Realtime vehicle positions feed.

This is adapted from the Queensland Translink example, but there is one important difference:

- The attached PTV realtime endpoint is a Protocol Buffers feed.
- TRMNL Liquid templates expect JSON.
- That means this plugin should poll a small JSON proxy that fetches the PTV feed, decodes the protobuf payload, and returns JSON to TRMNL.

The current plugin is therefore set up to consume a proxy URL, not the raw PTV endpoint directly.

## Deployment Modes

This repo now supports two ways to produce the JSON that TRMNL reads:

- local proxy mode: run [proxy/server.rb](/Users/user/Downloads/ptv-victoria/proxy/server.rb) on your machine and point TRMNL at `http://localhost:9910/ptv/metro/vehicle-positions`
- GitHub Actions snapshot mode: generate `ptv-metro.json` on a public `data` branch in your fork and point TRMNL at the raw GitHub URL

## Included Proxy

This folder now also includes a small Ruby proxy at [proxy/server.rb](/Users/user/Downloads/ptv-victoria/proxy/server.rb).

It:

- calls the PTV metro train `vehicle-positions` endpoint
- sends your `KeyId` or `Ocp-Apim-Subscription-Key`
- decodes the GTFS Realtime protobuf feed
- auto-downloads and unzips the static GTFS schedule when the expected local folder is missing
- returns JSON that matches the Liquid templates in this plugin
- caches responses for 30 seconds by default to stay friendly to the PTV rate limits
- returns structured JSON error details so TRMNL can render a useful message instead of only showing a generic fetch failure

The same fetch/decode/enrich path is also exposed as a one-shot snapshot generator for CI:

- [generate_snapshot.rb](/Users/user/Downloads/ptv-victoria/proxy/bin/generate_snapshot.rb)
- [generate_stop_index.rb](/Users/user/Downloads/ptv-victoria/proxy/bin/generate_stop_index.rb)
- [schedule_gate.rb](/Users/user/Downloads/ptv-victoria/proxy/bin/schedule_gate.rb)
- [snapshot_changed.rb](/Users/user/Downloads/ptv-victoria/proxy/bin/snapshot_changed.rb)
- [find_stop.rb](/Users/user/Downloads/ptv-victoria/proxy/bin/find_stop.rb)

## What This Version Shows

This starter renders live metro train status filtered by:

- `stopid` optionally
- `routeid` optionally
- a staleness window so very old vehicle updates are hidden

It uses the live GTFS Realtime feed plus the static GTFS schedule files to show:

- route and destination
- matched stop name from the trip timetable
- on-time or delayed status based on the scheduled stop time

## Expected JSON Shape

The templates assume your proxy returns GTFS Realtime data in JSON with the standard shape:

```json
{
  "header": {
    "timestamp": 1710000000
  },
  "entity": [
    {
      "id": "123",
      "vehicle": {
        "timestamp": 1710000000,
        "stop_id": "19842",
        "trip": {
          "route_id": "1",
          "trip_id": "12345"
        },
        "vehicle": {
          "id": "9001",
          "label": "9001"
        },
        "position": {
          "latitude": -37.81,
          "longitude": 144.96,
          "bearing": 180
        }
      }
    }
  ]
}
```

## Setup

### Local Proxy

1. `brew install rbenv`
2. `brew install firefox@nightly`
3. `brew install imagemagick`
4. `rbenv init`
5. `rbenv local`
6. `bundler install`
7. `trmnlp login`
8. `cd proxy`
9. `bundle install`
10. Copy [proxy/.env.example](/Users/user/Downloads/ptv-victoria/proxy/.env.example) to `.env` or export the variables in your shell
11. Start the proxy with `PTV_KEY_ID=your_keyid bundle exec ruby server.rb`
12. Add `http://localhost:9910/ptv/metro/vehicle-positions` as the plugin `proxyurl`
13. `cd ..`
14. `trmnlp serve`
15. `trmnlp push`

If [proxy/server.rb](/Users/user/Downloads/ptv-victoria/proxy/server.rb) does not find the GTFS files at `PTV_GTFS_PATH`, it will download the zip from `PTV_GTFS_ZIP_URL`, unzip it into `PTV_GTFS_DOWNLOAD_ROOT`, and then locate the extracted schedule directory automatically. By default these paths are relative to the current working directory where you start the proxy, such as `./data/gtfs/2`.

### Finding Your Stop ID

The easiest option for someone using the GitHub Actions mode is the published stop finder page on the `data` branch.

After the workflow runs and GitHub Pages is enabled for the `data` branch root, open:

`https://<your-user>.github.io/<your-repo>/`

Then search for a station name like `Ringwood`. The page will load `stops.json`, filter it in the browser, and show the station record plus the platform stop IDs you can copy into the TRMNL plugin.

For Ringwood, the useful matches are:

- `12235` for `Ringwood Station` platform `3`
- `12236` for `Ringwood Station` platform `1`
- `12237` for `Ringwood Station` platform `2`
- `vic:rail:RWD` for the station group record

For the TRMNL plugin `stopid`, you should usually use the platform stop ID, not the station group ID. For example, if you want Ringwood platform 1, set `stopid` to `12236`.

If you are running the local proxy instead, you can still search locally with:

```bash
curl "http://localhost:9910/ptv/stops/search?q=Ringwood"
```

That endpoint returns the same stop lookup results as the published page.

### GitHub Actions Snapshot Mode

1. Fork the repository.
2. Keep the fork public so TRMNL can read the raw JSON file.
3. Add `PTV_KEY_ID` as a repository secret.
4. Optionally add `PTV_SUBSCRIPTION_KEY` if you want to use that auth path instead.
5. Enable GitHub Actions on the fork.
6. In GitHub `Settings` -> `Pages`, set the source to deploy from branch `data` and folder `/ (root)`.
7. Run the [publish-ptv-data.yml](/Users/user/Downloads/ptv-victoria/.github/workflows/publish-ptv-data.yml) workflow once with `workflow_dispatch`.
8. Confirm the workflow creates a `data` branch containing `ptv-metro.json`, `stops.json`, and `index.html`.
9. Set the TRMNL plugin `proxyurl` to `https://raw.githubusercontent.com/<your-user>/<your-repo>/data/ptv-metro.json`.
10. Open the stop finder at `https://<your-user>.github.io/<your-repo>/` to look up station/platform stop IDs.

### GitHub Token Notes

For the included workflow, you usually do not need to create a separate personal access token for GitHub.

- The workflow pushes to the `data` branch using the built-in `GITHUB_TOKEN`.
- This works as long as GitHub Actions has write access to repository contents.

To make sure that works in your fork:

1. Open your fork on GitHub.
2. Go to `Settings` -> `Actions` -> `General`.
3. Under `Workflow permissions`, choose `Read and write permissions`.
4. Save the change.

If you do want to create a personal access token anyway, use it only if you have a custom workflow setup that cannot rely on `GITHUB_TOKEN`.

To create a fine-grained personal access token:

1. Open GitHub `Settings` -> `Developer settings` -> `Personal access tokens` -> `Fine-grained tokens`.
2. Click `Generate new token`.
3. Set the resource owner to your GitHub account.
4. Limit repository access to your fork of this repo.
5. Give it `Contents: Read and write` permission.
6. Generate the token and copy it immediately.
7. Add it as a repository secret such as `GH_PAT` if you later customize the workflow to use it.

The default workflow in this repo does not require `GH_PAT`.

Default cadence:

- every 15 minutes all day
- every 5 minutes from 7:00am to 9:00am Melbourne time on weekdays

Supported scheduling presets via workflow environment variables:

- keep defaults for `15 min all day` plus `5 min` on weekday peak
- set `PEAK_INTERVAL_MINUTES=15` to keep `15 min all day only`
- set `BASE_INTERVAL_MINUTES=5` and `PEAK_INTERVAL_MINUTES=5` for `5 min all day`
- change `PEAK_DAYS`, `PEAK_START_LOCAL`, and `PEAK_END_LOCAL` for custom peak windows

## Proxy Endpoints

- `GET /health`
- `GET /ptv/metro/vehicle-positions`
- `GET /ptv/stops/search?q=Ringwood`

## Proxy Environment Variables

- `PTV_KEY_ID`: preferred when using the auth style from your working curl example
- `PTV_SUBSCRIPTION_KEY`: optional alternate auth method
- `PORT`: optional, defaults to `9910`
- `PTV_CACHE_TTL_SECONDS`: optional, defaults to `30`
- `PTV_METRO_VEHICLE_POSITIONS_URL`: optional override for the upstream feed URL
- `PTV_GTFS_PATH`: optional override for the local static GTFS folder
- `PTV_GTFS_ZIP_URL`: optional override for the GTFS zip download URL
- `PTV_GTFS_DOWNLOAD_ROOT`: optional override for where the GTFS zip is unpacked
- `BASE_INTERVAL_MINUTES`: GitHub Actions cadence outside the peak window
- `PEAK_INTERVAL_MINUTES`: GitHub Actions cadence inside the peak window
- `PEAK_START_LOCAL`: Melbourne local start time for the peak window
- `PEAK_END_LOCAL`: Melbourne local end time for the peak window
- `PEAK_DAYS`: comma-separated day keys such as `mon,tue,wed,thu,fri`, or `weekday`, or `daily`

## Notes

- This starter currently targets the metro train vehicle positions feed because that is what your attached files describe.
- If you want a true stop departures plugin next, we can extend this proxy to call a PTV departures endpoint and reshape that JSON for the original timetable-style UI.
- The proxy bundle is intentionally separate from the root TRMNL preview bundle so protobuf dependencies do not interfere with plugin preview tooling.
- The proxy includes local Bundler config in [proxy/.bundle/config](/Users/user/Downloads/ptv-victoria/proxy/.bundle/config) to prefer a native build of `google-protobuf`, which helps on Apple Silicon machines.
- GitHub Actions compares snapshots with volatile timestamps stripped, so the `data` branch only changes when the underlying payload meaningfully changes.
- The GitHub Actions publish step also writes a static stop finder page to the `data` branch so users can search station names in the browser and copy the correct platform stop ID.
