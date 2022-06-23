# Features
## SAP HANA HA Automated discovery

The central server integrates with the Agents discoveries by **collecting** information about the target SAP infrastructure and then **detects** different kind of scenarios and **reacts** accordingly.

See also [Trento Agent](https://github.com/trento-project/agent) for additional information.
## Reactive Control Plane

By leveraging modern approaches to software architecture and engineering and top notch technologies we built a **reactive system** that provides **realtime** feedbacks about the **changes in the target** infrastructure.

Here's a non-comprehensive list of the capabilities provided by the bundled Web UI:

- Global Health Overview
- Hosts Overview and Detail
- Pacemaker Clusters Overview and Detail
- SAP Systems Overview and Detail
- HANA Databases Overview and Detail 
- Checks Catalog
## Configuration validation

Trento is able to execute a variety of *configuration health checks* (a.k.a. the _HA Config Checks_) among the installed Trento Agents.

- Pacemaker, Corosync, SBD, SAPHanaSR and other generic _SUSE Linux Enterprise for SAP Application_ OS settings
- Specific configuration audits for SAP HANA Scale-Up Performance-Optimized scenarios deployed on MS Azure cloud.

See [Trento Runner](https://github.com/trento-project/runner) for additional information.

## Monitoring
It is important in critycal business systems to have access to relevant information about _how things are going_.

Currently Trento provides a basic integration with **Grafana** and **Prometheus**.

See [related documentation](./docs/monitoring/monitoring.md) for more information.

## Alerting
Alerting feature notifies the SAP Administrator about important updated in the Landscape being monitored/observed by Trento.

See [related documentation](./docs/alerting/alerting.md) for more information.