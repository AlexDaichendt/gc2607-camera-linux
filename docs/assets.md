# Included HAL Assets

This repo includes the GC2607 AIQB and graph XML files used by the IPU6 HAL pipeline.

Included files:

```text
assets/hal/gc2607_gc2607_MTL.aiqb
assets/hal/graph_settings_gc2607_gc2607_MTL.xml
assets/hal/graph_descriptor.xml
```

Checksums:

```text
83c5aee68ba151eded1f54301093bad99f52f9086fd130f2e30d836ccebb4ccd  assets/hal/gc2607_gc2607_MTL.aiqb
e72f1809e92fe043d7abbc7e7ada5f6450b7efc315f4e4dca16e824538a0c180  assets/hal/graph_settings_gc2607_gc2607_MTL.xml
c028c39f321f47d70ab1499828b2f1511f3bef6d84a729965965d0abebe26e80  assets/hal/graph_descriptor.xml
```

Install them into a HAL checkout with:

```sh
scripts/install-hal-assets.sh /path/to/ipu6-camera-hal
```

These assets came from the Windows driver payload used during bring-up. Verify redistribution terms
before publishing this repo publicly.
