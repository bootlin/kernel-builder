# Kernel builder

This project works in two steps: 

  * First launch `./update-source-tarball.sh all` to prepare the tarballs of the
sources to be built.
  * Then run `./build.py -d path/to/defconfig` to build the white-listed
tarballs with the defconfig provided.

## Adding a new tree/branch

### Add the sources

First add the combination to the `update-source-tarball.sh` script, so that the
right sources get prepared.


### Allow the builds

Then add the `tree/branch` to the `WHITE_LIST` dictionary in `config.py` so that
they can actually be built with the defconfigs you choose.

**WARNING**: Be careful with that file: since the sources are stored on a
filesystem, the '/' character is not allowed like in git branches names. Thus,
simply replace all '/' by '\_' in the `config.py` file, since it's what
`update-source-tarball.sh` does.

## Adding a new config

Multiple choices:
  * You want a defconfig that is already existing in the kernel, simply `touch
defconfigs/<arch>/<defconfig>`, and the builder will go find the upstream
defconfig.
  * You want a defconfig that exists, but you just want to change a very few
options:
`touch defconfigs/<arch>/<defconfig>+CONFIG_MY_OPTION=y+CONFIG_OTHER_OPT=m`  
The builder will append the found options to the upstream defconfig.
  * You want an upstream defconfig, but want to add a whole fragment to it: put
your fragment in `defconfigs/<arch>/<defconfig>+myfragment`, and as `myfragment`
does not looks like a Kconfig option (starting with `CONFIG_`), nor an existing
defconfig, the builder will append the content of this file to the found
defconfig.
  * You want a completely custom defconfig: simply put it in
`defconfigs/<arch>/<my_defconfig_name>`. As `my_defconfig_name` does not exists
in the kernel, it will just behave as a fragment, and be set in the used
`.config` file.

## Credits

This kernel builder is mostly borrowed from [KernelCI](https://kernelci.org/)'s
[builder](https://github.com/kernelci/kernelci-build). Thanks for their work!
