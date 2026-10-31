# Loads Halo's MediaRemote helper library inside /usr/bin/perl, which macOS allows to read
# now playing information, and runs it. See MediaRemoteHelper.m.
use strict;
use warnings;
use DynaLoader;

my $path = shift @ARGV or die "usage: media-remote.pl <path to MediaRemoteHelper>\n";
my $library = DynaLoader::dl_load_file($path, 0) or die DynaLoader::dl_error();
my $symbol = DynaLoader::dl_find_symbol($library, "HaloMediaRemoteRun") or die DynaLoader::dl_error();
my $run = DynaLoader::dl_install_xsub("main::halo_media_remote_run", $symbol);
&$run();
