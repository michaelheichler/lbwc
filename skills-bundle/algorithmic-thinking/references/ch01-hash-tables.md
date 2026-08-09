# Chapter 1: Hash Tables

## Key Concepts

- **Hash Table**: A data structure consisting of an array (whose slots are called *buckets*) and a *hash function* that maps an object to an integer index (its *hashcode*) determining which bucket the object is stored in. Hash tables convert slow O(n) linear searches into expected O(1) lookups, yielding overall O(n) algorithms where naive pairwise approaches would be O(n²).

- **Hash Function**: A function that takes an object and returns an integer index into the hash table array. Two objects that are considered "identical" by the problem's definition *must* hash to the same bucket. Non-identical objects may also share a bucket (a *collision*), but good hash functions keep collisions rare. The quality of a hash function directly determines hash table performance.

- **Hashcode / Hash Code**: The integer returned by the hash function for a given object. Used directly as the array index (bucket number).

- **Bucket**: One slot in the hash table array. Each bucket typically holds a linked list (chaining scheme) of all objects that hashed to that index.

- **Collision**: When two distinct objects produce the same hashcode and therefore land in the same bucket. Collisions are unavoidable in general but should be minimized by good hash function design and appropriate table sizing.

- **Chaining**: The collision-resolution strategy used throughout this chapter: each bucket stores a linked list of all objects that hash to it. Insertion is O(1) (prepend to list). Search is O(k) where k is the bucket's list length. When lists stay short (expected under uniform hashing), all operations are effectively O(1).

- **Open Addressing**: An alternative collision-resolution strategy (mentioned but not implemented) where each bucket holds at most one element. Collisions are resolved by probing nearby buckets. Saves linked-list node memory but can degrade with high load factors.

- **Linked List (singly-linked)**: Each node holds a data payload and a `next` pointer to the following node. New nodes are prepended (O(1)) rather than appended (O(n)) to keep insertion fast. Used as the per-bucket container in both Unique Snowflakes and Login Mayhem.

- **Hash Table Size / Load Factor**: The array size controls the memory-time tradeoff. Too small → many collisions and long bucket lists. Too large → memory waste. A practical rule of thumb: choose an array size in the range of 20-100% of the maximum number of elements to be inserted. The chapter uses array size equal to the maximum element count (100,000) for Unique Snowflakes.

- **oaat (One-At-A-Time) Hash Function**: A high-quality general-purpose hash function by Bob Jenkins that hashes arbitrary byte sequences. It implements an *avalanche effect* (a small change in the key causes a large change in the hashcode), making collisions unlikely on non-adversarial data. It requires the hash table size to be a power of 2 (uses bitmask `hashmask(n)` instead of mod). Signature: `unsigned long oaat(char *key, unsigned long len, unsigned long bits)`.

- **Sum-Based Hash Function**: A simple domain-specific hash function used for snowflakes: sum the six arm values mod table size. Guarantees that identical snowflakes (under the problem's rotation/reflection definition) hash identically, because any rotation/reflection preserves the sum. Prone to collisions for anagrams, so unsuitable for order-sensitive strings.

- **Big O / Quadratic vs. Linear Time**: The chapter contrasts O(n²) pairwise comparison algorithms with O(n) hash-table-based solutions. With n = 100,000 and a ~30 million operations/second budget, O(n²) produces ~5 billion comparisons (~3 minutes) while O(n) completes in a fraction of a second.

- **Incremental Hash Functions**: Hash functions that can extend an existing hashcode with one additional character in O(1) rather than recomputing from scratch. Shown as an intermediate (ultimately abandoned) approach for Spelling Check using the recurrence `prefix[i] = prefix[i-1] * 39 + s[i]`.

- **Static Arrays in C**: Arrays declared `static` inside a function are placed in a separate memory region (not the stack), allowing large allocations (e.g., `static int snowflakes[100000][6]`) that would overflow the stack otherwise. Static variables retain their value across function calls.

- **Mod Operator for Wraparound**: The `%` operator is used in two ways in this chapter: (1) to wrap a large hashcode into a valid array index (`sum % SIZE`), and (2) to implement circular traversal of a snowflake's arms (`(start + offset) % 6`). The mod trick does not work for leftward traversal in C because `(-1) % 6 == -1` (not 5).

---

## Problems Covered

### Problem: Unique Snowflakes
- **Source**: DMOJ `cco07p2` (2007 Canadian Computing Olympiad)
- **Core Idea**: Given up to 100,000 snowflakes, each represented by 6 integers (arm lengths), determine whether any two snowflakes are identical. Two snowflakes are identical if one can be rotated clockwise or counterclockwise to match the other (i.e., they match starting at some offset moving right *or* moving left through the circular sequence).
- **Approach**: Build a hash table of size 100,000 where each bucket is a linked list. The hash function sums a snowflake's six values mod 100,000. Insert each snowflake into its bucket. For each bucket, perform pairwise comparisons only among snowflakes in that same bucket using the `are_identical` function. Because identical snowflakes must have the same element sum, they are guaranteed to land in the same bucket.
- **Complexity**: Expected O(n) time and O(n) space. Worst case (adversarial data forcing all snowflakes into one bucket) degrades to O(n²), but this does not occur on judge test cases.
- **Key Insight**: The snowflake identity check requires testing 12 offset/direction combinations (6 starting positions × 2 directions). Rather than comparing all O(n²) pairs, hashing by sum guarantees identical snowflakes co-locate in the same bucket, reducing comparisons to only within-bucket pairs which are expected to be short.

**Helper functions**:
- `identical_right(int snow1[], int snow2[], int start)`: checks whether snow1 matches snow2 starting at index `start` moving rightward (clockwise), using `(start + offset) % 6` for wraparound.
- `identical_left(int snow1[], int snow2[], int start)`: checks whether snow1 matches snow2 starting at index `start` moving leftward (counterclockwise), using subtraction with explicit underflow correction (`snow2_index + 6` when `snow2_index <= -1`).
- `are_identical(int snow1[], int snow2[])`: iterates all 6 starting positions, calling both `identical_right` and `identical_left`.
- `code(int snowflake[])`: sums 6 elements mod `SIZE` (100,000), defined in terms of `#define SIZE 100000`.
- `snowflake_node` struct: holds `int snowflake[6]` and `struct snowflake_node *next`.
- `identify_identical(snowflake_node *snowflakes[])`: outer loop over all buckets. Inner nested while-loops for pairwise comparison within each bucket's linked list (node2 starts at `node1->next` to avoid self-comparison).

**Sorting dead-end**: An attempt to sort snowflakes so identical ones are adjacent fails because the `are_identical` equality relation does not induce a consistent total order satisfying transitivity. `qsort` may infer `a < c` by transitivity without directly comparing `a` and `c`, causing identical pairs to be separated.

---

### Problem: Login Mayhem
- **Source**: DMOJ `coci17c1p3hard` (2017 Croatian Open Competition in Informatics, Round 1)
- **Core Idea**: Support two operations on a growing set of user passwords (each 1-10 lowercase chars, up to 100,000 operations total): (1) Add a new user password. (2) Query: given a proposed password `p`, count how many existing user passwords contain `p` as a substring. A user's password grants access to an account with password `p` if and only if the user's password contains `p` as a substring.
- **Approach**: On each Add operation, enumerate every distinct substring of the new password and increment a counter for each substring in a hash table (keyed by the substring string, value is count). On each Query operation, look up the proposed password in the hash table and return its count (or 0 if absent). Uses `oaat` hash function with `NUM_BITS = 20` (table size 2²⁰ = 1,048,576). Insertion prepends to the bucket's linked list. A separate `already_added` linear-search helper prevents double-counting duplicate substrings within a single password (e.g., `aaa` contributes only 1 to `a`'s count, not 3).
- **Complexity**: O(n) expected overall. Each Add processes at most 10×10 = 100 substrings (passwords ≤ 10 chars). Each Query is an O(1) hash lookup. Total substring insertions bounded by 100,000 × 100 = 10,000,000.
- **Key Insight**: Instead of scanning all existing passwords on each query (O(n) per query → O(n²) total), precompute counts for every possible substring during insertion. This inverts the work from query-time to add-time. Because passwords are at most 10 characters, the number of distinct substrings per password is at most 55 (and at most 100 with the double-loop bound), keeping per-add work constant.

**Key functions**:
- `password_node` struct: holds `char password[MAX_PASSWORD + 1]`, `int total`, `struct password_node *next`.
- `in_hash_table(password_node *hash_table[], char *find)`: computes `oaat` hashcode, walks the linked list at that bucket comparing with `strcmp`, returns pointer to matching node or `NULL`.
- `add_to_hash_table(password_node *hash_table[], char *find)`: calls `in_hash_table`. If absent, allocates a new node with `total = 0` and prepends it, then increments `total` unconditionally.
- `already_added(char all_substrings[][MAX_PASSWORD + 1], int total_substrings, char *find)`: linear scan of the per-password substring accumulator array, used to skip duplicate substrings before calling `add_to_hash_table`.
- In `main`, `strncpy` + manual null-termination extracts each substring by varying start index `i` and end index `j`.

**Bug illustrated**: The first `main` (Listing 1-17) is labeled "bugged" because it counts each occurrence of a substring (e.g., three `a`s in `aaa`), not each distinct substring per password. Fix: track `all_substrings[]` per password and skip duplicates.

---

### Problem: Spelling Check
- **Source**: Codeforces 39J (2010 School Team Contest #1)
- **Core Idea**: Given two strings where the first is exactly one character longer than the second (both up to 1,000,000 characters), output the number of positions in the first string where a single character deletion transforms it into the second string, along with the list of those positions (1-indexed).
- **Approach**: Compute the length `p` of the longest common prefix of the two strings and the length `s` of the longest common suffix (with the suffix comparison offset by 1 to account for the length difference). Valid deletion indices form a contiguous range `[n - s, p + 1]` (1-indexed, where `n` is the length of the first string). The count is `(p + 1) - (n - s) + 1`. If negative, output 0. Print the indices in that range.
- **Complexity**: O(n) time, O(n) space (for input storage). No hash table needed.
- **Key Insight**: Any valid deletion index must satisfy two independent constraints: it must be within the first `p + 1` characters (otherwise the prefix mismatch at position `p + 1` is unfixed) and within the last `s + 1` characters (otherwise the suffix mismatch is unfixed). The valid indices are exactly those in the overlap of these two ranges, a contiguous block computable in O(n).

**Helper functions**:
- `prefix_length(char s1[], char s2[])`: walks from index 1 forward while `s1[i] == s2[i]`, returns `i - 1`. Works with 1-based indexing. Null-terminator mismatch naturally ends the loop.
- `suffix_length(char s1[], char s2[], int len)`: walks from index `len` backward comparing `s1[i]` with `s2[i - 1]` (offset by 1 because s1 is longer), stopping at `i == 2` to avoid accessing `s2[0]`, and returns `len - i`.
- `main` allocates `static char s1[SIZE + 2], s2[SIZE + 2]` (extra slot for 1-based indexing and null terminator) and uses `gets(&s1[1])` to read into index 1.

**Hash table dead-end**: The author's attempted hash-table approach (hashing all prefixes and suffixes of the second string) failed because: (1) strings of up to 1,000,000 characters make string comparison in hash buckets prohibitively expensive, and (2) recomputing `oaat` on million-character prefixes duplicates O(n) work per call. An incremental hash (`prefix[i] = prefix[i-1] * 39 + s[i]`) was explored but ultimately abandoned in favor of the cleaner direct solution.

---

## Algorithm Patterns

- **Pattern 1 (Hash-Before-Compare)**: When a problem requires finding matching pairs or counting matches among n elements, avoid O(n²) pairwise comparison by using a hash function to group likely-matches into buckets, then compare only within buckets. Requires a hash function that *guarantees* identical objects land in the same bucket.

- **Pattern 2 (Precompute-at-Insert, Lookup-at-Query)**: When queries ask "how many existing items satisfy property P with respect to query key k?", consider inverting: at insert time, enumerate all keys that could match this item and increment their counts. Queries then become O(1) lookups. Feasible when the set of enumerable keys per item is bounded (here, ≤ 100 substrings per password).

- **Pattern 3 (Circular Array Traversal with Mod)**: To traverse a length-6 array circularly in the forward direction starting at `start`, use index `(start + offset) % 6`. For backward direction, use explicit underflow correction: if `index < 0`, add 6. The mod trick does not work cleanly for negative indices in C.

- **Pattern 4 (Prepend-to-Linked-List for O(1) Insert)**: When building hash table buckets as linked lists, always insert new nodes at the *head* of the list (`new->next = head; head = new`). Appending would require traversing the entire list. Correctness is unaffected by list order.

- **Pattern 5 (Longest Common Prefix/Suffix for String Matching)**: When a problem requires determining whether a deletion/insertion at some position produces a target string, compute the longest common prefix length `p` and longest common suffix length `s`. Valid operation positions form the range `[n - s, p + 1]`. This avoids any substring comparison beyond a single linear pass.

- **Pattern 6 (Incremental Hashing)**: When a sequence of related strings must be hashed (e.g., all prefixes of a string), use a polynomial rolling hash `h[i] = h[i-1] * BASE + s[i]` to compute each new hashcode in O(1) from the previous one. Requires unsigned integer arithmetic to avoid undefined overflow behavior in C.

- **Pattern 7 (Question Hash Function Design)**: The hash function must respect the problem's notion of equality. For Unique Snowflakes, rotation/reflection preserves the sum, so sum-mod-n is valid. For order-sensitive strings (Login Mayhem), sum-based hashing is unsuitable because anagrams collide. Use `oaat` instead.

- **When to recognize a hash table problem**: The solution involves repeatedly searching for some element in a growing collection. A naive O(n²) solution uses two nested loops where the inner loop is a linear scan. Two objects must be found/matched based on a custom equality definition. A "precompute everything, answer in O(1)" trade-off is feasible given bounded enumerable keys.

- **When a hash table is the wrong tool**: The keys are long strings (hashing and comparison cost O(|key|) per operation). The problem has hidden structure (like the prefix/suffix overlap in Spelling Check) that yields a direct O(n) solution without any search. A sorting-based approach suffices and the equality relation satisfies transitivity (hash tables when sorting fails).

---

## Common Pitfalls

- **Off-by-one in circular traversal**: Starting the inner loop at `j = i` instead of `j = i + 1` causes a snowflake to be compared against itself, producing a false positive. Always start the duplicate-finding inner loop at `i + 1`.

- **Negative mod in C**: In C, `(-1) % 6` evaluates to `-1`, not `5`. The mod wraparound trick only works for non-negative indices. For leftward circular traversal, use an explicit `if (index < 0) index += 6` check.

- **Sorting when the order relation isn't transitive**: Calling `qsort` with a comparator that uses a non-transitive equality (like snowflake identity) causes `qsort` to infer orderings by transitivity without making all pairwise comparisons, potentially separating identical elements.

- **Double-counting duplicate substrings**: When enumerating substrings of a password, a substring like `a` may appear multiple times in `aaa`. Incrementing the hash table count for each occurrence over-counts. Fix: track which substrings have already been processed for the current password and skip duplicates.

- **Wrong array size for hash table**: The `oaat` hash function requires a table size that is a power of 2 (it uses a bitmask). Using an arbitrary size (e.g., 100,000) with `oaat` produces incorrect hashcodes. Use `1 << NUM_BITS` as the table size when using `oaat`.

- **Memory allocation on the stack**: Declaring large arrays as local (non-static) variables can overflow the stack. Use `static` for large arrays inside functions to place them in a separate memory region.

- **Assuming hash-table equality implies object equality**: Matching hashcodes only means two objects are in the same bucket. Actual identity must still be verified by explicit comparison (`are_identical` or `strcmp`). Skipping the comparison (hoping for no false positives) is only acceptable as a deliberate approximation.

- **Applying a hash table to a problem with unbounded key sizes**: Hash lookup and comparison both cost O(|key|). For million-character strings, hashing prefixes/suffixes is impractical. Look for structural properties (longest common prefix/suffix) before reaching for a hash table.

- **Linked list insertion order**: Setting `new->next = head` must come *before* `head = new`. Reversing these two lines loses all previously inserted nodes.

---

## Connections to Other Chapters

- **Chapter 7 (Binary Search)**: Mentioned as an alternative to hash tables when elements can be sorted and the equality relation satisfies transitivity. Binary search on a sorted array gives O(log n) lookup. Hash tables give expected O(1). For Unique Snowflakes, sorting was infeasible due to the non-transitive identity relation, making hash tables necessary.

- **Chapter 8 (Heaps)**: Mentioned in the Summary as the analogous data structure for a different operation: quickly finding the maximum or minimum element. Just as hash tables are the right tool for search, heaps are the right tool for min/max extraction. The chapter frames data structures as purpose-built accelerators for specific operations.

- **Appendix A (Big O)**: Referred to for a brief introduction to O(n²) vs. O(n) complexity notation used throughout this chapter.

- **Appendix B (Implicit Linked Lists for Unique Snowflakes)**: Offers an alternative hash table implementation that avoids `malloc` and explicit node structs entirely, using implicit linked lists encoded in arrays.

- **General theme**: This chapter establishes the core pattern of the book: start with a correct but slow O(n²) solution, diagnose the bottleneck (repeated search), and replace it with a data structure that performs that operation efficiently. Subsequent chapters apply this same pattern to other data structures (heaps, tries, segment trees, etc.) for different bottleneck operations.
