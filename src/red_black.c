/*
**      cdecl -- C gibberish translator
**      src/red_black.c
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

/*
 * Adapted from the following code:
 * https://opensource.apple.com/source/sudo/sudo-46/src/redblack.c
 */

/*
 * Copyright (c) 2004-2005, 2007 Todd C. Miller <Todd.Miller@courtesan.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

/*
 * Adapted from the following code written by Emin Martinian:
 * http://web.mit.edu/~emin/www/source_code/red_black_tree/index.html
 *
 * Copyright (c) 2001 Emin Martinian
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that neither the name of Emin
 * Martinian nor the names of any contributors are be used to endorse or
 * promote products derived from this software without specific prior
 * written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

// local
#include "config.h"                     /* must go first */
#include "red_black.h"
#include "util.h"

// standard
#include <assert.h>
#include <stdio.h>                      /* for NULL */

#define RB_FIRST(TREE)  (RB_ROOT(TREE)->left)
#define RB_NIL(TREE)    (&(TREE)->nil)
#define RB_ROOT(TREE)   (&(TREE)->root)

///////////////////////////////////////////////////////////////////////////////

/**
 * Red-black tree colors.
 */
enum rb_color {
  RB_RED,
  RB_BLACK
};
typedef enum rb_color rb_color_t;

/**
 * A red-black tree node.
 */
struct rb_node {
  void *data;                           // must be first
  rb_color_t color;
  rb_node_t *left;
  rb_node_t *right;
  rb_node_t *parent;
};

/**
 * A red-black tree.
 */
struct rb_tree {
  rb_node_t root;
  rb_node_t nil;                        // sentinel
  rb_data_cmp_t data_cmp_fn;
};

// local functions
static void rb_rotate_left( rb_tree_t*, rb_node_t* );
static void rb_rotate_right( rb_tree_t*, rb_node_t* );

////////// inline functions ///////////////////////////////////////////////////

/**
 * Convenience function for checking that a node is black.
 *
 * @param node A pointer to the node to check.
 * @return Returns \c true only if the node is black.
 */
static inline bool is_black( rb_node_t *node ) {
  return node->color == RB_BLACK;
}

/**
 * Convenience function for checking that a node is red.
 *
 * @param node A pointer to the node to check.
 * @return Returns \c true only if the node is red.
 */
static inline bool is_red( rb_node_t *node ) {
  return node->color == RB_RED;
}

////////// local functions ////////////////////////////////////////////////////

/**
 * Initializes an rb_node.
 *
 * @param tree A pointer to the red-black tree to which \a node belongs.
 * @param node A pointer to the node to initialize.
 */
static void rb_node_init( rb_tree_t *tree, rb_node_t *node ) {
  node->color = RB_BLACK;
  node->left = node->right = RB_NIL(tree);
  node->data = NULL;
}

/**
 * Performs an in-order traversal of the red-black tree starting at \a node.
 *
 * @param tree A pointer to the red-black tree to visit.
 * @param node A pointer to the node to start visiting at.
 * @param visitor The visitor to use.
 * @param aux_data Optional data passed to \a visitor.
 * @return Returns a pointer to the node at which visiting stopped or NULL if
 * the entire sub-tree was visited.
 */
static rb_node_t* rb_node_visit( rb_tree_t const *tree, rb_node_t *node,
                                 rb_visitor_t visitor, void *aux_data ) {
  if ( node == RB_NIL(tree) )
    return NULL;

  rb_node_t *const stopped_node =
    rb_node_visit( tree, node->left, visitor, aux_data );
  if ( stopped_node )
    return stopped_node;

  if ( visitor( node->data, aux_data ) )
    return node;

  return rb_node_visit( tree, node->right, visitor, aux_data );
}

/**
 * Frees all memory associated with \a tree.
 *
 * @param tree A pointer to the red-black tree to free.
 * @param node A pointer to the node to free.
 * @param data_free_fn A pointer to the function to use to free data associated
 * with each node, if any.
 */
static void rb_tree_free_impl( rb_tree_t *tree, rb_node_t *node,
                               rb_data_free_t data_free_fn ) {
  if ( node != RB_NIL(tree) ) {
    rb_tree_free_impl( tree, node->left, data_free_fn );
    rb_tree_free_impl( tree, node->right, data_free_fn );
    if ( data_free_fn != NULL )
      data_free_fn( node->data );
    FREE( node );
  }
}

/**
 * Repairs the tree after a node has been deleted by rotating and repainting
 * colors to restore the 4 properties inherent in red-black trees.
 *
 * @param tree A pointer to the red-black tree to repair.
 * @param node A pointer to the node to start the repair at.
 */
static void rb_tree_repair( rb_tree_t *tree, rb_node_t *node ) {
  assert( tree != NULL );
  assert( node != NULL );

  while ( is_black( node ) ) {
    if ( node == node->parent->left ) {
      rb_node_t *sibling = node->parent->right;
      if ( is_red( sibling ) ) {
        sibling->color = RB_BLACK;
        node->parent->color = RB_RED;
        rb_rotate_left( tree, node->parent );
        sibling = node->parent->right;
      }
      if ( is_black( sibling->right ) && is_black( sibling->left ) ) {
        sibling->color = RB_RED;
        node = node->parent;
      } else {
        if ( is_black( sibling ) ) {
          sibling->left->color = RB_BLACK;
          sibling->color = RB_RED;
          rb_rotate_right( tree, sibling );
          sibling = node->parent->right;
        }
        sibling->color = node->parent->color;
        node->parent->color = RB_BLACK;
        sibling->right->color = RB_BLACK;
        rb_rotate_left( tree, node->parent );
        break;
      }
    } else {                            // node == node->parent->right
      rb_node_t *sibling = node->parent->left;
      if ( is_red( sibling ) ) {
        sibling->color = RB_BLACK;
        node->parent->color = RB_RED;
        rb_rotate_right( tree, node->parent );
        sibling = node->parent->left;
      }
      if ( is_black( sibling->right ) && is_black( sibling->left ) ) {
        sibling->color = RB_RED;
        node = node->parent;
      } else {
        if ( is_black( sibling->left ) ) {
          sibling->right->color = RB_BLACK;
          sibling->color = RB_RED;
          rb_rotate_left( tree, sibling );
          sibling = node->parent->left;
        }
        sibling->color = node->parent->color;
        node->parent->color = RB_BLACK;
        sibling->left->color = RB_BLACK;
        rb_rotate_right( tree, node->parent );
        break;
      }
    }
  } // while
}

/**
 * Rotates a subtree of a red-black tree left.
 *
 * @param tree A pointer to the red-black tree to manipulate.
 * @param node A pointer to the node to rotate.
 */
static void rb_rotate_left( rb_tree_t *tree, rb_node_t *node ) {
  assert( tree != NULL );
  assert( node != NULL );

  rb_node_t *const child = node->right;
  node->right = child->left;

  if ( child->left != RB_NIL(tree) )
    child->left->parent = node;
  child->parent = node->parent;

  if ( node == node->parent->left )
    node->parent->left = child;
  else
    node->parent->right = child;

  child->left = node;
  node->parent = child;
}

/**
 * Rotates a subtree of a red-black tree right.
 *
 * @param tree A pointer to the red-black tree to manipulate.
 * @param node A pointer to the node to rotate.
 */
static void rb_rotate_right( rb_tree_t *tree, rb_node_t *node ) {
  assert( tree != NULL );
  assert( node != NULL );

  rb_node_t *const child = node->left;
  node->left = child->right;

  if ( child->right != RB_NIL(tree) )
    child->right->parent = node;
  child->parent = node->parent;

  if ( node == node->parent->left )
    node->parent->left = child;
  else
    node->parent->right = child;

  child->right = node;
  node->parent = child;
}

/**
 * Gets the successor of \a node.
 *
 * @param tree A pointer to the red-black tree \a node is part of.
 * @param node A pointer to the node to get the successor of.
 * @return Returns said successor.
 */
static rb_node_t* rb_successor( rb_tree_t *tree, rb_node_t *node ) {
  assert( tree != NULL );
  assert( node != NULL );

  rb_node_t *succ = node->right;

  if ( succ != RB_NIL(tree) ) {
    while ( succ->left != RB_NIL(tree) )
      succ = succ->left;
  } else {
    // No right child, move up until we find it or hit the root.
    for ( succ = node->parent; node == succ->right; succ = succ->parent )
      node = succ;
    if ( succ == RB_ROOT(tree) )
      succ = RB_NIL(tree);
  }
  return succ;
}

////////// extern functions ///////////////////////////////////////////////////

void* rb_node_delete( rb_tree_t *tree, rb_node_t *delete_node ) {
  assert( tree != NULL );
  assert( delete_node != NULL );

  void *const data = delete_node->data;

  rb_node_t *const y =
    delete_node->left == RB_NIL(tree) || delete_node->right == RB_NIL(tree) ?
      delete_node :
      rb_successor( tree, delete_node );

  rb_node_t *const x = y->left == RB_NIL(tree) ? y->right : y->left;

  if ( (x->parent = y->parent) == RB_ROOT(tree) ) {
    RB_FIRST(tree) = x;
  } else {
    if ( y == y->parent->left )
      y->parent->left = x;
    else
      y->parent->right = x;
  }

  if ( is_black( y ) )
    rb_tree_repair( tree, x );

  if ( y != delete_node ) {
    y->color = delete_node->color;
    y->left = delete_node->left;
    y->right = delete_node->right;
    y->parent = delete_node->parent;
    delete_node->left->parent = delete_node->right->parent = y;
    if ( delete_node == delete_node->parent->left )
      delete_node->parent->left = y;
    else
      delete_node->parent->right = y;
  }

  FREE( delete_node );
  return data;
}

rb_node_t* rb_tree_find( rb_tree_t *tree, void const *data ) {
  assert( tree != NULL );
  assert( data != NULL );

  for ( rb_node_t *node = RB_FIRST(tree); node != RB_NIL(tree); ) {
    int const cmp = tree->data_cmp_fn( data, node->data );
    if ( cmp == 0 )
      return node;
    node = cmp < 0 ? node->left : node->right;
  } // for
  return NULL;
}

void rb_tree_free( rb_tree_t *tree, rb_data_free_t data_free_fn ) {
  if ( tree != NULL ) {
    rb_tree_free_impl( tree, RB_FIRST(tree), data_free_fn );
    FREE( tree );
  }
}

rb_node_t* rb_tree_insert( rb_tree_t *tree, void *data ) {
  assert( tree != NULL );
  assert( data != NULL );

  rb_node_t *node = RB_FIRST(tree);
  rb_node_t *parent = RB_ROOT(tree);

  // Find correct insertion point.
  while ( node != RB_NIL(tree) ) {
    parent = node;
    int const cmp = tree->data_cmp_fn( data, node->data );
    if ( cmp == 0 )
      return node;
    node = cmp < 0 ? node->left : node->right;
  } // while

  node = MALLOC( rb_node_t, 1 );
  node->data = data;
  node->left = node->right = RB_NIL(tree);
  node->parent = parent;

  if ( parent == RB_ROOT(tree) || tree->data_cmp_fn( data, parent->data ) < 0 )
    parent->left = node;
  else
    parent->right = node;
  node->color = RB_RED;

  //
  // If the parent node is black, we're all set; if it's red, we have the
  // following possible cases to deal with.  We iterate through the rest of the
  // tree to make sure none of the required properties is violated.
  //
  //  1. The uncle is red.  We repaint both the parent and uncle black and
  //     repaint the grandparent node red.
  //
  //  2. The uncle is black and the new node is the right child of its parent,
  //     and the parent in turn is the left child of its parent.  We do a left
  //     rotation to switch the roles of the parent and child, relying on
  //     further iterations to fixup the old parent.
  //
  //  3. The uncle is black and the new node is the left child of its parent,
  //     and the parent in turn is the left child of its parent.  We switch the
  //     colors of the parent and grandparent and perform a right rotation
  //     around the grandparent.  This makes the former parent the parent of
  //     the new node and the former grandparent.
  //
  // Note that because we use a sentinel for the root node we never need to
  // worry about replacing the root.
  //
  while ( is_red( node->parent ) ) {
    rb_node_t *uncle;
    if ( node->parent == node->parent->parent->left ) {
      uncle = node->parent->parent->right;
      if ( is_red( uncle ) ) {
        node->parent->color = RB_BLACK;
        uncle->color = RB_BLACK;
        node->parent->parent->color = RB_RED;
        node = node->parent->parent;
      } else {                          // if ( is_black( uncle ) )
        if ( node == node->parent->right ) {
          node = node->parent;
          rb_rotate_left( tree, node );
        }
        node->parent->color = RB_BLACK;
        node->parent->parent->color = RB_RED;
        rb_rotate_right( tree, node->parent->parent );
      }
    } else { // if ( node->parent == node->parent->parent->right )
      uncle = node->parent->parent->left;
      if ( is_red( uncle ) ) {
        node->parent->color = RB_BLACK;
        uncle->color = RB_BLACK;
        node->parent->parent->color = RB_RED;
        node = node->parent->parent;
      } else {                          // if ( is_black( uncle ) )
        if ( node == node->parent->left ) {
          node = node->parent;
          rb_rotate_right( tree, node );
        }
        node->parent->color = RB_BLACK;
        node->parent->parent->color = RB_RED;
        rb_rotate_left( tree, node->parent->parent );
      }
    }
  } // while

  RB_FIRST(tree)->color = RB_BLACK;     // first node is always black
  return NULL;
}

rb_tree_t* rb_tree_new( rb_data_cmp_t data_cmp_fn ) {
  assert( data_cmp_fn != NULL );

  rb_tree_t *const tree = MALLOC( rb_tree_t, 1 );
  rb_node_init( tree, RB_ROOT(tree) );
  rb_node_init( tree, RB_NIL(tree) );
  tree->data_cmp_fn = data_cmp_fn;

  return tree;
}

rb_node_t* rb_tree_visit( rb_tree_t const *tree, rb_visitor_t visitor,
                          void *aux_data ) {
  assert( tree != NULL );
  assert( visitor != NULL );

  return rb_node_visit(
    CONST_CAST( rb_tree_t*, tree ),
    CONST_CAST( rb_node_t*, RB_FIRST(tree) ),
    visitor, aux_data
  );
}

///////////////////////////////////////////////////////////////////////////////
/* vim:set et sw=2 ts=2: */
