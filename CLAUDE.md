# Notes for Claude

* Every new version gets an entry in `CHANGELOG.md`, newest first, with the version and date and the changes grouped under Added, Changed and Fixed
* Bump the version in `RedGuildForever.toc`, `Core.lua` and `README.md` together with the changelog entry
* Run `lua5.1 tests/run.lua` before every commit and build the zip with `./build.sh`
