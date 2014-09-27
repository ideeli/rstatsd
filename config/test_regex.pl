#!/usr/bin/perl

# example:
# perl test_regex.pl "Charlie has 9 girls in 12 cities" "Charlie\s+has\s+(?<girls>\d+)\s+girls\s+in\s+(?<cities>\d+)\s+cities"
#
# Should return:
# girls: 9
# cities: 12

# Parse command line arguments
$input_string = $ARGV[0];
$input_regexp = $ARGV[1];

# Perform regexp matching
$input_string =~ m/($input_regexp)/;

# Print the resulting groups and values
while (($key, $value) = each(%+)){
     print $key.": ".$value."\n";
}

