# Code Examples: Algorithmic Thinking

## How to Use

This file collects reusable C code patterns from *Algorithmic Thinking* (Daniel Zingaro), organized by chapter and data structure. Each snippet is annotated with:

- **When to use**: the problem shape that calls for this pattern.
- **Complexity**: time and space in Big-O notation.
- **Key variation**: how the pattern changes for related problems.

All code is in C. Adapt to your target language: replace `malloc` with constructors, linked lists with dynamic arrays or built-in hash maps, etc. Array-based heaps and segment trees translate almost directly into any language.

---

## Chapter 1: Hash Tables

### Hash Table with Chaining: Node Structure (Chapter 1)

**When to use**: Store multiple items per hash bucket using a linked list to handle collisions.

```c
typedef struct snowflake_node {
  int snowflake[6];
  struct snowflake_node *next;
} snowflake_node;
```

**Complexity**: Time O(1) average insert/lookup, Space O(n)

**Key variation**: The `password_node` variant adds an `int total` field for counting occurrences and a `char *password` field for string keys.

---

### Hash Table with Chaining: Insert (Chapter 1)

**When to use**: Add a new element to the front of the linked list at the computed hash bucket.

```c
#define SIZE 100000

int code(int snowflake[]) {
  return (snowflake[0] + snowflake[1] + snowflake[2]
          + snowflake[3] + snowflake[4] + snowflake[5]) % SIZE;
}

// Inside main, after reading each snowflake into snow->snowflake[]:
snowflake_code = code(snow->snowflake);
snow->next = snowflakes[snowflake_code]; // point new node at current head
snowflakes[snowflake_code] = snow;       // new node becomes new head
```

**Complexity**: Time O(1) insert, Space O(n)

**Key variation**: Inserting at the front of the list avoids traversal. Inserting at the end would require O(k) traversal for a bucket of size k.

---

### Hash Table with Chaining: Collision Search / Duplicate Detection (Chapter 1)

**When to use**: Search within a chained linked list to find duplicate elements.

```c
void identify_identical(snowflake_node *snowflakes[]) {
  snowflake_node *node1, *node2;
  int i;
  for (i = 0; i < SIZE; i++) {
    node1 = snowflakes[i];          // walk each bucket's linked list
    while (node1 != NULL) {
      node2 = node1->next;          // compare node1 against all nodes to its right
      while (node2 != NULL) {
        if (are_identical(node1->snowflake, node2->snowflake)) {
          printf("Twin snowflakes found.\n");
          return;
        }
        node2 = node2->next;
      }
      node1 = node1->next;
    }
  }
  printf("No two snowflakes are alike.\n");
}
```

**Complexity**: Time O(n) expected (O(n^2) worst case with pathological input), Space O(1) extra

**Key variation**: Only pairwise comparisons *within* each bucket are needed, since elements in different buckets have different hash codes and cannot be identical (given a hash function that maps identical items to the same bucket).

---

### Hash Table with Chaining: String Key Lookup (Chapter 1)

**When to use**: Search a chained hash table for a string key, and return the node pointer or NULL.

```c
#define NUM_BITS 20

password_node *in_hash_table(password_node *hash_table[], char *find) {
  unsigned password_code;
  password_node *password_ptr;
  password_code = oaat(find, strlen(find), NUM_BITS); // compute hash
  password_ptr = hash_table[password_code];           // go to bucket
  while (password_ptr) {
    if (strcmp(password_ptr->password, find) == 0)    // compare strings
      return password_ptr;
    password_ptr = password_ptr->next;
  }
  return NULL;
}
```

**Complexity**: Time O(1) expected, O(k) worst case per bucket of size k, Space O(1)

**Key variation**: For integer keys (snowflakes), comparison uses `are_identical()`. For string keys, use `strcmp()`.

---

## Chapter 2: Trees and Recursion

### Binary Tree Node Structure (Chapter 2)

**When to use**: Define a node for a full binary tree where each node has at most two children.

```c
typedef struct node {
  int candy;
  struct node *left, *right;
} node;
```

**Complexity**: Space O(1) per node

**Key variation**: Add `struct node *parent` for upward traversal (not needed for this problem).

---

### Binary Tree Node Construction Helpers (Chapter 2)

**When to use**: Allocate and initialize leaf (house) or internal (nonhouse) binary tree nodes.

```c
node *new_house(int candy) {
  node *house = malloc(sizeof(node));
  if (house == NULL) {
    fprintf(stderr, "malloc error\n");
    exit(1);
  }
  house->candy = candy;
  house->left = NULL;
  house->right = NULL;
  return house;
}

node *new_nonhouse(node *left, node *right) {
  node *nonhouse = malloc(sizeof(node));
  if (nonhouse == NULL) {
    fprintf(stderr, "malloc error\n");
    exit(1);
  }
  nonhouse->left = left;
  nonhouse->right = right;
  return nonhouse;
}
```

**Complexity**: Time O(1), Space O(1)

**Key variation**: Build tree bottom-up: create leaves first, then unite under a parent.

---

### Recursive Binary Tree Traversal: Sum of Values (Chapter 2)

**When to use**: Recursively sum values stored only in leaf nodes of a full binary tree.

```c
int tree_candy(node *tree) {
  if (!tree->left && !tree->right)  // base case: leaf node
    return tree->candy;
  // recursive case: sum both subtrees
  return tree_candy(tree->left) + tree_candy(tree->right);
}
```

**Complexity**: Time O(n), Space O(h) call stack where h = tree height

**Key variation**: Stack-based iterative version uses explicit `stack` struct. Recursion is cleaner.

---

### Recursive Tree Construction from String Input (Chapter 2)

**When to use**: Parse a recursively-encoded string `(left right)` or integer leaf into a binary tree.

```c
node *read_tree_helper(char *line, int *pos) {
  node *tree;
  tree = malloc(sizeof(node));
  if (tree == NULL) {
    fprintf(stderr, "malloc error\n");
    exit(1);
  }
  if (line[*pos] == '(') {            // Rule 2: nonhouse node
    (*pos)++;                         // skip '('
    tree->left = read_tree_helper(line, pos);
    (*pos)++;                         // skip space between subtrees
    tree->right = read_tree_helper(line, pos);
    (*pos)++;                         // skip ')'
    return tree;
  } else {                            // Rule 1: house (leaf) node
    tree->left = NULL;
    tree->right = NULL;
    tree->candy = line[*pos] - '0';   // first digit
    (*pos)++;
    // check for second digit (candy values up to 2 digits)
    if (line[*pos] != ')' && line[*pos] != ' ' &&
        line[*pos] != '\0') {
      tree->candy = tree->candy * 10 + line[*pos] - '0';
      (*pos)++;
    }
    return tree;
  }
}

node *read_tree(char *line) {
  int pos = 0;
  return read_tree_helper(line, &pos);
}
```

**Complexity**: Time O(n) where n = string length, Space O(h) call stack

**Key variation**: The `int *pos` parameter threads position state through recursive calls, avoiding a separate pass to find subtree boundaries.

---

## Chapter 3: Memoization and Dynamic Programming

### Memoization Template: Top-Down DP (Chapter 3)

**When to use**: Add to a recursive solution when subproblems overlap. Cache results on first solve, return cached result on subsequent calls.

```c
#define SIZE 10000

// In the calling function (solve), declare and initialize memo:
int memo[SIZE];
for (i = 0; i <= t; i++)
    memo[i] = -2;  // -2 = "unknown"; -1 = "no solution"; >= 0 = answer

int solve_t(int m, int n, int t, int memo[]) {
    int first, second;
    if (memo[t] != -2)       // already solved, return cached answer
        return memo[t];
    if (t == 0) {
        memo[t] = 0;
        return memo[t];
    }
    if (t >= m)
        first = solve_t(m, n, t - m, memo);
    else
        first = -1;
    if (t >= n)
        second = solve_t(m, n, t - n, memo);
    else
        second = -1;
    if (first == -1 && second == -1) {
        memo[t] = -1;
        return memo[t];
    } else {
        memo[t] = max(first, second) + 1;
        return memo[t];
    }
}
```

**Complexity**: Time O(t), Space O(t)

**Key variation**: For 2-D subproblems (two varying parameters, e.g. Hockey Rivalry), use `static int memo[SIZE+1][SIZE+1]` and check/set `memo[i][j]`. The pattern is otherwise identical.

---

### Bottom-Up DP Template (Chapter 3)

**When to use**: Replace memoized recursion with an explicit loop that fills a `dp` array from smallest subproblem to largest, eliminating call-stack overhead.

```c
#define SIZE 10000

void solve(int m, int n, int t) {
    int result, i, first, second;
    int dp[SIZE];

    dp[0] = 0;                          // base case: 0 minutes -> 0 burgers
    for (i = 1; i <= t; i++) {
        if (i >= m)
            first = dp[i - m];          // look up already-solved subproblem
        else
            first = -1;
        if (i >= n)
            second = dp[i - n];
        else
            second = -1;
        if (first == -1 && second == -1)
            dp[i] = -1;                 // no solution for exactly i minutes
        else
            dp[i] = max(first, second) + 1;
    }

    result = dp[t];
    if (result >= 0)
        printf("%d\n", result);
    else {
        i = t - 1;
        result = dp[i];
        while (result == -1) {
            i--;
            result = dp[i];
        }
        printf("%d %d\n", result, t - i);
    }
}
```

**Complexity**: Time O(t), Space O(t)

**Key variation**: For 2-D DP (Hockey Rivalry), use `static int dp[SIZE+1][SIZE+1]`, initialize the entire row 0 and column 0 to 0, then fill with a double loop `for i ... for j ...` in row-major order. A space optimization reduces the 2-D array to two 1-D arrays (`previous[]` and `current[]`) when only the previous row is ever needed.

---

## Chapter 4: Advanced Memoization and Dynamic Programming

### Two-Parameter Backward Memoization: The Jumper (Chapter 4)

**When to use**: DP with two state parameters where the end state is known but the final parameter value is not, requiring a search over all possible final values.

```c
#define SIZE 1000

int min(int v1, int v2) {
  if (v1 < v2)
    return v1;
  else
    return v2;
}

int solve_ij(int cost[], int n, int i, int j, int memo[SIZE + 1][SIZE + 1]) {
  int first, second;

  if (memo[i][j] != -2)
    return memo[i][j];

  if (i == 2 && j == 1) {
    memo[i][j] = 0;
    return memo[i][j];
  }

  if (i - j >= 1 && j >= 2)
    first = solve_ij(cost, n, i - j, j - 1, memo);
  else
    first = -1;

  if (i + j <= n)
    second = solve_ij(cost, n, i + j, j, memo);
  else
    second = -1;

  if (first == -1 && second == -1) {
    memo[i][j] = -1;
  } else if (second == -1) {
    memo[i][j] = first + cost[i];
  } else if (first == -1) {
    memo[i][j] = second + cost[i];
  } else {
    memo[i][j] = min(first, second) + cost[i];
  }
  return memo[i][j];
}

int solve(int cost[], int n) {
  int i, j, best, result;
  static int memo[SIZE + 1][SIZE + 1];
  for (i = 1; i <= SIZE; i++)
    for (j = 1; j <= SIZE; j++)
      memo[i][j] = -2;

  best = -1;
  for (j = 1; j <= n; j++) {
    result = solve_ij(cost, n, n, j, memo);
    if (result != -1) {
      if (best == -1)
        best = cost[2] + result;
      else
        best = min(best, cost[2] + result);
    }
  }
  return best;
}
```

**Complexity**: Time O(n²), Space O(n²) for the memo table

**Key variation**: The forward formulation eliminates the search loop in `solve` by starting from the known initial state (square 2, jump distance 1) and filling forward. This avoids guessing the final jump distance but requires a non-standard fill order.

---

### Three-Parameter Counting DP with Modular Arithmetic: Ways to Build (Chapter 4)

**When to use**: Counting solutions (not optimizing) with 3+ state dimensions and results modulo a prime.

```c
#define MAX_A 1000
#define MAX_B 200
#define MAX_K 200
#define MOD 1000000007

int solve_ijk(char a[], char b[], int i, int j, int k,
              int memo[MAX_A][MAX_B][MAX_K + 1]) {
  int total, q;
  if (memo[i][j][k] != -1)
    return memo[i][j][k];

  // Base: single-char match at start of b
  if (j == 0 && k == 1 && a[i] == b[j]) {
    memo[i][j][k] = 1;
    return memo[i][j][k];
  }

  // Base: out of bounds or no substrings left
  if (i == 0 || j == 0 || k == 0) {
    memo[i][j][k] = 0;
    return memo[i][j][k];
  }

  // Characters don't match, can't end a substring here
  if (a[i] != b[j]) {
    memo[i][j][k] = 0;
    return memo[i][j][k];
  }

  total = 0;
  // Try starting a new substring at every earlier position
  for (q = 0; q < i; q++)
    total = (total + solve_ijk(a, b, q, j - 1, k - 1, memo)) % MOD;
  // Or extend the current substring
  total = (total + solve_ijk(a, b, i - 1, j - 1, k, memo)) % MOD;
  memo[i][j][k] = total;
  return memo[i][j][k];
}
```

**Complexity**: Time O(m²nk) where m = len(a), n = len(b), k = num_substrings. The inner `for q` loop makes each subproblem O(m). Space O(mnk).

**Key variation**: Adding a `total[i][j][k]` prefix-sum subproblem that accumulates `solve_ijk` across all `q < i` eliminates the inner loop, reducing time to O(mnk). This is the prefix-aggregate trick, adding subproblems to remove a per-subproblem loop.

---

## Chapter 5: Graphs and BFS

### Adjacency List Construction (Chapter 5)

**When to use**: Represent an explicit undirected weighted graph when node degree is unknown in advance.

```c
#define MAX_LANGS 101
#define WORD_LENGTH 16

typedef struct edge {
  int to_lang, cost;
  struct edge *next;       // linked list per source node
} edge;

// In main():
static edge *adj_list[MAX_LANGS] = {NULL};

// For each translator (undirected: add edge in both directions)
edge *e;
e = malloc(sizeof(edge));
e->to_lang = to_index;
e->cost    = cost;
e->next    = adj_list[from_index];  // prepend to list
adj_list[from_index] = e;           // head now points to new edge

e = malloc(sizeof(edge));
e->to_lang = from_index;
e->cost    = cost;
e->next    = adj_list[to_index];
adj_list[to_index] = e;
```

**Complexity**: Build time O(m), Space O(n + m) where n = nodes, m = edges. BFS traversal visits each edge once, O(m).

**Key variation**: For directed graphs, add only one edge per translator instead of two. The `from_lang` is implicit (it is the array index), so the struct stores only `to_lang` and `cost`.

---

### BFS on Implicit Graph: Knight Moves (Chapter 5)

**When to use**: Find minimum moves from a source node when the graph is generated on-the-fly (no explicit adjacency list).

```c
typedef struct position {
  int row, col;
} position;

#define MAX_ROWS 99
#define MAX_COLS 99

typedef int board[MAX_ROWS + 1][MAX_COLS + 1];
typedef position positions[MAX_ROWS * MAX_COLS];

void add_position(int from_row, int from_col,
                  int to_row, int to_col,
                  int num_rows, int num_cols,
                  positions new_positions, int *num_new_positions,
                  board min_moves) {
  struct position new_position;
  if (to_row >= 1 && to_col >= 1 &&
      to_row <= num_rows && to_col <= num_cols &&
      min_moves[to_row][to_col] == -1) {  // -1 means not yet visited
    min_moves[to_row][to_col] = 1 + min_moves[from_row][from_col];
    new_position = (position){to_row, to_col};
    new_positions[*num_new_positions] = new_position;
    (*num_new_positions)++;
  }
}

int find_distance(int knight_row, int knight_col,
                  int dest_row, int dest_col,
                  int num_rows, int num_cols) {
  positions cur_positions, new_positions;
  int num_cur_positions, num_new_positions;
  int i, j, from_row, from_col;
  board min_moves;

  for (i = 1; i <= num_rows; i++)
    for (j = 1; j <= num_cols; j++)
      min_moves[i][j] = -1;

  min_moves[knight_row][knight_col] = 0;        // source is 0 moves away
  cur_positions[0] = (position){knight_row, knight_col};
  num_cur_positions = 1;

  while (num_cur_positions > 0) {
    num_new_positions = 0;
    for (i = 0; i < num_cur_positions; i++) {
      from_row = cur_positions[i].row;
      from_col = cur_positions[i].col;

      if (from_row == dest_row && from_col == dest_col)
        return min_moves[dest_row][dest_col];   // early exit when dest found

      // All 8 knight moves
      add_position(from_row, from_col, from_row + 1, from_col + 2,
                   num_rows, num_cols, new_positions, &num_new_positions, min_moves);
      add_position(from_row, from_col, from_row + 1, from_col - 2,
                   num_rows, num_cols, new_positions, &num_new_positions, min_moves);
      add_position(from_row, from_col, from_row - 1, from_col + 2,
                   num_rows, num_cols, new_positions, &num_new_positions, min_moves);
      add_position(from_row, from_col, from_row - 1, from_col - 2,
                   num_rows, num_cols, new_positions, &num_new_positions, min_moves);
      add_position(from_row, from_col, from_row + 2, from_col + 1,
                   num_rows, num_cols, new_positions, &num_new_positions, min_moves);
      add_position(from_row, from_col, from_row + 2, from_col - 1,
                   num_rows, num_cols, new_positions, &num_new_positions, min_moves);
      add_position(from_row, from_col, from_row - 2, from_col + 1,
                   num_rows, num_cols, new_positions, &num_new_positions, min_moves);
      add_position(from_row, from_col, from_row - 2, from_col - 1,
                   num_rows, num_cols, new_positions, &num_new_positions, min_moves);
    }
    // Advance to next BFS round
    num_cur_positions = num_new_positions;
    for (i = 0; i < num_cur_positions; i++)
      cur_positions[i] = new_positions[i];
  }
  return -1;  // destination unreachable
}
```

**Complexity**: Time O(r*c) per call (at most 8rc edges explored), Space O(r*c)

**Key variation**: Remove the early-exit check at the destination to compute distances from the source to *all* nodes in one BFS call instead of one call per destination (500% speedup on the Knight Chase problem).

---

### BFS on Explicit Adjacency-List Graph (Chapter 5)

**When to use**: Shortest-path (fewest edges) on an explicit graph, which also accumulates the minimum-cost edge used to reach each node.

```c
void add_position(int from_lang, int to_lang,
                  positions new_positions, int *num_new_positions,
                  board min_moves) {
  if (min_moves[to_lang] == -1) {
    min_moves[to_lang] = 1 + min_moves[from_lang];
    new_positions[*num_new_positions] = to_lang;
    (*num_new_positions)++;
  }
}

void find_distances(edge *adj_list[], int num_langs, board min_costs) {
  static board min_moves;
  static positions cur_positions, new_positions;
  int num_cur_positions, num_new_positions;
  int i, from_lang, added_lang, best;
  edge *e;

  for (i = 0; i < num_langs; i++) {
    min_moves[i] = -1;
    min_costs[i] = -1;
  }
  min_moves[0] = 0;        // English = node 0 is the source
  cur_positions[0] = 0;
  num_cur_positions = 1;

  while (num_cur_positions > 0) {
    num_new_positions = 0;
    for (i = 0; i < num_cur_positions; i++) {
      from_lang = cur_positions[i];
      e = adj_list[from_lang];       // walk the linked list of edges
      while (e) {
        add_position(from_lang, e->to_lang,
                     new_positions, &num_new_positions, min_moves);
        e = e->next;
      }
    }

    // For each newly discovered node, find the cheapest incoming edge
    // from the previous BFS round (min_moves distance one less)
    for (i = 0; i < num_new_positions; i++) {
      added_lang = new_positions[i];
      e = adj_list[added_lang];
      best = -1;
      while (e) {
        if (min_moves[e->to_lang] + 1 == min_moves[added_lang] &&
            (best == -1 || e->cost < best))
          best = e->cost;
        e = e->next;
      }
      min_costs[added_lang] = best;
    }

    num_cur_positions = num_new_positions;
    for (i = 0; i < num_cur_positions; i++)
      cur_positions[i] = new_positions[i];
  }
}
```

**Complexity**: Time O(n + m), Space O(n + m)

**Key variation**: The secondary loop over `new_positions` (finding cheapest incoming edge) is specific to this problem's tie-breaking rule. For plain shortest-path BFS without cost tie-breaking, that loop is omitted entirely.

---

### 0-1 BFS on Implicit Graph: Two-State Rope Climb (Chapter 5)

**When to use**: Graph has edges costing either 0 or 1 move. Free edges must be processed in the *current* BFS round, not the next.

```c
typedef struct position {
  int height, state;  // state 0 = main rope, state 1 = free-fall rope
} position;

#define SIZE 1000000
typedef int board[SIZE * 2][2];
typedef position positions[SIZE * 4];

/* Jump up one j-distance (costs 1 move, state 0 only) */
void add_position_up(int from_height, int to_height, int max_height,
                     positions pos, int *num_pos,
                     int itching[], board min_moves) {
  int distance = 1 + min_moves[from_height][0];
  if (to_height <= max_height && itching[to_height] == 0 &&
      (min_moves[to_height][0] == -1 ||
       min_moves[to_height][0] > distance)) {
    min_moves[to_height][0] = distance;
    pos[*num_pos] = (position){to_height, 0};
    (*num_pos)++;
  }
}

/* Fall one meter (costs 0 moves, state 1 only) */
void add_position_down(int from_height, int to_height,
                       positions pos, int *num_pos,
                       board min_moves) {
  int distance = min_moves[from_height][1];  // no +1: free move
  if (to_height >= 0 &&
      (min_moves[to_height][1] == -1 ||
       min_moves[to_height][1] > distance)) {
    min_moves[to_height][1] = distance;
    pos[*num_pos] = (position){to_height, 1};
    (*num_pos)++;
  }
}

/* Switch from state 0 to state 1 to begin a fall (costs 1 move) */
void add_position_01(int from_height,
                     positions pos, int *num_pos,
                     board min_moves) {
  int distance = 1 + min_moves[from_height][0];
  if (min_moves[from_height][1] == -1 ||
      min_moves[from_height][1] > distance) {
    min_moves[from_height][1] = distance;
    pos[*num_pos] = (position){from_height, 1};
    (*num_pos)++;
  }
}

/* Switch from state 1 to state 0 to end a fall (costs 0 moves) */
void add_position_10(int from_height,
                     positions pos, int *num_pos,
                     int itching[], board min_moves) {
  int distance = min_moves[from_height][1];  // no +1: free move
  if (itching[from_height] == 0 &&           // can't land on itching powder
      (min_moves[from_height][0] == -1 ||
       min_moves[from_height][0] > distance)) {
    min_moves[from_height][0] = distance;
    pos[*num_pos] = (position){from_height, 0};
    (*num_pos)++;
  }
}

void find_distances(int target_height, int jump_distance,
                    int itching[], board min_moves) {
  static positions cur_positions, new_positions;
  int num_cur_positions, num_new_positions;
  int i, j, from_height, from_state;

  for (i = 0; i < target_height * 2; i++)
    for (j = 0; j < 2; j++)
      min_moves[i][j] = -1;

  min_moves[0][0] = 0;
  cur_positions[0] = (position){0, 0};
  num_cur_positions = 1;

  while (num_cur_positions > 0) {
    num_new_positions = 0;
    for (i = 0; i < num_cur_positions; i++) {
      from_height = cur_positions[i].height;
      from_state  = cur_positions[i].state;

      if (from_state == 0) {
        // Costly moves -> go to new_positions (next BFS round)
        add_position_up(from_height, from_height + jump_distance,
                        target_height * 2 - 1,
                        new_positions, &num_new_positions, itching, min_moves);
        add_position_01(from_height, new_positions, &num_new_positions, min_moves);
      } else {
        // Free moves -> go to cur_positions (same BFS round)
        add_position_down(from_height, from_height - 1,
                          cur_positions, &num_cur_positions, min_moves);
        add_position_10(from_height,
                        cur_positions, &num_cur_positions, itching, min_moves);
      }
    }
    num_cur_positions = num_new_positions;
    for (i = 0; i < num_cur_positions; i++)
      cur_positions[i] = new_positions[i];
  }
}
```

**Complexity**: Time O(h) with ~4h edges (linear), Space O(h). The naive single-rope BFS is O(h^2) due to quadratic fall edges.

**Key variation**: The "two ropes / two states" remodeling trick reduces quadratic fall edges to linear by making individual one-meter falls free and charging only once per fall sequence. This is the defining 0-1 BFS pattern: free edges are appended to `cur_positions`, while costly edges go to `new_positions`.

---

## Chapter 6: Shortest Paths

### Adjacency Matrix to Adjacency List (Chapter 6)

**When to use**: Input is given as an n*n grid of edge weights (complete graph), and adjacency lists are built from it.

```c
#define MAX_TOWNS 700

typedef struct edge {
  int to_town, length;
  struct edge *next;
} edge;

// Reading an adjacency matrix and building adjacency lists
static edge *adj_list[MAX_TOWNS + 1] = {NULL};

for (from_town = 1; from_town <= num_towns; from_town++)
  for (to_town = 1; to_town <= num_towns; to_town++) {
    scanf("%d", &length);
    if (from_town != to_town) {   // skip self-loops (diagonal zeros)
      e = malloc(sizeof(edge));
      if (e == NULL) { fprintf(stderr, "malloc error\n"); exit(1); }
      e->to_town = to_town;
      e->length = length;
      e->next = adj_list[from_town];
      adj_list[from_town] = e;
      // For undirected graphs the symmetric entry handles to_town->from_town
    }
  }
```

**Complexity**: Time O(n^2) to read and build, Space O(n^2) edges stored as adjacency lists

**Key variation**: For undirected graphs, both directions are added automatically as each row is processed (no need to explicitly add the reverse edge).

---

### Dijkstra's Algorithm (Chapter 6)

**When to use**: Find shortest paths in a weighted directed graph from a single source node.

```c
int find_time(edge *adj_list[], int num_cells,
              int from_cell, int exit_cell) {
  static int done[MAX_CELLS + 1];
  static int min_times[MAX_CELLS + 1];

  int i, j, found;
  int min_time, min_time_index, old_time;
  edge *e;

  // Initialize: all cells not done, no known distances
  for (i = 1; i <= num_cells; i++) {
    done[i] = 0;
    min_times[i] = -1;   // -1 means "not yet reached"
  }

  min_times[from_cell] = 0;  // distance from source to itself is 0

  for (i = 0; i < num_cells; i++) {
    min_time = -1;
    found = 0;

    // Inner loop: find the not-done cell with minimum known distance
    for (j = 1; j <= num_cells; j++) {
      if (!done[j] && min_times[j] >= 0) {
        if (min_time == -1 || min_times[j] < min_time) {
          min_time = min_times[j];
          min_time_index = j;
          found = 1;
        }
      }
    }

    if (!found)      // unreachable cells remain; stop early
      break;
    done[min_time_index] = 1;

    // Relax edges from the newly done cell
    e = adj_list[min_time_index];
    while (e) {
      old_time = min_times[e->to_cell];
      if (old_time == -1 || old_time > min_time + e->length)
        min_times[e->to_cell] = min_time + e->length;
      e = e->next;
    }
  }

  return min_times[exit_cell];  // -1 if no path exists
}
```

**Complexity**: Time O(n^2), Space O(n)

**Key variation**: Early termination once exit cell is set to done. Reversed-graph trick to run once from exit instead of once per cell. Can be improved to O((n + m) log n) with a min-heap priority queue.

---

## Chapter 7: Binary Search

### Binary Search on Answer: Continuous Range (Chapter 7)

**When to use**: Optimize a real-valued answer when feasibility is easy to check but optimality is not. Search space transitions from infeasible to feasible.

```c
#define HIGHEST 2000000000

void solve(edge *adj_list[], int liquid_needed[]) {
  double low, high, mid;
  low = 0;
  high = HIGHEST;
  while (high - low > 0.00001) {  // stop once 4-decimal accuracy achieved
    mid = (low + high) / 2;
    if (can_feed(1, mid, adj_list, liquid_needed))
      high = mid;   // mid is feasible; cut off larger values
    else
      low = mid;    // mid is infeasible; cut off smaller values
  }
  printf("%.4lf\n", high);
}
```

**Complexity**: Time O(n log m), Space O(n), where n = tree nodes and m = range width (2*10^9 here). About 48 iterations are needed for 4-decimal accuracy over a 2-billion range.

**Key variation**: When feasible-to-infeasible (maximize), use `low = mid` on feasibility. When infeasible-to-feasible (minimize), use `high = mid` on feasibility. Output `high` when minimizing, `low` when maximizing.

---

### Feasibility Testing: Recursive Tree Traversal (Chapter 7)

**When to use**: Check whether a candidate value is feasible by simulating the problem on the input structure (here: does `liquid` liters fed into a tree root satisfy all leaf demands?).

```c
int can_feed(int node, double liquid,
             edge *adj_list[], int liquid_needed[]) {
  edge *e;
  int ok;
  double down_pipe;
  if (liquid_needed[node] != -1)        // base case: leaf node
    return liquid >= liquid_needed[node];
  e = adj_list[node];
  ok = 1;
  while (e && ok) {
    down_pipe = liquid * e->percentage / 100;
    if (e->superpipe)
      down_pipe = down_pipe * down_pipe; // always activate: squaring only helps
    if (!can_feed(e->to_node, down_pipe, adj_list, liquid_needed))
      ok = 0;
    e = e->next;
  }
  return ok;
}
```

**Complexity**: Time O(n) per call (linear tree traversal), Space O(depth) recursion stack.

**Key variation**: Non-obvious insight, always activate superpipe (squaring) because it maximizes liquid, and any infeasible subtree remains infeasible regardless.

---

### Binary Search on Answer: Integer Range with Invariant (Chapter 7)

**When to use**: Maximize a discrete (integer) answer. Search space transitions from feasible to infeasible.

```c
void solve(int rocks[], int num_rocks,
           int num_remove, int length) {
  int low, high, mid;
  low = 0;
  high = length + 1;  // +1 ensures high is always infeasible (invariant)
  while (high - low > 1) {
    mid = (low + high) / 2;
    if (can_make_min_distance(mid, rocks, num_rocks, num_remove, length))
      low = mid;   // mid feasible: everything <= mid is feasible
    else
      high = mid;  // mid infeasible: everything >= mid is infeasible
  }
  printf("%d\n", low);  // low = largest feasible value when loop ends
}
```

**Complexity**: Time O(n log L), Space O(1), where n = number of rocks, L = river length.

**Key variation**: Invariant-based initialization: `low` is always feasible, `high` is always infeasible. Output `low` (maximization). For minimization (feasible-to-infeasible split), initialize `high = r*c+1`, output `high`.

---

### Feasibility Testing: Greedy Left-to-Right Scan (Chapter 7)

**When to use**: Check whether a minimum jump distance `distance` is achievable by removing at most `num_remove` rocks. Greedily remove any rock too close to the previously kept rock.

```c
int can_make_min_distance(int distance, int rocks[], int num_rocks,
                          int num_remove, int length) {
  int i;
  int removed = 0, prev_rock_location = 0, cur_rock_location;
  if (length < distance)
    return 0;
  for (i = 0; i < num_rocks; i++) {
    cur_rock_location = rocks[i];
    if (cur_rock_location - prev_rock_location < distance)
      removed++;               // too close: must remove
    else
      prev_rock_location = cur_rock_location;  // far enough: keep it
  }
  if (length - prev_rock_location < distance)
    removed++;  // rightmost kept rock too close to river end
  return removed <= num_remove;
}
```

**Complexity**: Time O(n) per call. Rocks array must be sorted ascending before use.

**Key variation**: The greedy "remove if too close" rule is provably optimal for feasibility checking, even though a direct greedy approach to the optimization problem (remove smallest gap first) is incorrect.

---

### Binary Search on Answer: 2D Feasibility with Prefix Sums (Chapter 7)

**When to use**: Minimize a discrete answer over a 2D grid. Feasibility check replaces sorting with a +/-1 transform and 2D prefix sums for O(1) rectangle queries.

```c
int rectangle(int r, int c, int h, int w, board q) {
  int low, high, mid;
  low = 0;
  high = r * c + 1;  // +1 ensures high is always feasible (invariant)
  while (high - low > 1) {
    mid = (low + high) / 2;
    if (can_make_quality(mid, r, c, h, w, q))
      high = mid;  // mid feasible: a smaller median may exist
    else
      low = mid;   // mid infeasible: need larger cutoff
  }
  return high;     // smallest feasible value
}
```

**Complexity**: Time O(m^2 log m) overall, O(m^2) per feasibility call * O(log m) binary search iterations, where m = max(r, c).

**Key variation**: Feasibility test replaces each cell value with -1 (<=quality) or +1 (>quality), builds 2D prefix sum array, then checks if any h*w rectangle has sum <= 0 (meaning at least half its values <= quality, i.e., median <= quality).

---

### Feasibility Testing: 2D Prefix Sum Rectangle Query (Chapter 7)

**When to use**: Determine in O(1) whether any h*w rectangle in a grid has median <= quality, after O(m^2) preprocessing.

```c
int can_make_quality(int quality, int r, int c, int h, int w, board q) {
  static int zero_one[MAX_ROWS][MAX_COLS];
  static int sum[MAX_ROWS + 1][MAX_COLS + 1];  // 1-indexed; row/col 0 = sentinel zeros
  int i, j;
  int top_row, left_col, bottom_row, right_col;
  int total;

  // Step 1: map values to -1 (<=quality) or +1 (>quality)
  for (i = 0; i < r; i++)
    for (j = 0; j < c; j++)
      if (q[i][j] <= quality)
        zero_one[i][j] = -1;
      else
        zero_one[i][j] = 1;

  // Step 2: build 2D prefix sum (1-indexed, borders pre-zeroed)
  for (i = 0; i <= c; i++) sum[0][i] = 0;
  for (i = 0; i <= r; i++) sum[i][0] = 0;
  for (i = 1; i <= r; i++)
    for (j = 1; j <= c; j++)
      sum[i][j] = zero_one[i-1][j-1] + sum[i-1][j] +
                  sum[i][j-1] - sum[i-1][j-1];  // inclusion-exclusion

  // Step 3: O(1) query per rectangle; return true if any has median <= quality
  for (top_row = 1; top_row <= r - h + 1; top_row++)
    for (left_col = 1; left_col <= c - w + 1; left_col++) {
      bottom_row = top_row + h - 1;
      right_col = left_col + w - 1;
      total = sum[bottom_row][right_col] - sum[top_row-1][right_col] -
              sum[bottom_row][left_col-1] + sum[top_row-1][left_col-1];
      if (total <= 0)
        return 1;
    }
  return 0;
}
```

**Complexity**: Time O(m^2) per call (build prefix sum + scan rectangles), Space O(m^2) for sum array.

**Key variation**: The rectangle sum formula `sum[br][rc] - sum[tr-1][rc] - sum[br][lc-1] + sum[tr-1][lc-1]` is the standard 2D inclusion-exclusion identity. The 1-indexed layout avoids bounds-checking on edge rows/columns.

---

## Chapter 8: Heaps and Segment Trees

### Max-Heap Insert (Chapter 8)

**When to use**: Insert a new element into a max-heap, maintaining the heap-order property.

```c
typedef struct heap_element {
  int receipt_index;
  int cost;
} heap_element;

void max_heap_insert(heap_element heap[], int *num_heap,
                     int receipt_index, int cost) {
  int i;
  heap_element temp;

  (*num_heap)++;
  heap[*num_heap] = (heap_element){receipt_index, cost};

  i = *num_heap;
  while (i > 1 && heap[i].cost > heap[i / 2].cost) {  // bubble up while larger than parent
    temp = heap[i];
    heap[i] = heap[i / 2];
    heap[i / 2] = temp;
    i = i / 2;  // move to parent
  }
}
```

**Complexity**: Time O(log n), Space O(1)

**Key variation**: Array is 1-indexed. heap[0] is unused. Parent of node i is at i/2, children at 2i and 2i+1.

---

### Max-Heap Extract (Chapter 8)

**When to use**: Remove and return the maximum element from a max-heap.

```c
heap_element max_heap_extract(heap_element heap[], int *num_heap) {
  heap_element remove, temp;
  int i, child;

  remove = heap[1];           // save root (maximum)
  heap[1] = heap[*num_heap];  // move last element to root
  (*num_heap)--;

  i = 1;
  while (i * 2 <= *num_heap) {        // while left child exists
    child = i * 2;                    // start with left child
    if (child < *num_heap && heap[child + 1].cost > heap[child].cost)
      child++;                        // use right child if it's larger
    if (heap[child].cost > heap[i].cost) {  // violation: swap down
      temp = heap[i];
      heap[i] = heap[child];
      heap[child] = temp;
      i = child;
    } else
      break;  // no violation; heap order restored
  }
  return remove;
}
```

**Complexity**: Time O(log n), Space O(1)

**Key variation**: Always swap with the larger child to preserve heap-order with both children.

---

### Min-Heap Insert (Chapter 8)

**When to use**: Insert a new element into a min-heap, maintaining the min-heap-order property.

```c
void min_heap_insert(heap_element heap[], int *num_heap,
                     int receipt_index, int cost) {
  int i;
  heap_element temp;
  (*num_heap)++;
  heap[*num_heap] = (heap_element){receipt_index, cost};

  i = *num_heap;
  while (i > 1 && heap[i].cost < heap[i / 2].cost) {  // bubble up while smaller than parent
    temp = heap[i];
    heap[i] = heap[i / 2];
    heap[i / 2] = temp;
    i = i / 2;
  }
}
```

**Complexity**: Time O(log n), Space O(1)

**Key variation**: Identical to max-heap insert with `>` changed to `<`.

---

### Min-Heap Extract (Chapter 8)

**When to use**: Remove and return the minimum element from a min-heap.

```c
heap_element min_heap_extract(heap_element heap[], int *num_heap) {
  heap_element remove, temp;
  int i, child;
  remove = heap[1];
  heap[1] = heap[*num_heap];
  (*num_heap)--;
  i = 1;
  while (i * 2 <= *num_heap) {
    child = i * 2;
    if (child < *num_heap && heap[child + 1].cost < heap[child].cost)
      child++;                               // use smaller child
    if (heap[child].cost < heap[i].cost) {  // violation: swap down
      temp = heap[i];
      heap[i] = heap[child];
      heap[child] = temp;
      i = child;
    } else
      break;
  }
  return remove;
}
```

**Complexity**: Time O(log n), Space O(1)

**Key variation**: Identical to max-heap extract with `>` changed to `<`.

---

### Segment Tree: Initialize (Chapter 8)

**When to use**: Set up the left/right range fields for every node before filling values, called once before build.

```c
typedef struct segtree_node {
  int left, right;
  int max_index;  // or max_sum/max_element depending on query type
} segtree_node;

// Initial call: init_segtree(segtree, 1, 0, num_elements - 1)
void init_segtree(segtree_node segtree[], int node,
                  int left, int right) {
  int mid;
  segtree[node].left = left;
  segtree[node].right = right;

  if (left == right)   // base case: single-element segment
    return;

  mid = (left + right) / 2;
  init_segtree(segtree, node * 2,     left,    mid);   // left child
  init_segtree(segtree, node * 2 + 1, mid + 1, right); // right child
}
```

**Complexity**: Time O(n), Space O(n), allocate array of size 4n to be safe

**Key variation**: Allocate segment tree array of 4*n elements. It is 1-indexed, so pass MAX_NODES*4+1 as array size.

---

### Segment Tree: Build (Range Maximum Query) (Chapter 8)

**When to use**: Fill each node with the index of the maximum element in its segment, used for RMQ after init_segtree.

```c
// Returns index of max-priority element in node's segment
// Initial call: fill_segtree(segtree, 1, treap_nodes)
int fill_segtree(segtree_node segtree[], int node,
                 treap_node treap_nodes[]) {
  int left_max, right_max;

  if (segtree[node].left == segtree[node].right) {  // base: single element
    segtree[node].max_index = segtree[node].left;
    return segtree[node].max_index;
  }

  left_max  = fill_segtree(segtree, node * 2,     treap_nodes);
  right_max = fill_segtree(segtree, node * 2 + 1, treap_nodes);

  // choose whichever child has higher priority
  if (treap_nodes[left_max].priority > treap_nodes[right_max].priority)
    segtree[node].max_index = left_max;
  else
    segtree[node].max_index = right_max;

  return segtree[node].max_index;
}
```

**Complexity**: Time O(n), Space O(n)

**Key variation**: Replace priority comparison with any associative operation (min, sum, etc.) to support different query types.

---

### Segment Tree: Query (Range Maximum Query) (Chapter 8)

**When to use**: Answer a range maximum index query in O(log n) after the tree is built.

```c
// Returns index of max-priority element in [left, right]; -1 if no overlap
// Initial call: query_segtree(segtree, 1, treap_nodes, left, right)
int query_segtree(segtree_node segtree[], int node,
                  treap_node treap_nodes[], int left, int right) {
  int left_max, right_max;

  // Case 1: no overlap with query range
  if (right < segtree[node].left || left > segtree[node].right)
    return -1;

  // Case 2: node's segment fully contained in query range
  if (left <= segtree[node].left && segtree[node].right <= right)
    return segtree[node].max_index;

  // If partial overlap, recurse into both children
  left_max  = query_segtree(segtree, node * 2,     treap_nodes, left, right);
  right_max = query_segtree(segtree, node * 2 + 1, treap_nodes, left, right);

  if (left_max  == -1) return right_max;
  if (right_max == -1) return left_max;

  if (treap_nodes[left_max].priority > treap_nodes[right_max].priority)
    return left_max;
  return right_max;
}
```

**Complexity**: Time O(log n), Space O(log n) call stack

**Key variation**: The three-case pattern (no overlap / full containment / partial overlap) applies to all segment tree query types.

---

### Segment Tree: Update (Chapter 8)

**When to use**: Update a single array element and propagate changes up the segment tree in O(log n).

```c
typedef struct node_info {
  int max_sum, max_element;
} node_info;

// Call AFTER seq[index] has been updated
// Initial call: update_segtree(segtree, 1, seq, index)
node_info update_segtree(segtree_node segtree[], int node,
                         int seq[], int index) {
  segtree_node left_node, right_node;
  node_info left_info, right_info;

  if (segtree[node].left == segtree[node].right) {  // base: leaf node
    segtree[node].max_element = seq[index];
    return (node_info){segtree[node].max_sum, segtree[node].max_element};
  }

  left_node  = segtree[node * 2];
  right_node = segtree[node * 2 + 1];

  // recurse only into the child that contains the updated index
  if (index <= left_node.right) {
    left_info  = update_segtree(segtree, node * 2, seq, index);
    right_info = (node_info){right_node.max_sum, right_node.max_element};
  } else {
    right_info = update_segtree(segtree, node * 2 + 1, seq, index);
    left_info  = (node_info){left_node.max_sum, left_node.max_element};
  }

  segtree[node].max_element = max(left_info.max_element, right_info.max_element);

  // recompute max_sum (-1 means segment has only one element, no valid pair sum)
  if (left_info.max_sum == -1 && right_info.max_sum == -1)
    segtree[node].max_sum = left_info.max_element + right_info.max_element;
  else if (left_info.max_sum == -1)
    segtree[node].max_sum = max(left_info.max_element + right_info.max_element,
                                right_info.max_sum);
  else if (right_info.max_sum == -1)
    segtree[node].max_sum = max(left_info.max_element + right_info.max_element,
                                left_info.max_sum);
  else
    segtree[node].max_sum = max(left_info.max_element + right_info.max_element,
                                max(left_info.max_sum, right_info.max_sum));

  return (node_info){segtree[node].max_sum, segtree[node].max_element};
}
```

**Complexity**: Time O(log n), Space O(log n) call stack

**Key variation**: Only one recursive branch is taken (the child whose segment contains `index`), keeping the update to O(log n) rather than O(n).

---

## Chapter 9: Union-Find

### Union-Find with Union by Size + Path Compression (Chapter 9)

**When to use**: Maintain disjoint sets with near-constant-time union and find operations. Use when the problem reduces to equivalence-class membership rather than shortest paths.

```c
// find with path compression
int find(int person, int parent[]) {
  int community = person, temp;

  // Phase 1: walk up to root
  while (parent[community] != community)
    community = parent[community];

  // Flatten by pointing every node on path directly to root
  while (parent[person] != community) {
    temp = parent[person];
    parent[person] = community;
    person = temp;
  }
  return community;
}

// union with union-by-size
void union_communities(int person1, int person2, int parent[],
                       int size[], int num_community) {
  int community1, community2, temp;
  community1 = find(person1, parent);
  community2 = find(person2, parent);
  if (community1 != community2 &&
      size[community1] + size[community2] <= num_community) {

    // ensure community2 is the larger (or equal) set
    if (size[community1] > size[community2]) {
      temp = community1;
      community1 = community2;
      community2 = temp;
    }

    // fold smaller community1 into larger community2
    parent[community1] = community2;
    size[community2] = size[community2] + size[community1];
  }
}

// initialization
// for (i = 1; i <= num_people; i++) {
//   parent[i] = i;   // each person is their own root
//   size[i] = 1;
// }
```

**Complexity**: Time O(alpha(n)) amortized per operation (inverse Ackermann, effectively constant), Space O(n)

**Key variation**: When the root identity carries semantic meaning (e.g., the Drawer Chore problem where the root must always be the empty drawer), union by size must be omitted: always fold the first set into the second regardless of size. Path compression remains safe in such cases. A sentinel representative of `0` can flag sets where no valid placement is possible.

---

## Chapter 10: Randomization

### Randomized Algorithm: Monte Carlo (Chapter 10)

**When to use**: Randomly sample candidates when the probability of hitting a valid answer per attempt is high (>= 1/3), repeating enough times to make failure probability negligible.

```c
#define NUM_ATTEMPTS 60  // 60 attempts per friend gives ~99.9999999% success per query

int random_piece(int left, int width) {
    return (rand() % width) + left;  // random index in [left, left+width-1]
}

// Binary search: leftmost index in pieces[] with value >= at_least
int lowest_index(int pieces[], int num_pieces, int at_least) {
    int low, high, mid;
    low = 0;
    high = num_pieces;  // one past end
    while (high - low >= 1) {
        mid = (low + high) / 2;
        if (pieces[mid] < at_least)
            low = mid + 1;
        else
            high = mid;
    }
    return low;
}

// Count how many elements of pieces[] fall in [left, right]
int num_in_range(int pieces[], int num_pieces, int left, int right) {
    int left_index  = lowest_index(pieces, num_pieces, left);
    int right_index = lowest_index(pieces, num_pieces, right + 1);
    return right_index - left_index;
}

void solve(int yokan[], int *pieces_for_flavor[],
           int num_of_flavor[], int left, int right) {
    int attempt, rand_piece, flavor, result;
    int width = right - left + 1;
    double threshold = width / 3.0;  // min pieces needed to satisfy one friend
    int first_flavor = 0;

    // Step 1: find a flavor for the first friend
    for (attempt = 0; attempt < NUM_ATTEMPTS; attempt++) {
        rand_piece = random_piece(left, width);
        flavor = yokan[rand_piece];
        result = num_in_range(pieces_for_flavor[flavor],
                              num_of_flavor[flavor], left, right);
        if (result >= 2 * threshold) {  // flavor satisfies BOTH friends alone
            printf("YES\n");
            return;
        }
        if (result >= threshold)        // flavor satisfies first friend
            first_flavor = flavor;
    }

    if (first_flavor == 0) { printf("NO\n"); return; }

    // Step 2: find a distinct flavor for the second friend
    for (attempt = 0; attempt < NUM_ATTEMPTS; attempt++) {
        rand_piece = random_piece(left, width);
        flavor = yokan[rand_piece];
        if (flavor == first_flavor)     // skip the already-used flavor
            continue;
        result = num_in_range(pieces_for_flavor[flavor],
                              num_of_flavor[flavor], left, right);
        if (result >= threshold) {
            printf("YES\n");
            return;
        }
    }
    printf("NO\n");
}
```

**Complexity**: Time O(NUM_ATTEMPTS * log n) per query, Space O(n)

**Key variation**: One-sided error: YES answers are always correct, but only NO answers can (with negligible probability) be wrong. Seeding with `srand((unsigned) time(NULL))` is required before use.

---

### Quicksort with Random Pivot (Chapter 10)

**When to use**: General-purpose sorting. Randomizing the pivot prevents adversarial O(n^2) worst cases, giving O(n log n) expected runtime.

```c
void swap(int *x, int *y) {
    int temp = *x;
    *x = *y;
    *y = temp;
}

void quicksort(int values[], int n) {
    int i, small_count, big_count, pivot_index, pivot;
    int *small_values = malloc_safe(n * sizeof(int));
    int *big_values   = malloc_safe(n * sizeof(int));
    if (n == 0)
        return;

    small_count = 0;
    big_count   = 0;

    pivot_index = rand() % n;                    // random pivot, key Las Vegas step
    swap(&values[0], &values[pivot_index]);      // move pivot to front
    pivot = values[0];

    for (i = 1; i < n; i++) {                   // partition remaining elements
        if (values[i] > pivot) {
            big_values[big_count++] = values[i];
        } else {
            small_values[small_count++] = values[i];
        }
    }

    quicksort(small_values, small_count);
    quicksort(big_values, big_count);

    // Reconstruct: [small | pivot | big] back into values[]
    for (i = 0; i < small_count; i++)
        values[i] = small_values[i];
    values[small_count] = pivot;
    for (i = 0; i < big_count; i++)
        values[small_count + 1 + i] = big_values[i];
}

// Caller must seed once: srand((unsigned) time(NULL));
```

**Complexity**: Time O(n log n) expected, O(n^2) worst case (astronomically unlikely with random pivot), Space O(n) auxiliary per level

**Key variation**: This is a Las Vegas algorithm: it always produces a correct sorted result, but only runtime varies. An in-place variant (covered in Appendix B) reduces memory usage significantly.
