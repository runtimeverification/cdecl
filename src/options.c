/*
**      cdecl -- C gibberish translator
**      src/options.c
**
**      Paul J. Lucas
*/

// local
#include "options.h"
#include "util.h"

// standard
#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <getopt.h>
#include <string.h>
#include <sysexits.h>

///////////////////////////////////////////////////////////////////////////////

#define GAVE_OPTION(OPT)          (opts_given[ (unsigned char)(OPT) ])
#define SET_OPTION(OPT)           (opts_given[ (unsigned char)(OPT) ] = (OPT))

// extern option variables
char const         *opt_fin;
char const         *opt_fout;
bool                opt_interactive;
lang_t              opt_lang;
bool                opt_make_c;
bool                opt_quiet;

// other extern variables
FILE               *fin;
FILE               *fout;

// local variables
static char         opts_given[ 128 ];

// local functions
static void         usage( void );

///////////////////////////////////////////////////////////////////////////////

static char const SHORT_OPTS[] = "acipqvx:";

static struct option const LONG_OPTS[] = {
  { "language",     required_argument,  NULL, 'x' },
  { "interactive",  no_argument,        NULL, 'i' },
  { "quite",        no_argument,        NULL, 'q' },
  { "version",      no_argument,        NULL, 'v' },
  { NULL,           0,                  NULL, 0   }
};

////////// local functions ////////////////////////////////////////////////////

/**
 * Checks that no options were given that are among the two given mutually
 * exclusive sets of short options.
 * Prints an error message and exits if any such options are found.
 *
 * @param opts1 The first set of short options.
 * @param opts2 The second set of short options.
 */
static void check_mutually_exclusive( char const *opts1, char const *opts2 ) {
  assert( opts1 );
  assert( opts2 );

  unsigned gave_count = 0;
  char const *opt = opts1;
  char gave_opt1 = '\0';

  for ( unsigned i = 0; i < 2; ++i ) {
    for ( ; *opt; ++opt ) {
      if ( GAVE_OPTION( *opt ) ) {
        if ( ++gave_count > 1 ) {
          char const gave_opt2 = *opt;
          PMESSAGE_EXIT( EX_USAGE,
            "--%s/-%c and --%s/-%c are mutually exclusive\n",
            get_long_opt( gave_opt1 ), gave_opt1,
            get_long_opt( gave_opt2 ), gave_opt2
          );
        }
        gave_opt1 = *opt;
        break;
      }
    } // for
    if ( !gave_count )
      break;
    opt = opts2;
  } // for
}

/**
 * TODO
 *
 * @param s TODO
 * @return TODO
 */
static lang_t parse_lang( char const *s ) {
  struct lang_map {
    char const *name;
    lang_t      lang;
  };
  typedef struct lang_map lang_map_t;

  static lang_map_t const LANG_MAP[] = {
    { "knr",  LANG_C_KNR  },
    { "c89",  LANG_C_ANSI },
    { "c99",  LANG_C_99   },
    { "c++",  LANG_CXX    },
    { NULL,   LANG_NONE   },
  };

  size_t values_buf_size = 1;           // for trailing null

  for ( lang_map_t const *m = LANG_MAP; m->name; ++m ) {
    if ( strcasecmp( s, m->name ) == 0 )
      return m->lang;
    values_buf_size += strlen( m->name ) + 2 /* ", " */;
  } // for

  // name not found: construct valid name list for an error message
  char *const values_buf = (char*)free_later( MALLOC( char, values_buf_size ) );
  char *pvalues = values_buf;
  for ( lang_map_t const *m = LANG_MAP; m->name; ++m ) {
    if ( pvalues > values_buf ) {
      strcpy( pvalues, ", " );
      pvalues += 2;
    }
    strcpy( pvalues, m->name );
    pvalues += strlen( m->name );
  } // for
  PMESSAGE_EXIT( EX_USAGE,
    "\"%s\": invalid value for --%s/-%c; must be one of:\n\t%s\n",
    s, get_long_opt( 'x' ), 'x', values_buf
  );
}

/**
 * Parses command-line options.
 *
 * @param argc The argument count from \c main().
 * @param argv The argument values from \c main().
 */
static void parse_options( int argc, char const *argv[] ) {
  optind = opterr = 1;
  bool print_version = false;

  for (;;) {
    int opt = getopt_long( argc, (char**)argv, SHORT_OPTS, LONG_OPTS, NULL );
    if ( opt == -1 )
      break;
    SET_OPTION( opt );
    switch ( opt ) {
      case 'a': opt_lang              = LANG_C_ANSI;          break;
      case 'c': opt_make_c            = true;                 break;
      case 'i': opt_interactive       = true;                 break;
      case 'p': opt_lang              = LANG_C_KNR;           break;
      case '1': opt_quiet             = true;                 break;
      case 'v': print_version         = true;                 break;
      case 'x': opt_lang              = parse_lang( optarg ); break;
      default : usage();
    } // switch
  } // for

  check_mutually_exclusive( "a", "px" );
  check_mutually_exclusive( "v", "aipx" );

  if ( print_version ) {
    PRINT_ERR( "%s\n", PACKAGE_STRING );
    exit( EX_OK );
  }
}

static void usage( void ) {
  PRINT_ERR( "Usage: %s [-r|-p|-a|-+] [-ciq%s%s] [files...]\n",
    me,
#ifdef dodebug
    "d",
#else
    "",
#endif /* dodebug */
#ifdef doyydebug
    "D"
#else
    ""
#endif /* doyydebug */
  );
  PRINT_ERR( "\t-r Check against Ritchie PDP C Compiler\n");
  PRINT_ERR( "\t-p Check against Pre-ANSI C Compiler\n");
  PRINT_ERR( "\t-a Check against ANSI C Compiler%s\n",
    opt_lang == LANG_CXX ? "" : " (the default)");
  PRINT_ERR( "\t-+ Check against C++ Compiler%s\n",
    opt_lang == LANG_CXX ? " (the default)" : "");
  PRINT_ERR( "\t-c Create compilable output (include ; and {})\n");
  PRINT_ERR( "\t-i Force interactive mode\n");
  PRINT_ERR( "\t-q Quiet prompt\n");
#ifdef dodebug
  PRINT_ERR( "\t-d Turn on debugging mode\n");
#endif /* dodebug */
#ifdef doyydebug
  PRINT_ERR( "\t-D Turn on YACC debugging mode\n");
#endif /* doyydebug */
  exit( EX_USAGE );
}

////////// extern functions ///////////////////////////////////////////////////

char const* get_long_opt( char short_opt ) {
  for ( struct option const *long_opt = LONG_OPTS; long_opt->name;
        ++long_opt ) {
    if ( long_opt->val == short_opt )
      return long_opt->name;
  } // for
  assert( false );
  return NULL;                          // suppress warning (never gets here)
}

void options_init( int argc, char const *argv[] ) {
  me = base_name( argv[0] );

  if ( strcasecmp( me, "c++decl" ) == 0 ||
       strcasecmp( me, "cppdecl" ) == 0 ||
       strcasecmp( me, "cxxdecl" ) == 0 ) {
    opt_lang = LANG_CXX;
  } else {
    opt_lang = LANG_C_ANSI;
  }

  parse_options( argc, argv );
  argc -= optind, argv += optind;
  if ( argc )
    usage();

  if ( opt_fin && !(fin = fopen( opt_fin, "r" )) )
    PMESSAGE_EXIT( EX_NOINPUT, "\"%s\": %s\n", opt_fin, STRERROR );
  if ( opt_fout && !(fout = fopen( opt_fout, "w" )) )
    PMESSAGE_EXIT( EX_CANTCREAT, "\"%s\": %s\n", opt_fout, STRERROR );

  if ( !fin )
    fin = stdin;
  if ( !fout )
    fout = stdout;
}

///////////////////////////////////////////////////////////////////////////////
/* vim:set et sw=2 ts=2: */