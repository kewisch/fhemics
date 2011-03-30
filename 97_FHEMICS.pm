package main;
# ***** BEGIN LICENSE BLOCK *****
# Version: MPL 1.1/GPL 2.0/LGPL 2.1
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
# http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.
#
# The Original Code is FHEMICS code.
#
# The Initial Developer of the Original Code is
#   Philipp Kewisch <fhem@kewis.ch>
# Portions created by the Initial Developer are Copyright (C) 2011
# the Initial Developer. All Rights Reserved.
#
# Contributor(s):
#
# Alternatively, the contents of this file may be used under the terms of
# either the GNU General Public License Version 2 or later (the "GPL"), or
# the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
# in which case the provisions of the GPL or the LGPL are applicable instead
# of those above. If you wish to allow use of your version of this file only
# under the terms of either the GPL or the LGPL, and not to allow others to
# use your version of this file under the terms of the MPL, indicate your
# decision by deleting the provisions above and replace them with the notice
# and other provisions required by the GPL or the LGPL. If you do not delete
# the provisions above, a recipient may use your version of this file under
# the terms of any one of the MPL, the GPL or the LGPL.
#
# ***** END LICENSE BLOCK *****

use strict;
use warnings;

# Welcome to FHEMICS 0.1.
# This module will allow you to show certain information of the FHEM system in
# rfc5545/ics format.
#
# If you haven't used the auto mode of your FHT, the times may not have been
# reported. You can fix this by going through each day's values with the control
# unit. Remember that changing times may take a while to propagate due to the 1%
# bandwidth use regulation, so you won't be able to see changes right away.
#
# Usage:
#
# Default to http://host/fhem/fhem.ics for all devices:
#   define ICS FHEMICS
#
# Use a different URL, i.e http://host/fhem/calendar.ics:
#   define ICS FHEMICS /calendar.ics
#
# Define an instance only for certain devices (comma separated):
#   define ICS FHEMICS
#   attr ICS devspec FHT_1234,FHT_4321
#
# Planned features/Known issues:
#  * Write support to modify heating times
#  * Support for showing information for other sensor types
#  * Make ICS output more robust
#
# Please report bugs at: https://github.com/kewisch/fhemics/issues

sub
FHEMICS_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}   = "FICS_Define";
  $hash->{UndefFn} = "FICS_Undef";
  $hash->{GetFn}  = "FICS_Get";

  $hash->{AttrList} = "devspec";
}

sub
FICS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  # Check parameters, we have one optional parameter
  return "wrong syntax: define <name> FHEMICS [<path>]"
    if (int(@a) < 2 || int(@a) > 3);

  # Set up the path, this can be left out if no devspec is specified
  my $path = $a[2] || "/fhem.ics";
  $hash->{PATH} = $path;

  # Add a FHEMWEB extension to output the .ics file
  $data{FWEXT}{$path}{FUNC} = sub($) {
    return ("text/calendar", FICS_CreateICS($hash));
  };

  $hash->{STATE} = "Initialized at $path";

  return undef;
}

sub
FICS_Undef($$)
{
  my ($hash, $arg) = @_;
  my $path = $hash->{PATH};

  # Remove the FHEMWEB extension
  delete($data{FWEXT}{$path});

  return undef;
}

sub
FICS_Get($)
{
  my ($hash, @a) = @_;

  # If the user would like to see the .ics file via console return it via getter
  return FICS_CreateICS($hash);
}

sub
FICS_CreateICS($)
{
  # The CreateICS function takes the name of the FHEMICS module as a parameter
  my ($moduleName) = @_;

  # Put together the .ics stream, we'll keep it simple for now
  my $devspec = AttrVal($moduleName, "devspec", "");
  my $ics = "BEGIN:VCALENDAR";
  for my $d (keys %defs) {
    my $name = $defs{$d}{NAME};
    my $type = $defs{$d}{TYPE};

    # Skip if we should ignore the device
    next if ($devspec && $devspec !~ /(^|,)$name(,|$)/);

    # We currently only support FHT devices
    if ($type eq "FHT") {
      my $room = AttrVal($name, "room", "");

      # Create an Event for each weekday, ...
      my @wkdays = ("mon", "tue", "wed", "thu", "fri", "sat", "sun");

      foreach my $offset (0..$#wkdays) {
        my $wkday = $wkdays[$offset];

        # ... and for each period (FHT supports 2) of this weekday
        foreach my $period (1..2) {
          my $from = ReadingsVal($name, "$wkday-from$period", "24:00");
          my $to = ReadingsVal($name, "$wkday-to$period", "24:00");

          # Strip colon between time so we can output the date in .ics format
          $from =~ s/://;
          $to =~ s/://;

          # If the times match, then this interval is disabled
          if ($from ne $to) {
            # The historic date 2011-04-04 was a monday. We want the date to start
            # on the correct day, so add a weekday offset to the day
            my $daynum = 4 + $offset;

            # Put together the event
            # TODO escaping, line wrapping, etc.
            $ics .= "\n" . join("\n",
              ("BEGIN:VEVENT",
               "UID:fhem-$name-$wkday-$period",
               "DTSTART:" . sprintf("%04d%02d%02dT%04d00", 2011, 4, $daynum, $from),
               "DTEND:" . sprintf("%04d%02d%02dT%04d00", 2011, 4, $daynum, $to),
               "SUMMARY:" . $name,
               "LOCATION:" . $room,
               "RRULE:FREQ=WEEKLY",
               "END:VEVENT")
            );
          }
        }
      }
    }
  }
  return $ics . "\nEND:VCALENDAR";
}

1;
