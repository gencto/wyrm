// Canvas data, kept as the boards write it.
// ignore_for_file: lines_longer_than_80_chars

import 'package:material_ui/material_ui.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/task_sheet.dart';

import 'backups.dart';
import 'system.dart';

// The data of boards `BrokerUpdate`, `BrokerUpdateRestart`,
// `BrokerUpdateDone`, `BrokerUpdateRolledBack` and `BrokerUpdateExternal`
// (design canvas): the dialog over System. The broker side (ADR 0048 §2)
// is not built; these view-models are fixtures.

Widget _over(TaskSheetVm sheet) => over(systemMaint(), sheet, width: 640);

/// Board `BrokerUpdate`: the review.
Widget brokerUpdateReview() => _over(
  const TaskSheetVm(
    title: 'Update plant to wyrmd 0.2.0',
    pill: '0.1.0 → 0.2.0',
    pillTone: Tone.ember,
    sub: 'Released 12 Nov · from the official release channel · the broker restarts once',
    blocks: [
      SheetLabel('Checked before anything changes'),
      SheetCard(
        title: 'Release signed and checked',
        detail: 'wyrmd 0.2.0 linux-aarch64 · Ed25519 signature of the WYRM release key · SHA-256 ok',
      ),
      SheetCard(
        title: 'The new binary accepts this configuration',
        detail: 'wyrmd 0.2.0 check /etc/wyrm/wyrmd.json5: ok',
      ),
      SheetCard(
        title: 'Room for it',
        detail:
            '41 MiB for the binary and the pre-update backup; 38.2 GiB free',
      ),
      SheetCard(
        tone: Tone.warn,
        title: 'Registry moves from SCHEMA 19 to 20',
        detail: '0.1.0 cannot read it afterwards: a rollback restores the pre-update backup of the control plane, so changes made after the update are lost on rollback.',
      ),
      SheetCard(
        title: 'Links built for this broker',
        detail: 'Every installed package says wyrm_link 3; 0.2.0 runs 2 and 3.',
      ),
      SheetCard(
        tone: Tone.warn,
        title: 'A standby follows this broker',
        detail: 'Update standby:plant first (it takes no traffic), then this one: the standby takes over for the restart.',
      ),
      SheetLabel('How it goes'),
      SheetBullets(
        [
          'Pre-update backup of the control plane, secrets sealed (12 MiB, kept until the update is confirmed).',
          'The new binary is staged beside the current one; 0.1.0 stays on disk.',
          'The broker stops cleanly and the service manager starts 0.2.0 (systemd: about 5–15 s without the broker).',
          '0.2.0 runs on trial: it must have the router, the gateway and its links back within 3 min.',
          'Then it confirms itself. If it does not, the next start goes back to 0.1.0 with the backup of step 1.',
        ],
        numbered: true,
      ),
      SheetField(
        id: 'confirm',
        label: 'Type plant to confirm',
        value: 'plant',
      ),
    ],
    note: 'Needs config on sys · audited',
    secondary: 'Cancel',
    primary: 'Back up and update',
  ),
);

/// Board `BrokerUpdateRestart`: Studio reconnects by itself.
Widget brokerUpdateRestart() => _over(
  const TaskSheetVm(
    title: 'Updating plant',
    pill: 'restarting',
    pillTone: Tone.ember,
    sub: 'This screen reconnects by itself.',
    blocks: [
      SheetSpinner(
        title: 'plant is restarting on 0.2.0',
        text: 'Studio lost the gateway at 15:31:04 and tries again every 2 s · 00:14',
      ),
      SheetSteps([
        SheetStep(
          'Pre-update backup',
          SheetStepState.done,
          detail: 'backups/pre-update-0.2.0.wyrm-backup · 12 MiB',
        ),
        SheetStep(
          '0.2.0 staged',
          SheetStepState.done,
          detail: 'versions/0.2.0/wyrmd',
        ),
        SheetStep(
          'Stopped on 0.1.0, started on 0.2.0',
          SheetStepState.done,
          detail: 'systemd restart',
        ),
        SheetStep('Registry migrated 19 → 20', SheetStepState.now),
        SheetStep('Router, gateway, links back', SheetStepState.todo),
        SheetStep('Confirmed', SheetStepState.todo),
      ]),
      SheetText(
        'Links on other machines walk to their next endpoint or wait; devices keep their last outputs. Values recorded by links during the restart are not lost if the link buffers them.',
        small: true,
      ),
    ],
    note: 'Closing Studio does not stop it.',
    secondary: 'Hide',
    primary: 'Reconnecting…',
    primaryEnabled: false,
    busy: true,
  ),
);

/// Board `BrokerUpdateDone`: confirmed after its trial start.
Widget brokerUpdateDone() => _over(
  const TaskSheetVm(
    title: 'plant updated',
    pill: '0.2.0',
    pillTone: Tone.good,
    blocks: [
      SheetBanner(
        title: 'plant runs 0.2.0',
        text: 'Router, gateway and 9 of 9 links back in 41 s. The update is confirmed; 0.1.0 and the pre-update backup are kept for 7 days.',
      ),
      SheetFacts([
        FactVm(
          label: 'Version',
          value: '0.1.0 → 0.2.0 · Zenoh 1.10.1 → 1.11.0',
        ),
        FactVm(label: 'Without the broker', value: '9 s'),
        FactVm(label: 'Links back', value: '9 of 9 in 41 s'),
        FactVm(
          label: 'Roll back',
          value: 'possible until 20 Nov (control plane as at 15:30)',
        ),
        FactVm(label: 'Audit', value: 'update_start, update_confirmed'),
      ]),
    ],
    secondary: 'Close',
    primary: 'Roll back to 0.1.0…',
    primaryQuiet: true,
  ),
);

/// Board `BrokerUpdateRolledBack`: the trial start failed.
Widget brokerUpdateRolledBack() => _over(
  const TaskSheetVm(
    title: 'Update rolled back',
    pill: '0.1.0',
    pillTone: Tone.warn,
    blocks: [
      SheetBanner(
        tone: Tone.warn,
        title: 'Back on 0.1.0',
        text: '0.2.0 started but the gateway did not come up in 3 min (port 8446 in use). The next start went back to 0.1.0 and restored the control plane from the pre-update backup. Nothing changed on the links.',
      ),
      SheetFacts([
        FactVm(label: 'Tried', value: '0.2.0 · 15:31 – 15:34'),
        FactVm(
          label: 'Reason',
          value: 'gateway: bind 127.0.0.1:8446: address in use',
        ),
        FactVm(label: 'Now', value: '0.1.0 · control plane as at 15:30'),
        FactVm(
          label: 'Log of 0.2.0',
          value: 'kept in backups/pre-update-0.2.0',
        ),
        FactVm(label: 'Audit', value: 'update_rollback'),
      ]),
    ],
    secondary: 'Close',
    primary: 'Open the log of 0.2.0',
  ),
);

/// Board `BrokerUpdateExternal`: in a container, update the image.
Widget brokerUpdateExternal() => _over(
  const TaskSheetVm(
    title: 'Update plant to wyrmd 0.2.0',
    pill: 'container',
    sub: 'Released 12 Nov',
    blocks: [
      SheetText(
        'This broker runs in a container (updates.mode: "external"). It cannot replace itself: the image is changed where the container is defined, and the data volume carries the state across.',
      ),
      SheetCode(
        'image: ghcr.io/gencto/wyrmd:0.2.0\ndocker compose pull wyrmd && docker compose up -d wyrmd',
      ),
      SheetText(
        'Studio still makes the pre-update backup for you before you do it.',
      ),
    ],
    secondary: 'Close',
    primary: 'Make the backup',
  ),
);
