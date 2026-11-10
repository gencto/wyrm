# frx batches

The scaffold of WYRM Studio as `frx batch` declarations (ADR 0037, `docs/studio.md` §4). Apply them in this order from `studio/`; each one is one transaction (all or nothing).

| File | Phase | What it makes |
|---|---|---|
| `10-domain.json` | 2 | enums `link_mode`, `quality`, `task_state`, `peer_kind`, `links_tab`; freezed models (fields are written by hand) and the `install_source` union |
| `20-state.json` | 2 | substates `site`, `nodes`, `live`, `links`, `quarantine`, `packages`, `link_install`, `peers`, `flows`, `flow_editor`, `tasks`, `assistant` |
| `21-fields.json` | 2 | typed tables (`IMap<String, Model>`, views `IList<String>`), the fields of each substate and their setter actions |
| `30-actions.json` | 6–12 | the broker actions of Links, Add a link, Sites, Flows and the Assistant |
| `40-navigation.json` | 5 | the `studio` tabs shell (eight workspaces) and the `link_install` and `flow_editor(id)` pages |
| `50-services.json` | 3 | services + dispatchers `wyrm_connection`, `live_values`, `tree_watch`, `agent_tasks` |
| `60-system.json` | System spec | models `log_line`, `traffic_sample`, `profile_info`; the fields of `system` (tab, measure, source, lines, auto, shown, samples, profiles, …) with their setters; actions `sample_traffic`, `clear_conns`, `retrieve_profiles`, `put_profile`, `remove_profile`, `retrieve_sys_about`; service `traffic` |
| `61-system-widgets.json` | System spec | the widgets of the System boards: `pill_tabs`, `sys_tile`, `traffic_card`, `attention_panel`, `standby_pair`, `log_table`, `command_card`, `section_card`, `row_list`, `term_table`, `code_text`, `log_toolbar`, `warn_banner`, `guide_card` |

```sh
frx batch docs/batches/10-domain.json --dry-run   # the plan, nothing kept
frx batch docs/batches/10-domain.json             # apply; codegen runs once afterwards
frx doctor
```

Checked with frx 0.3.7 on a fresh `frx create` after the commands of phase 1: every file applies, and `frx doctor` then reports only the generated parts that build_runner has not written yet.

A batch only creates (`add-*`); removals (`frx remove … --apply`) are separate commands, listed in `docs/studio.md`.
