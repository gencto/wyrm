# `dsa-nodes.json`: sources

A hand-written `nodes.json` of `dslink-java-modbus` (commit `0745d7d`, v1.0.0;
no real one exists on the owner's machine, checked 2026-10-29): one IP and one
serial connection, a device on each, a folder, points of several data types
and scalings. Each attribute below is cited from that source
(`src/main/java/modbus/`). JSON has no comments, so the citations are here.

## File format

The link persists its tree with the DSA Java SDK serializer. The link builds
against `sdk-dslink-java` 1.0.0 (`build.gradle`); the serializer was read from
the bytecode of `dslink-0.20.1.jar` of the same SDK
(`org.dsa.iot.dslink.serializer.Serializer.serializeChildren`, found in
`~/Projects/DSA/dsa-volume/dslinks/MQTT/lib`), the only copy on this machine:

- the top level holds the link node's children by name;
- a node is an object: `$name` (display name), `$interface`, `$is` (profile,
  `node`), `$type`, `?value`, `$$password`, `$writable` (`write`), `$hidden`,
  `$$<key>` (ro configs), `$<key>` (configs), `@<key>` (attributes), then each
  serializable child under `Node.getName()`;
- names are encoded with `StringUtils.encodeName` (`%XX`); the importer decodes
  them;
- actions are created with `setSerializable(false)`, so they are not in the
  file; the status leaves are (they are plain value children).

The importer reads attributes as `@<key>` only, and accepts numbers written
as strings (as `Util.getIntValue` / `getDoubleValue` do, `Util.java:155-177`).
The byte orders of the SWAP types are those of modbus4j 3.0.5
`NumericLocator.bytesToValueRealOffset`.

## Connections

| Attribute | Source | Value |
|---|---|---|
| `@restoreType` = `conn` | `ModbusConnection.java:61-62,115`; restore `ModbusLink.java:335-339,376` | node without it is removed at start |
| `@transport type` | `ModbusConnection.java:47`, `IpConnection.java:26` | `TCP`/`UDP` (`IpTransportType.java:4`), `RTU`/`ASCII` (`SerialTransportType.java:4`); read upper-cased (`IpConnection.java:192`, `SerialConn.java:268`) |
| `@host`, `@port` | `ModbusConnection.java:63`, `IpConnection.java:27`; written `ModbusLink.java:527-529` | IP connection when both are set (`ModbusLink.java:388`) |
| `@comm port id` (`@comm port id (manual entry)`) | `ModbusConnection.java:64-65`; written `ModbusLink.java:479` | serial port; the manual entry is stored as `comm port id` (`ModbusLink.java:451-456`) |
| `@baud rate`, `@data bits`, `@stop bits`, `@parity` | `SerialConn.java:29-32`; written `ModbusLink.java:480-483` | parity `NONE`/`ODD`/`EVEN`/`MARK`/`SPACE` (`ParityType.java:4`), unknown read as NONE (`ParityType.java:6-26`) |
| `@Timeout` (capital T) | `ModbusConnection.java:48` | ms; default 500 (`ModbusLink.java:353-355`) |
| `@retries` | `ModbusConnection.java:49` | default 2 (`ModbusLink.java:356-358`) |
| `@max read bit count`, `@max read register count`, `@max write register count` | `ModbusConnection.java:50-52`; written `413-421` | defaults 2000/125/120 (`ModbusLink.java:200-204`) |
| `@discard data delay` | `ModbusConnection.java:53` | default 0 (`ModbusLink.java:205`) |
| `@use multiple write commands` | `ModbusConnection.java:54-59` | `Always`/`Never`/`As Appropriate`; legacy bool `use multiple write commands only` (`ModbusLink.java:364-372`); used on writes `SlaveFolder.java:570-593` |
| `Connection Status` child | `ModbusConnection.java:67,112-113` | string value child, serialized |

## Devices

| Attribute | Source | Value |
|---|---|---|
| `@restoreType` = `folder` | `SlaveFolder.java:84` (a `SlaveNode` is a `SlaveFolder`) | |
| `@slave id`, `@polling interval` | `ModbusConnection.java:39-40`; a child with both is a device (`ModbusConnection.java:172-196`) | |
| `@polling interval` | written in **ms**: `IpConnection.java:173-181`, `SerialConn.java:201-227`; read `SlaveNode.java:77`; the edit form divides by 1000 (`SlaveNode.java:103`) | 5000 = 5 s |
| `@zero on failed poll` | `ModbusConnection.java:41`; default false (`174-177`); used `SlaveNode.java:208-216,243-249,358-364` | |
| `@use batch polling` | `ModbusConnection.java:42`; default true (`178-181`); used `SlaveNode.java:172-253` | |
| `@contiguous batch requests only` | `ModbusConnection.java:43`; default true at restore (`182-185`), false in the add form (`282`) | written explicitly here |
| `@suppress non-cov update duration` | `ModbusConnection.java:44`; written in **ms** (`IpConnection.java:178,185`); default 60000 (`ModbusConnection.java:186-189`); 0 = publish on every poll (`SlaveNode.java:375-386`) | |
| copies of the connection's attributes on a serial device | `SerialConn.java:208-245` | read from the connection, ignored on the device |
| `Device Status` child | `SlaveFolder.java:68`, `SlaveNode.java:65-68` | string value child, serialized |

## Folders and points

| Attribute | Source | Value |
|---|---|---|
| folder: `@restoreType` = `folder` | `SlaveFolder.java:65,84,135-137` | nested without a limit in DSA |
| point: `@restoreType` = `point` | `SlaveFolder.java:66,349` | |
| `@type` | `SlaveFolder.java:55`; `COIL`/`DISCRETE`/`HOLDING`/`INPUT` (`PointType.java:6`) | |
| `@offset` | `SlaveFolder.java:56` | the register address (0-based modbus4j offset) |
| `@number of registers` | `SlaveFolder.java:57` | used by text types only (`SlaveNode.java:274`, `SlaveFolder.java:648-650`) |
| `@data type` | `SlaveFolder.java:58`; names `DataType.java:4-31`; modbus4j codes `DataType.java:60-112` | coil/discrete always `BOOLEAN` (`SlaveFolder.java:317-319`) |
| `@bit` | `SlaveFolder.java:59`; -1 when unset (`144-145`, `334`) | BOOLEAN on a register with bit -1 reads the register as 16 bools (`SlaveNode.java:270-271,313-319`) |
| `@scaling`, `@scaling offset` | `SlaveFolder.java:60-61` | value = raw / scaling + offset (`SlaveNode.java:326,339,348`); write = value × scaling − offset (`SlaveFolder.java:640,684`) |
| `@writable` | `SlaveFolder.java:62`; only coil and holding (`314-315`) | |
| a point without one of type, offset, number of registers, data type, scaling, scaling offset, writable is removed | `SlaveFolder.java:149-167` | |
| `$type`, `?value`, `$writable` | runtime state (`SlaveFolder.java:338,392`) | ignored |

## Cases in the fixture

- `Plant TCP/Meter 1/Setpoint`: Review Focus 3 (`scaling 10`, `scaling offset 2`, raw 250 → 27.0).
- `Line 2 RS485/VFD 7`: `zero on failed poll` true, batch polling off, suppress 0.
- `Line 2 RS485/VFD 7/Ratio`: `scaling 0`, refused.
- `@max write register count` on both connections: no equivalent, reported.
