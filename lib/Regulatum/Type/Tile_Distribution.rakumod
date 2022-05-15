# SPDX-License-Identifier: Artistic-2.0
##===========================================================================
##  Class : Tile_Distribution
##
##  Represents the probabilities of available tile types.
##
##  (Note that a Distribution class already exists in Raku.)
##===========================================================================
use Regulatum::Type::Subsets;
use Regulatum::Type::Tile;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
unit class Regulatum::Type::Tile_Distribution is export;



#----------------------------------------------------------------------------
#  tile
#
#  The Tile associated with the percentile range.
#----------------------------------------------------------------------------
has Tile $.tile
  is required;

#----------------------------------------------------------------------------
#  percentile
#
#  The upper bound of the percentile range for this Tile.
#  When sorted by this value an array of Tiles will provide a means to select
#  a consitutent by a supplied target value.
#----------------------------------------------------------------------------
has Int_N $.percentile
  is required;
#____________________________________________________________________________



## EOF
