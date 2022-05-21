# SPDX-License-Identifier: Artistic-2.0
##===========================================================================
##
##  Regulatum
##
##  Rectilinear tiling
##
##===========================================================================
use v6;
#----------------------------------------------------------------------------
use Regulatum::Service::Colors;
use Regulatum::Service::SVG;
use Regulatum::Type::Parameters;
use Regulatum::Type::Subsets;
use Regulatum::Type::Tile;
use Regulatum::Type::Tile_Distribution;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
unit module Regulatum:ver<0.4.0>:api<1>;



#============================================================================
#  generate
#
#  Main process for generating the tilespace
#----------------------------------------------------------------------------
sub generate(Parameters $parameters --> Int_N) is export
{
  #  Set an origin position (0) for each dimension
  my Position @positions = $parameters.dimensions.map({ 0 });

  #  The maximum dimensional index of the space
  my Index $maximum_dim = @positions - 1;

  #  Tracks spaces of the domain which may affect the current inning
  my List @occupied_spaces;

  #  Total number of tiles laid
  my Int_N $tiles-total = 0;

  #--------------------------------------------------------------------------
  #  Loop through all cells in the space
  #--------------------------------------------------------------------------
  repeat while step($parameters.dimensions, @positions)
  {
    #------------------------------------------------------------------------
    #  Determine if the current position is available.
    #
    #  Also check for obsolete occupied spaces along the way.
    #------------------------------------------------------------------------
    #  Indices of @occupied_spaces: representing spaces which can be excised
    my Index @obsolete_spaces;

    #  Whether or not to skip the current position (because it is already
    #  occupied)
    my Bool $is_occupied = False;

    #------------------------------------------------------------------------
    #  Examine occupied spaces
    #------------------------------------------------------------------------
    for @occupied_spaces.kv -> Index $space_index, @occupied_space
    {
      #  Count of intersections at the current position
      my Int_N $position_conflict_count = 0;

      #  The count of obsolete points in order to check for condition 2 below
      my Int_N $obsolete_point_count = 0;

      #  Track the status of the current position (see conditions below)
      my Bool $largest_dim_equal = False;

      #----------------------------------------------------------------------
      #  Examine each point in the space.  We work from the largest dimension
      #  to the smallest; the order shouldn't matter for the intersection
      #  checks.
      #----------------------------------------------------------------------
      for $maximum_dim...0 -> Index $dim
      {
        my List $occupied_range = @occupied_space[$dim];

        #--------------------------------------------------------------------
        #  First determine whether or not this occupied space is obsolete/out
        #  of range (that is: if tiles laid at our current position or beyond
        #  can no longer intersect with it).  We naturally wish to remove
        #  those from the collection of spaces.
        #
        #  We can excise an occupied space if one of the following conditions
        #  obtains:
        #
        #    1. The ending position value of the largest dimension of the
        #       space is less than the value of the largest current position.
        #    2. (1) The ending position value of the largest dimension of the
        #       space is equal to the value of the largest current position
        #       and (2) the ending position values of all of the lower
        #       dimensions of the space are less than the respective values
        #       of the current position.
        #--------------------------------------------------------------------
        if $occupied_range[1] <= @positions[$dim]
        {
          #  If examining the largest dimension
          if $dim == $maximum_dim
          {
            #  Condition 1 above has been satisfied; no need to check for
            #  intersections
            (push @obsolete_spaces, $space_index) && last
            if $occupied_range[1] < @positions[$dim];

            #  The maximum range is equal to the current position
            $largest_dim_equal = True;
          }
          #  Examining a lower dimension
          else
          {
            #  One dimension toward condition 2 above has been satisfied
            ++$obsolete_point_count if $occupied_range[1] < @positions[$dim];

            #  Condition 2 above has been fully satisfied
            (push @obsolete_spaces, $space_index) && last
            if $largest_dim_equal && $obsolete_point_count == $maximum_dim;
          }
        }

        #--------------------------------------------------------------------
        #  Determine if there is an intersection at the current position for
        #  this dimension
        #--------------------------------------------------------------------
        ++$position_conflict_count
        if   @positions[$dim] <= $occupied_range[1]
          && @positions[$dim] >= $occupied_range[0];
      }
      #______________________________________________________________________

      #  Prepare to advance if the current position is occupied
      if $position_conflict_count == @positions
      {
        ++@positions[0];
        $is_occupied = True;
        last;
      }
    }
    #________________________________________________________________________

    #  But before proceeding: remove inactive spaces from active list
    @occupied_spaces.splice(@obsolete_spaces.reverse.all, 1);

    #  Skip the current position if necessary
    next if $is_occupied;

    #------------------------------------------------------------------------
    #  Propose a tile for placement
    #------------------------------------------------------------------------
    my Tile $tile = propose_tile($parameters.distributions);

    #  If no tile proposed then simply advance
    if !$tile
    {
      ++@positions[0];
      next;
    }

    #  Attempt to obtain a fit for the tile (can ignore any end positions returned)
    ($tile, $) = fit_tile(
      $parameters.dimensions,
      $parameters.tiles,
      $parameters.fit_strategy,
      @positions,
      @occupied_spaces,
      $tile
    );

    #------------------------------------------------------------------------
    #  Act on proposed tile
    #------------------------------------------------------------------------
    #  If a tile has been accepted
    if $tile
    {
      #  Determine the color
      my Color $tile_color = select_tile_color(
        $parameters.coloring_method,
        $parameters.default_color_selection,
        $parameters.tile_color_default,
        $parameters.colors,
        $parameters.tiles,
        $tile
      );

      #  Write tile to output
      write_output(
        $parameters.fh-out,
        generate_tile_element($parameters.spacing_ratio, @positions, $tile, $tile_color)
      );

      #  Increment count of tiles laid
      ++$tiles-total;

      #  Update (if not a 0-unit tile) the data structure tracking tiles
      #  which may influence the current inning or future innings.
      push @occupied_spaces,
        #  Contribute list of min, max pairs for each dimension to @occupied_spaces
        (@positions.List Z (@positions.List Z+ ($tile.extensions.List))).List
      if $tile.extensions.all != 0;

      #  Advance (beyond latest tile)
      @positions[0] += $tile.extensions[0] + 1;
    }
    #  The tile has not been approved; advance to next cell
    else
    {
      ++@positions[0];
    }
  }
  #__________________________________________________________________________


  return $tiles-total;
}
#____________________________________________________________________________



#============================================================================
#  step
#
#  Examine @positions counters et cetera.  This does one of the following:
#
#    1. Makes no changes to @positions (because none of its wheels needs to
#       turn).
#    2. Produces a new, valid @positions with properly-incremented values.
#    3. Halts all processing of this function (because all wheels of
#       @positions have now reached their maxima and no further action should
#       be taken).
#
#  (Does not increment the motile base dimension (x); that is done after
#  fully processing the inning.  This step merely increments one or more of
#  the other dimension position values if the recently-incremented, incoming
#  x value is at its maximum.)
#----------------------------------------------------------------------------
#|TYPE| Ints actually Dimension, Position
sub step(Int @dimensions, Int @positions --> Bool)
{
  for ^@positions -> Index $dim
  {
    #  If this dimension's wheel is at its maximum
    if @positions[$dim] == @dimensions[$dim]
    {
      #  Reset the position of the dimension
      @positions[$dim] = 0;

      #  If a higher-dimensional wheel exists then increment it and continue
      if $dim + 1 < @positions
      {
        ++@positions[$dim + 1];
        next;
      }

      #  Otherwise we've reached the maxima of all wheels; stop all processing
      #  Due to closures @positions is updated in the outer scope as well.  Hm.
      return False;
    }
  }

  return True;
}
#____________________________________________________________________________



#============================================================================
#  propose_tile
#
#  Choose a tile from the available set.
#----------------------------------------------------------------------------
sub propose_tile(Tile_Distribution @distributions --> Tile)
{
  #  Determine random percentile value
  my Int $percentile = (rand * 100).Int;

  #  Match appropriate tile type by comparing random value to tile percentages
  for @distributions -> $distribution
  {
    return $distribution.tile if $percentile <= $distribution.percentile;
  }

  #  No tile identified.  (May happen if supplied distribution percentages
  #  total < 100.)
  return Nil;
}
#____________________________________________________________________________



#============================================================================
#  produce_minimal_tile
#
#  Locate or create a tile which possesses an extension of 0 units in all
#  dimensions.
#----------------------------------------------------------------------------
#|TYPE| Int actually Dimension
sub produce_minimal_tile(Int @dimensions, Tile @tiles --> Tile)
{
  #  Locate and return any defined 0-unit tile
  for @tiles -> $tile
  {
    return $tile if so $tile.extensions.all == 0;
  }

  #  Return an ad-hoc 0-unit tile
  return Tile.new(extensions => @dimensions.map({ 0 }));
}
#____________________________________________________________________________



#============================================================================
#  fit_tile
#
#  Attempt to obtain a fit for the provided tile.
#
#  Upon an initial call we expect to be in a currently-unoccupied cell
#  holding a proposed tile.
#
#  Determine whether any cells to be occupied by the proposed tile are
#  blocked or not.  There is an intersection if the below condition for
#  possibly-overlapping cubes A and B (where "cube" is an object of any
#  dimensionality) must simultaneously be true for all dimensions in
#  d = {x, y, z, ...}.
#
#      (A.maximum_d > B.minimum_d) AND (A.minimum_d < B.maximum_d)
#----------------------------------------------------------------------------
sub fit_tile
(
  Int  @dimensions,      #|TYPE| Int actually Dimension
  Tile @tiles,
  Int  @fit_strategy,    #|TYPE| Int actually Fit_Tactic
  Int  @positions,       #|TYPE| Int actually Position
  List @occupied_spaces,
  Tile $tile
  #  Return form: (tile, @end_positions)
  --> List
)
{
  #  The ending positions of the proposed tile permitted by current
  #  conditions.
  #    . After initial processing this shall contain only the complete
  #      results of comparisons in all dimensions.  A non-Nil value for any
  #      dimension represented in this array therefore indicates a known
  #      limit in that dimension.
  #    . Later we fill in any Nil values with the maximum extensions of the
  #      tile itself to ultimately obtain the tile space both available and
  #      necessary.
  my Position @end_positions = Nil xx @dimensions.elems;

  #  Accept the proposed tile if it will occupy one cell only
  return ($tile, @end_positions) if so $tile.extensions.all == 0;

  #  Determine expected positions (in format (min, max)) for each dimension
  #  of the proposed tile.  (May result in positions which overlap other
  #  tiles or fall outside of the dimensional space.)
#|FIX| For some reason the same calculation in &generate returns a Seq
#|FIX| unless you manually cast the result to List.
  my List @tile_space = @positions.List Z (@positions.List Z+ ($tile.extensions.List));

  #--------------------------------------------------------------------------
  #  Search for overlaps (intersection in all dimensions) of the proposed
  #  tile with occupied spaces.
  #
  #  Proceed comprehensively.  That is: check for intersections with all
  #  still-relevant occupied spaces and thereby determine the largest space
  #  given all restrictions imposed by occupied spaces.  Then apply any fit
  #  strategy.
  #
  #  We also prune the set of occupied spaces regularly as they may
  #  not extend into the present coordinates of activity.
  #--------------------------------------------------------------------------
  for @occupied_spaces -> @occupied_space
  {
    #  Boundary positions for this occupied space relative to the proposed tile
    my Position @tile_boundaries = Nil xx @dimensions.elems;

    #  Count of total number of dimensional intersections found
    my Int_N $intersection_count = 0;

    #------------------------------------------------------------------------
    #  Examine each dimension of the occupied space
    #------------------------------------------------------------------------
    #|TYPE| List actually List[Position]
    for @occupied_space.kv -> Index $dim, List $occupied_range
    {
      #  Determine the boundaries of the tile per the limitations of this
      #  occupied space
      #
      #  Determine if an intersection in this dimension exists
      if   @tile_space[$dim][0] <= $occupied_range[1]
        && @tile_space[$dim][1] >= $occupied_range[0]
      {
        ++$intersection_count;

        #  Treat the minimum position of the limiting point as a boundary
        @tile_boundaries[$dim] = ($occupied_range[0] - 1)
        #  if (since a tile may always expand freely into the maximum
        #  dimension) we are inspecting a dimension other than the maximum
        if $dim < (@dimensions - 1)
          #  and the overlap lies ahead of the tile's origin position
          && @tile_space[$dim][0] < $occupied_range[0];
      }
    }
    #________________________________________________________________________


    #  Populate (or replace with more restrictive values) ending positions if
    #  overlap is found.
    #
    #  (Even if so we actually do not want to immediately proceed since
    #  multiple occupied spaces may be obstacles for this tile and we need to
    #  consider all of them in order to determine the full set of dimensional
    #  restrictions.)
    @end_positions = @end_positions.kv.map(-> Index $dim, Position $position
    {
      (
        #  If the current ending position is not defined
        ($position ~~ Int:U)
        #  or the latest boundary position is closer than the current ending position
        || ((@tile_boundaries[$dim] ~~ Int:D) && ($position > @tile_boundaries[$dim]))
      )
        #  Use the latest boundary value
        ?? (@tile_boundaries[$dim] // Nil)
        #  Retain the current ending position (which may be undefined)
        !! $position;
    #  If overlap is found
    }) if $intersection_count == @positions;
  }
  #__________________________________________________________________________


  #--------------------------------------------------------------------------
  #  Determine whether or not the proposed tile will also not exceed any
  #  dimensional limit
  #--------------------------------------------------------------------------
  #  First collect the ending positions of the proposed tile
  my Position @end_positions_orig = @tile_space.map({ $_[1] });

  #  If any of the proposed positions exceeds a dimensional limit
  if so (@end_positions_orig Z>= @dimensions.List).any
  {
    for @dimensions.kv -> Index $dim, Dimension $size
    {
      #  If there is no known limit (as no intersection was found earlier)
      #  but this position does exceed the respective dimensional limit then
      #  use said limit to assign the appropriate ending position.
      @end_positions[$dim] = $size - 1
      if (@end_positions[$dim] ~~ Int:U) && @end_positions_orig[$dim] >= $size;
    }
  }

  #--------------------------------------------------------------------------
  #  If there are no restrictions on placement as-is then accept tile
  #--------------------------------------------------------------------------
  my Bool $accept = so (@end_positions.all ~~ Int:U);

  #--------------------------------------------------------------------------
  #  (Even if the tile is accepted we first populate @end_positions (in case
  #  we are recursing).)
  #
  #  Some ending positions may not be blocked by either existing tiles or
  #  space limitations at all; fill in such ending positions with values
  #  implied by the tile itself.
  #--------------------------------------------------------------------------
  for $tile.extensions.kv -> Index $dim, Extension $extension
  {
    @end_positions[$dim] = @positions[$dim] + $extension
    if @end_positions[$dim] ~~ Int:U;
  }

  #--------------------------------------------------------------------------
  #  Return if accepted
  #--------------------------------------------------------------------------
  return ($tile, @end_positions) if $accept;

  #--------------------------------------------------------------------------
  #  As restrictions do exist: resort to any prescribed fit strategy
  #--------------------------------------------------------------------------
  for @fit_strategy
  {
    #------------------------------------------------------------------------
    #  Minimal satisfaction
    #------------------------------------------------------------------------
    when 1
    {
      return (produce_minimal_tile(@dimensions, @tiles), @end_positions);
    }

    #------------------------------------------------------------------------
    #  Best existing match
    #  Transformation
    #------------------------------------------------------------------------
    when 2..4
    {
      #  Calculate the new extensions which will fit into the
      #  newly-restricted space.  (Subtract the current from the end
      #  positions.)
      my Extension @max_extensions = (@end_positions.List Z- @positions.List);

      #  Retrieve any tile in the tileset matching the maximum extensions
      # my @matching_tiles = @tiles.grep({ .extensions eq @max_extensions });
      my Tile @matching_tiles = @tiles.grep({ $_.extensions.List eq @max_extensions.List });

      #----------------------------------------------------------------------
      #  An available tile matches; accept it
      #----------------------------------------------------------------------
      return (@matching_tiles[0], @end_positions) if @matching_tiles;

      #----------------------------------------------------------------------
      #  Best existing match
      #----------------------------------------------------------------------
      when 2
      {
        my %best = 'diff', Int_N, 'tiles', Array[Tile];

        #  Scan the full tileset
        for @tiles
        {
          #  (Ignoring the proposed tile)
          next if $_ eq $tile.extensions;

          #  Find the differential between this tile's extensions and the maximum
          my $diff = @max_extensions.List >>->> $_.extensions.List;

          #  If this tile is compatible with the maximum extensions
          if $diff.all >= 0
          {
            # #  A zero differential is optimum; find the one(s) closest to zero
            # my $diff_sum = $diff.sum;
            # if %best<diff> ~~ Int_N:U || $diff_sum < %best<diff>
            # {
            #   %best<diff> = $diff_sum;
            #   %best<tiles>.push: $_;
            # }

            #  A zero differential is optimum; find the one(s) closest to zero
            #
            my Int_N $diff_sum = $diff.sum;

            if %best<diff> ~~ Int:D
            {
              if $diff_sum < %best<diff>
              {
                %best<diff> = $diff_sum;
                %best<tiles> = [$_];
              }
              elsif $diff_sum == %best<diff>
              {
                %best<tiles>.push: $_;
              }
            }
            else
            {
              %best<diff> = $diff_sum;
              %best<tiles>.push: $_;
            }
          }
        }

        #  Either return an appropriate tile or continue
        return (%best<tiles>.pick, @end_positions) if %best<diff> ~~ Int:D;
        next;
      }

      #----------------------------------------------------------------------
      #  Transformation
      #----------------------------------------------------------------------
      #  No available tile matches
      #
      #  The fit tactic restricts by available tiles; continue
      next when 3;

      #  The fit tactic (4) is not restricted by available tiles;
      #  create a tile satisfying the maximum extensions
      return (Tile.new(extensions => @max_extensions), @end_positions);
    }

    #------------------------------------------------------------------------
    #  Rotation
    #------------------------------------------------------------------------
    when 5..6
    {
      #  Obtain all permutations (minus the one known to have failed) of this
      #  tile's orientations
      my List @orientations = $tile.extensions.permutations.grep({ $_ ne $tile.extensions });

      #  End tactic if no alternative orientations found
      next if !@orientations;

      my Tile @prospective_tiles;

      when 5
      {
        #  Since this tactic requires an existing tile we first select only (as
        #  actual Tiles) those permutations which exist in the tileset
        for @orientations -> $orientation
        {
          for @tiles
          {
            (push @prospective_tiles, $_) && last if $_.extensions eq $orientation;
          }
        }
        proceed;
      }
      when 6
      {
        #  This tactic does not require an existing tile; for each orientation
        #  we either find a tile in the tileset or create a Tile
        @prospective_tiles = @orientations.map(-> $orientation
        {
          my Tile $found_tile;
          for @tiles
          {
            ($found_tile = $_) && last if $_.extensions eq $orientation;
          }
          $found_tile ?? $found_tile !! Tile.new(extensions => |$orientation);
        });
        proceed;
      }

      #  End tactic if no matches found
      next if !@prospective_tiles;

      #----------------------------------------------------------------------
      #  Check for acceptance of each prospective tile
      #----------------------------------------------------------------------
      my List @candidates;

      for @prospective_tiles -> $prospective_tile
      {
        #  Recurse
        my Fit_Tactic @fit_strategy-empty;
        my (Tile $candidate_tile, List $candidate_end_positions) =
          fit_tile(@dimensions, @tiles, @fit_strategy-empty, @positions, @occupied_spaces, $prospective_tile);

        #  Next if tile not accepted
        next if !$candidate_tile;

        #  Calculate the new extensions which will fit into the
        #  newly-restricted space.  (Subtract the current from the end
        #  positions.)
        my Extension @max_extensions = ($candidate_end_positions.List Z- @positions.List);

        #  Add to list of candidates; store (0) the tile itself along with
        #  (1) its ending positions and (2) the difference between the
        #  necessary extensions and those defined for the tile (this last
        #  will be used when attempting to determine best fit).
        push @candidates, (
          $candidate_tile,
          $candidate_end_positions,
          @max_extensions.List >>->> $candidate_tile.extensions.List
        );
      }

      #----------------------------------------------------------------------
      #  Conclude
      #----------------------------------------------------------------------
      #  End tactic if no candidates found
      next if !@candidates;

      #  Sort the candidates: obtain decreasing tightness of fit
      @candidates = @candidates.sort({ $^a[2] cmp $^b[2] });

      #  Return the first candidate
      return (@candidates[0][0], @candidates[0][1]);
    }
  }
  #__________________________________________________________________________


  return (Nil, @end_positions);
}
#____________________________________________________________________________



#============================================================================
#  select_tile_color
#--------------------------------------------------------------------------
sub select_tile_color
(
  Parameters::Coloring_Method $coloring_method,
  Parameters::Default_Color_Selection $default_color_selection,
  Color $tile_color_default,
        %colors, #|TYPE| Contains elements of type Color
  Tile  @tiles,
  Tile  $tile
  --> Color
)
{
  given $coloring_method
  {
    when 'tiles' | 'random-assignment'
    {
      return $tile.color if $tile.color;

      #  Use default tile color
      given $default_color_selection
      {
        when 'default'
        {
          return $tile_color_default;
        }
        when 'random-tile'
        {
          my $color;
          loop
          {
            #  Choose a color from existing tiles
            $color = @tiles.pick.color;
            redo unless $color ~~ Str:D;
            last;
          }
          return $color;
        }
        when 'random-colors'
        {
          return %colors.pick;
        }
        when 'random-each-truncated' | 'random-each'
        {
          return generate_color($_ eq 'random-each-truncated');
        }
      }
    }
    when 'random-colors'
    {
      return %colors.pick;
    }
    when 'random-each-truncated' | 'random-each'
    {
      return generate_color($_ eq 'random-each-truncated');
    }
  }
}
#__________________________________________________________________________



#============================================================================
#  write_output
#
#  Write Str output to supplied filehandle.
#----------------------------------------------------------------------------
sub write_output(IO::Handle $fh-out, Str $content --> Bool)
{
  if $fh-out && $fh-out.opened
  {
    $fh-out.put: $content;
  }
  else
  {
    say $content;
  }
  return True;
}
#____________________________________________________________________________




##|EOF
