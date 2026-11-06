# Atlas Reign v0.25.1

This release snapshot contains the corresponding source for Atlas Reign, a Roblox strategy game derived from RoWorld and OpenFront. It includes the client, server, shared modules, build tools, asset inputs and copyright notices.

## Build

Install Rojo 7.7.0 and run this command from the repository root.

```sh
rojo build release.project.json -o Atlas-Reign.rbxlx
```

The release targets Atlas Reign's Roblox universe. A separate experience needs its own developer products and permission to use the required assets. The licensed Cute & Cozy UI sound effects are referenced by Roblox asset ID. Obtain your own licence and asset access to use those recordings in another experience.

The Roblox release includes this archive in `ServerStorage > AtlasReignSource`. To attach the archive to a rebuilt place, run `python tools/frontier/embed_source.py Atlas-Reign.rbxlx Frontier-v0.25.1-Corresponding-Source.zip Atlas-Reign-Distribution.rbxlx`.

## Licence

Atlas Reign's source is available under the GNU Affero General Public License v3 with the additional terms in [LICENSE](LICENSE). See [NOTICE](NOTICE.md) and the [asset audit](docs/ASSET-AUDIT.md) for credits and asset-specific licences. Atlas Reign is an independent modification of RoWorld and OpenFront.
