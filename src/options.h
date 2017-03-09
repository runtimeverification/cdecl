/*
**      cdecl -- C gibberish translator
**      src/options.h
**
**      Paul J. Lucas
*/

#ifndef cdecl_options_H
#define cdecl_options_H

/**
 * @file
 * Contains global variables and functions for command-line options.
 */

// local
#include "config.h"                     /* must go first */
#include "types.h"
#include "lang.h"                       /* for lang_t */

// standard
#include <stdbool.h>
#include <stdio.h>                      /* for FILE */

///////////////////////////////////////////////////////////////////////////////

enum explicit_int {
  EI_SHORT,
  EI_LONG,
  EI_LONG_LONG
};
typedef enum explicit_int explicit_int_t;

typedef c_type_t e_int_set_t[3];

// extern option variables
extern bool         opt_debug;
extern e_int_set_t  opt_explicit_int;
extern char const  *opt_fin;
extern char const  *opt_fout;
extern bool         opt_interactive;
extern lang_t       opt_lang;
extern bool         opt_make_c;
extern bool         opt_quiet;          // don't print the prompt

// other extern variables
extern FILE        *fin;                // file in
extern FILE        *fout;               // file out
#ifdef YYDEBUG
extern int          yydebug;            // yacc debugging
#endif /* YYDEBUG */

////////// extern functions ///////////////////////////////////////////////////

/**
 * Initializes command-line option variables.
 *
 * @param argc The argument count from \c main().
 * @param argv The argument values from \c main().
 */
void options_init( int argc, char const *argv[] );

///////////////////////////////////////////////////////////////////////////////

#endif /* cdecl_options_H */
/* vim:set et sw=2 ts=2: */
