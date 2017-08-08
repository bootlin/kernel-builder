# Kernel builder

This project works in two steps: first launch `./update-source-tarball.sh` to
prepare the tarballs of the sources to be built, then run `./build.py` to build
all the available tarballs.

## Adding a new tree/branch

First add the combination to the `update-source-tarball.sh` script, so that the
right sources get prepared.

Then add them to the `config.py` so that they can actually be built.

**WARNING**: Be careful with that file: since the sources are stored on a
filesystem, the '/' character is not allowed like in git branches names. Thus,
simply replace all '/' by '\_' in the `config.py` file, since it's what
`update-source-tarball.sh` does.
