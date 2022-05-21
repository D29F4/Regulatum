# SPDX-License-Identifier: Artistic-2.0
##===========================================================================
##
##  Regulatum | Rectilinear tiling
##
##  Command-line interface
##
##===========================================================================
use v6;
#----------------------------------------------------------------------------
use Getopt::Long;
use JSON::Tiny;
#----------------------------------------------------------------------------
use Regulatum;
use Regulatum::Service::Colors;
use Regulatum::Service::SVG;
use Regulatum::Type::Parameters;
use Regulatum::Type::Subsets;
use Regulatum::Type::Tile;
use Regulatum::Type::Tile_Distribution;
use Regulatum::Type::Verbosity;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
unit class Regulatum::CLI;



#----------------------------------------------------------------------------
#  Options_Adjutant
#
#  Various elements employed in processing command-line options.
#----------------------------------------------------------------------------
class Options_Adjutant
{
  #  Option keys available for user specification
  has List $.available;

  #  Required keys
  has List $.required;

  #  Keys of elements which may be set with generic assignments
  has List $.basic;

  #  The Coloring_Methods which require specification of the `colors` parameter
  has Parameters::Coloring_Method %.requires_colors is Set;
}

#----------------------------------------------------------------------------
#  The default base directory shall be user home.
#
#  Storing current CWD because the :CWD argument to the IO::Path constructor
#  does not seem to work and we need it later.
#
#  It seems quite silly to have to call indir() all over the place when you
#  just want the user's home directory to be the standard root.
#----------------------------------------------------------------------------
temp $*CWD = $*HOME;



#||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||



{
  #--------------------------------------------------------------------------
  #  Arguments/options
  #--------------------------------------------------------------------------
  my Capture $options-incoming = get-options
  (
    compat-builtin => True,
    auto-help => False,
    #  Parameters  ...............................................................
    'dimensions|d=s',                                # dimensions              | d
    'tiles|t=s',                                     # tiles                   | t
    'fit_strategy|fit-strategy|f=s',                 # fit_strategy            | f
    'spacing_ratio|spacing-ratio|spacing|s=i',       # spacing_ratio           | s
    'tile_color_default|tile-color-default'
      ~ '|tile_colour_default|tile-colour-default|c=s', # tile_color_default   | c
    'colors|colours|C=s',                            # colors                  | C
    'coloring_method|coloring-method|coloring'
      ~ '|colouring_method|colouring-method'
      ~ '|colouring|m=s',                            # coloring_method         | m
    'default_color_selection|default-color-selection'
      ~ '|default_colour_selection'
      ~ '|default-colour-selection|M=s',             # default_color_selection | M
    'output_file|output-file|o=p',                   # output_file             | o
    'verbosity_out|verbosity-out|V=p',               # verbosity_out           | V
    #  Other options  ............................................................
    'ignore_default_config|ignore-default-config|x', # ignore_default_config   | x
    'config_file|config-file|config|i=p',            # config_file             | i
    'verbosity|v=i',                                 # verbosity               | v
    #  Terminable requests  ......................................................
    'print_config|print-config|p',                   # print_config            | p
    'version',                                       # version
    'help|h',                                        # help                    | h
    'man'                                            # man
  );

  #  Convert Capture to Hash
  my %options{Str} = $options-incoming.Hash;

  #--------------------------------------------------------------------------
  #  Preliminaries
  #--------------------------------------------------------------------------
  #  Read META6.json (at the top level of the module, two levels up from here)
  #
  my Map $meta6;
  indir($*PROGRAM.parent(2), {
    #  $meta6 is actually a Hash here
    $meta6 = from-json(IO::Path.new('META6.json').slurp);
  });

  #  Store as an immutable structure
  $meta6 = Map.new($meta6.kv);

  #  Respond to terminable requests
  #
  (say help) && exit if %options<help>;
  (say man) && exit if %options<man>;
  (say $meta6<version>) && exit if %options<version>;
  if %options<print_config>
  {
    my Hash $config-default = obtain_default_config($meta6);
    say ($config-default ?? $config-default !! 'Default configuration file not found.');
    exit;
  }

  #  Resort to prepreprepreprocessing by converting nonscalar option values
  #
  my Str @cli_error_options;

  for <dimensions tiles colors fit_strategy> -> $option
  {
    if %options{$option}:exists
    {
      if %options{$option}.trim ne ''
      {
        %options{$option} = from-json(%options{$option});
        next;
        CATCH { push @cli_error_options, $option; next; }
      }
      %options{$option} = ();
    }
  }

  #  Stop if there are command-line parsing errors
  die sprintf 'Failed to parse JSON of %d command-line option%s: %s.',
    @cli_error_options.elems, (@cli_error_options > 1 ?? 's' !! ''), @cli_error_options.join(', ')
    if @cli_error_options;

  #--------------------------------------------------------------------------
  #  Integrate options from all configuration sources
  #--------------------------------------------------------------------------
  my $options_adjutant = Options_Adjutant.new(
    available => <
      dimensions
      tiles
      fit_strategy
      spacing_ratio
      tile_color_default
      coloring_method
      default_color_selection
      output_file
      verbosity
      verbosity_out
    >,
    required => <
      dimensions
      tiles
    >,
    basic => <
      spacing_ratio
      tile_color_default
    >,
    requires_colors => (
      'random-colors',
    ),
  );

  %options = integrate_options($options_adjutant, %options, $meta6);

  #--------------------------------------------------------------------------
  #  Prepare constructor hash
  #--------------------------------------------------------------------------
  #  Initialize constructor hash
  my %parameters = (
    fh-out => determine_fh-out(%options),
  );

  #  Verbosity
  %parameters<verbosity> = determine_verbosity(%options, %parameters<fh-out>);

  #  Basic attributes
  %parameters = determine_remaining_attrs($options_adjutant.basic, %options, %parameters);

  #  Dimensions
  %parameters<dimensions> = determine_dimensions(%options);

  #  Tiles and distributions
  (%parameters<tiles>, %parameters<distributions>, my $warnings) =
    determine_tiles(%options<tiles>, %parameters);

  #  Colors
  %parameters = determine_colors(%options, %parameters);

  #  Coloring method
  %parameters = determine_coloring_method(%options, $options_adjutant.requires_colors, %parameters);

  #  Coloring method default
  %parameters = determine_default_color_selection(%options, %parameters);

  #  Fit strategy
  %parameters<fit_strategy> = %options<fit_strategy>.List
    if %options<fit_strategy>:exists;

  #--------------------------------------------------------------------------
  #  Create Parameters object
  #--------------------------------------------------------------------------
  my $parameters = Parameters.new(|%parameters.Map);

  #--------------------------------------------------------------------------
  #  Generation: preliminaries
  #--------------------------------------------------------------------------
  #  Filehandle (messages): open
  $parameters.verbosity.fh-out.open :w if !$parameters.verbosity.fh-out.opened;

  #  ((Messages))  Warnings; Parameters
  ($parameters.verbosity.print($_) for $warnings.list) && say ''
    if $parameters.verbosity.level >= 1;
  ($parameters.verbosity.print($_) for summarize($options_adjutant, $parameters))
    if $parameters.verbosity.level >= 2;

  #--------------------------------------------------------------------------
  #  Generation and output
  #--------------------------------------------------------------------------
  #  Filehandle (output): open
  #  (May already be open if opened for Verbosity messages.)
  $parameters.fh-out.open :w if !($parameters.fh-out === $parameters.verbosity.fh-out);

  #  Output: begin
  $parameters.fh-out.put: svg-start($parameters.dimensions, $parameters.spacing_ratio);

  #  Generate
  my Int_N $tiles-total = generate($parameters);

  #  Output: end
  $parameters.fh-out.put: svg-end;

  #--------------------------------------------------------------------------
  #  Generation: conclusion
  #--------------------------------------------------------------------------
  #  ((Messages))  Tiles laid
  $parameters.verbosity.print("Total tiles laid: $tiles-total") if $parameters.verbosity.level >= 2;

  #  Filehandles: close
  $parameters.fh-out.close;
  $parameters.verbosity.fh-out.close;


  #----------------------------------------------------------------------------
  #  Phaser
  #----------------------------------------------------------------------------
  CATCH
  {
    $*ERR.print: 'ERROR: ';

    when Getopt::Long::Exception
    {
      $*ERR.say: sprintf 'Failed to parse command-line arguments.  ' ~ .Str;
      #exit;
    }
    when X::TypeCheck
    {
      $*ERR.say: sprintf 'Invalid parameter value: %s', .got;
    }
    default
    {
      $*ERR.say: .Str;
    }
  };
}



#||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||



#============================================================================
#  integrate_options
#
#  Integrate options from all recognized sources.  Sources are (in descending
#  order of priority):
#
#    1. Basic command-line options
#    2. User-specified configuration file
#    3. Default configuration file
#----------------------------------------------------------------------------
sub integrate_options(
  Options_Adjutant $options_adjutant,
                   %options,
  Map              $meta6
  --> Hash
)
{
  #  If all available options have not been supplied via the command line
  #  and supplied options also specify a configuration file
  #  then seek (all or additional) options in said file
  if !available_options_exist($options_adjutant, %options)
    && (%options<config_file>:exists)
    && %options<config_file>.trim ne ''
  {
    #  Read file
    %options = merge_options(%options, from-json(%options<config_file>.IO.slurp));
  }

  #  If all available options are not present and options do not proscribe use of default file
  #  then look for default configuration file and read it if it exists
  if !available_options_exist($options_adjutant, %options)
    && (%options<ignore_default_config>:!exists)
  {
    my Hash $config-default = obtain_default_config($meta6);
    %options = merge_options(%options, $config-default) if $config-default;
  }

  #  If at least required options are not present then fail
  die 'Incomplete configuration options: could not collect required values from available sources.'
    unless %options{$options_adjutant.required.all}:exists;

  return %options;

  CATCH
  {
    when .^name eq 'JSON::Tiny::X::JSON::Tiny::Invalid'
    {
      die 'Failed to parse JSON of default configuration file.';
    }
  }
}
#____________________________________________________________________________



#============================================================================
#  available_options_exist
#
#  Check options structure for completeness with respect to all available
#  elements.
#----------------------------------------------------------------------------
sub available_options_exist(
  Options_Adjutant $options_adjutant,
                   %options
  --> Bool
)
{
  #  All available options exist
  return (so %options{$options_adjutant.available.all}:exists)
    && (
      #  (coloring_method amongst them);
      #  and coloring_method either doesn't require specification of colors
      !$options_adjutant.requires_colors{%options<coloring_method>}
      #  or it does and colors is duly defined
      || (%options<colors>:exists)
    );
}
#____________________________________________________________________________



#============================================================================
#  merge_options
#
#  Merge candidate options structure into %options.
#----------------------------------------------------------------------------
sub merge_options(%options, Hash $options-candidate --> Hash)
{
  for $options-candidate.keys -> $key
  {
    #  Integrate with CLI-provided options if not present
    (%options{$key} = $options-candidate{$key})
      if %options{$key}:!exists && ($options-candidate{$key}:exists);
  }

  return %options;
}
#____________________________________________________________________________



#============================================================================
#  obtain_default_config
#
#  Read default config file if one exists.
#
#  Base directory is user home.
#----------------------------------------------------------------------------
sub obtain_default_config(Map $meta6 --> Hash)
{
  #  If a default configuration file exists
  if $meta6<custom><default_config_path>:exists
    && $meta6<custom><default_config_path>.IO.f
  {
    return from-json($meta6<custom><default_config_path>.IO.slurp);
  }

  return Nil;

  CATCH { die 'Failed to parse JSON of default configuration file.'; }
}
#____________________________________________________________________________



#============================================================================
#  determine_fh-out
#
#  Produce the filehandle for main output.
#----------------------------------------------------------------------------
sub determine_fh-out(%options --> IO::Handle)
{
  my IO::Handle $fh-out;

  #  Use valid path if provided
  if %options<output_file>:exists && %options<output_file>.=trim ne ''
  {
    $fh-out = IO::Handle.new(:path(%options<output_file>));
  }
  #  Otherwise use STDOUT
  else
  {
    $fh-out = $*OUT;
  }

  return $fh-out;
}
#____________________________________________________________________________



#============================================================================
#  determine_verbosity
#----------------------------------------------------------------------------
sub determine_verbosity(%options, IO::Handle $fh-out --> Verbosity)
{
  #  The Verbosity filehandle
  my IO::Handle $vb-fh-out;

  if %options<verbosity_out>:exists && %options<verbosity_out>.=trim ne ''
  {
    #  Define output path for Verbosity functionality
    my $vb-path = IO::Path.new(%options<verbosity_out>);

    #  Use output filehandle if the same as that specified here
    when $vb-path.absolute eqv $fh-out.IO.absolute { $vb-fh-out := $fh-out }

    #  Otherwise prepare new filehandle
    $vb-fh-out = IO::Handle.new(:path($vb-path));
  }
  else
  {
    $vb-fh-out = $*OUT;
  }

  return Verbosity.new(
    level => (%options<verbosity>:exists && %options<verbosity> >= 0)
      ?? %options<verbosity>
      !! 0,
    fh-out => $vb-fh-out,
    as_comment => $vb-fh-out eqv $fh-out
  );
}
#____________________________________________________________________________



#============================================================================
#  determine_dimensions
#----------------------------------------------------------------------------
sub determine_dimensions(%options --> Array)
{
  die 'At least one dimension must be defined.'
    if %options<dimensions>:!exists || %options<dimensions>.elems !~~ Int_Pos;

  return %options<dimensions>;
}
#____________________________________________________________________________



#============================================================================
#  determine_tiles
#
#  Construct Parameters-compatible data structures for tiles and
#  distributions.
#----------------------------------------------------------------------------
sub determine_tiles(@tiles-incoming, %parameters --> List)
{
  #  ((Messages))
  my Str @warnings;

  my Int_N $pc-count = 0;
  my Int_N $tile_count = 0;
  my Tile %tile-map{Str};

  #--------------------------------------------------------------------------
  #  Process each incoming tile specification
  #--------------------------------------------------------------------------
  for @tiles-incoming.list -> @tile-in
  {
    #  Very simple initial check on incoming tile
    (die sprintf 'Tile supplied at position %d does not have the correct number of dimensions.  Stopping.',
      #  (The num. of elements is the num. of dim. plus 2 for color and probability.)
      $tile_count) if @tile-in.elems != %parameters<dimensions> + 2;

    #  Obtain nondimensional elements
    #
    #  Obtain percentile
    my $pc = @tile-in.pop;

    #  Obtain color (check first)
    die sprintf 'Invalid color supplied for tile %s.',
      @tile-in[0..(%parameters<dimensions> - 1)].Array.gist if @tile-in[*-1] !~~ Color;
    my Color $color = @tile-in.pop // Color;


    #  Lengths remain; concatenate for clavial use
    my Str $unique_tile = @tile-in.join('.');

    #  If supplied tile passes the filter
    #
    if
      #  Percentage value is a positive integer
      $pc ~~ Int_Pos:D
      #  Percentage count not at maximum
      && $pc-count < 100
      #  All tile lengths are > 0
      && so (@tile-in.all > 0)
      #  Each tile length is <= the size of its respective dimension
      && so (@tile-in.list Z<= %parameters<dimensions>)
    {
      #  Check for preexisting version of this tile; will overwrite if present
      if %tile-map{$unique_tile}:exists
      {
        #  But first: subtract percentage of tile to be ignored from running count
        $pc-count -= %tile-map{$unique_tile}.percentage;
      }

      #  Add percentage to running count and calculate any surplus
      $pc-count += $pc;
      my Int $pc-surplus = $pc-count - 100;

      #  If current percentage total adds up to > 100%
      if $pc-surplus > 0
      {
        #  Use truncated percentage for this tile
        $pc -= $pc-surplus;

        #  ((Messages))
        push @warnings, sprintf " . The probability value of tile %s was reduced to %s.",
          @tile-in.gist, $pc;
      }

      #  Save tile
      %tile-map{$unique_tile} = Tile.new(
        extensions => @tile-in.List >>->> 1,
        color => $color,
        probability => $pc
      );
    }
    else
    {
      push @warnings, sprintf " . Tile was ignored: %s.", @tile-in.gist;
      next;
    }
  }
  #__________________________________________________________________________


  #  ((Messages))
  if $pc-count != 100
  {
    unshift @warnings, 'Percentages were truncated at 100 and tiles ignored as necessary.'
      if $pc-count > 100;
    unshift @warnings, "Specified distribution percentages added up to $pc-count.";
  }

  #--------------------------------------------------------------------------
  #  Produce master Tile list
  #--------------------------------------------------------------------------
  #  Sort tiles (in decreasing order of dimensional lengths)
  my @tiles = %tile-map.values.sort({ $^b.extensions cmp $^a.extensions });

  #--------------------------------------------------------------------------
  #  Produce Tile_Distributions
  #--------------------------------------------------------------------------
  #  Maintain running total of distribution percentages
  my Int $range-max = -1;

  my Tile_Distribution @distributions = @tiles
    .sort({ $^b.probability cmp $^a.probability })
    .map(-> $tile
    {
      $range-max += $tile.probability;
      Tile_Distribution.new(:tile($tile), :percentile($range-max));
    });

  return @tiles, @distributions, @warnings;
}
#____________________________________________________________________________



#============================================================================
#  determine_colors
#----------------------------------------------------------------------------
sub determine_colors(%options, %parameters --> Hash)
{
  #  Parse and store colors
  %parameters<colors> = %options<colors>.=grep({ $_}) if %options<colors>:exists;

  return %parameters;
}
#____________________________________________________________________________



#============================================================================
#  determine_coloring_method
#----------------------------------------------------------------------------
sub determine_coloring_method
(
      %options,
  Set $requires_colors,
      %parameters
  --> Hash
)
{
  if %options<coloring_method>:exists
  {
    #  Ensure validity
    die 'An invalid value for the coloring method was provided.'
      if %options<coloring_method> !~~ Parameters::Coloring_Method;

    #  Store option value
    %parameters<coloring_method> = %options<coloring_method>;

    #  Treat coloring option if it requires specification of `colors`
    #
    if $requires_colors{%parameters<coloring_method>}
    {
      my Str @errors;
      my Cool @requirements;

      given %parameters<coloring_method>
      {
        when 'random-colors'
        {
          @requirements = 1, 'one color';
        }
      }

      #  Error: insufficient colors
      (push @errors, sprintf 'The `%s` coloring method requires'
        ~ ' specification of at least %s; %d provided.',
        %options<coloring_method>, @requirements[1],
        (%parameters<colors> ?? %parameters<colors>.elems !! 0))
        if !%parameters<colors> || %parameters<colors> < @requirements[0];

      die @errors.join("\n") if @errors;
    }
    else
    {
      #  Replace tile colors if using the "random-assignment" method
      %parameters<tiles>.=map(-> $tile { $tile.color = generate_color; $tile; })
        if %parameters<coloring_method> eq 'random-assignment';
    }
  }

  return %parameters;
}
#____________________________________________________________________________



#============================================================================
#  determine_default_color_selection
#----------------------------------------------------------------------------
sub determine_default_color_selection(%options, %parameters --> Hash)
{
  if %options<default_color_selection>:exists
  {
    #  Ensure validity
    die 'An invalid value for the default color-selection was provided.'
      if %options<default_color_selection> !~~ Parameters::Default_Color_Selection;

    #  Store option value
    %parameters<default_color_selection> = %options<default_color_selection>;

    given %parameters<default_color_selection>
    {
      when 'random-tile'
      {
        #  Error: incompatible parameters
        die sprintf 'The `random-tile` default color-selection method requires'
          ~ ' specification of the `tiles` or the `random-assignment` coloring'
          ~ ' method; `%s` provided.',
          %options<default_color_selection>
          if %parameters<coloring_method>
            && %parameters<coloring_method> !~~ <tiles random-assignment>.one;
      }
      when 'random-colors'
      {
        #  Error: insufficient colors
        die 'The `random-colors` default color-selection method requires'
          ~ ' specification of at least one color; 0 provided.',
          if !%parameters<colors> || %parameters<colors> == 0;
      }
    }
  }

  return %parameters;
}
#____________________________________________________________________________



#============================================================================
#  determine_remaining_attrs
#
#  Determine remaining Parameters attributes.
#----------------------------------------------------------------------------
sub determine_remaining_attrs
(
  List $options-basic,
       %options,
       %parameters
  --> Hash
)
{
  for $options-basic.list -> $key
  {
    #  Assign value
    %parameters{$key} = %options{$key}
      if %options{$key}:exists && %options{$key}.trim ne '';
  }

  return %parameters;
}
#____________________________________________________________________________



#============================================================================
#  summarize
#
#  ((Messages))  Summarize parameters in use.
#----------------------------------------------------------------------------
sub summarize(
  Options_Adjutant $options_adjutant,
  Parameters       $parameters
  --> Array[Str]
)
{
  my Str @text;

  #  Dimensions
  push @text, sprintf 'Dimensions: %s', $parameters.dimensions.gist;

  #  Tiles and distributions
  my Int %dists{Int};
  my Int $percentile = -1;
  for $parameters.distributions.kv -> $index, $distribution
  {
    %dists{$index} = $distribution.percentile - $percentile;
    $percentile = $distribution.percentile;
  }
  push @text, sprintf '%4s %13s %12s %14s', <Tile Dimensions Color Probability>;
  for $parameters.tiles.kv
  {
    push @text, sprintf '%4d %13s %12s %13s%%',
      $^a + 1,
      $^b.extensions.map({ $_ + 1 }).join(' '),
      $^b.color ?? $^b.color !! '(None)',
      %dists{$^a};
  }

  #  Fit strategy
  push @text, sprintf 'Fit strategy: %s', $parameters.fit_strategy.values
    ?? $parameters.fit_strategy.values.join(' ')
    !! '(None)';

  #  Spacing ratio
  push @text, sprintf 'Spacing ratio: %s', $parameters.spacing_ratio;

  #  Default tile color
  push @text, sprintf 'Default tile color: %s', $parameters.tile_color_default;

  #  Color options
  push @text, sprintf 'Coloring method: %s', $parameters.coloring_method;
  push @text, sprintf 'Default color selection: %s', $parameters.default_color_selection;
  push @text, (sprintf 'Colors: %s', $parameters.colors.keys.join(' '))
    if $options_adjutant.requires_colors{$parameters.coloring_method};

  #  Output
  push @text, sprintf 'Output: %s',
    $parameters.fh-out.IO.f ?? $parameters.fh-out.IO.absolute !! '<STDOUT>';

  #  Verbosity
  push @text, sprintf 'Verbosity output: %s',
    $parameters.verbosity.fh-out.IO.f
      ?? $parameters.verbosity.fh-out.IO.absolute
      !! '<STDOUT>';
  push @text, sprintf 'Verbosity level: %d', $parameters.verbosity.level;

  return @text;
}
#____________________________________________________________________________



#============================================================================
#  help
#
#  Brief help text.
#----------------------------------------------------------------------------
sub help(--> Str)
{
  return q:to/_XXX_/.chomp;
Regulatum

regulatum [OPTION...]

--dimensions      -d  J  The dimensions of the space ('[x, y, ...]').
--tiles           -t  J  The tiles available for placement ('[[x, y, "color", %], ...]').
--fit-strategy    -f  J  The agenda employed to obtain a tile fit ('[t1, t2, ...]').
--spacing-ratio   -s  N  The spacing ratio.
--tile-color-default
                  -c  S  The "default" tile color, where S = a valid color string.
--colors          -C  J  An array of available colors used by selected coloring methods.
--coloring-method -m  S  The method used in coloring defined tiles.
                         (tiles|random-colors|random-assignment|random-each|random-each-truncated)
--default-color-selection
                  -M  S  The method of selecting a "default color".
                         (default|random-tile|random-colors|random-each|random-each-truncated)
--output-file     -o  P  The target path and filename for output.
--verbosity-out   -V  P  The target path and filename for any verbosity content.
--ignore-default-config  Ignore any default configuration file if one exists.
                  -x
--config-file     -i  P  The location of a valid configuration file.
--verbosity       -v  N  The verbosity setting (0: silent; 1: warnings; 2: summary.)
--print-config           Print the contents of any default configuration file.
--version                Print the version number of this program.
--help            -h     Print help text.  (This text.)
--man                    Print extended man-style help text.

(Argument key:
  J: string containing valid JSON; N: integer; S: string; P: path and filename.)
_XXX_
}
#____________________________________________________________________________



#============================================================================
#  man
#
#  Extended man-style help text.
#----------------------------------------------------------------------------
sub man(--> Str)
{
  return q:to/_XXX_/.chomp;
================================================================================
  NAME
--------------------------------------------------------------------------------
Regulatum : Generate random rectangular tiling patterns as SVG output



================================================================================
  SYNOPSIS
--------------------------------------------------------------------------------
regulatum [OPTION...]



================================================================================
  DESCRIPTION
--------------------------------------------------------------------------------
Regulatum programmatically generates rectangular tiling patterns on a grid
background.  Output is a specification of individual tile shapes in SVG format.

Users define the dimensionality of the domain, the tiles which may occupy that
space, and possibly other parameters.  Individual tiles are randomly selected
for placement; rules governing alternative selections may be specified to handle
cases in which the proposed tile cannot fit in the available space.  Regulatum
is not designed to produce output representing any class of repeating pattern or
tessellation.

SVG rendering is of course limited to two dimensions.  Regulatum is capable of
producing consistent n-dimensional output, however, and theoretically could
print such output for an accommodating renderer.

A command-line interface is available and is described here.  Another Raku
program could also employ the internal classes and functionality in a fashion
similar to the CLI.  (Explicit documentation for such usage is not yet
available.)



================================================================================
  OPTIONS
--------------------------------------------------------------------------------

The alphabetic keys in the listing below indicate the type of data expected as
arguments:

  J: String containing valid JSON
  N: Zero or a positive integer
  P: Path and filename
  S: String

--------------------------------------------------------------------------------
  Options used to define parameters relevant to the tiling process
--------------------------------------------------------------------------------

  -d                      J  The dimensions of the space.
  --dimensions                 This takes the form of a JSON array of integers.
                             Each element is the size of (that is: the number of
                             units within) the corresponding dimension.
                               The ordering begins with the x axis and
                             dimensionality increases from left to right; that
                             is: x, y, z, ... .
                             Default: (none)

  -t                      J  The available tiles.
  --tiles                      This should be a JSON array of one or more
                             arrays, each representing a tile.  Tiles are
                             defined by a series of integers indicating
                             dimensional extension, a color, and a probability
                             of being selected.
                               See the Tiles section below for details.
                             Default: (none)

  -f                      J  The agenda employed (the "fit strategy") to obtain
  --fit-strategy             a tile fit in an inning.
                               The form is that of a JSON array of one or more
                             positive integers, each of which represents an
                             independent tactic; the tactics are progressively
                             employed to find a fit.  The strategy begins with
                             the first element of the array and ends with the
                             last.
                               The available tactics are presented in the Fit
                             Tactics section below.
                             Default: (none)

  -s                      N  The spacing ratio.
  --spacing-ratio              The proportion of intertile space to the tile
  --spacing                  width and height.  This value is n in the ratio n:1
                             (or 1/n).
                             Default: 16

  -c                      S  The default tile color.
  --tile-color-default         The color to be used for tiles in the absence of
  --tile-colour-default      tile-specific color definitions or rules.
                               Application of this value depends on the coloring
                             method and the default color selection setting.
                             Default: "#000"

  -C                      J  A set of available colors used by selected coloring
  --colors                   methods.
  --colours                    This takes the form of a JSON array of one or more
                             strings representing colors.
                               See also the Colors section below.
                             Default: (none)

  -m                      S  The method used in coloring defined tiles.
  --coloring-method            Options are presented in the Coloring Methods
  --coloring                 section below.
  --colouring-method         Default: "tiles"
  --colouring

  -M                      S  The method of selecting a default tile color.
  --default-color-selection    Options are presented in the Default Color
  --default-colour-selection Selection section below.
                             Default: "default"

  -o                      P  The target file for output.  Will overwrite any
  --output-file              existing file.
                               The base directory is user home.
                               All output is directed to standard output by
                             default and can therefore be redirected as desired
                             without use of this switch.
                             Default: (writes to standard output)

  -V                      P  The target file for any verbosity content.  Will
  --verbosity-out            overwrite any existing file.
                               The base directory is user home.
                               See also the Verbosity section below.
                             Default: (writes to standard output)

--------------------------------------------------------------------------------
  Other options
--------------------------------------------------------------------------------

  -x                         Ignore any default configuration file if one
  --ignore-default-config    exists.

  -i                      P  The location of a file containing configuration to
  --config                   inform processing.
  --config-file                The base directory is user home.
                               See also Configuration Sources below.

  -v                      N  The verbosity setting.
  --verbosity                  See the Verbosity section below for options.
                             Default: 0

--------------------------------------------------------------------------------
  Terminable Options
--------------------------------------------------------------------------------
These options produce the requested output and immediately quit.

  --print-config             Print the contents of any default configuration
                             file.

  --version                  Print the version number of this program.

  -h                         Print short help text.
  --help

  --man                      Print extended man-style help text.  (The current
                             text.)


(Hyphens in the names of the long switches may be replaced by underscores if
desired; for example: the long switch --spacing_ratio is equivalent to
--spacing-ratio.)



================================================================================
  Requirements
--------------------------------------------------------------------------------
Processing at a minimum requires the user to define dimensions and tiles.

Other parameters possess defaults, are contingent upon others, or are entirely
optional.



================================================================================
  Configuration Sources
--------------------------------------------------------------------------------
This interface will attempt to aggregate options for parameters from three
sources (listed here in decreasing order of priority):

  - Command line options

  - User-defined configuration file (identified via the config-file option)

  - Default configuration file

The process will run as long as a sufficient parameter set can be collected from
one or more of the above sources.


Configuration files must be in valid JSON format.  For the moment (greater
flexibility could later be introduced) the keys must be the underscore versions
of the long switches; namely:

  dimensions, tiles, fit_strategy, spacing_ratio, tile_color_default, colors,
  coloring_method, default_color_selection, output_file, verbosity,
  verbosity_out



================================================================================
  Tile Definition
--------------------------------------------------------------------------------
The basic form is a JSON array of arrays, where the inner arrays represent
tiles:

  [ [x, y, z, ..., "color", p], [x, y, z, ..., "color", p], ... ]

The initial values are positive integers indicating the length (or extension) of
the tile in the respective dimension.  Next is a string indicating the color
(see the Colors section).  The final element is a positive integer between 1 and
100 (inclusive) which determines the probability that the tile will be chosen
during each inning of laying tiles.

For example, the array [2, 4, "purple", 60] defines a tile which extends 2 units
along the x axis and 4 units along the y axis, will be colored purple (assuming
that the coloring method allows it), and has a 60% chance of being selected to
attempt to fill an empty space.  (Of course circumstances of available space may
nevertheless prevent placement.)


Notes on extension specification:

  - The number of extension values must agree with the dimensionality as defined
    in the dimensions parameter.

  - Tiles without positive integers specified for all extensions will be
    ignored.


Notes on color specification:

  - If the color is an empty string then tile_color_default will be used for
    that tile.  (Such a specification is interpreted to mean that a color should
    still be set by some means but that the user is declining to specify one.)

  - The use of individual tile colors supplied ultimately depends upon the
    settings of coloring_method and default_color_selection.


Notes on probability specification:

  - Tiles with a probability value less than 1 will be ignored.

  - The probability values of all valid tiles may sum to less than 100.  Any
    remainder prescribes an empty space of size 1 in all dimensions.

  - If the total probability value is greater than 100 then steps will be taken
    to reduce it to said maximum.  Namely, the probability value of the
    last-specified tile may be truncated and/or entire tiles may be ignored.



================================================================================
  Colors
--------------------------------------------------------------------------------
All user-specified colors should be in a standard representation supported by
SVG documents.

Colors randomly generated by Regulatum (via the "random-each" or
"random-each-truncated" methods of certain options) are rendered in either
three- or six-digit hexadecimal notation.



================================================================================
  Fit Tactics
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
  Minimal satisfaction
--------------------------------------------------------------------------------
  1: Place a tile which is one unit in length in all dimensions (irrespective of
     whether or not such a tile has been prescribed).  Will always be
     successful.

--------------------------------------------------------------------------------
  Best existing match
--------------------------------------------------------------------------------
  2: Select the best-fitting tile from the tileset if one exists.  Currently
     this means choosing the tile with the smallest overall distance from the
     boundaries of available space.  If multiple tiles happens to have the same
     differential ranking then one of them is chosen at random.

--------------------------------------------------------------------------------
  Transformation (reduction)
--------------------------------------------------------------------------------
  Reduce the length of one or more dimensions of the proposed tile.  The
  reduction should be minimal; that is: both the reduction in length and the
  number of dimensions affected should be only that required to ensure a fit.

  3: (Restricted by available tiles.)  Will succeed only if a tile with the
     necessary dimensions has been defined.

  4: (Not restricted by available tiles.)  If a tile with the necessary
     dimensions has been defined then it will be used; otherwise generate an
     ad-hoc tile.  Per the above specification, said tile should possess
     extensions as close to the original proposed tile as possible.

--------------------------------------------------------------------------------
  Rotation (reorientation)
--------------------------------------------------------------------------------
  Determine if a different orientation of the proposed tile will satisfy the
  placement conditions.

  5: (Restricted by available tiles.)  Will succeed only if a tile with the
     necessary assignments of lengths to dimensions has been defined.

  6: (Not restricted by available tiles.)  If a tile with the necessary
     assignments of lengths to dimensions has been defined then it will be used;
     otherwise generate a tile ad-hoc to the necessary specifications.  If more
     than one tile satisfies the requirements (something only possible in spaces
     with more than two dimensions) then the first matching tile will be used.



================================================================================
  Coloring Methods
--------------------------------------------------------------------------------
The set of available coloring methods.

  tiles
    Use colors defined for each tile.

  random-colors
    Randomly select a color from the colors attribute for each tile upon
    placement.  Requires that the colors attribute has been populated with at
    least one color.

  random-assignment
    Randomly assign a distinct color to each tile in the set of defined tiles.
    Then proceed per the "tiles" method.  Uses the smaller space of colors
    represented by the three-character format of Web colors.

  random-each
    Randomly select a color (not necessarily distinct) for each tile upon
    placement.  Uses the full, six-digit space of Web colors.

  random-each-truncated
    Randomly select a color (not necessarily distinct) for each tile upon
    placement.  Uses the smaller space of colors represented by the three-digit
    format of Web colors.



================================================================================
  Default Color Selection
--------------------------------------------------------------------------------
The set of available options for applying a default color.

  default
    Use the color defined in tile_color_default.

  random-tile
    Randomly select a color from the existing tiles for each tile upon
    placement.  Requires the use of the "tiles" or the "random-assignment" method
    for coloring_method.

  random-colors
    Randomly select a color from the colors attribute for each tile upon
    placement.  Requires that the colors attribute has been populated with at
    least one color.

  random-each
    Randomly select a color (not necessarily distinct across all instances of
    default tiles) upon placement.  Uses the full, six-digit space of Web
    colors.

  random-each-truncated
    Randomly select a color (not necessarily distinct across all instances of
    default tiles) upon placement.  Uses the smaller space of colors represented
    by the three-digit format of Web colors.



================================================================================
  Verbosity
--------------------------------------------------------------------------------
Informative message content by level value (values > 0 are cumulative):

  0: None (execute silently).

  1: Warnings and alerts concerning nonfatal conditions of note.

  2: A summary of parameters before generation commences; also, the total number
     of tiles laid upon the conclusion of the process.

Note that the short as well as the long versions of this switch accept an
integer argument and do not behave in the inconsistent manner typical of many
command-line programs (that is: indicating increasing verbosity levels via
repetition of the short switch's alphabetic component).

If the target of verbosity output is identical to that of process output then
any verbose message content is commented out.



================================================================================
  EXAMPLES
--------------------------------------------------------------------------------
Specifying four tiles, two square and two of unequal sides, to be laid on a
12-by-12 grid with unequal probability; resort (first) to shrinking proposed
tiles and (then) to one-unit pink tiles when necessary.

  regulatum -d '[12,12]' \
            -t '[[2,2,"#8F7FDF",8], [1,3,"#A68CB3",23], [3,1,"#838CC3",23], [1,2,"#999FB9",23], [2,1,"#C69F9F",23]]' \
            -f '[4,1]' \
            -c pink

Produce a moderately-spaced mosaic of randomly-colored squares in a horizontal
strip.  (It doesn't matter which string we specify for the tile's color as it is
overridden by the coloring method.)

  regulatum -d '[14,6]' -t '[[1,1,"",100]]' -m random-each -s 5

As above but without any intertile spacing.

  regulatum -d '[14,6]' -t '[[1,1,"null",100]]' -m random-each -s 0

Produce a mosaic of squares of two sizes in a vertical strip.  The colors for
each tile laid is chosen randomly from the three supplied.  The fit strategy
allows a minimal tile only.  Output is written to a file in the user's home
directory.

  regulatum -d '[10,20]' -t '[[1,1,"",40], [2,2,"",60]]' \
            -C '["darkslategrey", "darkslateblue", "#6F1C2A"]' \
            -m random-colors -f '[1]' -o ~/tiles.svg

A pattern somewhat reminiscent of a complicated city plan.

  regulatum -d '[20,20]' \
            -t '[[2,2,"",4], [2,1,"",18], [1,2,"",18], [3,1,"",30], [1,3,"",30]]' \
            -f '[1]' -C '["#4F4F4FFF"]' -m random-colors -s 1



================================================================================
  OTHER
--------------------------------------------------------------------------------
Proposed developments, bugs, and similar matters are tracked as GitHub Issues at
https://github.com/D29F4/Regulatum/issues.



================================================================================
  COPYRIGHT
--------------------------------------------------------------------------------
Copyright 2022  D29F4

Regulatum is distributed under the Artistic License, version 2.0.


________________________________________________________________________________

_XXX_
}




##|EOF
