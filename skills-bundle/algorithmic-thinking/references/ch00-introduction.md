# Chapter 0: Introduction

## Key Concepts

- **Data Structure**: A way to organize data so that desirable operations are fast. The book builds data structures from scratch in C rather than relying on language-provided abstractions, so the reader understands exactly what is happening under the hood.

- **Algorithm**: A sequence of steps that solves a problem. Algorithms and data structures are complementary: some fast algorithms need no special data structures, while others gain significant speed from the right one.

- **Call Stack vs. Static Storage**: Local variables in C are stored on the call stack, which is small and reclaimed on function return. The `static` keyword changes a local variable's storage duration to static, and the variable persists between calls and is stored in a separate memory segment, not the call stack. Such variables are initialized exactly once. This matters because the book uses large arrays that would overflow the stack if declared as ordinary locals.

- **Dynamic Memory Allocation in C**: Memory is allocated with `malloc` and must be freed with `free`. The book deliberately omits `free` calls to keep code readable, relying on OS reclamation at program termination. This is acceptable for short-lived competitive-programming submissions but not for production software.

- **Input Redirection**: Programs read from standard input (`scanf`, `getchar`, `printf`). To avoid re-typing test cases, input can be redirected from a file at the command line (e.g., `./food < food.txt`). Two problems in Chapter 7 are the only exceptions that do not use standard I/O.

- **Programming Judges**: Online systems (Codeforces, DMOJ, POJ, SPOJ, UVa) that compile submitted code and run it against hidden test cases. Outcomes are: **AC** (Accepted, all tests pass within the time limit), **WA** (Wrong Answer, at least one test case fails), and **TLE** (Time-Limit Exceeded, program is too slow). Further test cases are not run, so WA bugs may lurk behind a TLE.

- **Competitive Programming as a Learning Vehicle**: Problems from competitions (IOI, CCC/CCO, COCI, NOIP, SAPO, USACO, ECNA/ICPC, DWITE) are used throughout the book because they are novel, require genuine problem-solving rather than pattern recall, and come with time limits that force efficiency considerations.

## Problems Covered

### Problem: Food Lines

- **Source**: DMOJ, problem code `lkp18c2p1` (originally from the 2018 LKP Contest 2)
- **Core Idea**: Given `n` food lines each with an initial queue length, `m` new people arrive one at a time and each joins a shortest (minimum-length) line. For each arrival, output the length of the line they join before they enter it.
- **Approach**: Maintain the queue lengths in an integer array `lines[n]`. For each new person, scan the array linearly to find the index of the minimum element (`shortest_line_index`), print `lines[shortest]`, then increment `lines[shortest]` by one. The key functions are `shortest_line_index(int lines[], int n)` returning the index of the minimum, and `solve(int lines[], int n, int m)` driving the loop.
- **Complexity**: O(n·m) time (linear scan for each of the m arrivals), O(n) space for the array. With n, m ≤ 100 and a 3-second limit, this brute-force approach is entirely sufficient.
- **Key Insight**: The problem is straightforward with no advanced data structure needed. Its purpose is to introduce the problem-description format (The Problem / Input / Output sections), the coding workflow (write helper functions first, read input last), and submission mechanics on a judge. It verifies that the reader has baseline programming fluency before the book's harder chapters begin.

## Algorithm Patterns

- **Linear scan for minimum**: Iterate through an array tracking the current best index, and update whenever a strictly smaller element is found. This is the simplest selection strategy and suffices when n is small. (In later chapters, a heap replaces this linear scan when n is large.)

- **Helper-function decomposition**: Isolate the core operation (e.g., finding the shortest line) in its own function before writing the main loop. This makes it easy to test the helper independently and keeps `main` readable.

- **Solve-before-reading-input workflow**: Write and test the core logic with hard-coded values first, then wire up `scanf`-based input parsing only when the logic is correct. This reduces debugging surface area.

- **Problem description anatomy**: Every problem in the book follows the same three-part structure (The Problem, Input, Output) plus an explicit time limit. Reading Input carefully (exact vs. at-least quantities, number of test cases, value ranges) is as important as the algorithm itself. Misreading a word like "at least" vs. "exactly" causes wrong-answer failures.

## Common Pitfalls

- **`static` initialization trap**: A `static` local variable is initialized only once across all calls to the function. If a function is called multiple times (e.g., once per test case), the variable retains its value from the previous call rather than resetting. This is a subtle source of bugs when processing multiple test cases.

- **Stack overflow from large arrays**: Declaring a large array as a plain local variable can exhaust the call stack. Use `static` local arrays or global arrays to place them in the static-storage segment instead.

- **TLE does not imply correctness**: A submission that times out has not had all its test cases evaluated. There may be WA bugs hidden behind the TLE, so do not assume the logic is right just because the only failure mode shown is speed.

- **Output format errors**: The judge requires exact output format (correct number of lines, no extra blank lines, correct separators). A program that computes the right answer but formats output incorrectly will receive WA.

- **Misreading problem constraints**: Pay close attention to words like "at least," "exactly," "strictly less," etc. One example from Chapter 3 (buying apples) is cited as a case where "at least" vs. "exactly" changes which test cases pass.

- **Not freeing memory**: Acceptable in the book's short-lived programs, but irresponsible in production. The book recommends adding `free` calls as an optional exercise.

## Connections to Other Chapters

- **Chapter 1** (Hash Tables): The Food Lines problem is solvable with a simple array, but Chapter 1 introduces hash tables for cases where fast lookup by key (not by position) is needed. The second edition replaced the Compound Words problem with a password/social-network problem that genuinely requires hashing.

- **Chapter 3** (Dynamic Programming): The "at least N apples" pitfall mentioned in this introduction is a Chapter 3 problem. Chapter 3 also added guidance on discovering subproblems, and the introduction's emphasis on reading problem statements carefully is a prerequisite skill for DP problem formulation.

- **Chapter 4** (Advanced Memoization / DP, new in 2nd ed.): Extends Chapter 3 with reverse-DP, multi-dimensional subproblem arrays, and further optimization techniques.

- **Chapter 5** (Graphs): Added guidance on choosing between DP and a graph approach, a decision that requires understanding both chapters.

- **Chapter 6** (Dijkstra's Algorithm): The introduction uses Dijkstra as an example of "prototypical use + extension": the first problem finds shortest paths, and the second finds both shortest paths and the count of such paths. This illustrates the book's general chapter structure.

- **Chapter 7**: The only two problems that do not use standard I/O appear here.

- **Chapter 8** (Heaps): A heap is the data structure that replaces the linear scan used in Food Lines when n is large. The second edition added discussion of why heaps are implemented as arrays rather than explicit trees.

- **Chapter 10** (Randomization, new in 2nd ed.): A new topic covering randomized algorithms for problems that are otherwise difficult. The introduction signals what to look for in a problem to recognize whether randomization is applicable.

- **Appendix B**: Contains supplementary material related to Chapters 1, 3, 5, 6, 8, 9, and 10 for readers who want to go deeper.

- **Appendix C**: Lists the source competition and judge for every problem in the book.
