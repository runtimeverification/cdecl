/*
**      cdecl -- C gibberish translator
**      src/misc.h
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

#ifndef cdecl_misc_H
#define cdecl_misc_H

/**
 * @file
 * Declares miscellaneous macros and global variables.
 */

// local
#include "config.h"                     /* must go first */
#include "typedefs.h"

// standard
#include <stdbool.h>
#include <stddef.h>                     /* for size_t */

///////////////////////////////////////////////////////////////////////////////

#define CONF_FILE_NAME            "." PACKAGE "rc"
#define CPPDECL                   "c++decl"
#define DEBUG_INDENT              2     /* spaces per debug indent level */

// extern variables
extern c_mode_t     c_mode;             // parsing english or gibberish?
extern char const  *command_line;       // command from command line, if any
extern size_t       command_line_len;   // length of command_line
extern bool         is_input_a_tty;     // is our input from a tty?
extern char const  *me;                 // program name

///////////////////////////////////////////////////////////////////////////////

#endif /* cdecl_misc_H */
/* vim:set et sw=2 ts=2: */
