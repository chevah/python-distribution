python-distribution
===================

This code is here to generate a portable CPython distribution on all the
platforms supported by the Chevah project... and not only.

It is designed to be used by the Chevah Buildbot to automatically
generate and publish the binary python distribution.

Here are the steps used by Buildbot:

* Login on the new platform
* Get code from git
* ./chevah_build.sh build
* ./chevah_build.sh test
* upload to binary dist publishing website.

The resulted distribution should be installed and used with the help of the
`venv.sh` script.


Versioning
----------

The python distribution is named as:

* For public releases python-OSNAMEVER-ARCH-UPSTREAMVER+DOWNVER
* For testing and pre-releases python-OSNAMEVER-ARCH-UPSTREAMVER-PREVER

Where:

* OSNAMEVER look like linux, ubuntu1404, osx108, aix53, hpux1131
* ARCH look like x86, x64, ppc, ppc64le, s390x
* UPSTREAMVER is the exact Python upstream version like 2.7.8 or 2.7.10
* DOWNVER is the build maker for this specific distribution like chevah1 or
  chevah2
* PREVER is a marker to signal that the version should not be used for
  production. It can look like: test1 adir3


Distribution tests
------------------

A simple script is used for checking that a Python instance has the required
modules to be used by the Chevah project.
