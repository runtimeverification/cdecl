/*
**      cdecl -- C gibberish translator
**      src/parser.y
*/

%{
// local
#include "config.h"                     /* must come first */
#include "ast.h"
#include "ast_util.h"
#include "color.h"
#include "common.h"
#include "keywords.h"
#include "lang.h"
#include "literals.h"
#include "options.h"
#include "types.h"
#include "util.h"

// standard
#include <assert.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

///////////////////////////////////////////////////////////////////////////////

#ifdef WITH_CDECL_DEBUG
#define CDEBUG(...) BLOCK( if ( opt_debug ) { __VA_ARGS__ } )
#else
#define CDEBUG(...)                     /* nothing */
#endif /* WITH_CDECL_DEBUG */

#define C_AST_CHECK(AST,CHECK) BLOCK( \
  if ( !c_ast_check( (AST), (CHECK) ) ) PARSE_CLEANUP(); )

#define C_TYPE_ADD(DST,SRC,LOC) BLOCK( \
  if ( !c_type_add( (DST), (SRC), &(LOC) ) ) PARSE_CLEANUP(); )

#define C_TYPE_CHECK(TYPE,LOC) BLOCK( \
  if ( !c_type_check( TYPE, &(LOC) ) ) PARSE_CLEANUP(); )

#define DUMP_COMMA \
  CDEBUG( if ( true_or_set( &dump_comma ) ) FPUTS( ",\n", stdout ); )

#define DUMP_AST(KEY,AST) \
  CDEBUG( DUMP_COMMA; c_ast_json( (AST), 1, (KEY), stdout ); )

#define DUMP_AST_LIST(KEY,AST_LIST) CDEBUG(           \
  DUMP_COMMA; FPRINTF( stdout, "  \"%s\": ", (KEY) ); \
  c_ast_list_json( &(AST_LIST), 1, stdout ); )

#define DUMP_NAME(KEY,NAME) CDEBUG(         \
  DUMP_COMMA; FPUTS( "  ", stdout );        \
  json_print_kv( (KEY), (NAME), stdout ); )

#define DUMP_NUM(KEY,NUM) \
  CDEBUG( DUMP_COMMA; FPRINTF( stdout, "  \"" KEY "\": %d", (NUM) ); )

#ifdef WITH_CDECL_DEBUG
#define DUMP_START(NAME,PROD)               \
  bool dump_comma = false;                  \
  CDEBUG( FPUTS( "\n\"" NAME ": " PROD "\": {\n", stdout ); )
#else
#define DUMP_START(NAME,PROD)           /* nothing */
#endif

#define DUMP_END() CDEBUG( \
  FPUTS( "\n}\n", stdout ); )

#define DUMP_TYPE(KEY,TYPE) CDEBUG(         \
  DUMP_COMMA; FPUTS( "  ", stdout );        \
  json_print_kv( (KEY), c_type_name( TYPE ), stdout ); )

#define PARSE_CLEANUP()   BLOCK( parse_cleanup(); yyclearin; yyerrok; YYABORT; )
#define PARSE_ERROR(...)  BLOCK( parse_error( __VA_ARGS__ ); PARSE_CLEANUP(); )

///////////////////////////////////////////////////////////////////////////////

typedef struct qualifier_link qualifier_link_t;

/**
 * A simple \c struct "derived" from \c link that additionally holds a
 * qualifier and its source location.
 */
struct qualifier_link /* : link */ {
  qualifier_link_t *next;               // must be first struct member
  c_type_t          qualifier;          // T_CONST, T_RESTRICT, or T_VOLATILE
  YYLTYPE           loc;
};

/**
 * Inherited attributes.
 */
struct in_attr {
  qualifier_link_t *qualifier_head;
  c_ast_t *type_ast;
};
typedef struct in_attr in_attr_t;

// extern functions
extern void         print_help( void );
extern void         set_option( char const* );
extern int          yylex();

// local variables
static in_attr_t    in_attr;
static bool         newlined = true;
static unsigned     ast_depth;

// local functions
static void         qualifier_clear( void );

////////// inline functions ///////////////////////////////////////////////////

/**
 * Peeks at the type AST at the head of the type AST inherited attribute stack.
 *
 * @return Returns said AST.
 */
static inline c_ast_t* type_peek( void ) {
  return in_attr.type_ast;
}

/**
 * Pops a type AST from the type AST inherited attribute stack.
 *
 * @return Returns said AST.
 */
static inline c_ast_t* type_pop( void ) {
  return LINK_POP( c_ast_t, &in_attr.type_ast );
}

/**
 * Pushes a type AST onto the type AST inherited attribute stack.
 *
 * @param ast The AST to push.
 */
static inline void type_push( c_ast_t *ast ) {
  LINK_PUSH( &in_attr.type_ast, ast );
}

/**
 * Peeks at the qualifier at the head of the qualifier inherited attribute
 * stack.
 *
 * @return Returns said qualifier.
 */
static inline c_type_t qualifier_peek( void ) {
  return in_attr.qualifier_head->qualifier;
}

/**
 * Peeks at the location of the qualifier at the head of the qualifier
 * inherited attribute stack.
 *
 * @return Returns said qualifier location.
 * @hideinitializer
 */
#define qualifier_peek_loc() \
  (in_attr.qualifier_head->loc)

/**
 * Pops a qualifier from the head of the qualifier inherited attribute stack
 * and frees it.
 */
static inline void qualifier_pop( void ) {
  FREE( LINK_POP( qualifier_link_t, &in_attr.qualifier_head ) );
}

////////// local functions ////////////////////////////////////////////////////

/**
 * Cleans-up parser data.
 */
static void parse_cleanup( void ) {
  c_ast_gc();
  qualifier_clear();
  memset( &in_attr, 0, sizeof in_attr );
}

/**
 * Prints a parsing error message to standard error.
 *
 * @param format A \c printf() style format string.
 */
static void parse_error( char const *format, ... ) {
  if ( !newlined ) {
    PRINT_ERR( ": " );
    if ( *yytext )
      PRINT_ERR( "\"%s\": ", (*yytext == '\n' ? "\\n" : yytext) );
    va_list args;
    va_start( args, format );
    vfprintf( stderr, format, args );
    va_end( args );
    PRINT_ERR( "\n" );
    newlined = true;
  }
}

/**
 * Clears the qualifier stack.
 */
static void qualifier_clear( void ) {
  qualifier_link_t *q;
  while ( (q = LINK_POP( qualifier_link_t, &in_attr.qualifier_head )) )
    FREE( q );
}

/**
 * Pushed a quaifier onto the front of the qualifier inherited attribute list.
 *
 * @param qualifier The qualifier to push.
 * @param loc A pointer to the source location of the qualifier.
 */
static void qualifier_push( c_type_t qualifier, YYLTYPE const *loc ) {
  assert( (qualifier & ~T_MASK_QUALIFIER) == 0 );
  assert( loc );
  qualifier_link_t *const q = MALLOC( qualifier_link_t, 1 );
  q->qualifier = qualifier;
  q->loc = *loc;
  q->next = NULL;
  LINK_PUSH( &in_attr.qualifier_head, q );
}

/**
 * Implements the cdecl "quit" command.
 */
static void quit( void ) {
  exit( EX_OK );
}

/**
 * Called by bison to print a parsing error message.
 *
 * @param msg The error message to print.
 */
static void yyerror( char const *msg ) {
  print_caret( CARET_CURRENT_LEX_COL );
  PRINT_ERR( "%s%d: ", (newlined ? "" : "\n"), error_column() + 1 );
  SGR_START_COLOR( stderr, error );
  FPUTS( msg, stderr );
  SGR_END_COLOR( stderr );
  newlined = false;
  parse_cleanup();
}

///////////////////////////////////////////////////////////////////////////////
%}

%union {
  c_ast_list_t  ast_list; /* for function arguments */
  c_ast_pair_t  ast_pair; /* for the AST being built */
  char const   *name;     /* name being declared or explained */
  int           number;   /* for array sizes */
  c_type_t      type;     /* built-in types, storage classes, & qualifiers */
}

                    /* commands */
%token              Y_CAST
%token              Y_DECLARE
%token              Y_EXPLAIN
%token              Y_HELP
%token              Y_SET
%token              Y_QUIT

                    /* english */
%token              Y_ARRAY
%token              Y_AS
%token              Y_BLOCK             /* Apple: English for '^' */
%token              Y_FUNCTION
%token              Y_INTO
%token              Y_MEMBER
%token              Y_OF
%token              Y_POINTER
%token              Y_REFERENCE
%token              Y_RETURNING
%token              Y_TO

                    /* K&R C */
%token              ','
%token              '*'
%token              '[' ']'
%token              '(' ')'
%token  <type>      Y_AUTO
%token  <type>      Y_CHAR
%token  <type>      Y_DOUBLE
%token  <type>      Y_EXTERN
%token  <type>      Y_FLOAT
%token  <type>      Y_INT
%token  <type>      Y_LONG
%token  <type>      Y_REGISTER
%token  <type>      Y_SHORT
%token  <type>      Y_STATIC
%token  <type>      Y_STRUCT
%token  <type>      Y_TYPEDEF
%token  <type>      Y_UNION
%token  <type>      Y_UNSIGNED

                    /* C89 */
%token  <type>      Y_CONST
%token  <type>      Y_ENUM
%token  <type>      Y_SIGNED
%token  <type>      Y_VOID
%token  <type>      Y_VOLATILE

                    /* C99 */
%token  <type>      Y_BOOL
%token  <type>      Y_COMPLEX
%token  <type>      Y_RESTRICT
%token  <type>      Y_WCHAR_T

                    /* C11 */
%token              Y_NORETURN
%token  <type>      Y_THREAD_LOCAL

                    /* C++ */
%token              '&'
%token  <type>      Y_CLASS
%token              Y_COLON_COLON

                    /* C11 & C++11 */
%token  <type>      Y_CHAR16_T
%token  <type>      Y_CHAR32_T

                    /* miscellaneous */
%token              '^'                 /* Apple: block indicator */
%token  <type>      Y___BLOCK           /* Apple: block storage class */
%token              Y_END
%token              Y_ERROR
%token  <name>      Y_NAME
%token  <number>    Y_NUMBER

%type   <ast_pair>  decl_english
%type   <ast_list>  decl_list_english decl_list_opt_english
%type   <ast_list>  paren_decl_list_opt_english
%type   <ast_pair>  array_decl_english
%type   <number>    array_size_opt_english
%type   <ast_pair>  block_decl_english
%type   <ast_pair>  func_decl_english
%type   <ast_pair>  pointer_decl_english
%type   <ast_pair>  pointer_to_member_decl_english
%type   <ast_pair>  qualifiable_decl_english
%type   <ast_pair>  qualified_decl_english
%type   <ast_pair>  reference_decl_english
%type   <ast_pair>  returning_english
%type   <type>      storage_class_opt_english
%type   <ast_pair>  type_english
%type   <type>      type_modifier_english
%type   <type>      type_modifier_list_english
%type   <type>      type_modifier_list_opt_english
%type   <ast_pair>  unmodified_type_english
%type   <ast_pair>  var_decl_english

%type   <ast_pair>  cast_c cast2_c
%type   <ast_pair>  array_cast_c
%type   <ast_pair>  block_cast_c
%type   <ast_pair>  func_cast_c
%type   <ast_pair>  nested_cast_c
%type   <ast_pair>  pointer_cast_c
%type   <ast_pair>  pointer_to_member_cast_c
%type   <ast_pair>  reference_cast_c

%type   <ast_pair>  decl_c decl2_c
%type   <ast_pair>  array_decl_c
%type   <ast_pair>  block_decl_c
%type   <ast_pair>  func_decl_c
%type   <ast_pair>  name_c
%type   <ast_pair>  named_enum_class_struct_union_type_c
%type   <ast_pair>  nested_decl_c
%type   <ast_pair>  pointer_decl_c
%type   <ast_pair>  pointer_type_c
%type   <ast_pair>  pointer_to_member_decl_c
%type   <ast_pair>  pointer_to_member_type_c
%type   <ast_pair>  reference_decl_c
%type   <ast_pair>  reference_type_c

%type   <ast_pair>  type_c
%type   <ast_pair>  placeholder_type_c
%type   <type>      builtin_type_c
%type   <type>      class_struct_type_c
%type   <type>      enum_class_struct_union_type_c
%type   <type>      storage_class_c
%type   <type>      type_modifier_c
%type   <type>      type_modifier_list_c type_modifier_list_opt_c
%type   <type>      type_qualifier_c
%type   <type>      type_qualifier_list_opt_c

%type   <ast_pair>  arg_c
%type   <ast_list>  arg_list_c arg_list_opt_c
%type   <number>    array_size_c
%type   <name>      name_opt

/*****************************************************************************/
%%

command_list
  : /* empty */
  | command_list command_init command command_cleanup
  ;

command_init
  : /* empty */
    {
      if ( !newlined ) {
        FPUTC( '\n', fout );
        newlined = true;
      }
    }
  ;

command
  : cast_english
  | declare_english
  | explain_declaration_c
  | explain_cast_c
  | help_command
  | set_command
  | quit_command
  | Y_END
  | error Y_END
    {
      PARSE_ERROR( "unexpected token" );
    }
  ;

command_cleanup
  : /* empty */
    {
      parse_cleanup();
    }
  ;

/*****************************************************************************/
/*  cast                                                                     */
/*****************************************************************************/

cast_english
  : Y_CAST Y_NAME Y_INTO decl_english Y_END
    {
      DUMP_START( "cast_english", "CAST NAME INTO decl_english" );
      DUMP_NAME( "> NAME", $2 );
      DUMP_AST( "> decl_english", $4.top_ast );
      DUMP_END();

      C_AST_CHECK( $4.top_ast, CHECK_CAST );
      FPUTC( '(', fout );
      c_ast_gibberish_cast( $4.top_ast, fout );
      FPRINTF( fout, ")%s\n", $2 );
      FREE( $2 );
    }

  | Y_CAST decl_english Y_END
    {
      DUMP_START( "cast_english", "CAST decl_english" );
      DUMP_AST( "> decl_english", $2.top_ast );
      DUMP_END();

      C_AST_CHECK( $2.top_ast, CHECK_CAST );
      FPUTC( '(', fout );
      c_ast_gibberish_cast( $2.top_ast, fout );
      FPUTS( ")\n", fout );
    }
  ;

/*****************************************************************************/
/*  declare                                                                  */
/*****************************************************************************/

declare_english
  : Y_DECLARE Y_NAME Y_AS storage_class_opt_english decl_english Y_END
    {
      DUMP_START( "declare_english",
                  "DECLARE NAME AS storage_class_opt_english decl_english" );
      $5.top_ast->name = $2;
      DUMP_NAME( "> NAME", $2 );
      DUMP_TYPE( "> storage_class_opt_english", $4 );
      DUMP_AST( "> decl_english", $5.top_ast );
      DUMP_END();

      C_TYPE_ADD( &$5.top_ast->type, $4, @4 );
      C_AST_CHECK( $5.top_ast, CHECK_DECL );
      c_ast_gibberish_declare( $5.top_ast, fout );
      FPUTC( '\n', fout );
    }

  | Y_DECLARE error Y_AS
    {
      PARSE_ERROR( "name expected" );
    }
  ;

storage_class_opt_english
  : /* empty */                   { $$ = T_NONE; }
  | storage_class_c
  | Y_REGISTER
  ;

/*****************************************************************************/
/*  explain                                                                  */
/*****************************************************************************/

explain_declaration_c
  : Y_EXPLAIN type_c { type_push( $2.top_ast ); } decl_c Y_END
    {
      type_pop();

      DUMP_START( "explain_declaration_c", "EXPLAIN type_c decl_c" );
      DUMP_AST( "> type_c", $2.top_ast );
      DUMP_AST( "> decl_c", $4.top_ast );
      DUMP_END();

      c_ast_t *const ast = c_ast_patch_none( $2.top_ast, $4.top_ast );
      C_AST_CHECK( ast, CHECK_DECL );
      char const *const name = c_ast_take_name( ast );
      assert( name );
      FPRINTF( fout, "%s %s %s ", L_DECLARE, name, L_AS );
      if ( c_ast_take_typedef( ast ) )
        FPRINTF( fout, "%s ", L_TYPE );
      c_ast_english( ast, fout );
      FPUTC( '\n', fout );
      FREE( name );
    }
  ;

explain_cast_c
  : Y_EXPLAIN '(' type_c { type_push( $3.top_ast ); } cast_c ')' name_opt Y_END
    {
      type_pop();

      DUMP_START( "explain_cast_t",
                  "EXPLAIN '(' type_c cast_c ')' name_opt" );
      DUMP_AST( "> type_c", $3.top_ast );
      DUMP_AST( "> cast_c", $5.top_ast );
      DUMP_NAME( "> name_opt", $7 );
      DUMP_END();

      c_ast_t *const ast = c_ast_patch_none( $3.top_ast, $5.top_ast );
      C_AST_CHECK( ast, CHECK_CAST );
      FPUTS( L_CAST, fout );
      if ( $7 ) {
        FPRINTF( fout, " %s", $7 );
        FREE( $7 );
      }
      FPRINTF( fout, " %s ", L_INTO );
      c_ast_english( ast, fout );
      FPUTC( '\n', fout );
    }
  ;

/*****************************************************************************/
/*  help                                                                     */
/*****************************************************************************/

help_command
  : Y_HELP Y_END                  { print_help(); }
  ;

/*****************************************************************************/
/*  set                                                                      */
/*****************************************************************************/

set_command
  : Y_SET name_opt Y_END          { set_option( $2 ); FREE( $2 ); }
  ;

/*****************************************************************************/
/*  quit                                                                     */
/*****************************************************************************/

quit_command
  : Y_QUIT Y_END                  { quit(); }
  ;

/*****************************************************************************/
/*  declaration english productions                                          */
/*****************************************************************************/

decl_english
  : array_decl_english
  | func_decl_english
  | qualified_decl_english
  | var_decl_english
  ;

array_decl_english
  : Y_ARRAY array_size_opt_english Y_OF decl_english
    {
      DUMP_START( "array_decl_english",
                  "ARRAY array_size_opt_english OF decl_english" );
      DUMP_NUM( "> array_size_opt_english", $2 );
      DUMP_AST( "> decl_english", $4.top_ast );

      $$.top_ast = c_ast_new( K_ARRAY, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->as.array.size = $2;
      c_ast_set_parent( $4.top_ast, $$.top_ast );

      DUMP_AST( "< array_decl_english", $$.top_ast );
      DUMP_END();
    }
  ;

array_size_opt_english
  : /* empty */                   { $$ = C_ARRAY_NO_SIZE; }
  | Y_NUMBER
  | error                         { PARSE_ERROR( "array size expected" ); }
  ;

block_decl_english                      /* Apple extension */
  : Y_BLOCK paren_decl_list_opt_english returning_english
    {
      DUMP_START( "block_decl_english",
                  "BLOCK paren_decl_list_opt_english returning_english" );
      DUMP_TYPE( "^ qualifier", qualifier_peek() );
      DUMP_AST_LIST( "> paren_decl_list_opt_english", $2 );
      DUMP_AST( "> returning_english", $3.top_ast );

      $$.top_ast = c_ast_new( K_BLOCK, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->type = qualifier_peek();
      c_ast_set_parent( $3.top_ast, $$.top_ast );
      $$.top_ast->as.block.args = $2;

      DUMP_AST( "< block_decl_english", $$.top_ast );
      DUMP_END();
    }
  ;

func_decl_english
  : Y_FUNCTION paren_decl_list_opt_english returning_english
    {
      DUMP_START( "func_decl_english",
                  "FUNCTION paren_decl_list_opt_english returning_english" );
      DUMP_AST_LIST( "> decl_list_opt_english", $2 );
      DUMP_AST( "> returning_english", $3.top_ast );

      $$.top_ast = c_ast_new( K_FUNCTION, ast_depth, &@$ );
      $$.target_ast = NULL;
      c_ast_set_parent( $3.top_ast, $$.top_ast );
      $$.top_ast->as.func.args = $2;

      DUMP_AST( "< func_decl_english", $$.top_ast );
      DUMP_END();
    }
  ;

paren_decl_list_opt_english
  : /* empty */                   { $$.head_ast = $$.tail_ast = NULL; }
  | '(' decl_list_opt_english ')'
    {
      DUMP_START( "paren_decl_list_opt_english",
                  "'(' decl_list_opt_english ')'" );
      DUMP_AST_LIST( "> decl_list_opt_english", $2 );

      $$ = $2;

      DUMP_AST_LIST( "< paren_decl_list_opt_english", $$ );
      DUMP_END();
    }
  ;

decl_list_opt_english
  : /* empty */                   { $$.head_ast = $$.tail_ast = NULL; }
  | decl_list_english
  ;

decl_list_english
  : decl_english                  { $$.head_ast = $$.tail_ast = $1.top_ast; }
  | decl_list_english expect_comma decl_english
    {
      DUMP_START( "decl_list_opt_english",
                  "decl_list_opt_english ',' decl_english" );
      DUMP_AST_LIST( "> decl_list_opt_english", $1 );
      DUMP_AST( "> decl_english", $3.top_ast );

      $$ = $1;
      c_ast_list_append( &$$, $3.top_ast );

      DUMP_AST_LIST( "< decl_list_opt_english", $$ );
      DUMP_END();
    }
  ;

returning_english
  : Y_RETURNING decl_english
    {
      DUMP_START( "returning_english", "RETURNING decl_english" );
      DUMP_AST( "> decl_english", $2.top_ast );

      $$ = $2;

      DUMP_AST( "< returning_english", $$.top_ast );
      DUMP_END();
    }

  | error { PARSE_ERROR( "\"%s\" expected", L_RETURNING ); }
  ;

qualified_decl_english
  : type_qualifier_list_opt_c { qualifier_push( $1, &@1 ); }
    qualifiable_decl_english
    {
      qualifier_pop();
      DUMP_START( "qualified_decl_english",
                  "type_qualifier_list_opt_c qualifiable_decl_english" );
      DUMP_TYPE( "> type_qualifier_list_opt_c", $1 );
      DUMP_AST( "> qualifiable_decl_english", $3.top_ast );

      $$ = $3;

      DUMP_AST( "< qualified_decl_english", $$.top_ast );
      DUMP_END();
    }
  ;

qualifiable_decl_english
  : block_decl_english
  | pointer_decl_english
  | pointer_to_member_decl_english
  | reference_decl_english
  | type_english
  ;

pointer_decl_english
  : pointer_to decl_english
    {
      DUMP_START( "pointer_decl_english", "POINTER TO decl_english" );
      DUMP_TYPE( "^ qualifier", qualifier_peek() );
      DUMP_AST( "> decl_english", $2.top_ast );

      $$.top_ast = c_ast_new( K_POINTER, ast_depth, &@$ );
      $$.target_ast = NULL;
      c_ast_set_parent( $2.top_ast, $$.top_ast );
      $$.top_ast->as.ptr_ref.qualifier = qualifier_peek();

      DUMP_AST( "< pointer_decl_english", $$.top_ast );
      DUMP_END();
    }
  ;

pointer_to
  : Y_POINTER Y_TO
  | Y_POINTER error
    {
      PARSE_ERROR( "\"%s\" expected", L_TO );
    }
  ;

pointer_to_member_decl_english
  : pointer_to Y_MEMBER Y_OF class_struct_type_c Y_NAME decl_english
    {
      DUMP_START( "pointer_to_member_decl_english",
                  "POINTER TO MEMBER OF "
                  "class_struct_type_c NAME decl_english" );
      DUMP_TYPE( "^ qualifier", qualifier_peek() );
      DUMP_TYPE( "> class_struct_type_c", $4 );
      DUMP_NAME( "> NAME", $5 );
      DUMP_AST( "> decl_english", $6.top_ast );

      if ( opt_lang < LANG_CPP_MIN )
        print_warning( &@$, "pointer to member of class" );

      $$.top_ast = c_ast_new( K_POINTER_TO_MEMBER, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->type = $4;
      c_ast_set_parent( $6.top_ast, $$.top_ast );
      $$.top_ast->as.ptr_ref.qualifier = qualifier_peek();
      $$.top_ast->as.ptr_mbr.class_name = $5;

      DUMP_AST( "< pointer_to_member_decl_english", $$.top_ast );
      DUMP_END();
    }

  | pointer_to error
    {
      PARSE_ERROR( "\"%s\" expected", L_MEMBER );
    }

  | pointer_to Y_MEMBER error
    {
      PARSE_ERROR( "\"%s\" expected", L_OF );
    }

  | pointer_to Y_MEMBER Y_OF error
    {
      PARSE_ERROR(
        "\"%s\", \"%s\", or \"%s\" expected", L_CLASS, L_STRUCT, L_UNION
      );
    }

  | pointer_to Y_MEMBER Y_OF class_struct_type_c error
    {
      PARSE_ERROR(
        "\"%s\", \"%s\", or \"%s\" name expected",
        L_CLASS, L_STRUCT, L_UNION
      );
    }
  ;

reference_decl_english
  : Y_REFERENCE Y_TO decl_english
    {
      DUMP_START( "reference_decl_english", "REFERENCE TO decl_english" );
      DUMP_TYPE( "^ qualifier", qualifier_peek() );
      DUMP_AST( "> decl_english", $3.top_ast );

      if ( opt_lang < LANG_CPP_MIN )
        print_warning( &@$, "reference" );

      $$.top_ast = c_ast_new( K_REFERENCE, ast_depth, &@$ );
      $$.target_ast = NULL;
      c_ast_set_parent( $3.top_ast, $$.top_ast );
      $$.top_ast->as.ptr_ref.qualifier = qualifier_peek();

      DUMP_AST( "< reference_decl_english", $$.top_ast );
      DUMP_END();
    }

  | Y_REFERENCE error
    {
      PARSE_ERROR( "\"%s\" expected", L_TO );
    }
  ;

var_decl_english
  : Y_NAME Y_AS decl_english
    {
      DUMP_START( "var_decl_english", "NAME AS decl_english" );
      DUMP_NAME( "> NAME", $1 );
      DUMP_AST( "> decl_english", $3.top_ast );

      $$ = $3;
      assert( $$.top_ast->name == NULL );
      $$.top_ast->name = $1;

      DUMP_AST( "< var_decl_english", $$.top_ast );
      DUMP_END();
    }

  | Y_NAME                              /* K&R C type-less variable */
    {
      DUMP_START( "var_decl_english", "NAME" );
      DUMP_NAME( "> NAME", $1 );

      if ( opt_lang > LANG_C_KNR )
        print_warning( &@$, "missing function prototype" );

      $$.top_ast = c_ast_new( K_NAME, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->name = $1;

      DUMP_AST( "< var_decl_english", $$.top_ast );
      DUMP_END();
    }
  ;

/*****************************************************************************/
/*  type english productions                                                 */
/*****************************************************************************/

type_english
  : type_modifier_list_opt_english unmodified_type_english
    {
      DUMP_START( "type_english",
                  "type_modifier_list_opt_english unmodified_type_english" );
      DUMP_TYPE( "^ qualifier", qualifier_peek() );
      DUMP_TYPE( "> type_modifier_list_opt_english", $1 );
      DUMP_AST( "> unmodified_type_english", $2.top_ast );

      $$ = $2;
      C_TYPE_ADD( &$$.top_ast->type, qualifier_peek(), qualifier_peek_loc() );
      C_TYPE_ADD( &$$.top_ast->type, $1, @1 );

      DUMP_AST( "< type_english", $$.top_ast );
      DUMP_END();
    }

  | type_modifier_list_english          /* allows for default int type */
    {
      DUMP_START( "type_english", "type_modifier_list_english" );
      DUMP_TYPE( "> type_modifier_list_english", $1 );

      $$.top_ast = c_ast_new( K_BUILTIN, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->type = T_INT;
      C_TYPE_ADD( &$$.top_ast->type, $1, @1 );

      DUMP_AST( "< type_english", $$.top_ast );
      DUMP_END();
    }
  ;

type_modifier_list_opt_english
  : /* empty */                   { $$ = T_NONE; }
  | type_modifier_list_english
  ;

type_modifier_list_english
  : type_modifier_list_opt_english type_modifier_english
    {
      DUMP_START( "type_modifier_list_opt_english",
                  "type_modifier_list_opt_english type_modifier_english" );
      DUMP_TYPE( "> type_modifier_list_opt_english", $1 );
      DUMP_TYPE( "> type_modifier_english", $2 );

      $$ = $1;
      C_TYPE_ADD( &$$, $2, @2 );

      DUMP_TYPE( "< type_modifier_list_opt_english", $$ );
      DUMP_END();
    }

  | type_modifier_english
  ;

type_modifier_english
  : Y_COMPLEX
  | Y_LONG
  | Y_SHORT
  | Y_SIGNED
  | Y_UNSIGNED
  /*
   * Register is here (rather than in storage_class_c) because it's the only
   * storage class that can be specified for function arguments.  Therefore,
   * it's simpler to treat it as any other type modifier.
   */
  | Y_REGISTER
  ;

unmodified_type_english
  : builtin_type_c
    {
      DUMP_START( "unmodified_type_english", "builtin_type_c" );
      DUMP_TYPE( "> builtin_type_c", $1 );

      $$.top_ast = c_ast_new( K_BUILTIN, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->type = $1;

      DUMP_AST( "< unmodified_type_english", $$.top_ast );
      DUMP_END();
    }

  | enum_class_struct_union_type_c
    {
      DUMP_START( "unmodified_type_english", "enum_class_struct_union_type_c" );
      DUMP_TYPE( "> enum_class_struct_union_type_c", $1 );

      $$.top_ast = c_ast_new( K_ENUM_CLASS_STRUCT_UNION, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->type = $1;

      DUMP_AST( "< unmodified_type_english", $$.top_ast );
      DUMP_END();
    }
  ;

/*****************************************************************************/
/*  declaration gibberish productions                                        */
/*****************************************************************************/

decl_c
  : decl2_c
  | pointer_decl_c
  | pointer_to_member_decl_c
  | reference_decl_c
  ;

decl2_c
  : array_decl_c
  | block_decl_c
  | func_decl_c
  | name_c
  | nested_decl_c
  ;

array_decl_c
  : decl2_c array_size_c
    {
      DUMP_START( "array_decl_c", "decl2_c array_size_c" );
      DUMP_AST( "^ type_c", type_peek() );
      DUMP_AST( "> decl2_c", $1.top_ast );
      DUMP_NUM( "> array_size_c", $2 );
      if ( $1.target_ast )
        DUMP_AST( "> target_ast", $1.target_ast );

      c_ast_t *const array = c_ast_new( K_ARRAY, ast_depth, &@$ );
      array->as.array.size = $2;
      c_ast_set_parent( c_ast_new( K_NONE, ast_depth, &@1 ), array );
      if ( $1.target_ast ) {
        $$.top_ast = $1.top_ast;
        $$.target_ast = c_ast_add_array( $1.target_ast, array );
      } else {
        $$.top_ast = c_ast_add_array( $1.top_ast, array );
        $$.target_ast = NULL;
      }

      DUMP_AST( "< array_decl_c", $$.top_ast );
      DUMP_END();
    }
  ;

block_decl_c                            /* Apple extension */
  : /* type */ '(' '^'
    {
      //
      // A block AST has to be the type inherited attribute for decl_c so we
      // have to create it here.
      //
      type_push( c_ast_new( K_BLOCK, ast_depth, &@$ ) );
    }
    type_qualifier_list_opt_c decl_c ')' '(' arg_list_opt_c ')'
    {
      c_ast_t *const block = type_pop();

      DUMP_START( "block_decl_c",
                  "'(' '^' type_qualifier_list_opt_c decl_c ')' "
                  "'(' arg_list_opt_c ')'" );
      DUMP_AST( "^ type_c", type_peek() );
      DUMP_TYPE( "> type_qualifier_list_opt_c", $4 );
      DUMP_AST( "> decl_c", $5.top_ast );
      DUMP_AST_LIST( "> arg_list_opt_c", $8 );

      C_TYPE_ADD( &block->type, $4, @4 );
      block->as.block.args = $8;
      $$.top_ast = c_ast_add_func( $5.top_ast, type_peek(), block );
      $$.target_ast = block->as.block.ret_ast;

      DUMP_AST( "< block_decl_c", $$.top_ast );
      DUMP_END();
    }
  ;

func_decl_c
  : /* type_c */ decl2_c '(' arg_list_opt_c ')'
    {
      DUMP_START( "func_decl_c", "decl2_c '(' arg_list_opt_c ')'" );
      DUMP_AST( "^ type_c", type_peek() );
      DUMP_AST( "> decl2_c", $1.top_ast );
      DUMP_AST_LIST( "> arg_list_opt_c", $3 );

      c_ast_t *const func = c_ast_new( K_FUNCTION, ast_depth, &@$ );
      func->as.func.args = $3;
      $$.top_ast = c_ast_add_func( $1.top_ast, type_peek(), func );
      $$.target_ast = func->as.func.ret_ast;

      DUMP_AST( "< func_decl_c", $$.top_ast );
      DUMP_END();
    }
  ;

name_c
  : /* type_c */ Y_NAME
    {
      DUMP_START( "name_c", "NAME" );
      DUMP_AST( "^ type_c", type_peek() );
      DUMP_NAME( "> NAME", $1 );

      $$.top_ast = type_peek();
      $$.target_ast = NULL;
      assert( $$.top_ast->name == NULL );
      $$.top_ast->name = $1;

      DUMP_AST( "< name_c", $$.top_ast );
      DUMP_END();
    }
  ;

nested_decl_c
  : '(' placeholder_type_c { type_push( $2.top_ast ); ++ast_depth; } decl_c ')'
    {
      type_pop();
      --ast_depth;

      DUMP_START( "nested_decl_c", "'(' placeholder_type_c decl_c ')'" );
      DUMP_AST( "> placeholder_type_c", $2.top_ast );
      DUMP_AST( "> decl_c", $4.top_ast );

      $$ = $4;

      DUMP_AST( "< nested_decl_c", $$.top_ast );
      DUMP_END();
    }
  ;

placeholder_type_c
  : /* empty */
    {
      $$.top_ast = c_ast_new( K_NONE, ast_depth, &@$ );
      $$.target_ast = NULL;
    }
  ;

pointer_decl_c
  : pointer_type_c { type_push( $1.top_ast ); } decl_c
    {
      type_pop();
      DUMP_START( "pointer_decl_c", "pointer_type_c decl_c" );
      DUMP_AST( "> pointer_type_c", $1.top_ast );
      DUMP_AST( "> decl_c", $3.top_ast );

      (void)c_ast_patch_none( $1.top_ast, $3.top_ast );
      $$ = $3;

      DUMP_AST( "< pointer_decl_c", $$.top_ast );
      DUMP_END();
    }
  ;

pointer_type_c
  : /* type_c */ '*' type_qualifier_list_opt_c
    {
      DUMP_START( "pointer_type_c", "'*' type_qualifier_list_opt_c" );
      DUMP_AST( "^ type_c", type_peek() );
      DUMP_TYPE( "> type_qualifier_list_opt_c", $2 );

      $$.top_ast = c_ast_new( K_POINTER, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->as.ptr_ref.qualifier = $2;
      c_ast_set_parent( type_peek(), $$.top_ast );

      DUMP_AST( "< pointer_type_c", $$.top_ast );
      DUMP_END();
    }
  ;

pointer_to_member_decl_c
  : pointer_to_member_type_c { type_push( $1.top_ast ); } decl_c
    {
      type_pop();
      DUMP_START( "pointer_to_member_decl_c",
                  "pointer_to_member_type_c decl_c" );
      DUMP_AST( "> pointer_to_member_type_c", $1.top_ast );
      DUMP_AST( "> decl_c", $3.top_ast );

      $$ = $3;

      DUMP_AST( "< pointer_to_member_decl_c", $$.top_ast );
      DUMP_END();
    }
  ;

pointer_to_member_type_c
  : /* type_c */ Y_NAME Y_COLON_COLON expect_star
    {
      DUMP_START( "pointer_to_member_type_c", "NAME COLON_COLON '*'" );
      DUMP_AST( "^ type_c", type_peek() );
      DUMP_NAME( "> NAME", $1 );

      $$.top_ast = c_ast_new( K_POINTER_TO_MEMBER, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->type = T_CLASS;
      $$.top_ast->as.ptr_mbr.class_name = $1;
      c_ast_set_parent( type_peek(), $$.top_ast );

      DUMP_AST( "< pointer_to_member_type_c", $$.top_ast );
      DUMP_END();
    }
  ;

reference_decl_c
  : reference_type_c { type_push( $1.top_ast ); } decl_c
    {
      type_pop();
      DUMP_START( "reference_decl_c", "reference_type_c decl_c" );
      DUMP_AST( "> reference_type_c", $1.top_ast );
      DUMP_AST( "> decl_c", $3.top_ast );

      $$ = $3;

      DUMP_AST( "< reference_decl_c", $$.top_ast );
      DUMP_END();
    }
  ;

reference_type_c
  : /* type_c */ '&' type_qualifier_list_opt_c
    {
      DUMP_START( "reference_type_c", "'&' type_qualifier_list_opt_c" );
      DUMP_AST( "^ type_c", type_peek() );
      DUMP_TYPE( "> type_qualifier_list_opt_c", $2 );

      $$.top_ast = c_ast_new( K_REFERENCE, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->as.ptr_ref.qualifier = $2;
      c_ast_set_parent( type_peek(), $$.top_ast );

      DUMP_AST( "< reference_type_c", $$.top_ast );
      DUMP_END();
    }
  ;

/*****************************************************************************/
/*  function argument gibberish productions                                  */
/*****************************************************************************/

arg_list_opt_c
  : /* empty */                   { $$.head_ast = $$.tail_ast = NULL; }
  | arg_list_c
  ;

arg_list_c
  : arg_list_c expect_comma arg_c
    {
      DUMP_START( "arg_list_c", "arg_list_c ',' cast_c" );
      DUMP_AST_LIST( "> arg_list_c", $1 );
      DUMP_AST( "> cast_c", $3.top_ast );

      $$ = $1;
      c_ast_list_append( &$$, $3.top_ast );

      DUMP_AST_LIST( "< arg_list_c", $$ );
      DUMP_END();
    }

  | arg_c
    {
      DUMP_START( "arg_list_c", "arg_c" );
      DUMP_AST( "> arg_c", $1.top_ast );

      $$.head_ast = $$.tail_ast = NULL;
      c_ast_list_append( &$$, $1.top_ast );

      DUMP_AST_LIST( "< arg_list_c", $$ );
      DUMP_END();
    }
  ;

arg_c
  : type_c { type_push( $1.top_ast ); } cast_c
    {
      type_pop();
      DUMP_START( "arg_c", "type_c cast_c" );
      DUMP_AST( "> type_c", $1.top_ast );
      DUMP_AST( "> cast_c", $3.top_ast );

      $$ = $3.top_ast ? $3 : $1;
      if ( $$.top_ast->name == NULL )
        $$.top_ast->name = check_strdup( c_ast_name( $$.top_ast, V_DOWN ) );

      DUMP_AST( "< arg_c", $$.top_ast );
      DUMP_END();
    }

  | Y_NAME                              /* K&R C type-less argument */
    {
      DUMP_START( "argc", "NAME" );
      DUMP_NAME( "> NAME", $1 );

      $$.top_ast = c_ast_new( K_NAME, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->name = check_strdup( $1 );

      DUMP_END();
    }
  ;

/*****************************************************************************/
/*  type gibberish productions                                               */
/*****************************************************************************/

type_c
  : type_modifier_list_c                /* allows for default int type */
    {
      DUMP_START( "type_c", "type_modifier_list_c" );
      DUMP_TYPE( "> type_modifier_list_c", $1 );

      $$.top_ast = c_ast_new( K_BUILTIN, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->type = T_INT;
      C_TYPE_ADD( &$$.top_ast->type, $1, @1 );
      C_TYPE_CHECK( $$.top_ast->type, @1 );

      DUMP_AST( "< type_c", $$.top_ast );
      DUMP_END();
    }

  | type_modifier_list_c builtin_type_c type_modifier_list_opt_c
    {
      DUMP_START( "type_c",
                  "type_modifier_list_c builtin_type_c "
                  "type_modifier_list_opt_c" );
      DUMP_TYPE( "> type_modifier_list_c", $1 );
      DUMP_TYPE( "> builtin_type_c", $2 );
      DUMP_TYPE( "> type_modifier_list_opt_c", $3 );

      $$.top_ast = c_ast_new( K_BUILTIN, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->type = $2;
      C_TYPE_ADD( &$$.top_ast->type, $1, @1 );
      C_TYPE_ADD( &$$.top_ast->type, $3, @3 );
      C_TYPE_CHECK( $$.top_ast->type, @1 );

      DUMP_AST( "< type_c", $$.top_ast );
      DUMP_END();
    }

  | builtin_type_c type_modifier_list_opt_c
    {
      DUMP_START( "type_c", "builtin_type_c type_modifier_list_opt_c" );
      DUMP_TYPE( "> builtin_type_c", $1 );
      DUMP_TYPE( "> type_modifier_list_opt_c", $2 );

      $$.top_ast = c_ast_new( K_BUILTIN, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->type = $1;
      C_TYPE_ADD( &$$.top_ast->type, $2, @2 );
      C_TYPE_CHECK( $$.top_ast->type, @1 );

      DUMP_AST( "< type_c", $$.top_ast );
      DUMP_END();
    }

  | named_enum_class_struct_union_type_c
  ;

type_modifier_list_opt_c
  : /* empty */                   { $$ = T_NONE; }
  | type_modifier_list_c
  ;

type_modifier_list_c
  : type_modifier_list_c type_modifier_c
    {
      DUMP_START( "type_modifier_list_c",
                  "type_modifier_list_c type_modifier_c" );
      DUMP_TYPE( "> type_modifier_list_c", $1 );
      DUMP_TYPE( "> type_modifier_c", $2 );

      $$ = $1;
      C_TYPE_ADD( &$$, $2, @2 );
      C_TYPE_CHECK( $$, @2 );

      DUMP_TYPE( "< type_modifier_list_c", $$ );
      DUMP_END();
    }

  | type_modifier_c
    {
      $$ = $1;
      C_TYPE_CHECK( $$, @1 );
    }
  ;

type_modifier_c
  : type_modifier_english
  | type_qualifier_c
  | storage_class_c
  ;

builtin_type_c
  : Y_VOID
  | Y_BOOL
  | Y_CHAR
  | Y_CHAR16_T
  | Y_CHAR32_T
  | Y_WCHAR_T
  | Y_INT
  | Y_FLOAT
  | Y_DOUBLE
  ;

named_enum_class_struct_union_type_c
  : enum_class_struct_union_type_c Y_NAME
    {
      DUMP_START( "named_enum_class_struct_union_type_c",
                  "enum_class_struct_union_type_c NAME" );
      DUMP_TYPE( "> enum_class_struct_union_type_c", $1 );
      DUMP_NAME( "> NAME", $2 );

      $$.top_ast = c_ast_new( K_ENUM_CLASS_STRUCT_UNION, ast_depth, &@$ );
      $$.target_ast = NULL;
      $$.top_ast->type = $1;
      $$.top_ast->as.ecsu.ecsu_name = $2;
      C_TYPE_CHECK( $$.top_ast->type, @1 );

      DUMP_AST( "< named_enum_class_struct_union_type_c", $$.top_ast );
      DUMP_END();
    }

  | enum_class_struct_union_type_c error
    {
      PARSE_ERROR(
        "%s name expected", c_kind_name( K_ENUM_CLASS_STRUCT_UNION )
      );
    }
  ;

enum_class_struct_union_type_c
  : Y_ENUM
  | class_struct_type_c
  | Y_UNION
  ;

class_struct_type_c
  : Y_CLASS
  | Y_STRUCT
  ;

type_qualifier_list_opt_c
  : /* empty */                   { $$ = T_NONE; }
  | type_qualifier_list_opt_c type_qualifier_c
    {
      DUMP_START( "type_qualifier_list_opt_c",
                  "type_qualifier_list_opt_c type_qualifier_c" );
      DUMP_TYPE( "> type_qualifier_list_opt_c", $1 );
      DUMP_TYPE( "> type_qualifier_c", $2 );

      $$ = $1;
      C_TYPE_ADD( &$$, $2, @2 );
      C_TYPE_CHECK( $$, @2 );

      DUMP_TYPE( "< type_qualifier_list_opt_c", $$ );
      DUMP_END();
    }
  ;

type_qualifier_c
  : Y_CONST
  | Y_RESTRICT
  | Y_VOLATILE
  ;

storage_class_c
  : Y_AUTO
  | Y___BLOCK                           /* Apple extension */
  | Y_EXTERN
/*| Y_REGISTER */                       /* in type_modifier_english */
  | Y_STATIC
  | Y_TYPEDEF
  | Y_THREAD_LOCAL
  ;

/*****************************************************************************/
/*  cast gibberish productions                                               */
/*****************************************************************************/

cast_c
  : /* empty */                   { $$.top_ast = $$.target_ast = NULL; }
  | cast2_c
  | pointer_cast_c
  | pointer_to_member_cast_c
  | reference_cast_c
  ;

cast2_c
  : array_cast_c
  | block_cast_c
  | func_cast_c
  | name_c
  | nested_cast_c
  ;

array_cast_c
  : cast2_c array_size_c
    {
      DUMP_START( "array_cast_c", "cast2_c array_size_c" );
      DUMP_AST( "^ type_c", type_peek() );
      DUMP_AST( "> cast2_c", $1.top_ast );
      DUMP_NUM( "> array_size_c", $2 );
      if ( $1.target_ast )
        DUMP_AST( "> target_ast", $1.target_ast );

      c_ast_t *const array = c_ast_new( K_ARRAY, ast_depth, &@$ );
      array->as.array.size = $2;
      c_ast_set_parent( c_ast_new( K_NONE, ast_depth, &@1 ), array );
      if ( $1.target_ast ) {
        $$.top_ast = $1.top_ast;
        $$.target_ast = c_ast_add_array( $1.target_ast, array );
      } else {
        $$.top_ast = c_ast_add_array( $1.top_ast, array );
        $$.target_ast = NULL;
      }

      DUMP_AST( "< array_cast_c", $$.top_ast );
      DUMP_END();
    }
  ;

block_cast_c                            /* Apple extension */
  : /* type */ '(' '^'
    {
      //
      // A block AST has to be the type inherited attribute for cast_c so we
      // have to create it here.
      //
      type_push( c_ast_new( K_BLOCK, ast_depth, &@$ ) );
    }
    type_qualifier_list_opt_c cast_c ')' '(' arg_list_opt_c ')'
    {
      c_ast_t *const block = type_pop();

      DUMP_START( "block_cast_c",
                  "'(' '^' type_qualifier_list_opt_c cast_c ')' "
                  "'(' arg_list_opt_c ')'" );
      DUMP_AST( "^ type_c", type_peek() );
      DUMP_TYPE( "> type_qualifier_list_opt_c", $4 );
      DUMP_AST( "> cast_c", $5.top_ast );
      DUMP_AST_LIST( "> arg_list_opt_c", $8 );

      C_TYPE_ADD( &block->type, $4, @4 );
      block->as.block.args = $8;
      $$.top_ast = c_ast_add_func( $5.top_ast, type_peek(), block );
      $$.target_ast = block->as.block.ret_ast;

      DUMP_AST( "< block_cast_c", $$.top_ast );
      DUMP_END();
    }
  ;

func_cast_c
  : /* type_c */ cast2_c '(' arg_list_opt_c ')'
    {
      DUMP_START( "func_cast_c", "cast2_c '(' arg_list_opt_c ')'" );
      DUMP_AST( "^ type_c", type_peek() );
      DUMP_AST( "> cast2_c", $1.top_ast );
      DUMP_AST_LIST( "> arg_list_opt_c", $3 );

      c_ast_t *const func = c_ast_new( K_FUNCTION, ast_depth, &@$ );
      func->as.func.args = $3;
      $$.top_ast = c_ast_add_func( $1.top_ast, type_peek(), func );
      $$.target_ast = func->as.func.ret_ast;

      DUMP_AST( "< func_cast_c", $$.top_ast );
      DUMP_END();
    }
  ;

nested_cast_c
  : '(' placeholder_type_c { type_push( $2.top_ast ); ++ast_depth; } cast_c ')'
    {
      type_pop();
      --ast_depth;

      DUMP_START( "nested_cast_c", "'(' placeholder_type_c cast_c ')'" );
      DUMP_AST( "> placeholder_type_c", $2.top_ast );
      DUMP_AST( "> cast_c", $4.top_ast );

      $$ = $4;

      DUMP_AST( "< nested_cast_c", $$.top_ast );
      DUMP_END();
    }
  ;

pointer_cast_c
  : pointer_type_c { type_push( $1.top_ast ); } cast_c
    {
      type_pop();
      DUMP_START( "pointer_cast_c", "pointer_type_c cast_c" );
      DUMP_AST( "> pointer_type_c", $1.top_ast );
      DUMP_AST( "> cast_c", $3.top_ast );

      $$.top_ast = c_ast_patch_none( $1.top_ast, $3.top_ast );
      $$.target_ast = NULL;

      DUMP_AST( "< pointer_cast_c", $$.top_ast );
      DUMP_END();
    }
  ;

pointer_to_member_cast_c
  : pointer_to_member_type_c { type_push( $1.top_ast ); } cast_c
    {
      type_pop();
      DUMP_START( "pointer_to_member_cast_c",
                  "pointer_to_member_type_c cast_c" );
      DUMP_AST( "> pointer_to_member_type_c", $1.top_ast );
      DUMP_AST( "> cast_c", $3.top_ast );

      $$.top_ast = c_ast_patch_none( $1.top_ast, $3.top_ast );
      $$.target_ast = NULL;

      DUMP_AST( "< pointer_to_member_cast_c", $$.top_ast );
      DUMP_END();
    }
  ;

reference_cast_c
  : reference_type_c { type_push( $1.top_ast ); } cast_c
    {
      type_pop();
      DUMP_START( "reference_cast_c", "reference_type_c cast_c" );
      DUMP_AST( "> reference_type_c", $1.top_ast );
      DUMP_AST( "> cast_c", $3.top_ast );

      $$ = $3;

      DUMP_AST( "< reference_cast_c", $$.top_ast );
      DUMP_END();
    }
  ;

/*****************************************************************************/
/*  miscellaneous productions                                                */
/*****************************************************************************/

array_size_c
  : '[' ']'                       { $$ = C_ARRAY_NO_SIZE; }
  | '[' Y_NUMBER ']'              { $$ = $2; }
  | '[' error ']'
    {
      PARSE_ERROR( "integer expected for array size" );
    }
  ;

expect_comma
  : ','
  | error                         { PARSE_ERROR( "',' expected" ); }
  ;

expect_star
  : '*'
  | error                         { PARSE_ERROR( "'*' expected" ); }
  ;

name_opt
  : /* empty */                   { $$ = NULL; }
  | Y_NAME
  ;

%%

///////////////////////////////////////////////////////////////////////////////
/* vim:set et sw=2 ts=2: */