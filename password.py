#!/bin/python

import sys

from IPython.lib import passwd

def createPassword (var):
	p = passwd(var)
	print "%s" % p
	return p

if __name__ in '__main__':
	createPassword(sys.argv[1])
