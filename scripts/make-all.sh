#!/bin/sh

# make-all.sh: go into all of the submodules which are a part of the
#              index, build them, and put the resultant files in blib/
#              for use with perl -Mblib

[ -d blib ] && rm -rf blib
mkdir -p blib/lib blib/arch

git ls-files -c -m |
	while read x
	do
		[ -d $x/.git ] && (
			echo "Entering directory $x"
			cd $x
			[ -f Makefile ] || perl Makefile.PL
			make
			cp -r blib/* ../blib
		)
	done

