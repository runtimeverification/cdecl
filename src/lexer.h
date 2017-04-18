/*
**      cdecl -- C gibberish translator
**      src/lexer.h
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

#ifndef cdecl_lexer_H
#define cdecl_lexer_H

/**
 * @file
 * Declares global variables and functions interacting with the lexical
 * analyzer.
 */

// local
#include "config.h"                     /* must go first */

// standard
#include <stdbool.h>
#include <stddef.h>                     /* for size_t */

///////////////////////////////////////////////////////////////////////////////

// extern variables
extern char const  *lexer_token;        // text of current token

/**
 * Gets the lexer's current column number.
 *
 * @return Returns said column.
 */
size_t lexer_column( void );

/**
 * Gets the current input line.
 *
 * @param plen If not null, sets the value pointed at to be the length of said
 * line.
 * @return Returns said line.
 */
char const* lexer_input_line( size_t *plen );

/**
 * Resets the lexer to its initial state.
 *
 * @param hard_reset If \c true, does a "hard" reset that currently resets the
 * EOF flag also.
 */
void lexer_reset( bool hard_reset );

/**
 * Gets the next token.
 *
 * @return Returns the number of the current token or 0 if end-of-file.
 *
 * @note The code for this function is generated by flex and called by
 * yyparse() generated by bison.
 */
int yylex( void );

///////////////////////////////////////////////////////////////////////////////

#endif /* cdecl_lexer_H */
/* vim:set et sw=2 ts=2: */
