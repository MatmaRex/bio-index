#!/usr/bin/env bash
# Update the on-wiki data from dump. Pass dump date as first parameter.

rm plwiki-*-pages-meta-current.xml.bz2
rm savepoint-*

wget https://dumps.wikimedia.org/plwiki/$1/plwiki-$1-pages-meta-current.xml.bz2

sed -i "s/dump_filename = 'plwiki-[0-9]*/dump_filename = 'plwiki-"$1"/" build-index.rb

ruby build-index.rb
