# SPDX-License-Identifier: Artistic-2.0
##===========================================================================
##  Class : Parameters
##
##  All parameters involved in execution.
##===========================================================================
use Regulatum::Type::Subsets;
use Regulatum::Type::Tile;
use Regulatum::Type::Tile_Distribution;
use Regulatum::Type::Verbosity;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
unit class Regulatum::Type::Parameters is export;



#----------------------------------------------------------------------------
#  Tile-coloring methods
#----------------------------------------------------------------------------
subset Coloring_Method of Str where <
  tiles
  random-colors
  random-assignment
  random-each-truncated
  random-each
>.one;

#----------------------------------------------------------------------------
#  Coloring methods for default color
#----------------------------------------------------------------------------
subset Default_Color_Selection of Str where <
  default
  random-tile
  random-colors
  random-each-truncated
  random-each
>.one;
#____________________________________________________________________________



#----------------------------------------------------------------------------
#  Dimensions
#
#  The dimensions of the space.  Each element is the size of (that is: the
#  number of units within) the corresponding dimension.
#
#  The ordering begins with the x axis.
#
#  Form:
#    [ x, y, z, ... ]
#----------------------------------------------------------------------------
has Dimension @.dimensions
  is required;

#----------------------------------------------------------------------------
#  Tiles
#
#  The available tiles.
#----------------------------------------------------------------------------
has Tile @.tiles
  is required;

#----------------------------------------------------------------------------
#  Distributions
#
#  The array of arrays representing the available Tiles and their
#  probabilities.  Each element is a Tile_Distribution.
#----------------------------------------------------------------------------
has Tile_Distribution @.distributions
  is required;

#----------------------------------------------------------------------------
#  Fit strategy
#
#  The agenda for obtaining a tile fit in an inning.  Contains an array of
#  one or more tactics progressively employed to find a fit.
#
#  Tactics are adopted from left to right; that is: the strategy begins
#  with the first element of the array and ends with the last.
#
#  A summary of available tactics follows.
#
#  --------------------------------------------------------------------------
#    Minimal satisfaction
#  --------------------------------------------------------------------------
#    1: Place a tile which is one unit in length in all dimensions
#       (irrespective of whether or not such a tile has been prescribed) in
#       order to fill the current cell.  Will always be successful.
#
#  --------------------------------------------------------------------------
#    Best existing match
#  --------------------------------------------------------------------------
#    2: Select the best-fitting tile from the tileset if possible.
#
#  --------------------------------------------------------------------------
#    Transformation (reduction)
#  --------------------------------------------------------------------------
#    Reduce the length of one or more dimensions of the proposed tile.  The
#    reduction should be minimal; that is: both the reduction in length and
#    the number of dimensions affected should be only that required to ensure
#    a fit.
#
#    3: (Restricted by available tiles.)  Will succeed only if a tile with
#       the necessary dimensions has been defined.
#
#    4: (Not restricted by available tiles.)  If a tile with the necessary
#       dimensions has been defined then it will be used; otherwise generate
#       a tile ad-hoc to the necessary specifications.
#
#  --------------------------------------------------------------------------
#    Rotation (reorientation)
#  --------------------------------------------------------------------------
#    Determine if a different orientation of the proposed tile will satisfy
#    the placement conditions.
#
#    5: (Restricted by available tiles.)  Will succeed only if a tile with
#       the necessary dimensions has been defined.
#
#    6: (Not restricted by available tiles.)  If a tile with the necessary
#       assignments of lengths to dimensions has been defined then it will be
#       used; otherwise generate a tile ad-hoc to the necessary
#       specifications.  If more than one tile satisfies the requirements
#       (something only possible in spaces with more than two dimensions)
#       then the first matching tile will be used.
#----------------------------------------------------------------------------
has Fit_Tactic @.fit_strategy
  = ();

#----------------------------------------------------------------------------
#  Spacing ratio
#
#  The proportion of intertile space to the tile width and height.  This
#  value is n in the ratio n:1 (or 1/n).
#----------------------------------------------------------------------------
has Spacing_Ratio $.spacing_ratio
  = 16;

#----------------------------------------------------------------------------
#  Default tile color
#
#  An SVG-compatible representation of the default color to be used for all
#  tiles in the absence of tile-specific color definitions or rules.
#
#  Potential application of this value depends on the coloring method.
#
#  Will be used for 1-unit tiles if no such tile is defined for some
#  dimension and the fit strategy calls for one.
#----------------------------------------------------------------------------
has Color $.tile_color_default
  = '#000';

#----------------------------------------------------------------------------
#  Coloring method
#
#  The method used in coloring defined tiles.
#
#  (Does not govern the application of tile_color_default.  That will be
#  applied according to default_color_selection if and where necessary.)
#
#  tiles
#    Use colors defined for each tile.
#  random-colors
#    Randomly select a color from the colors attribute for each tile upon
#    placement.  Requires that the colors attribute has been populated
#    with at least one color.
#  random-assignment
#    Randomly assign a distinct color to each tile in the set of defined
#    tiles.  Then proceed per the "tiles" method.  Uses the smaller space of
#    colors represented by the three-character format of Web colors.
#  random-each
#    Randomly select a color (not necessarily distinct) for each tile upon
#    placement.  Uses the full, six-character space of Web colors.
#  random-each-truncated
#    Randomly select a color (not necessarily distinct) for each tile upon
#    placement.  Uses the smaller space of colors represented by the
#    three-character format of Web colors.
#----------------------------------------------------------------------------
has Coloring_Method $.coloring_method
  = 'tiles';

#----------------------------------------------------------------------------
#  Default color selection
#
#  The method used in selecting a color for tiles when the coloring method is
#  "tiles" or "random-assignment" and a default color is necessary.
#
#  default
#    Use the color defined in tile_color_default.
#  random-tile
#    Randomly select a color from the existing tiles for each tile upon
#    placement.  Requires the use of the "tiles" or the "random-assignment"
#    method for coloring_method.
#  random-colors
#    Randomly select a color from the colors attribute for each tile upon
#    placement.  Requires that the colors attribute has been populated
#    with at least one color.
#  random-each
#    Randomly select a color (not necessarily distinct across all instances
#    of default tiles) upon placement.  Uses the full, six-character space of
#    Web colors.
#  random-each-truncated
#    Randomly select a color (not necessarily distinct across all instances
#    of default tiles) upon placement.  Uses the smaller space of colors
#    represented by the three-character format of Web colors.
#----------------------------------------------------------------------------
has Default_Color_Selection $.default_color_selection
  = 'default';

#----------------------------------------------------------------------------
#  colors
#
#  A set of available colors for selected coloring methods
#----------------------------------------------------------------------------
has %.colors
  is Set;

#----------------------------------------------------------------------------
#  fh-out
#
#  Filehandle for output
#----------------------------------------------------------------------------
has IO::Handle $.fh-out
  = $*OUT;

#----------------------------------------------------------------------------
#  Verbosity
#----------------------------------------------------------------------------
has Verbosity $.verbosity
  is rw
  = Verbosity.new(:as_comment(True));
#____________________________________________________________________________




## EOF
