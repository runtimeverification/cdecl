/*
**      cdecl -- C gibberish translator
**      src/diagnostics.h
**
**      Copyright (C) 2017  Paul J. Lucas, et al.
**
**      This program is free software: you can redistribute it and/or modify
**      it under the terms of the GNU General Public License as published by
**      the Free Software Foundation, either version 3 of the License, or
**      (at your option) any later version.
**
**      This program is distributed in the hope that it will be useful,
**      but WITHOUT ANY WARRANTY; without even the implied warranty of
**      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
**      GNU General Public License for more details.
**
**      You should have received a copy of the GNU General Public License
**      along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef cdecl_diagnostics_H
#define cdecl_diagnostics_H

/**
 * @file
 * Declares functions for printing error and warning messages.
 */

// local
#include "config.h"                     /* must go first */
#include "typedefs.h"                   /* for c_loc_t */

////////// extern functions ///////////////////////////////////////////////////

/**
 * Prints an error message to standard error.
 * A newline is printed.
 *
 * @param loc The location of the error.
 * @param format The \c printf() style format string.
 */
void print_error( c_loc_t const *loc, char const *format, ... );

/**
 * Prints a hint message to standard error in the form:
 *
 *      \t(did you mean _____?)\n
 *
 * @param format The \c printf() style format string.
 */
void print_hint( char const *format, ... );

/**
 * Prints the location of the error including:
 *
 *  + The error line (if neither a TTY nor interactive).
 *  + A '^' (in color, if possible and requested) under the offending token.
 *  + The error column.
 *
 * A newline is \e not printed.
 */
void print_loc( c_loc_t const *loc );

/**
 * Prints a warning message to standard error.
 * A newline is printed.
 *
 * @param loc The location of the warning.
 * @param format The \c printf() style format string.
 */
void print_warning( c_loc_t const *loc, char const *format, ... );

///////////////////////////////////////////////////////////////////////////////

#endif /* cdecl_diagnostics_H */
/* vim:set et sw=2 ts=2: */
