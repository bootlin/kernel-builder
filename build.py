#!/usr/bin/env python3
# -*- coding:utf-8 -*
#

import argparse
import os
import shutil
import fnmatch
import tempfile
import subprocess

ROOT_DIR = os.path.dirname(os.path.realpath(__file__))
WORKSPACE = os.path.join(ROOT_DIR, "workspace")
STORAGE = os.path.join(ROOT_DIR, "storage")
SOURCES = os.path.join(STORAGE, "sources")
CROSS_COMPILERS = {
    "arm": "arm-linux-gnueabihf-",
    "arm64": "aarch64-linux-gnu-",
    "mips": "mips-linux-gnu-",
    "i386": None,
    "x86": None,
    "x86_64": None,
}

parser = argparse.ArgumentParser(description='Build Kernels')
parser.add_argument('-d', help='Path to the defconfig to build '\
        '(must be a direct child of its arch folder)', metavar='PATH',
        required=True)
parser.add_argument('--verbose', '-v', action='store_true', help='Verbose mode')
kwargs = vars(parser.parse_args())

# Set number of make threads to number of local processors + 2
if os.path.exists('/proc/cpuinfo'):
    output = subprocess.check_output('grep -c processor /proc/cpuinfo',
                                     shell=True)
    make_threads = int(output) + 2
else:
    make_threads = 1

defconfig_full = os.path.abspath(kwargs['d'])
arch, defconfig = os.path.split(defconfig_full)
arch = os.path.basename(arch)
cross_compile = CROSS_COMPILERS[arch]
print("defconfig: ", defconfig)
print("arch: ", arch)
print("cross_compile: ", cross_compile)

# Default umask for file creation
os.umask(0o22)

def build_kernel(source_dir):
    tree, branch = os.path.split(os.path.abspath(source_dir))
    tree = os.path.basename(tree)
    sources = os.path.join(source_dir, "linux-src.tar.gz")
    print("  tree: %s, branch: %s" % (tree, branch))
    with open(os.path.join(source_dir, "last.git_describe")) as f:
        git_describe = f.read().strip()

    # BUILD_OUTPUT
    kbuild_output = os.path.join(WORKSPACE, "build")
    build_dir = os.path.join(WORKSPACE, "tmp")
    kconfig_file = os.path.join(kbuild_output, ".config")
    print("  building in %s" % kbuild_output)
    if not os.path.exists(build_dir):
        os.makedirs(build_dir)
    if not os.path.exists(kbuild_output):
        os.makedirs(kbuild_output)
    os.chdir(build_dir)

    def do_make(target=None, log=False):
        make_args = ''
        make_args += "-j%d -k " % make_threads
        if not kwargs['verbose']:
            make_args += "-s "
        make_args += "ARCH=%s " % arch
        if cross_compile:
            make_args += "CROSS_COMPILE=%s " % cross_compile
        if kbuild_output:
            make_args += "O=%s " % kbuild_output
        if target:
            make_args += target
        make_cmd = 'make %s' % make_args
        if target == "oldconfig":
            make_cmd = 'yes "" |' + make_cmd
        print(make_cmd)

        make_stdout = None
        if log:
            build_log_f.write("#\n# " + make_cmd + "\n#\n")
            build_log_f.flush()
            make_stdout = build_log_f
        p1 = subprocess.Popen(make_cmd , shell=True,
                              stdout=make_stdout,
                              stderr=subprocess.STDOUT,
        )
        p1.communicate()
        return p1.wait()

    if subprocess.call('tar xvf %s' % sources, shell=True,
            stdout=subprocess.DEVNULL, stderr=None):
        print("  Error extracting %s" % sources)
        print("  Not going further")
        return

    build_log = os.path.join(kbuild_output, "build.log")
    build_log_f = open(build_log, 'w')
    shutil.copy(defconfig_full, kconfig_file)
    do_make("olddefconfig", log=True)

    # Build the kernel
    result = do_make(log=True)

    # Build the modules
    modules = None
    if result == 0:
        modules = not subprocess.call('grep -cq CONFIG_MODULES=y %s' %
                kconfig_file, shell=True)
        if modules:
            result |= do_make('modules', log=True)
    # do_make("modules", log=True)
    build_log_f.close()

    # Build is done, install everything
    install_path = os.path.join(STORAGE, "builds", tree, branch, git_describe,
            arch, defconfig)
    if not os.path.exists(install_path):
        os.makedirs(install_path)
    system_map = os.path.join(kbuild_output, "System.map")

    shutil.copy(kconfig_file, os.path.join(install_path, "kernel.config"))
    shutil.copy(build_log, install_path)

    if os.path.exists(system_map):
        shutil.copy(system_map, install_path)

    boot_dir = os.path.join(kbuild_output, "arch", arch, "boot")

    # Patterns for matching kernel images by architecture
    if arch == 'arm':
        patterns = ['zImage', 'xipImage']
    elif arch == 'arm64':
        patterns = ['Image']
    # TODO: Fix this assumption. ARCH != ARM* == x86
    else:
        patterns = ['bzImage']

    kimages = []
    for pattern in patterns:
        for root, dirnames, filenames in os.walk(boot_dir):
            for filename in fnmatch.filter(filenames, pattern):
                kimages.append(os.path.join(root, filename))
                shutil.copy(os.path.join(root, filename), install_path)
    for root, dirnames, filenames in os.walk(os.path.join(boot_dir, 'dts')):
        for filename in fnmatch.filter(filenames, '*.dtb'):
            # Found a dtb
            dtb = os.path.join(root, filename)
            dtb_dest = os.path.join(install_path, 'dtbs')
            # Check if the dtb exists in a subdirectory
            if root.split(os.path.sep)[-1] != 'dts':
                dest = os.path.join(install_path, 'dtbs',
                                        root.split(os.path.sep)[-1])
            else:
                dest = os.path.join(install_path, 'dtbs')
            if not os.path.exists(dest):
                os.makedirs(dest)
            # Copy the dtb
            shutil.copy(dtb, dest)

    if modules:
        tmp_mod_dir = tempfile.mkdtemp()
        os.environ['INSTALL_MOD_PATH'] = tmp_mod_dir
        os.environ['INSTALL_MOD_STRIP'] = "1"
        os.environ['STRIP'] = "%sstrip" % cross_compile
        do_make('modules_install')
        modules_tarball = "modules.tar.xz"
        cmd = "(cd %s; tar -Jcf %s lib/modules)" % (tmp_mod_dir, modules_tarball)
        subprocess.call(cmd, shell=True)
        shutil.copy(os.path.join(tmp_mod_dir, modules_tarball), install_path)
        shutil.rmtree(tmp_mod_dir)

    # Return to main folder and clean temp files
    os.chdir(ROOT_DIR)
    print("  Cleaning up %s" % kbuild_output)
    # shutil.rmtree(kbuild_output)
    print("  Cleaning up %s" % build_dir)
    # shutil.rmtree(build_dir)

for root, dirs, files in os.walk(SOURCES):
    if 'linux-src.tar.gz' in files:
        print("Building %s" % root)
        build_kernel(root)

