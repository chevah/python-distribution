Distribution tests
------------------

A simple script is used for checking that a Python instance has the required
modules to be used by the Chevah project.


Triggering remote builds
------------------------

Chevah project has a set of buildslaves which are used to build the
distribution on each supported platform.

To trigger a build you need access the the VPN.

To list all available builders use::

    ./venv.sh buildbot_list

To trigger a specific builder use::

    ./venv.sh buildbot_try -b python-distribution-raspbian-7

You can also trigger multiple builders from the same command::

    ./venv.sh buildbot_try -b python-distribution-raspbian-7 \
        python-distribution-solaris-10-sparc
