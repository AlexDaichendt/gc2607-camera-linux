# Private HAL Assets

The best-quality GC2607 path requires AIQB/graph files recovered from the Windows driver payload.
They are intentionally not committed to this repo.

Put these files in:

```sh
assets/private/
```

Expected filenames:

```text
gc2607_gc2607_MTL.aiqb
graph_settings_gc2607_gc2607_MTL.xml
graph_descriptor.xml
```

Checksums from the working host on 2026-06-20:

```text
83c5aee68ba151eded1f54301093bad99f52f9086fd130f2e30d836ccebb4ccd  gc2607_gc2607_MTL.aiqb
e72f1809e92fe043d7abbc7e7ada5f6450b7efc315f4e4dca16e824538a0c180  graph_settings_gc2607_gc2607_MTL.xml
c028c39f321f47d70ab1499828b2f1511f3bef6d84a729965965d0abebe26e80  graph_descriptor.xml
```

Install them into a HAL checkout with:

```sh
scripts/install-private-hal-assets.sh ~/repos/ipu6-camera-hal-gc2607 assets/private
```

Redistribution status is unknown. Treat these files as local-only unless their license is clarified.
