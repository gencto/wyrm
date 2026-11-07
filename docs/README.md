# WYRM documentation

Start with the root [README](../README.md): what WYRM is, a quick start with one broker, and the demo of three sites (`examples/demo/run.sh`).

## Guides

| Guide | Read it when you want to |
|---|---|
| [links.md](links.md) | install a link while the broker runs, package one, give it network or grants |
| [history.md](history.md) | record points, read their history, keep broker storage (`storage`) |
| [scheduler.md](scheduler.md) | switch equipment on a weekly schedule, with special days and overrides |
| [dql.md](dql.md) | collect values from many points into one table, or write them on to a target |
| [alarm.md](alarm.md) | raise alarms from points (range, boolean, staleness, quality), acknowledge them, send the records to a central database |
| [uplink.md](uplink.md) | send live values to an MQTT broker (UNS), a Sparkplug B host, ThingsBoard, Azure IoT Hub or AWS IoT Core |
| [../deploy/docker](../deploy/docker/README.md) | run the broker and links in minimal `scratch` containers; image sizes and memory |
| [filestores.md](filestores.md) | connect S3, Google Drive, WebDAV or a local directory and move files |
| [mcp.md](mcp.md) | let an AI assistant read the tree and propose changes for a person to approve |
| [agent.md](agent.md) | work on the broker network from the command line (`wyrm-agent`), or run the AI agent link |
| [flow-blocks.md](flow-blocks.md) | calculate in a dataflow with blocks: variables, math, if, hub, stopwatch, text |
| [operations.md](operations.md) | run `wyrmd` under systemd or a container, know what a restart recovers and how fast, back up and restore `data_dir` |

## Protocol links

| Guide | Devices or services |
|---|---|
| [modbus.md](modbus.md) | Modbus TCP and RTU, as a master or as a slave |
| [bacnet.md](bacnet.md) | BACnet/IP devices |
| [opcua.md](opcua.md) | OPC UA servers |
| [s7.md](s7.md) | Siemens S7 PLCs |
| [snmp.md](snmp.md) | SNMP v2c and v3 agents |
| [http.md](http.md) | HTTP/REST services that answer JSON |
| [prometheus.md](prometheus.md) | Prometheus and OpenMetrics endpoints |

The history sync links (`links/postgres`, `mysql`, `mongodb`, `influxdb`, `dynamodb`) send the historian's data to an external database. ADR 0026 describes them.

Every protocol link has a simulator. The guides show how to run it. No link has been checked against a real device yet (ADR 0029, decision 5).

## Rules and decisions

- [`spec/`](../spec/README.md) is the normative protocol: keys, metadata, values, tokens, methods, flows.
- [`adr/`](adr/) holds one file per decision. [ADR 0029](adr/0029-delegated-decisions.md) collects the decisions the owner delegated on 2026-10-31. [ADR 0031](adr/0031-security-review-2026-10-31.md) says what happens to each finding of the security review of 2026-10-31 (`security/review-2026-10-31.md`).
- [`security/threats.md`](security/threats.md) lists the threats and what answers each one.
- [`backlog.md`](backlog.md) lists the work that is known and not done.
