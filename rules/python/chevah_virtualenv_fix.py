#
# Simple script to fix path for a newly relocated virtualenv.
#
import os
import sys


def main():
    _fix_interpretor_path('pip')


def _fix_interpretor_path(script_name):
    """
    Fix the interpertor path for `script_name`.
    """
    scripts_dir = os.path.dirname(sys.executable)
    script_path = os.path.join(scripts_dir, script_name)

    with open(script_path, 'r') as pip_file:
        lines = pip_file.readlines()
        lines[0] = '#!%s' % (sys.executable,)

    with open(script_path, 'w') as pip_file:
        pip_file.write(''.join(lines))

if __name__ == '__main__':
    main()
