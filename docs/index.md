# Trento

An open cloud-native web console improving on the work day of SAP Applications administrators.

## Introduction

_Trento_ is a comprehensive cloud-native, distributed monitoring solution.

It's made by three main components:

- Trento Agent
- Trento Runner
- Trento Web (current repository)

[Trento Agent](https://github.com/trento-project/agent) is a single background **process running in each host of the target** infrastructure the user desires to monitor.

[Trento Runner](https://github.com/trento-project/runner) responsible of **running the Trento configuration health checks** among the installed Trento Agents.

_Trento Web_ is the **control plane of the Trento Platform**.
In cooperation with the Agents and the Runner discovers, observes, monitors and checks the target SAP infrastructure.

See the [architecture document](./docs/architecture/trento-architecture.md) for additional details.

> Being the project in development, all of the above might be subject to change!

## Support

Please only report bugs via [GitHub issues](https://github.com/trento-project/web/issues);
for any other inquiry or topic use [GitHub discussion](https://github.com/trento-project/trento/discussions).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## License

Copyright 2021-2022 SUSE LLC

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at

https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.